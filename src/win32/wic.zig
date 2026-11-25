//! Pure Zig Windows Imaging Component (WIC) COM bindings: decoders, format
//! converter, scaler, PNG encoder and memory streams.
const std = @import("std");
const com = @import("com.zig");

const HRESULT = com.HRESULT;
const GUID = com.GUID;
const IUnknownVTable = com.IUnknownVTable;

pub const CLSID_WICImagingFactory = GUID.init(0xcacaf262, 0x9370, 0x4615, .{ 0xa1, 0x3b, 0x9f, 0x55, 0x39, 0xda, 0x4c, 0x0a });
pub const IID_IWICImagingFactory = GUID.init(0xec5ec8a9, 0xc395, 0x4314, .{ 0x9c, 0x77, 0x54, 0xd7, 0xa9, 0x35, 0xff, 0x70 });

pub const GUID_WICPixelFormat32bppPBGRA = GUID.init(0x6fddc324, 0x4e03, 0x4bfe, .{ 0xb1, 0x85, 0x3d, 0x77, 0x76, 0x8d, 0xc9, 0x10 });
pub const GUID_WICPixelFormat32bppBGRA = GUID.init(0x6fddc324, 0x4e03, 0x4bfe, .{ 0xb1, 0x85, 0x3d, 0x77, 0x76, 0x8d, 0xc9, 0x0f });
pub const GUID_WICPixelFormat24bppBGR = GUID.init(0x6fddc324, 0x4e03, 0x4bfe, .{ 0xb1, 0x85, 0x3d, 0x77, 0x76, 0x8d, 0xc9, 0x0c });
pub const GUID_ContainerFormatJpeg = GUID.init(0x19e4a5aa, 0x5662, 0x4fc5, .{ 0xa0, 0xc0, 0x17, 0x58, 0x02, 0x8e, 0x10, 0x57 });
pub const GUID_ContainerFormatPng = GUID.init(0x1b7cfaf4, 0x713f, 0x473c, .{ 0xbb, 0xcd, 0x61, 0x37, 0x42, 0x5f, 0xae, 0xaf });

pub const CLSCTX_INPROC_SERVER: u32 = 0x1;
pub const COINIT_MULTITHREADED: u32 = 0x0;
pub const RPC_E_CHANGED_MODE: HRESULT = @bitCast(@as(u32, 0x80010106));

pub const WICDecodeMetadataCacheOnDemand: u32 = 0;
pub const WICBitmapDitherTypeNone: u32 = 0;
pub const WICBitmapPaletteTypeCustom: u32 = 0;
pub const WICBitmapInterpolationModeFant: u32 = 3;
pub const WICBitmapEncoderNoCache: u32 = 2;

pub const STREAM_SEEK_SET: u32 = 0;
pub const STREAM_SEEK_CUR: u32 = 1;

pub const WICRect = extern struct { X: i32, Y: i32, Width: i32, Height: i32 };

/// IStream (ISequentialStream + IStream), only the calls used here.
pub const IStream = extern struct {
    vtbl: *const VTable,

    pub const VTable = extern struct {
        base: IUnknownVTable,
        Read: *const fn (*IStream, [*]u8, u32, ?*u32) callconv(.winapi) HRESULT, // 3
        Write: *const fn (*IStream, [*]const u8, u32, ?*u32) callconv(.winapi) HRESULT, // 4
        Seek: *const fn (*IStream, i64, u32, ?*u64) callconv(.winapi) HRESULT, // 5
        _rest: [8]*const anyopaque, // 6..13
    };

    pub fn seek(self: *IStream, offset: i64, origin: u32) ?u64 {
        var pos: u64 = 0;
        if (com.failed(self.vtbl.Seek(self, offset, origin, &pos))) return null;
        return pos;
    }

    pub fn read(self: *IStream, buf: []u8) ?usize {
        var n: u32 = 0;
        if (com.failed(self.vtbl.Read(self, buf.ptr, @intCast(buf.len), &n))) return null;
        return n;
    }
};

/// IWICStream: an IStream that can wrap a memory block.
pub const IWICStream = extern struct {
    vtbl: *const VTable,

    pub const VTable = extern struct {
        base: IUnknownVTable,
        _istream: [11]*const anyopaque, // 3..13
        InitializeFromIStream: *const anyopaque, // 14
        InitializeFromFilename: *const anyopaque, // 15
        InitializeFromMemory: *const fn (*IWICStream, [*]const u8, u32) callconv(.winapi) HRESULT, // 16
        InitializeFromIStreamRegion: *const anyopaque, // 17
    };

    pub fn initializeFromMemory(self: *IWICStream, bytes: []const u8) bool {
        return com.succeeded(self.vtbl.InitializeFromMemory(self, bytes.ptr, @intCast(bytes.len)));
    }
};

/// IWICBitmapSource (and the frame decode / converter / scaler that extend it).
pub const IWICBitmapSource = extern struct {
    vtbl: *const VTable,

    pub const VTable = extern struct {
        base: IUnknownVTable,
        GetSize: *const fn (*IWICBitmapSource, *u32, *u32) callconv(.winapi) HRESULT, // 3
        GetPixelFormat: *const fn (*IWICBitmapSource, *GUID) callconv(.winapi) HRESULT, // 4
        GetResolution: *const anyopaque, // 5
        CopyPalette: *const anyopaque, // 6
        CopyPixels: *const fn (*IWICBitmapSource, ?*const WICRect, u32, u32, [*]u8) callconv(.winapi) HRESULT, // 7
    };

    pub fn getSize(self: *IWICBitmapSource) ?[2]u32 {
        var w: u32 = 0;
        var h: u32 = 0;
        if (com.failed(self.vtbl.GetSize(self, &w, &h))) return null;
        return .{ w, h };
    }

    pub fn copyPixels(self: *IWICBitmapSource, stride: u32, out: []u8) bool {
        return com.succeeded(self.vtbl.CopyPixels(self, null, stride, @intCast(out.len), out.ptr));
    }
};

pub const IWICBitmapDecoder = extern struct {
    vtbl: *const VTable,

    pub const VTable = extern struct {
        base: IUnknownVTable,
        _pre: [9]*const anyopaque, // 3..11
        GetFrameCount: *const fn (*IWICBitmapDecoder, *u32) callconv(.winapi) HRESULT, // 12
        GetFrame: *const fn (*IWICBitmapDecoder, u32, *?*IWICBitmapSource) callconv(.winapi) HRESULT, // 13
    };

    /// The frame (an IWICBitmapFrameDecode, used as its IWICBitmapSource base).
    pub fn getFrame(self: *IWICBitmapDecoder, index: u32) ?*IWICBitmapSource {
        var out: ?*IWICBitmapSource = null;
        if (com.failed(self.vtbl.GetFrame(self, index, &out))) return null;
        return out;
    }
};

pub const IWICFormatConverter = extern struct {
    vtbl: *const VTable,

    pub const VTable = extern struct {
        base: IUnknownVTable,
        _source: [5]*const anyopaque, // 3..7
        Initialize: *const fn (*IWICFormatConverter, *IWICBitmapSource, *const GUID, u32, ?*anyopaque, f64, u32) callconv(.winapi) HRESULT, // 8
        CanConvert: *const anyopaque, // 9
    };

    pub fn initialize(self: *IWICFormatConverter, src: *IWICBitmapSource, format: *const GUID) bool {
        return com.succeeded(self.vtbl.Initialize(self, src, format, WICBitmapDitherTypeNone, null, 0, WICBitmapPaletteTypeCustom));
    }

    pub fn asSource(self: *IWICFormatConverter) *IWICBitmapSource {
        return @ptrCast(self);
    }
};

pub const IWICBitmapScaler = extern struct {
    vtbl: *const VTable,

    pub const VTable = extern struct {
        base: IUnknownVTable,
        _source: [5]*const anyopaque, // 3..7
        Initialize: *const fn (*IWICBitmapScaler, *IWICBitmapSource, u32, u32, u32) callconv(.winapi) HRESULT, // 8
    };

    pub fn initialize(self: *IWICBitmapScaler, src: *IWICBitmapSource, w: u32, h: u32) bool {
        return com.succeeded(self.vtbl.Initialize(self, src, w, h, WICBitmapInterpolationModeFant));
    }

    pub fn asSource(self: *IWICBitmapScaler) *IWICBitmapSource {
        return @ptrCast(self);
    }
};

pub const IWICBitmapFlipRotator = extern struct {
    vtbl: *const VTable,

    pub const VTable = extern struct {
        base: IUnknownVTable,
        _source: [5]*const anyopaque, // 3..7
        Initialize: *const fn (*IWICBitmapFlipRotator, *IWICBitmapSource, u32) callconv(.winapi) HRESULT, // 8
    };

    pub fn initialize(self: *IWICBitmapFlipRotator, src: *IWICBitmapSource, options: u32) bool {
        return com.succeeded(self.vtbl.Initialize(self, src, options));
    }

    pub fn asSource(self: *IWICBitmapFlipRotator) *IWICBitmapSource {
        return @ptrCast(self);
    }
};

pub const WICBitmapTransformRotate90: u32 = 1;
pub const WICBitmapTransformRotate180: u32 = 2;
pub const WICBitmapTransformRotate270: u32 = 3;
pub const WICBitmapTransformFlipHorizontal: u32 = 8;
pub const WICBitmapTransformFlipVertical: u32 = 0x10;

/// PROPVARIANT (24 bytes on 64-bit Windows); only small integer values are read.
pub const PROPVARIANT = extern struct {
    vt: u16 = 0,
    r1: u16 = 0,
    r2: u16 = 0,
    r3: u16 = 0,
    data: [16]u8 = @splat(0),
};
pub const VT_UI2: u16 = 18;

pub const IWICMetadataQueryReader = extern struct {
    vtbl: *const VTable,

    pub const VTable = extern struct {
        base: IUnknownVTable,
        GetContainerFormat: *const anyopaque, // 3
        GetLocation: *const anyopaque, // 4
        GetMetadataByName: *const fn (*IWICMetadataQueryReader, [*:0]const u16, *PROPVARIANT) callconv(.winapi) HRESULT, // 5
    };
};

/// IWICBitmapFrameDecode: a bitmap source with metadata.
pub const IWICBitmapFrameDecode = extern struct {
    vtbl: *const VTable,

    pub const VTable = extern struct {
        base: IUnknownVTable,
        _source: [5]*const anyopaque, // 3..7
        GetMetadataQueryReader: *const fn (*IWICBitmapFrameDecode, *?*IWICMetadataQueryReader) callconv(.winapi) HRESULT, // 8
    };

    /// EXIF orientation (1..8) of a JPEG frame; 1 when absent.
    pub fn exifOrientation(self: *IWICBitmapFrameDecode) u16 {
        var reader: ?*IWICMetadataQueryReader = null;
        if (com.failed(self.vtbl.GetMetadataQueryReader(self, &reader))) return 1;
        defer com.safeRelease(&reader);
        const name = std.unicode.utf8ToUtf16LeStringLiteral("/app1/ifd/{ushort=274}");
        var pv: PROPVARIANT = .{};
        if (com.failed(reader.?.vtbl.GetMetadataByName(reader.?, name, &pv))) return 1;
        defer _ = PropVariantClear(&pv);
        if (pv.vt != VT_UI2) return 1;
        const v = std.mem.readInt(u16, pv.data[0..2], .little);
        return if (v >= 1 and v <= 8) v else 1;
    }
};

pub extern "ole32" fn PropVariantClear(pvar: *PROPVARIANT) callconv(.winapi) HRESULT;

pub const IWICBitmapFrameEncode = extern struct {
    vtbl: *const VTable,

    pub const VTable = extern struct {
        base: IUnknownVTable,
        Initialize: *const fn (*IWICBitmapFrameEncode, ?*IPropertyBag2) callconv(.winapi) HRESULT, // 3
        SetSize: *const fn (*IWICBitmapFrameEncode, u32, u32) callconv(.winapi) HRESULT, // 4
        SetResolution: *const anyopaque, // 5
        SetPixelFormat: *const fn (*IWICBitmapFrameEncode, *GUID) callconv(.winapi) HRESULT, // 6
        SetColorContexts: *const anyopaque, // 7
        SetPalette: *const anyopaque, // 8
        SetThumbnail: *const anyopaque, // 9
        WritePixels: *const fn (*IWICBitmapFrameEncode, u32, u32, u32, [*]const u8) callconv(.winapi) HRESULT, // 10
        WriteSource: *const anyopaque, // 11
        Commit: *const fn (*IWICBitmapFrameEncode) callconv(.winapi) HRESULT, // 12
    };
};

pub const PROPBAG2 = extern struct {
    dwType: u32 = 0,
    vt: u16 = 0,
    cfType: u16 = 0,
    dwHint: u32 = 0,
    pstrName: ?[*:0]const u16 = null,
    clsid: GUID = GUID.init(0, 0, 0, .{ 0, 0, 0, 0, 0, 0, 0, 0 }),
};

/// VARIANT (24 bytes on 64-bit Windows); only VT_R4 is written here.
pub const VARIANT = extern struct {
    vt: u16 = 0,
    r1: u16 = 0,
    r2: u16 = 0,
    r3: u16 = 0,
    data: [16]u8 = @splat(0),
};
pub const VT_R4: u16 = 4;

/// Encoder options ("ImageQuality" for JPEG).
pub const IPropertyBag2 = extern struct {
    vtbl: *const VTable,

    pub const VTable = extern struct {
        base: IUnknownVTable,
        Read: *const anyopaque, // 3
        Write: *const fn (*IPropertyBag2, u32, *const PROPBAG2, *const VARIANT) callconv(.winapi) HRESULT, // 4
    };

    pub fn writeFloat(self: *IPropertyBag2, name: [*:0]const u16, value: f32) bool {
        const prop: PROPBAG2 = .{ .vt = VT_R4, .pstrName = name };
        var v: VARIANT = .{ .vt = VT_R4 };
        std.mem.writeInt(u32, v.data[0..4], @bitCast(value), .little);
        return com.succeeded(self.vtbl.Write(self, 1, &prop, &v));
    }
};

pub const IWICBitmapEncoder = extern struct {
    vtbl: *const VTable,

    pub const VTable = extern struct {
        base: IUnknownVTable,
        Initialize: *const fn (*IWICBitmapEncoder, *IStream, u32) callconv(.winapi) HRESULT, // 3
        _mid: [6]*const anyopaque, // 4..9
        CreateNewFrame: *const fn (*IWICBitmapEncoder, *?*IWICBitmapFrameEncode, ?*?*IPropertyBag2) callconv(.winapi) HRESULT, // 10
        Commit: *const fn (*IWICBitmapEncoder) callconv(.winapi) HRESULT, // 11
    };
};

pub const IWICImagingFactory = extern struct {
    vtbl: *const VTable,

    pub const VTable = extern struct {
        base: IUnknownVTable,
        CreateDecoderFromFilename: *const anyopaque, // 3
        CreateDecoderFromStream: *const fn (*IWICImagingFactory, *IWICStream, ?*const GUID, u32, *?*IWICBitmapDecoder) callconv(.winapi) HRESULT, // 4
        CreateDecoderFromFileHandle: *const anyopaque, // 5
        CreateComponentInfo: *const anyopaque, // 6
        CreateDecoder: *const anyopaque, // 7
        CreateEncoder: *const fn (*IWICImagingFactory, *const GUID, ?*const GUID, *?*IWICBitmapEncoder) callconv(.winapi) HRESULT, // 8
        CreatePalette: *const anyopaque, // 9
        CreateFormatConverter: *const fn (*IWICImagingFactory, *?*IWICFormatConverter) callconv(.winapi) HRESULT, // 10
        CreateBitmapScaler: *const fn (*IWICImagingFactory, *?*IWICBitmapScaler) callconv(.winapi) HRESULT, // 11
        CreateBitmapClipper: *const anyopaque, // 12
        CreateBitmapFlipRotator: *const fn (*IWICImagingFactory, *?*IWICBitmapFlipRotator) callconv(.winapi) HRESULT, // 13
        CreateStream: *const fn (*IWICImagingFactory, *?*IWICStream) callconv(.winapi) HRESULT, // 14
    };

    pub fn createStream(self: *IWICImagingFactory) ?*IWICStream {
        var out: ?*IWICStream = null;
        if (com.failed(self.vtbl.CreateStream(self, &out))) return null;
        return out;
    }
    pub fn createDecoderFromStream(self: *IWICImagingFactory, stream: *IWICStream) ?*IWICBitmapDecoder {
        var out: ?*IWICBitmapDecoder = null;
        if (com.failed(self.vtbl.CreateDecoderFromStream(self, stream, null, WICDecodeMetadataCacheOnDemand, &out))) return null;
        return out;
    }
    pub fn createFormatConverter(self: *IWICImagingFactory) ?*IWICFormatConverter {
        var out: ?*IWICFormatConverter = null;
        if (com.failed(self.vtbl.CreateFormatConverter(self, &out))) return null;
        return out;
    }
    pub fn createBitmapScaler(self: *IWICImagingFactory) ?*IWICBitmapScaler {
        var out: ?*IWICBitmapScaler = null;
        if (com.failed(self.vtbl.CreateBitmapScaler(self, &out))) return null;
        return out;
    }
    pub fn createFlipRotator(self: *IWICImagingFactory) ?*IWICBitmapFlipRotator {
        var out: ?*IWICBitmapFlipRotator = null;
        if (com.failed(self.vtbl.CreateBitmapFlipRotator(self, &out))) return null;
        return out;
    }
    pub fn createEncoder(self: *IWICImagingFactory, container: *const GUID) ?*IWICBitmapEncoder {
        var out: ?*IWICBitmapEncoder = null;
        if (com.failed(self.vtbl.CreateEncoder(self, container, null, &out))) return null;
        return out;
    }
};

pub extern "ole32" fn CoCreateInstance(rclsid: *const GUID, pUnkOuter: ?*anyopaque, dwClsContext: u32, riid: *const GUID, ppv: *?*anyopaque) callconv(.winapi) HRESULT;
pub extern "ole32" fn CreateStreamOnHGlobal(hGlobal: ?*anyopaque, fDeleteOnRelease: i32, ppstm: *?*IStream) callconv(.winapi) HRESULT;

pub fn createFactory() ?*IWICImagingFactory {
    var out: ?*anyopaque = null;
    if (com.failed(CoCreateInstance(&CLSID_WICImagingFactory, null, CLSCTX_INPROC_SERVER, &IID_IWICImagingFactory, &out))) return null;
    return @ptrCast(@alignCast(out));
}
