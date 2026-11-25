//! Image decoding and encoding through WIC (JPEG, PNG, GIF, BMP, TIFF, ICO,
//! and WebP / HEIF where Windows has the codec).
//!
//! `decode` turns encoded bytes into premultiplied BGRA pixels, scaled down
//! to fit a box and turned upright (EXIF orientation). It may run on any
//! thread (it joins the thread's COM apartment or enters the MTA), so decode
//! on a worker and hand the pixels to `Renderer.createImage` on the UI thread:
//!
//!     var px = try image.decode(gpa, bytes, .{ .max_w = 480, .max_h = 480 });
//!     defer px.deinit(gpa);
//!     const id = renderer.createImage(px.w, px.h, px.data);   // UI thread
//!     ui.imageAt(rect, id, .{ .rounding = 8 });
const std = @import("std");
const com = @import("win32/com.zig");
const wic = @import("win32/wic.zig");

const Allocator = std.mem.Allocator;

pub const Error = error{
    /// Not an image, or no codec for its format.
    InvalidImage,
    /// More pixels than `max_source_side` allows.
    ImageTooLarge,
    /// WIC is unavailable (COM failure).
    Unavailable,
    OutOfMemory,
};

/// Larger sources are refused (decompression bombs).
pub const max_source_side: u32 = 32768;

/// Decoded pixels: premultiplied BGRA, `w * 4` bytes per row.
pub const Pixels = struct {
    w: u32,
    h: u32,
    data: []u8,
    /// Size of the upright source image before scaling.
    src_w: u32,
    src_h: u32,

    pub fn deinit(p: *Pixels, gpa: Allocator) void {
        gpa.free(p.data);
        p.data = &.{};
    }
};

pub const DecodeOptions = struct {
    /// Fit inside this box (keeping the aspect ratio, never enlarging); 0 = no limit.
    max_w: u32 = 0,
    max_h: u32 = 0,
};

/// Size of `src` scaled down to fit inside `max_w` x `max_h` (0 = unbounded),
/// keeping the aspect ratio and at least 1 px per side. Never enlarges.
pub fn fitSize(src_w: u32, src_h: u32, max_w: u32, max_h: u32) [2]u32 {
    if (src_w == 0 or src_h == 0) return .{ 0, 0 };
    const mw: f64 = if (max_w == 0) std.math.inf(f64) else @floatFromInt(max_w);
    const mh: f64 = if (max_h == 0) std.math.inf(f64) else @floatFromInt(max_h);
    const sw: f64 = @floatFromInt(src_w);
    const sh: f64 = @floatFromInt(src_h);
    const k = @min(1.0, @min(mw / sw, mh / sh));
    if (k >= 1.0) return .{ src_w, src_h };
    return .{
        @max(1, @as(u32, @intFromFloat(@round(sw * k)))),
        @max(1, @as(u32, @intFromFloat(@round(sh * k)))),
    };
}

/// WIC flip/rotate options for an EXIF orientation (1..8); 0 = upright already.
pub fn orientationTransform(orientation: u16) u32 {
    return switch (orientation) {
        2 => wic.WICBitmapTransformFlipHorizontal,
        3 => wic.WICBitmapTransformRotate180,
        4 => wic.WICBitmapTransformFlipVertical,
        5 => wic.WICBitmapTransformRotate90 | wic.WICBitmapTransformFlipHorizontal,
        6 => wic.WICBitmapTransformRotate90,
        7 => wic.WICBitmapTransformRotate270 | wic.WICBitmapTransformFlipHorizontal,
        8 => wic.WICBitmapTransformRotate270,
        else => 0,
    };
}

const ComScope = struct {
    entered: bool,

    fn enter() ComScope {
        // An STA thread (the UI thread) keeps its apartment: RPC_E_CHANGED_MODE.
        const hr = com.CoInitializeEx(null, wic.COINIT_MULTITHREADED);
        return .{ .entered = hr >= 0 };
    }
    fn leave(s: ComScope) void {
        if (s.entered) com.CoUninitialize();
    }
};

fn release(p: anytype) void {
    var x: ?@TypeOf(p) = p;
    com.safeRelease(&x);
}

/// The first frame of an encoded image (upright, scaled to fit, premultiplied BGRA).
pub fn decode(gpa: Allocator, bytes: []const u8, opts: DecodeOptions) Error!Pixels {
    if (bytes.len == 0 or bytes.len > std.math.maxInt(u32)) return error.InvalidImage;
    const scope = ComScope.enter();
    defer scope.leave();
    const f = wic.createFactory() orelse return error.Unavailable;
    defer release(f);
    const stream = f.createStream() orelse return error.Unavailable;
    defer release(stream);
    if (!stream.initializeFromMemory(bytes)) return error.InvalidImage;
    const dec = f.createDecoderFromStream(stream) orelse return error.InvalidImage;
    defer release(dec);
    const frame = dec.getFrame(0) orelse return error.InvalidImage;
    defer release(frame);

    const raw = frame.getSize() orelse return error.InvalidImage;
    if (raw[0] == 0 or raw[1] == 0) return error.InvalidImage;
    if (raw[0] > max_source_side or raw[1] > max_source_side) return error.ImageTooLarge;
    const transform = orientationTransform(@as(*wic.IWICBitmapFrameDecode, @ptrCast(frame)).exifOrientation());
    // 90° / 270°: width and height trade places.
    const swaps = transform & 1 != 0;
    const up_w = if (swaps) raw[1] else raw[0];
    const up_h = if (swaps) raw[0] else raw[1];
    const fit = fitSize(up_w, up_h, opts.max_w, opts.max_h);

    var src: *wic.IWICBitmapSource = frame;
    // Scale first (cheap with JPEG's built-in downscaling), rotate the small result.
    const scale_w = if (swaps) fit[1] else fit[0];
    const scale_h = if (swaps) fit[0] else fit[1];
    var scaler: ?*wic.IWICBitmapScaler = null;
    defer com.safeRelease(&scaler);
    if (scale_w != raw[0] or scale_h != raw[1]) {
        scaler = f.createBitmapScaler() orelse return error.Unavailable;
        if (!scaler.?.initialize(src, scale_w, scale_h)) return error.InvalidImage;
        src = scaler.?.asSource();
    }
    var rot: ?*wic.IWICBitmapFlipRotator = null;
    defer com.safeRelease(&rot);
    if (transform != 0) {
        if (f.createFlipRotator()) |r| {
            rot = r;
            if (r.initialize(src, transform)) src = r.asSource();
        }
    }
    var conv: ?*wic.IWICFormatConverter = f.createFormatConverter() orelse return error.Unavailable;
    defer com.safeRelease(&conv);
    if (!conv.?.initialize(src, &wic.GUID_WICPixelFormat32bppPBGRA)) return error.InvalidImage;
    const out_size = conv.?.asSource().getSize() orelse return error.InvalidImage;
    const w = out_size[0];
    const h = out_size[1];
    const stride = std.math.mul(u32, w, 4) catch return error.ImageTooLarge;
    const total = std.math.mul(usize, stride, h) catch return error.ImageTooLarge;
    if (total > std.math.maxInt(u32)) return error.ImageTooLarge;
    const data = try gpa.alloc(u8, total);
    errdefer gpa.free(data);
    if (!conv.?.asSource().copyPixels(stride, data)) return error.InvalidImage;
    return .{ .w = w, .h = h, .data = data, .src_w = up_w, .src_h = up_h };
}

pub const Info = struct {
    /// Upright size.
    w: u32,
    h: u32,
    /// More than 1 for animations (GIF, WebP).
    frames: u32,
};

/// Upright size and frame count of an encoded image without decoding its pixels.
pub fn info(bytes: []const u8) ?Info {
    if (bytes.len == 0 or bytes.len > std.math.maxInt(u32)) return null;
    const scope = ComScope.enter();
    defer scope.leave();
    const f = wic.createFactory() orelse return null;
    defer release(f);
    const stream = f.createStream() orelse return null;
    defer release(stream);
    if (!stream.initializeFromMemory(bytes)) return null;
    const dec = f.createDecoderFromStream(stream) orelse return null;
    defer release(dec);
    var frames: u32 = 1;
    _ = dec.vtbl.GetFrameCount(dec, &frames);
    const frame = dec.getFrame(0) orelse return null;
    defer release(frame);
    const raw = frame.getSize() orelse return null;
    if (raw[0] == 0 or raw[1] == 0) return null;
    const transform = orientationTransform(@as(*wic.IWICBitmapFrameDecode, @ptrCast(frame)).exifOrientation());
    const swaps = transform & 1 != 0;
    return .{ .w = if (swaps) raw[1] else raw[0], .h = if (swaps) raw[0] else raw[1], .frames = @max(frames, 1) };
}

/// Re-encodes any decodable image (e.g. a clipboard bitmap) as PNG. Caller frees.
pub fn toPng(gpa: Allocator, bytes: []const u8) Error![]u8 {
    if (bytes.len == 0 or bytes.len > std.math.maxInt(u32)) return error.InvalidImage;
    const scope = ComScope.enter();
    defer scope.leave();
    const f = wic.createFactory() orelse return error.Unavailable;
    defer release(f);
    const stream = f.createStream() orelse return error.Unavailable;
    defer release(stream);
    if (!stream.initializeFromMemory(bytes)) return error.InvalidImage;
    const dec = f.createDecoderFromStream(stream) orelse return error.InvalidImage;
    defer release(dec);
    const frame = dec.getFrame(0) orelse return error.InvalidImage;
    defer release(frame);
    const size = frame.getSize() orelse return error.InvalidImage;
    if (size[0] == 0 or size[1] == 0) return error.InvalidImage;
    if (size[0] > max_source_side or size[1] > max_source_side) return error.ImageTooLarge;
    var conv: ?*wic.IWICFormatConverter = f.createFormatConverter() orelse return error.Unavailable;
    defer com.safeRelease(&conv);
    if (!conv.?.initialize(frame, &wic.GUID_WICPixelFormat32bppBGRA)) return error.InvalidImage;
    const stride = size[0] * 4;
    const total = std.math.mul(usize, stride, size[1]) catch return error.ImageTooLarge;
    if (total > std.math.maxInt(u32)) return error.ImageTooLarge;
    const px = try gpa.alloc(u8, total);
    defer gpa.free(px);
    if (!conv.?.asSource().copyPixels(stride, px)) return error.InvalidImage;
    return encodeFrame(gpa, f, &wic.GUID_ContainerFormatPng, size[0], size[1], &wic.GUID_WICPixelFormat32bppBGRA, size[0] * 4, px, null);
}

/// Encodes straight-alpha BGRA pixels (`w * 4` bytes per row) as PNG. Caller frees.
pub fn encodePng(gpa: Allocator, w: u32, h: u32, bgra: []const u8) Error![]u8 {
    if (w == 0 or h == 0 or bgra.len < @as(usize, w) * h * 4) return error.InvalidImage;
    const scope = ComScope.enter();
    defer scope.leave();
    const f = wic.createFactory() orelse return error.Unavailable;
    defer release(f);
    return encodeFrame(gpa, f, &wic.GUID_ContainerFormatPng, w, h, &wic.GUID_WICPixelFormat32bppBGRA, w * 4, bgra, null);
}

/// Encodes decoded (premultiplied) pixels as a baseline JPEG, flattened onto
/// white; `quality` is 0..1 (0.78 = "q78"). Caller frees.
pub fn encodeJpeg(gpa: Allocator, px: *const Pixels, quality: f32) Error![]u8 {
    if (px.w == 0 or px.h == 0 or px.data.len < @as(usize, px.w) * px.h * 4) return error.InvalidImage;
    const stride = (px.w * 3 + 3) & ~@as(u32, 3);
    const bgr = try gpa.alloc(u8, @as(usize, stride) * px.h);
    defer gpa.free(bgr);
    flattenOnWhite(px, bgr, stride);
    const scope = ComScope.enter();
    defer scope.leave();
    const f = wic.createFactory() orelse return error.Unavailable;
    defer release(f);
    return encodeFrame(gpa, f, &wic.GUID_ContainerFormatJpeg, px.w, px.h, &wic.GUID_WICPixelFormat24bppBGR, stride, bgr, std.math.clamp(quality, 0.0, 1.0));
}

/// Premultiplied BGRA over white: 24-bit BGR rows of `stride` bytes.
fn flattenOnWhite(px: *const Pixels, out: []u8, stride: u32) void {
    var y: usize = 0;
    while (y < px.h) : (y += 1) {
        const src = px.data[y * px.w * 4 ..][0 .. px.w * 4];
        const dst = out[y * stride ..][0 .. px.w * 3];
        var x: usize = 0;
        while (x < px.w) : (x += 1) {
            const a = src[x * 4 + 3];
            inline for (0..3) |c| dst[x * 3 + c] = src[x * 4 + c] +| (255 - a);
        }
    }
}

fn encodeFrame(gpa: Allocator, f: *wic.IWICImagingFactory, container: *const com.GUID, w: u32, h: u32, format: *const com.GUID, stride: u32, pixels: []const u8, quality: ?f32) Error![]u8 {
    var out: ?*wic.IStream = null;
    if (com.failed(wic.CreateStreamOnHGlobal(null, 1, &out))) return error.Unavailable;
    defer com.safeRelease(&out);
    var enc: ?*wic.IWICBitmapEncoder = f.createEncoder(container) orelse return error.Unavailable;
    defer com.safeRelease(&enc);
    if (com.failed(enc.?.vtbl.Initialize(enc.?, out.?, wic.WICBitmapEncoderNoCache))) return error.Unavailable;
    var frame: ?*wic.IWICBitmapFrameEncode = null;
    var bag: ?*wic.IPropertyBag2 = null;
    if (com.failed(enc.?.vtbl.CreateNewFrame(enc.?, &frame, &bag))) return error.Unavailable;
    defer com.safeRelease(&frame);
    defer com.safeRelease(&bag);
    const fe = frame.?;
    if (quality) |q| if (bag) |b| {
        _ = b.writeFloat(std.unicode.utf8ToUtf16LeStringLiteral("ImageQuality"), q);
    };
    if (com.failed(fe.vtbl.Initialize(fe, bag))) return error.Unavailable;
    if (com.failed(fe.vtbl.SetSize(fe, w, h))) return error.Unavailable;
    var fmt = format.*;
    if (com.failed(fe.vtbl.SetPixelFormat(fe, &fmt))) return error.Unavailable;
    if (!std.mem.eql(u8, std.mem.asBytes(&fmt), std.mem.asBytes(format))) return error.Unavailable;
    if (com.failed(fe.vtbl.WritePixels(fe, h, stride, stride * h, pixels.ptr))) return error.InvalidImage;
    if (com.failed(fe.vtbl.Commit(fe))) return error.Unavailable;
    if (com.failed(enc.?.vtbl.Commit(enc.?))) return error.Unavailable;

    const len = out.?.seek(0, wic.STREAM_SEEK_CUR) orelse return error.Unavailable;
    if (len == 0 or len > std.math.maxInt(u32)) return error.Unavailable;
    _ = out.?.seek(0, wic.STREAM_SEEK_SET) orelse return error.Unavailable;
    const buf = try gpa.alloc(u8, @intCast(len));
    errdefer gpa.free(buf);
    var got: usize = 0;
    while (got < buf.len) {
        const n = out.?.read(buf[got..]) orelse return error.Unavailable;
        if (n == 0) return error.Unavailable;
        got += n;
    }
    return buf;
}

/// A BMP file for a packed DIB (CF_DIB clipboard data: BITMAPINFO + pixels), so
/// WIC's BMP decoder can read it. Caller frees.
pub fn bmpFromDib(gpa: Allocator, dib: []const u8) Error![]u8 {
    if (dib.len < 40) return error.InvalidImage;
    const header_size = std.mem.readInt(u32, dib[0..4], .little);
    if (header_size < 40 or header_size > dib.len) return error.InvalidImage;
    const bit_count = std.mem.readInt(u16, dib[14..16], .little);
    const compression = std.mem.readInt(u32, dib[16..20], .little);
    const clr_used = std.mem.readInt(u32, dib[32..36], .little);
    var colors: u32 = clr_used;
    if (colors == 0 and bit_count <= 8) colors = @as(u32, 1) << @intCast(bit_count);
    if (colors > 256) return error.InvalidImage;
    // BI_BITFIELDS with a plain BITMAPINFOHEADER: three DWORD masks follow it.
    const masks: u32 = if (header_size == 40 and compression == 3) 12 else 0;
    const off_bits = 14 + header_size + masks + colors * 4;
    const total = 14 + dib.len;
    if (off_bits > total or total > std.math.maxInt(u32)) return error.InvalidImage;
    const out = try gpa.alloc(u8, total);
    out[0] = 'B';
    out[1] = 'M';
    std.mem.writeInt(u32, out[2..6], @intCast(total), .little);
    std.mem.writeInt(u32, out[6..10], 0, .little);
    std.mem.writeInt(u32, out[10..14], off_bits, .little);
    @memcpy(out[14..], dib);
    return out;
}

test "fit size keeps the aspect ratio and never enlarges" {
    try std.testing.expectEqual([2]u32{ 400, 300 }, fitSize(400, 300, 0, 0));
    try std.testing.expectEqual([2]u32{ 400, 300 }, fitSize(400, 300, 480, 480));
    try std.testing.expectEqual([2]u32{ 480, 360 }, fitSize(4000, 3000, 480, 480));
    try std.testing.expectEqual([2]u32{ 270, 480 }, fitSize(1080, 1920, 480, 480));
    try std.testing.expectEqual([2]u32{ 1, 240 }, fitSize(10, 20000, 480, 240));
    try std.testing.expectEqual([2]u32{ 0, 0 }, fitSize(0, 5, 10, 10));
}

test "orientation transforms" {
    try std.testing.expectEqual(@as(u32, 0), orientationTransform(1));
    try std.testing.expectEqual(wic.WICBitmapTransformRotate90, orientationTransform(6));
    try std.testing.expectEqual(wic.WICBitmapTransformRotate270, orientationTransform(8));
    try std.testing.expectEqual(@as(u32, 0), orientationTransform(9));
}

test "png encode and decode round trip" {
    const gpa = std.testing.allocator;
    // 3x2: red, green, blue / white, black, half-transparent red.
    const px = [_]u8{
        0,   0,   255, 255, 0,   255, 0, 255, 255, 0,   0, 255,
        255, 255, 255, 255, 0,   0,   0, 255, 0,   0,   255, 128,
    };
    const png = try encodePng(gpa, 3, 2, &px);
    defer gpa.free(png);
    try std.testing.expectEqualSlices(u8, "\x89PNG", png[0..4]);
    const inf = info(png).?;
    try std.testing.expectEqual(@as(u32, 3), inf.w);
    try std.testing.expectEqual(@as(u32, 2), inf.h);
    try std.testing.expectEqual(@as(u32, 1), inf.frames);
    var d = try decode(gpa, png, .{});
    defer d.deinit(gpa);
    try std.testing.expectEqual(@as(u32, 3), d.w);
    try std.testing.expectEqual(@as(u32, 2), d.h);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 255, 255 }, d.data[0..4]);
    // Premultiplied: half-transparent red becomes (0, 0, 128, 128).
    try std.testing.expectEqual(@as(u8, 128), d.data[20 + 3]);
    try std.testing.expect(d.data[20 + 2] >= 127 and d.data[20 + 2] <= 129);

    // Scaled to fit.
    var s = try decode(gpa, png, .{ .max_w = 2, .max_h = 2 });
    defer s.deinit(gpa);
    try std.testing.expectEqual(@as(u32, 2), s.w);
    try std.testing.expectEqual(@as(u32, 1), s.h);
    try std.testing.expectEqual(@as(u32, 3), s.src_w);

    try std.testing.expectError(error.InvalidImage, decode(gpa, "not an image", .{}));
    try std.testing.expect(info("nope") == null);

    // JPEG: transparency becomes white.
    var full = try decode(gpa, png, .{});
    defer full.deinit(gpa);
    const jpg = try encodeJpeg(gpa, &full, 0.95);
    defer gpa.free(jpg);
    try std.testing.expectEqualSlices(u8, &.{ 0xff, 0xd8 }, jpg[0..2]);
    var back = try decode(gpa, jpg, .{});
    defer back.deinit(gpa);
    try std.testing.expectEqual(@as(u32, 3), back.w);
    try std.testing.expectEqual(@as(u8, 255), back.data[3]);
}

test "clipboard DIB to PNG" {
    const gpa = std.testing.allocator;
    // BITMAPINFOHEADER, 2x1, 24 bpp, bottom-up; rows padded to 4 bytes.
    var dib: [40 + 8]u8 = @splat(0);
    std.mem.writeInt(u32, dib[0..4], 40, .little);
    std.mem.writeInt(i32, dib[4..8], 2, .little);
    std.mem.writeInt(i32, dib[8..12], 1, .little);
    std.mem.writeInt(u16, dib[12..14], 1, .little);
    std.mem.writeInt(u16, dib[14..16], 24, .little);
    @memcpy(dib[40..46], &[_]u8{ 255, 0, 0, 0, 255, 0 }); // blue, green (BGR)
    const bmp = try bmpFromDib(gpa, &dib);
    defer gpa.free(bmp);
    try std.testing.expectEqual(@as(u32, 54), std.mem.readInt(u32, bmp[10..14], .little));
    const png = try toPng(gpa, bmp);
    defer gpa.free(png);
    var d = try decode(gpa, png, .{});
    defer d.deinit(gpa);
    try std.testing.expectEqual(@as(u32, 2), d.w);
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255, 0, 255, 0, 255 }, d.data[0..8]);
    try std.testing.expectError(error.InvalidImage, bmpFromDib(gpa, "short"));
}
