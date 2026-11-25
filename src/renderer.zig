//! Pure native Direct3D 11 + DXGI + DirectComposition + Direct2D 1.1 + DirectWrite renderer.
const std = @import("std");
const com = @import("win32/com.zig");
const win32 = @import("win32/win32.zig");
const d3d = @import("win32/d3d_dxgi.zig");
const dcomp = @import("win32/dcomp.zig");
const d2d = @import("win32/d2d1.zig");
const dwrite = @import("win32/dwrite.zig");
const math = @import("math.zig");
const Color = @import("color.zig").Color;
const dl_mod = @import("drawlist.zig");

const Vec2 = math.Vec2;
const Rect = math.Rect;
const DrawList = dl_mod.DrawList;
const TextStyle = dl_mod.TextStyle;
const TextWeight = dl_mod.TextWeight;

const FontKey = struct {
    size_tenths: u16,
    weight: u8,
    mono: bool,
    wrap: bool,
};

/// Cache key of a shaped text layout: string hash + length + font + wrap width.
const LayoutKey = struct {
    hash: u64,
    len: u32,
    font: FontKey,
    max_w_q: u32,
};

const LayoutEntry = struct {
    layout: *dwrite.IDWriteTextLayout,
    last_frame: u64,
};

/// Layouts unused for this many frames are released once the cache is large.
const layout_ttl_frames: u64 = 240;
const layout_soft_cap: usize = 3000;

/// Converts UTF-8 to UTF-16 in a stack buffer, falling back to the heap for long text.
const Utf16Scratch = struct {
    stack: [1024]u16 = undefined,
    heap: ?[]u16 = null,

    fn convert(self: *Utf16Scratch, allocator: std.mem.Allocator, str: []const u8) []const u16 {
        if (str.len <= self.stack.len) {
            const n = std.unicode.utf8ToUtf16Le(&self.stack, str) catch return lossy(&self.stack, str);
            return self.stack[0..n];
        }
        const buf = allocator.alloc(u16, str.len) catch return lossy(&self.stack, str[0..self.stack.len]);
        self.heap = buf;
        const n = std.unicode.utf8ToUtf16Le(buf, str) catch return lossy(buf, str);
        return buf[0..n];
    }

    /// Invalid UTF-8 (e.g. a truncated server string): replace bad bytes with U+FFFD.
    fn lossy(buf: []u16, str: []const u8) []const u16 {
        var n: usize = 0;
        var i: usize = 0;
        while (i < str.len and n < buf.len) {
            const seq = std.unicode.utf8ByteSequenceLength(str[i]) catch {
                buf[n] = 0xFFFD;
                n += 1;
                i += 1;
                continue;
            };
            if (i + seq > str.len) {
                buf[n] = 0xFFFD;
                n += 1;
                break;
            }
            const cp = std.unicode.utf8Decode(str[i .. i + seq]) catch 0xFFFD;
            if (cp >= 0x10000) {
                if (n + 2 > buf.len) break;
                const v = cp - 0x10000;
                buf[n] = @intCast(0xD800 + (v >> 10));
                buf[n + 1] = @intCast(0xDC00 + (v & 0x3FF));
                n += 2;
            } else {
                buf[n] = @intCast(cp);
                n += 1;
            }
            i += seq;
        }
        return buf[0..n];
    }

    fn deinit(self: *Utf16Scratch, allocator: std.mem.Allocator) void {
        if (self.heap) |h| allocator.free(h);
        self.heap = null;
    }
};

/// UTF-16 index of the UTF-8 byte offset `byte` in `str`.
pub fn utf16IndexOf(str: []const u8, byte: usize) u32 {
    var i: usize = 0;
    var units: u32 = 0;
    const end = @min(byte, str.len);
    while (i < end) {
        const seq = std.unicode.utf8ByteSequenceLength(str[i]) catch 1;
        units += if (seq == 4) 2 else 1;
        i += seq;
    }
    return units;
}

/// UTF-8 byte offset of the UTF-16 index `index` in `str` (clamped to a code point boundary).
pub fn byteOffsetOf(str: []const u8, index: u32) usize {
    var i: usize = 0;
    var units: u32 = 0;
    while (i < str.len and units < index) {
        const seq = std.unicode.utf8ByteSequenceLength(str[i]) catch 1;
        units += if (seq == 4) 2 else 1;
        i = @min(i + seq, str.len);
    }
    return i;
}

pub const Renderer = struct {
    allocator: std.mem.Allocator,
    d3d_device: ?*d3d.ID3D11Device = null,
    d3d_ctx: ?*d3d.ID3D11DeviceContext = null,
    dxgi_device: ?*d3d.IDXGIDevice = null,
    swapchain: ?*d3d.IDXGISwapChain1 = null,

    dcomp_device: ?*dcomp.IDCompositionDevice = null,
    dcomp_target: ?*dcomp.IDCompositionTarget = null,
    dcomp_visual: ?*dcomp.IDCompositionVisual = null,

    d2d_factory: ?*d2d.ID2D1Factory1 = null,
    d2d_device: ?*d2d.ID2D1Device = null,
    dc: ?*d2d.ID2D1DeviceContext = null,
    target_bitmap: ?*d2d.ID2D1Bitmap1 = null,
    solid_brush: ?*d2d.ID2D1SolidColorBrush = null,
    round_stroke: ?*d2d.ID2D1StrokeStyle = null,

    dwrite_factory: ?*dwrite.IDWriteFactory = null,
    font_cache: std.AutoHashMap(FontKey, *dwrite.IDWriteTextFormat),
    layout_cache: std.AutoHashMap(LayoutKey, LayoutEntry),
    frame_index: u64 = 0,

    /// UI font family and locale. The locale drives DirectWrite's fallback for
    /// scripts the family lacks ("zh-cn" picks Microsoft YaHei for Han text).
    font_family: [64]u16 = undefined,
    font_locale: [24]u16 = undefined,

    pixel_w: u32 = 1,
    pixel_h: u32 = 1,
    dpi: f32 = 96.0,

    pub const default_font_family = "Segoe UI";
    pub const default_font_locale = "zh-cn";

    pub fn init(allocator: std.mem.Allocator, hwnd: win32.HWND, width: u32, height: u32, dpi: f32) !Renderer {
        var self: Renderer = .{
            .allocator = allocator,
            .font_cache = std.AutoHashMap(FontKey, *dwrite.IDWriteTextFormat).init(allocator),
            .layout_cache = std.AutoHashMap(LayoutKey, LayoutEntry).init(allocator),
            .pixel_w = @max(width, 1),
            .pixel_h = @max(height, 1),
            .dpi = dpi,
        };
        _ = win32.utf8ToUtf16Z(&self.font_family, default_font_family);
        _ = win32.utf8ToUtf16Z(&self.font_locale, default_font_locale);
        errdefer self.deinit();

        // 1. Direct3D 11 device with BGRA support for Direct2D interop
        var hr = d3d.D3D11CreateDevice(
            null,
            d3d.D3D_DRIVER_TYPE_HARDWARE,
            null,
            d3d.D3D11_CREATE_DEVICE_BGRA_SUPPORT,
            null,
            0,
            d3d.D3D11_SDK_VERSION,
            &self.d3d_device,
            null,
            &self.d3d_ctx,
        );
        if (com.failed(hr)) {
            hr = d3d.D3D11CreateDevice(
                null,
                d3d.D3D_DRIVER_TYPE_WARP,
                null,
                d3d.D3D11_CREATE_DEVICE_BGRA_SUPPORT,
                null,
                0,
                d3d.D3D11_SDK_VERSION,
                &self.d3d_device,
                null,
                &self.d3d_ctx,
            );
            if (com.failed(hr)) return error.D3D11InitFailed;
        }

        const unk: *com.IUnknown = @ptrCast(@alignCast(self.d3d_device.?));
        self.dxgi_device = unk.queryInterface(d3d.IDXGIDevice, &d3d.IID_IDXGIDevice) orelse return error.DXGIInitFailed;

        const adapter = self.dxgi_device.?.getAdapter() orelse return error.DXGIInitFailed;
        defer {
            var a: ?*d3d.IDXGIAdapter = adapter;
            com.safeRelease(&a);
        }
        const dxgi_factory = adapter.getParentFactory2() orelse return error.DXGIInitFailed;
        defer {
            var f: ?*d3d.IDXGIFactory2 = dxgi_factory;
            com.safeRelease(&f);
        }

        // 2. DirectComposition SwapChain (premultiplied alpha, flip sequential)
        const sc_desc: d3d.DXGI_SWAP_CHAIN_DESC1 = .{
            .Width = self.pixel_w,
            .Height = self.pixel_h,
            .Format = d3d.DXGI_FORMAT_B8G8R8A8_UNORM,
            .BufferCount = 2,
            .SwapEffect = d3d.DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL,
            .AlphaMode = d3d.DXGI_ALPHA_MODE_PREMULTIPLIED,
        };
        self.swapchain = dxgi_factory.createSwapChainForComposition(self.dxgi_device.?, &sc_desc) orelse return error.SwapChainFailed;

        // 3. DirectComposition Device -> Target(HWND) -> Visual(SwapChain)
        self.dcomp_device = dcomp.createDevice(self.dxgi_device.?) orelse return error.DCompInitFailed;
        self.dcomp_target = self.dcomp_device.?.createTargetForHwnd(hwnd, true) orelse return error.DCompInitFailed;
        self.dcomp_visual = self.dcomp_device.?.createVisual() orelse return error.DCompInitFailed;
        _ = self.dcomp_visual.?.setContent(self.swapchain.?);
        _ = self.dcomp_target.?.setRoot(self.dcomp_visual.?);
        _ = self.dcomp_device.?.commit();

        // 4. Direct2D 1.1 Factory -> Device -> DeviceContext
        self.d2d_factory = d2d.createFactory1() orelse return error.D2DInitFailed;
        self.d2d_device = self.d2d_factory.?.createDevice(self.dxgi_device.?) orelse return error.D2DInitFailed;
        self.dc = self.d2d_device.?.createDeviceContext() orelse return error.D2DInitFailed;

        self.solid_brush = self.dc.?.createSolidColorBrush(.{ .r = 1, .g = 1, .b = 1, .a = 1 }) orelse return error.D2DInitFailed;
        const stroke_props: d2d.D2D1_STROKE_STYLE_PROPERTIES = .{};
        self.round_stroke = self.d2d_factory.?.createStrokeStyle(&stroke_props);

        // 5. DirectWrite Factory
        self.dwrite_factory = dwrite.createFactory() orelse return error.DWriteInitFailed;

        try self.bindBackBuffer();
        return self;
    }

    pub fn deinit(self: *Renderer) void {
        self.clearTextCaches();
        self.font_cache.deinit();
        self.layout_cache.deinit();

        if (self.dc) |dc| dc.setTarget(null);
        com.safeRelease(&self.target_bitmap);
        com.safeRelease(&self.round_stroke);
        com.safeRelease(&self.solid_brush);
        com.safeRelease(&self.dc);
        com.safeRelease(&self.d2d_device);
        com.safeRelease(&self.d2d_factory);
        com.safeRelease(&self.dwrite_factory);
        com.safeRelease(&self.dcomp_visual);
        com.safeRelease(&self.dcomp_target);
        com.safeRelease(&self.dcomp_device);
        com.safeRelease(&self.swapchain);
        com.safeRelease(&self.dxgi_device);
        com.safeRelease(&self.d3d_ctx);
        com.safeRelease(&self.d3d_device);
    }

    fn bindBackBuffer(self: *Renderer) !void {
        const dc = self.dc.?;
        dc.setTarget(null);
        com.safeRelease(&self.target_bitmap);

        const surface = self.swapchain.?.getBufferSurface() orelse return error.BackBufferFailed;
        defer {
            var s: ?*d3d.IDXGISurface = surface;
            com.safeRelease(&s);
        }

        const props: d2d.D2D1_BITMAP_PROPERTIES1 = .{
            .dpiX = self.dpi,
            .dpiY = self.dpi,
        };
        self.target_bitmap = dc.createBitmapFromDxgiSurface(surface, &props) orelse return error.BackBufferFailed;
        dc.setTarget(self.target_bitmap);
        dc.setDpi(self.dpi, self.dpi);
        dc.setAntialiasMode(d2d.D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
        // Grayscale AA works cleanly with premultiplied alpha DirectComposition surfaces.
        dc.setTextAntialiasMode(d2d.D2D1_TEXT_ANTIALIAS_MODE_GRAYSCALE);
    }

    pub fn resize(self: *Renderer, width: u32, height: u32, dpi: f32) void {
        const w = @max(width, 1);
        const h = @max(height, 1);
        if (w == self.pixel_w and h == self.pixel_h and dpi == self.dpi) return;
        self.pixel_w = w;
        self.pixel_h = h;
        self.dpi = dpi;
        if (self.dc) |dc| dc.setTarget(null);
        com.safeRelease(&self.target_bitmap);
        if (self.swapchain) |sc| {
            _ = sc.resizeBuffers(w, h);
        }
        self.bindBackBuffer() catch {};
    }

    pub fn logicalSize(self: *const Renderer) Vec2 {
        const scale = self.dpi / 96.0;
        return .{
            .x = @as(f32, @floatFromInt(self.pixel_w)) / scale,
            .y = @as(f32, @floatFromInt(self.pixel_h)) / scale,
        };
    }

    /// Sets the UI font family and fallback locale (e.g. "Segoe UI", "zh-cn").
    pub fn setFont(self: *Renderer, family: []const u8, locale: []const u8) void {
        _ = win32.utf8ToUtf16Z(&self.font_family, family);
        _ = win32.utf8ToUtf16Z(&self.font_locale, locale);
        self.clearTextCaches();
    }

    fn clearTextCaches(self: *Renderer) void {
        var lit = self.layout_cache.valueIterator();
        while (lit.next()) |e| {
            var l: ?*dwrite.IDWriteTextLayout = e.layout;
            com.safeRelease(&l);
        }
        self.layout_cache.clearRetainingCapacity();
        var it = self.font_cache.valueIterator();
        while (it.next()) |v| {
            var p: ?*dwrite.IDWriteTextFormat = v.*;
            com.safeRelease(&p);
        }
        self.font_cache.clearRetainingCapacity();
    }

    fn fontKey(style: TextStyle) FontKey {
        return .{
            .size_tenths = @intFromFloat(@round(std.math.clamp(style.size, 6.0, 200.0) * 10.0)),
            .weight = @intFromEnum(style.weight),
            .mono = style.mono,
            .wrap = style.wrap,
        };
    }

    fn getTextFormat(self: *Renderer, style: TextStyle) ?*dwrite.IDWriteTextFormat {
        const key = fontKey(style);
        if (self.font_cache.get(key)) |fmt| return fmt;

        const dw_weight: u32 = switch (style.weight) {
            .regular => dwrite.DWRITE_FONT_WEIGHT_REGULAR,
            .medium => dwrite.DWRITE_FONT_WEIGHT_MEDIUM,
            .semibold => dwrite.DWRITE_FONT_WEIGHT_SEMIBOLD,
            .bold => dwrite.DWRITE_FONT_WEIGHT_BOLD,
        };
        const family: [*:0]const u16 = if (style.mono)
            std.unicode.utf8ToUtf16LeStringLiteral("Consolas")
        else
            @ptrCast(&self.font_family);

        const fmt = self.dwrite_factory.?.createTextFormat(family, dw_weight, style.size, @ptrCast(&self.font_locale)) orelse return null;
        fmt.setWordWrapping(if (style.wrap) dwrite.DWRITE_WORD_WRAPPING_WRAP else dwrite.DWRITE_WORD_WRAPPING_NO_WRAP);
        fmt.setTextAlignment(dwrite.DWRITE_TEXT_ALIGNMENT_LEADING);
        fmt.setParagraphAlignment(dwrite.DWRITE_PARAGRAPH_ALIGNMENT_NEAR);
        self.font_cache.put(key, fmt) catch {};
        return fmt;
    }

    /// Shaped layout for `str`, cached across frames (shaping CJK text and
    /// wrapping long messages is the dominant per-frame cost in a chat view).
    /// The cache owns the returned layout; do not release it.
    pub fn layoutFor(self: *Renderer, str: []const u8, style: TextStyle, max_w: f32) ?*dwrite.IDWriteTextLayout {
        const font = fontKey(style);
        const wrap_w: f32 = if (max_w > 0) max_w else 100000.0;
        const key: LayoutKey = .{
            .hash = std.hash.Wyhash.hash(0x6d6f6f6e, str),
            .len = @intCast(@min(str.len, std.math.maxInt(u32))),
            .font = font,
            .max_w_q = @intFromFloat(@round(std.math.clamp(wrap_w, 0, 1.0e6) * 4.0)),
        };
        if (self.layout_cache.getPtr(key)) |e| {
            e.last_frame = self.frame_index;
            return e.layout;
        }
        const fmt = self.getTextFormat(style) orelse return null;
        var scratch: Utf16Scratch = .{};
        defer scratch.deinit(self.allocator);
        const wide = scratch.convert(self.allocator, str);
        const layout = self.dwrite_factory.?.createTextLayout(wide, fmt, wrap_w, 100000.0) orelse return null;
        self.layout_cache.put(key, .{ .layout = layout, .last_frame = self.frame_index }) catch {
            // Cache full / OOM: hand out an uncached layout that is released next frame.
            var l: ?*dwrite.IDWriteTextLayout = layout;
            com.safeRelease(&l);
            return null;
        };
        return layout;
    }

    /// Releases layouts that have not been used for a while (called once per frame).
    fn trimLayoutCache(self: *Renderer) void {
        if (self.layout_cache.count() < layout_soft_cap) return;
        var stale: [256]LayoutKey = undefined;
        while (true) {
            var n: usize = 0;
            var it = self.layout_cache.iterator();
            while (it.next()) |kv| {
                if (self.frame_index - kv.value_ptr.last_frame > layout_ttl_frames) {
                    stale[n] = kv.key_ptr.*;
                    n += 1;
                    if (n == stale.len) break;
                }
            }
            for (stale[0..n]) |k| {
                if (self.layout_cache.fetchRemove(k)) |kv| {
                    var l: ?*dwrite.IDWriteTextLayout = kv.value.layout;
                    com.safeRelease(&l);
                }
            }
            if (n < stale.len) break;
        }
    }

    pub fn layoutCacheSize(self: *const Renderer) usize {
        return self.layout_cache.count();
    }

    pub fn measureText(self: *Renderer, str: []const u8, style: TextStyle, max_w: f32) Vec2 {
        if (str.len == 0) return .{ .x = 0, .y = style.size * 1.32 };
        const layout = self.layoutFor(str, style, max_w) orelse return .{ .x = @as(f32, @floatFromInt(str.len)) * style.size * 0.55, .y = style.size * 1.32 };
        const m = layout.getMetrics();
        return .{
            .x = m.widthIncludingTrailingWhitespace,
            .y = @max(m.height, style.size * 1.25),
        };
    }

    /// Byte offset in `str` of the caret position nearest to the layout-relative point.
    pub fn caretFromPoint(self: *Renderer, str: []const u8, style: TextStyle, max_w: f32, pt: Vec2) usize {
        if (str.len == 0) return 0;
        const layout = self.layoutFor(str, style, max_w) orelse return str.len;
        const hit = layout.hitTestPoint(pt.x, pt.y);
        return byteOffsetOf(str, hit.index);
    }

    pub const Caret = struct { pos: Vec2, height: f32 };

    /// Layout-relative caret position before byte offset `byte` (handles wrapped lines).
    pub fn caretAt(self: *Renderer, str: []const u8, style: TextStyle, max_w: f32, byte: usize) Caret {
        const line_h = style.size * 1.32;
        if (str.len == 0) return .{ .pos = .{ .x = 0, .y = 0 }, .height = line_h };
        const layout = self.layoutFor(str, style, max_w) orelse return .{ .pos = .{ .x = 0, .y = 0 }, .height = line_h };
        const c = layout.hitTestTextPosition(utf16IndexOf(str, byte));
        return .{ .pos = .{ .x = c.x, .y = c.y }, .height = if (c.height > 0) c.height else line_h };
    }

    pub fn render(self: *Renderer, bg: Color, main_dl: *const DrawList, overlay_dl: *const DrawList, vsync: bool) void {
        self.frame_index +%= 1;
        defer self.trimLayoutCache();
        const dc = self.dc orelse return;
        dc.beginDraw();
        dc.setTransform(.{});
        dc.clear(bg.d2dColor());

        self.executeDrawList(main_dl);
        self.executeDrawList(overlay_dl);

        _ = dc.endDraw();
        if (self.swapchain) |sc| {
            _ = sc.present(if (vsync) 1 else 0, 0);
        }
        if (self.dcomp_device) |comp| {
            _ = comp.commit();
        }
    }

    fn executeDrawList(self: *Renderer, dl: *const DrawList) void {
        const dc = self.dc.?;
        const brush = self.solid_brush.?;
        const stroke = self.round_stroke;

        for (dl.cmds.items) |cmd| {
            switch (cmd) {
                .rect_filled => |c| {
                    brush.setColor(c.color.d2dColor());
                    if (c.rounding > 0.1) {
                        dc.fillRoundedRectangle(c.rect.d2dRounded(c.rounding), brush.asBrush());
                    } else {
                        dc.fillRectangle(c.rect.d2dRect(), brush.asBrush());
                    }
                },
                .rect_stroke => |c| {
                    brush.setColor(c.color.d2dColor());
                    const h = c.thickness * 0.5;
                    const inset = c.rect.expand(-h);
                    if (c.rounding > 0.1) {
                        dc.drawRoundedRectangle(inset.d2dRounded(@max(c.rounding - h, 0)), brush.asBrush(), c.thickness, null);
                    } else {
                        dc.drawRectangle(inset.d2dRect(), brush.asBrush(), c.thickness, null);
                    }
                },
                .gradient_rect => |c| {
                    const start = c.rect.min.d2dPt();
                    const end = if (c.horizontal)
                        d2d.D2D1_POINT_2F{ .x = c.rect.max.x, .y = c.rect.min.y }
                    else
                        d2d.D2D1_POINT_2F{ .x = c.rect.min.x, .y = c.rect.max.y };
                    if (dc.createLinearGradientBrush(start, end, c.from.d2dColor(), c.to.d2dColor())) |gb| {
                        defer {
                            var g: ?*d2d.ID2D1LinearGradientBrush = gb;
                            com.safeRelease(&g);
                        }
                        if (c.rounding > 0.1) {
                            dc.fillRoundedRectangle(c.rect.d2dRounded(c.rounding), gb.asBrush());
                        } else {
                            dc.fillRectangle(c.rect.d2dRect(), gb.asBrush());
                        }
                    }
                },
                .shadow => |c| {
                    const steps: usize = 7;
                    const base = c.rect.translate(.{ .x = 0, .y = c.offset_y });
                    var i: usize = 0;
                    while (i < steps) : (i += 1) {
                        const t = @as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(steps));
                        const grow = c.blur * (1.0 - t) + 0.5;
                        const alpha = c.color.a * (t * t) * (1.6 / @as(f32, @floatFromInt(steps)));
                        const rr = base.expand(grow - c.blur * 0.25);
                        brush.setColor(c.color.withAlpha(alpha).d2dColor());
                        dc.fillRoundedRectangle(rr.d2dRounded(c.rounding + grow), brush.asBrush());
                    }
                },
                .circle_filled => |c| {
                    brush.setColor(c.color.d2dColor());
                    dc.fillEllipse(.{ .point = c.center.d2dPt(), .radiusX = c.radius, .radiusY = c.radius }, brush.asBrush());
                },
                .circle_stroke => |c| {
                    brush.setColor(c.color.d2dColor());
                    dc.drawEllipse(.{ .point = c.center.d2dPt(), .radiusX = c.radius, .radiusY = c.radius }, brush.asBrush(), c.thickness, null);
                },
                .line => |c| {
                    brush.setColor(c.color.d2dColor());
                    dc.drawLine(c.a.d2dPt(), c.b.d2dPt(), brush.asBrush(), c.thickness, stroke);
                },
                .arc => |c| {
                    self.drawArcGeometry(c.center, c.radius, c.a0, c.a1, c.color, c.thickness);
                },
                .polyline => |c| {
                    const pts = dl.points.items[c.start .. c.start + c.count];
                    self.drawPolylineGeometry(pts, c.closed, c.color, c.thickness);
                },
                .polygon_filled => |c| {
                    const pts = dl.points.items[c.start .. c.start + c.count];
                    self.fillPolygonGeometry(pts, c.color);
                },
                .polygon_gradient => |c| {
                    const pts = dl.points.items[c.start .. c.start + c.count];
                    self.fillPolygonGradientGeometry(pts, c.y0, c.y1, c.from, c.to);
                },
                .text => |c| {
                    const str = dl.text_buf.items[c.start .. c.start + c.len];
                    self.drawTextCmd(c.pos, c.max_w, c.color, c.style, str);
                },
                .push_clip => |r| dc.pushAxisAlignedClip(r.d2dRect()),
                .pop_clip => dc.popAxisAlignedClip(),
            }
        }
    }

    fn drawArcGeometry(self: *Renderer, center: Vec2, radius: f32, a0: f32, a1: f32, col: Color, thickness: f32) void {
        const sweep = a1 - a0;
        if (@abs(sweep) < 1e-4) return;
        const geom = self.d2d_factory.?.createPathGeometry() orelse return;
        defer {
            var g: ?*d2d.ID2D1PathGeometry = geom;
            com.safeRelease(&g);
        }
        const sink = geom.open() orelse return;
        defer {
            var s: ?*d2d.ID2D1GeometrySink = sink;
            com.safeRelease(&s);
        }
        const p0: d2d.D2D1_POINT_2F = .{
            .x = center.x + @cos(a0) * radius,
            .y = center.y + @sin(a0) * radius,
        };
        sink.beginFigure(p0, d2d.D2D1_FIGURE_BEGIN_HOLLOW);
        // Split into 2 segments if sweep >= 180° for numerical stability
        const segs: usize = if (@abs(sweep) > std.math.pi) 2 else 1;
        var i: usize = 0;
        while (i < segs) : (i += 1) {
            const ang = a0 + sweep * @as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(segs));
            const seg: d2d.D2D1_ARC_SEGMENT = .{
                .point = .{ .x = center.x + @cos(ang) * radius, .y = center.y + @sin(ang) * radius },
                .size = .{ .width = radius, .height = radius },
                .sweepDirection = if (sweep >= 0) d2d.D2D1_SWEEP_DIRECTION_CLOCKWISE else d2d.D2D1_SWEEP_DIRECTION_COUNTER_CLOCKWISE,
                .arcSize = d2d.D2D1_ARC_SIZE_SMALL,
            };
            sink.addArc(&seg);
        }
        sink.endFigure(d2d.D2D1_FIGURE_END_OPEN);
        _ = sink.close();

        self.solid_brush.?.setColor(col.d2dColor());
        self.dc.?.drawGeometry(geom, self.solid_brush.?.asBrush(), thickness, self.round_stroke);
    }

    fn drawPolylineGeometry(self: *Renderer, pts: []const Vec2, closed: bool, col: Color, thickness: f32) void {
        const geom = self.d2d_factory.?.createPathGeometry() orelse return;
        defer {
            var g: ?*d2d.ID2D1PathGeometry = geom;
            com.safeRelease(&g);
        }
        const sink = geom.open() orelse return;
        defer {
            var s: ?*d2d.ID2D1GeometrySink = sink;
            com.safeRelease(&s);
        }
        sink.beginFigure(pts[0].d2dPt(), d2d.D2D1_FIGURE_BEGIN_HOLLOW);
        for (pts[1..]) |pt| sink.addLine(pt.d2dPt());
        sink.endFigure(if (closed) d2d.D2D1_FIGURE_END_CLOSED else d2d.D2D1_FIGURE_END_OPEN);
        _ = sink.close();

        self.solid_brush.?.setColor(col.d2dColor());
        self.dc.?.drawGeometry(geom, self.solid_brush.?.asBrush(), thickness, self.round_stroke);
    }

    fn fillPolygonGeometry(self: *Renderer, pts: []const Vec2, col: Color) void {
        const geom = self.d2d_factory.?.createPathGeometry() orelse return;
        defer {
            var g: ?*d2d.ID2D1PathGeometry = geom;
            com.safeRelease(&g);
        }
        const sink = geom.open() orelse return;
        defer {
            var s: ?*d2d.ID2D1GeometrySink = sink;
            com.safeRelease(&s);
        }
        sink.setFillMode(d2d.D2D1_FILL_MODE_WINDING);
        sink.beginFigure(pts[0].d2dPt(), d2d.D2D1_FIGURE_BEGIN_FILLED);
        for (pts[1..]) |pt| sink.addLine(pt.d2dPt());
        sink.endFigure(d2d.D2D1_FIGURE_END_CLOSED);
        _ = sink.close();

        self.solid_brush.?.setColor(col.d2dColor());
        self.dc.?.fillGeometry(geom, self.solid_brush.?.asBrush());
    }

    fn fillPolygonGradientGeometry(self: *Renderer, pts: []const Vec2, y0: f32, y1: f32, from: Color, to: Color) void {
        const geom = self.d2d_factory.?.createPathGeometry() orelse return;
        defer {
            var g: ?*d2d.ID2D1PathGeometry = geom;
            com.safeRelease(&g);
        }
        const sink = geom.open() orelse return;
        defer {
            var s: ?*d2d.ID2D1GeometrySink = sink;
            com.safeRelease(&s);
        }
        sink.setFillMode(d2d.D2D1_FILL_MODE_WINDING);
        sink.beginFigure(pts[0].d2dPt(), d2d.D2D1_FIGURE_BEGIN_FILLED);
        for (pts[1..]) |pt| sink.addLine(pt.d2dPt());
        sink.endFigure(d2d.D2D1_FIGURE_END_CLOSED);
        _ = sink.close();

        const dc = self.dc.?;
        if (dc.createLinearGradientBrush(.{ .x = 0, .y = y0 }, .{ .x = 0, .y = y1 }, from.d2dColor(), to.d2dColor())) |gb| {
            defer {
                var g: ?*d2d.ID2D1LinearGradientBrush = gb;
                com.safeRelease(&g);
            }
            dc.fillGeometry(geom, gb.asBrush());
        }
    }

    fn drawTextCmd(self: *Renderer, pos: Vec2, max_w: f32, col: Color, style: TextStyle, str: []const u8) void {
        const layout = self.layoutFor(str, style, max_w) orelse return;
        self.solid_brush.?.setColor(col.d2dColor());
        self.dc.?.drawTextLayout(pos.d2dPt(), layout, self.solid_brush.?.asBrush());
    }

    /// Reads back the swapchain backbuffer via a D3D11 staging texture and writes a 24-bit BMP.
    pub fn captureBmp(self: *Renderer, path: []const u8) bool {
        const sc = self.swapchain orelse return false;
        const dev = self.d3d_device orelse return false;
        const ctx = self.d3d_ctx orelse return false;

        const back = sc.getBufferTexture2D() orelse return false;
        defer {
            var b: ?*d3d.ID3D11Texture2D = back;
            com.safeRelease(&b);
        }

        const desc: d3d.D3D11_TEXTURE2D_DESC = .{
            .Width = self.pixel_w,
            .Height = self.pixel_h,
        };
        const staging = dev.createTexture2D(&desc) orelse return false;
        defer {
            var s: ?*d3d.ID3D11Texture2D = staging;
            com.safeRelease(&s);
        }

        ctx.copyResource(staging, back);
        var mapped: d3d.D3D11_MAPPED_SUBRESOURCE = .{};
        if (com.failed(ctx.mapRead(staging, &mapped))) return false;
        defer ctx.unmap(staging);

        const src: [*]const u8 = @ptrCast(mapped.pData orelse return false);
        const w = self.pixel_w;
        const h = self.pixel_h;
        const row_stride = ((w * 3 + 3) / 4) * 4;
        const pixel_bytes = row_stride * h;
        const file_size = 54 + pixel_bytes;

        const buf = self.allocator.alloc(u8, file_size) catch return false;
        defer self.allocator.free(buf);
        @memset(buf[0..54], 0);
        // BITMAPFILEHEADER
        buf[0] = 'B';
        buf[1] = 'M';
        std.mem.writeInt(u32, buf[2..6], file_size, .little);
        std.mem.writeInt(u32, buf[10..14], 54, .little);
        // BITMAPINFOHEADER
        std.mem.writeInt(u32, buf[14..18], 40, .little);
        std.mem.writeInt(i32, buf[18..22], @intCast(w), .little);
        std.mem.writeInt(i32, buf[22..26], @intCast(h), .little); // bottom-up
        std.mem.writeInt(u16, buf[26..28], 1, .little);
        std.mem.writeInt(u16, buf[28..30], 24, .little);
        std.mem.writeInt(u32, buf[34..38], pixel_bytes, .little);

        var y: u32 = 0;
        while (y < h) : (y += 1) {
            const src_row = src + (h - 1 - y) * mapped.RowPitch;
            const dst_row = buf[54 + y * row_stride ..];
            var x: u32 = 0;
            while (x < w) : (x += 1) {
                dst_row[x * 3 + 0] = src_row[x * 4 + 0]; // B
                dst_row[x * 3 + 1] = src_row[x * 4 + 1]; // G
                dst_row[x * 3 + 2] = src_row[x * 4 + 2]; // R
            }
        }

        return writeFileWin32(path, buf);
    }
};

extern "kernel32" fn CreateFileW(
    lpFileName: [*:0]const u16,
    dwDesiredAccess: u32,
    dwShareMode: u32,
    lpSecurityAttributes: ?*anyopaque,
    dwCreationDisposition: u32,
    dwFlagsAndAttributes: u32,
    hTemplateFile: ?win32.HANDLE,
) callconv(.winapi) isize;
extern "kernel32" fn WriteFile(
    hFile: isize,
    lpBuffer: [*]const u8,
    nNumberOfBytesToWrite: u32,
    lpNumberOfBytesWritten: *u32,
    lpOverlapped: ?*anyopaque,
) callconv(.winapi) i32;
extern "kernel32" fn CloseHandle(hObject: isize) callconv(.winapi) i32;

fn writeFileWin32(path: []const u8, data: []const u8) bool {
    var wbuf: [512]u16 = undefined;
    const wpath = win32.utf8ToUtf16Z(&wbuf, path);
    const GENERIC_WRITE: u32 = 0x40000000;
    const CREATE_ALWAYS: u32 = 2;
    const FILE_ATTRIBUTE_NORMAL: u32 = 0x80;
    const h = CreateFileW(wpath.ptr, GENERIC_WRITE, 0, null, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, null);
    if (h == -1) return false;
    defer _ = CloseHandle(h);
    var written: u32 = 0;
    return WriteFile(h, data.ptr, @intCast(data.len), &written, null) != 0 and written == data.len;
}

test "utf16 index mapping" {
    const s = "a中😀b";
    // a=1 unit, 中=1 unit, 😀=2 units (surrogate pair), b=1
    try std.testing.expectEqual(@as(u32, 0), utf16IndexOf(s, 0));
    try std.testing.expectEqual(@as(u32, 1), utf16IndexOf(s, 1));
    try std.testing.expectEqual(@as(u32, 2), utf16IndexOf(s, 4));
    try std.testing.expectEqual(@as(u32, 4), utf16IndexOf(s, 8));
    try std.testing.expectEqual(@as(usize, 4), byteOffsetOf(s, 2));
    try std.testing.expectEqual(@as(usize, 8), byteOffsetOf(s, 4));
    try std.testing.expectEqual(s.len, byteOffsetOf(s, 99));
}

test "lossy utf16 conversion" {
    var buf: [16]u16 = undefined;
    const out = Utf16Scratch.lossy(&buf, "a\xffb");
    try std.testing.expectEqual(@as(usize, 3), out.len);
    try std.testing.expectEqual(@as(u16, 0xFFFD), out[1]);
}
