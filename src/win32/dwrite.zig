//! Pure Zig DirectWrite COM bindings for high-DPI, CJK-fallback typography.
const com = @import("com.zig");

const HRESULT = com.HRESULT;
const GUID = com.GUID;
const IUnknownVTable = com.IUnknownVTable;

pub const IID_IDWriteFactory = GUID.init(0xb859ee5a, 0xd838, 0x4b5b, .{ 0xa2, 0xe8, 0x1a, 0xdc, 0x7d, 0x93, 0xdb, 0x48 });

pub const DWRITE_FACTORY_TYPE_SHARED: u32 = 0;

pub const DWRITE_FONT_WEIGHT_REGULAR: u32 = 400;
pub const DWRITE_FONT_WEIGHT_MEDIUM: u32 = 500;
pub const DWRITE_FONT_WEIGHT_SEMIBOLD: u32 = 600;
pub const DWRITE_FONT_WEIGHT_BOLD: u32 = 700;

pub const DWRITE_FONT_STYLE_NORMAL: u32 = 0;
pub const DWRITE_FONT_STRETCH_NORMAL: u32 = 5;

pub const DWRITE_WORD_WRAPPING_WRAP: u32 = 0;
pub const DWRITE_WORD_WRAPPING_NO_WRAP: u32 = 1;

pub const DWRITE_TEXT_ALIGNMENT_LEADING: u32 = 0;
pub const DWRITE_TEXT_ALIGNMENT_TRAILING: u32 = 1;
pub const DWRITE_TEXT_ALIGNMENT_CENTER: u32 = 2;

pub const DWRITE_PARAGRAPH_ALIGNMENT_NEAR: u32 = 0;
pub const DWRITE_PARAGRAPH_ALIGNMENT_FAR: u32 = 1;
pub const DWRITE_PARAGRAPH_ALIGNMENT_CENTER: u32 = 2;

pub const DWRITE_TEXT_METRICS = extern struct {
    left: f32 = 0,
    top: f32 = 0,
    width: f32 = 0,
    widthIncludingTrailingWhitespace: f32 = 0,
    height: f32 = 0,
    layoutWidth: f32 = 0,
    layoutHeight: f32 = 0,
    maxBidiReorderingDepth: u32 = 0,
    lineCount: u32 = 0,
};

pub const IDWriteTextFormat = extern struct {
    vtbl: *const VTable,

    pub const VTable = extern struct {
        base: IUnknownVTable,
        SetTextAlignment: *const fn (*IDWriteTextFormat, u32) callconv(.winapi) HRESULT, // 3
        SetParagraphAlignment: *const fn (*IDWriteTextFormat, u32) callconv(.winapi) HRESULT, // 4
        SetWordWrapping: *const fn (*IDWriteTextFormat, u32) callconv(.winapi) HRESULT, // 5
    };

    pub fn setTextAlignment(self: *IDWriteTextFormat, alignment: u32) void {
        _ = self.vtbl.SetTextAlignment(self, alignment);
    }

    pub fn setParagraphAlignment(self: *IDWriteTextFormat, alignment: u32) void {
        _ = self.vtbl.SetParagraphAlignment(self, alignment);
    }

    pub fn setWordWrapping(self: *IDWriteTextFormat, wrapping: u32) void {
        _ = self.vtbl.SetWordWrapping(self, wrapping);
    }
};

pub const IDWriteTextLayout = extern struct {
    vtbl: *const VTable,

    pub const VTable = extern struct {
        base: IUnknownVTable,
        // IDWriteTextFormat (3..27, 25 methods)
        _fmt: [25]*const anyopaque,
        // IDWriteTextLayout (28..59, 32 methods)
        _layout_pre: [32]*const anyopaque,
        // 60
        GetMetrics: *const fn (*IDWriteTextLayout, *DWRITE_TEXT_METRICS) callconv(.winapi) HRESULT,
    };

    pub fn getMetrics(self: *IDWriteTextLayout) DWRITE_TEXT_METRICS {
        var m: DWRITE_TEXT_METRICS = .{};
        _ = self.vtbl.GetMetrics(self, &m);
        return m;
    }
};

pub const IDWriteFactory = extern struct {
    vtbl: *const VTable,

    pub const VTable = extern struct {
        base: IUnknownVTable,
        // Slots 3..14 (12 methods)
        _pre_fmt: [12]*const anyopaque,
        // 15
        CreateTextFormat: *const fn (
            *IDWriteFactory,
            [*:0]const u16,
            ?*anyopaque,
            u32,
            u32,
            u32,
            f32,
            [*:0]const u16,
            *?*IDWriteTextFormat,
        ) callconv(.winapi) HRESULT,
        CreateTypography: *const anyopaque, // 16
        GetGdiInterop: *const anyopaque, // 17
        // 18
        CreateTextLayout: *const fn (
            *IDWriteFactory,
            [*]const u16,
            u32,
            *IDWriteTextFormat,
            f32,
            f32,
            *?*IDWriteTextLayout,
        ) callconv(.winapi) HRESULT,
    };

    pub fn createTextFormat(
        self: *IDWriteFactory,
        family: [*:0]const u16,
        weight: u32,
        size: f32,
        locale: [*:0]const u16,
    ) ?*IDWriteTextFormat {
        var out: ?*IDWriteTextFormat = null;
        if (com.succeeded(self.vtbl.CreateTextFormat(
            self,
            family,
            null,
            weight,
            DWRITE_FONT_STYLE_NORMAL,
            DWRITE_FONT_STRETCH_NORMAL,
            size,
            locale,
            &out,
        ))) return out;
        return null;
    }

    pub fn createTextLayout(
        self: *IDWriteFactory,
        text: []const u16,
        format: *IDWriteTextFormat,
        max_w: f32,
        max_h: f32,
    ) ?*IDWriteTextLayout {
        var out: ?*IDWriteTextLayout = null;
        if (com.succeeded(self.vtbl.CreateTextLayout(
            self,
            text.ptr,
            @intCast(text.len),
            format,
            max_w,
            max_h,
            &out,
        ))) return out;
        return null;
    }
};

pub extern "dwrite" fn DWriteCreateFactory(
    factoryType: u32,
    iid: *const GUID,
    factory: *?*anyopaque,
) callconv(.winapi) HRESULT;

pub fn createFactory() ?*IDWriteFactory {
    var out: ?*anyopaque = null;
    if (com.succeeded(DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, &IID_IDWriteFactory, &out))) {
        return @ptrCast(@alignCast(out));
    }
    return null;
}
