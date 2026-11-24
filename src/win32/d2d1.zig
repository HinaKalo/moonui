//! Pure Zig Direct2D 1.1 COM bindings.
const com = @import("com.zig");
const d3d = @import("d3d_dxgi.zig");

const HRESULT = com.HRESULT;
const GUID = com.GUID;
const IUnknownVTable = com.IUnknownVTable;

pub const IID_ID2D1Factory1 = GUID.init(0xbb12d362, 0xdaee, 0x4b9a, .{ 0xaa, 0x1d, 0x14, 0xba, 0x40, 0x1c, 0xfa, 0x1f });

pub const D2D1_FACTORY_TYPE_SINGLE_THREADED: u32 = 0;
pub const D2D1_DEVICE_CONTEXT_OPTIONS_NONE: u32 = 0;

pub const D2D1_ALPHA_MODE_PREMULTIPLIED: u32 = 1;
pub const D2D1_BITMAP_OPTIONS_TARGET: u32 = 0x1;
pub const D2D1_BITMAP_OPTIONS_CANNOT_DRAW: u32 = 0x2;

pub const D2D1_ANTIALIAS_MODE_PER_PRIMITIVE: u32 = 0;
pub const D2D1_ANTIALIAS_MODE_ALIASED: u32 = 1;

pub const D2D1_TEXT_ANTIALIAS_MODE_DEFAULT: u32 = 0;
pub const D2D1_TEXT_ANTIALIAS_MODE_CLEARTYPE: u32 = 1;
pub const D2D1_TEXT_ANTIALIAS_MODE_GRAYSCALE: u32 = 2;

pub const D2D1_DRAW_TEXT_OPTIONS_NONE: u32 = 0;
pub const D2D1_DRAW_TEXT_OPTIONS_CLIP: u32 = 0x2;
pub const D2D1_DRAW_TEXT_OPTIONS_ENABLE_COLOR_FONT: u32 = 0x4;

pub const D2D1_CAP_STYLE_FLAT: u32 = 0;
pub const D2D1_CAP_STYLE_ROUND: u32 = 2;
pub const D2D1_LINE_JOIN_ROUND: u32 = 2;
pub const D2D1_DASH_STYLE_SOLID: u32 = 0;

pub const D2D1_GAMMA_2_2: u32 = 0;
pub const D2D1_EXTEND_MODE_CLAMP: u32 = 0;

pub const D2D1_FILL_MODE_ALTERNATE: u32 = 0;
pub const D2D1_FILL_MODE_WINDING: u32 = 1;

pub const D2D1_FIGURE_BEGIN_FILLED: u32 = 0;
pub const D2D1_FIGURE_BEGIN_HOLLOW: u32 = 1;

pub const D2D1_FIGURE_END_OPEN: u32 = 0;
pub const D2D1_FIGURE_END_CLOSED: u32 = 1;

pub const D2D1_SWEEP_DIRECTION_COUNTER_CLOCKWISE: u32 = 0;
pub const D2D1_SWEEP_DIRECTION_CLOCKWISE: u32 = 1;

pub const D2D1_ARC_SIZE_SMALL: u32 = 0;
pub const D2D1_ARC_SIZE_LARGE: u32 = 1;

pub const D2D1_POINT_2F = extern struct { x: f32, y: f32 };
pub const D2D1_SIZE_F = extern struct { width: f32, height: f32 };
pub const D2D1_RECT_F = extern struct { left: f32, top: f32, right: f32, bottom: f32 };
pub const D2D1_ROUNDED_RECT = extern struct { rect: D2D1_RECT_F, radiusX: f32, radiusY: f32 };
pub const D2D1_ELLIPSE = extern struct { point: D2D1_POINT_2F, radiusX: f32, radiusY: f32 };
pub const D2D1_COLOR_F = extern struct { r: f32, g: f32, b: f32, a: f32 };

pub const D2D1_MATRIX_3X2_F = extern struct {
    m11: f32 = 1,
    m12: f32 = 0,
    m21: f32 = 0,
    m22: f32 = 1,
    dx: f32 = 0,
    dy: f32 = 0,
};

pub const D2D1_PIXEL_FORMAT = extern struct {
    format: u32 = d3d.DXGI_FORMAT_B8G8R8A8_UNORM,
    alphaMode: u32 = D2D1_ALPHA_MODE_PREMULTIPLIED,
};

pub const D2D1_BITMAP_PROPERTIES1 = extern struct {
    pixelFormat: D2D1_PIXEL_FORMAT = .{},
    dpiX: f32 = 96.0,
    dpiY: f32 = 96.0,
    bitmapOptions: u32 = D2D1_BITMAP_OPTIONS_TARGET | D2D1_BITMAP_OPTIONS_CANNOT_DRAW,
    colorContext: ?*anyopaque = null,
};

pub const D2D1_STROKE_STYLE_PROPERTIES = extern struct {
    startCap: u32 = D2D1_CAP_STYLE_ROUND,
    endCap: u32 = D2D1_CAP_STYLE_ROUND,
    dashCap: u32 = D2D1_CAP_STYLE_ROUND,
    lineJoin: u32 = D2D1_LINE_JOIN_ROUND,
    miterLimit: f32 = 10.0,
    dashStyle: u32 = D2D1_DASH_STYLE_SOLID,
    dashOffset: f32 = 0.0,
};

pub const D2D1_GRADIENT_STOP = extern struct {
    position: f32,
    color: D2D1_COLOR_F,
};

pub const D2D1_LINEAR_GRADIENT_BRUSH_PROPERTIES = extern struct {
    startPoint: D2D1_POINT_2F,
    endPoint: D2D1_POINT_2F,
};

pub const D2D1_ARC_SEGMENT = extern struct {
    point: D2D1_POINT_2F,
    size: D2D1_SIZE_F,
    rotationAngle: f32 = 0,
    sweepDirection: u32 = D2D1_SWEEP_DIRECTION_CLOCKWISE,
    arcSize: u32 = D2D1_ARC_SIZE_SMALL,
};

pub const ID2D1Bitmap1 = extern struct {
    vtbl: *const IUnknownVTable,
};

pub const ID2D1Brush = extern struct {
    vtbl: *const IUnknownVTable,
};

pub const ID2D1StrokeStyle = extern struct {
    vtbl: *const IUnknownVTable,
};

pub const ID2D1GradientStopCollection = extern struct {
    vtbl: *const IUnknownVTable,
};

pub const ID2D1LinearGradientBrush = extern struct {
    vtbl: *const IUnknownVTable,

    pub fn asBrush(self: *ID2D1LinearGradientBrush) *ID2D1Brush {
        return @ptrCast(self);
    }
};

pub const ID2D1SolidColorBrush = extern struct {
    vtbl: *const VTable,

    pub const VTable = extern struct {
        base: IUnknownVTable,
        GetFactory: *const anyopaque,
        // ID2D1Brush (4..7)
        SetOpacity: *const fn (*ID2D1SolidColorBrush, f32) callconv(.winapi) void,
        SetTransform: *const anyopaque,
        GetOpacity: *const anyopaque,
        GetTransform: *const anyopaque,
        // ID2D1SolidColorBrush (8..9)
        SetColor: *const fn (*ID2D1SolidColorBrush, *const D2D1_COLOR_F) callconv(.winapi) void,
        GetColor: *const anyopaque,
    };

    pub fn setColor(self: *ID2D1SolidColorBrush, color: D2D1_COLOR_F) void {
        self.vtbl.SetColor(self, &color);
    }

    pub fn asBrush(self: *ID2D1SolidColorBrush) *ID2D1Brush {
        return @ptrCast(self);
    }
};

pub const ID2D1GeometrySink = extern struct {
    vtbl: *const VTable,

    pub const VTable = extern struct {
        base: IUnknownVTable,
        // ID2D1SimplifiedGeometrySink (3..9)
        SetFillMode: *const fn (*ID2D1GeometrySink, u32) callconv(.winapi) void,
        SetSegmentFlags: *const anyopaque,
        BeginFigure: *const fn (*ID2D1GeometrySink, D2D1_POINT_2F, u32) callconv(.winapi) void,
        AddLines: *const fn (*ID2D1GeometrySink, [*]const D2D1_POINT_2F, u32) callconv(.winapi) void,
        AddBeziers: *const anyopaque,
        EndFigure: *const fn (*ID2D1GeometrySink, u32) callconv(.winapi) void,
        Close: *const fn (*ID2D1GeometrySink) callconv(.winapi) HRESULT,
        // ID2D1GeometrySink (10..14)
        AddLine: *const fn (*ID2D1GeometrySink, D2D1_POINT_2F) callconv(.winapi) void,
        AddBezier: *const anyopaque,
        AddQuadraticBezier: *const anyopaque,
        AddQuadraticBeziers: *const anyopaque,
        AddArc: *const fn (*ID2D1GeometrySink, *const D2D1_ARC_SEGMENT) callconv(.winapi) void,
    };

    pub fn setFillMode(self: *ID2D1GeometrySink, mode: u32) void {
        self.vtbl.SetFillMode(self, mode);
    }
    pub fn beginFigure(self: *ID2D1GeometrySink, start: D2D1_POINT_2F, begin_type: u32) void {
        self.vtbl.BeginFigure(self, start, begin_type);
    }
    pub fn addLine(self: *ID2D1GeometrySink, pt: D2D1_POINT_2F) void {
        self.vtbl.AddLine(self, pt);
    }
    pub fn addLines(self: *ID2D1GeometrySink, pts: []const D2D1_POINT_2F) void {
        if (pts.len > 0) self.vtbl.AddLines(self, pts.ptr, @intCast(pts.len));
    }
    pub fn addArc(self: *ID2D1GeometrySink, seg: *const D2D1_ARC_SEGMENT) void {
        self.vtbl.AddArc(self, seg);
    }
    pub fn endFigure(self: *ID2D1GeometrySink, end_type: u32) void {
        self.vtbl.EndFigure(self, end_type);
    }
    pub fn close(self: *ID2D1GeometrySink) HRESULT {
        return self.vtbl.Close(self);
    }
};

pub const ID2D1PathGeometry = extern struct {
    vtbl: *const VTable,

    pub const VTable = extern struct {
        base: IUnknownVTable,
        GetFactory: *const anyopaque,
        // ID2D1Geometry (4..16, 13 methods)
        _geom: [13]*const anyopaque,
        // ID2D1PathGeometry (17)
        Open: *const fn (*ID2D1PathGeometry, *?*ID2D1GeometrySink) callconv(.winapi) HRESULT,
    };

    pub fn open(self: *ID2D1PathGeometry) ?*ID2D1GeometrySink {
        var out: ?*ID2D1GeometrySink = null;
        if (com.succeeded(self.vtbl.Open(self, &out))) return out;
        return null;
    }
};

pub const ID2D1DeviceContext = extern struct {
    vtbl: *const VTable,

    pub const VTable = extern struct {
        base: IUnknownVTable,
        GetFactory: *const anyopaque,
        // ID2D1RenderTarget (4..56)
        CreateBitmap: *const anyopaque, // 4
        CreateBitmapFromWicBitmap: *const anyopaque, // 5
        CreateSharedBitmap: *const anyopaque, // 6
        CreateBitmapBrush: *const anyopaque, // 7
        CreateSolidColorBrush: *const fn (*ID2D1DeviceContext, *const D2D1_COLOR_F, ?*const anyopaque, *?*ID2D1SolidColorBrush) callconv(.winapi) HRESULT, // 8
        CreateGradientStopCollection: *const fn (*ID2D1DeviceContext, [*]const D2D1_GRADIENT_STOP, u32, u32, u32, *?*ID2D1GradientStopCollection) callconv(.winapi) HRESULT, // 9
        CreateLinearGradientBrush: *const fn (*ID2D1DeviceContext, *const D2D1_LINEAR_GRADIENT_BRUSH_PROPERTIES, ?*const anyopaque, *ID2D1GradientStopCollection, *?*ID2D1LinearGradientBrush) callconv(.winapi) HRESULT, // 10
        CreateRadialGradientBrush: *const anyopaque, // 11
        CreateCompatibleRenderTarget: *const anyopaque, // 12
        CreateLayer: *const anyopaque, // 13
        CreateMesh: *const anyopaque, // 14
        DrawLine: *const fn (*ID2D1DeviceContext, D2D1_POINT_2F, D2D1_POINT_2F, *ID2D1Brush, f32, ?*ID2D1StrokeStyle) callconv(.winapi) void, // 15
        DrawRectangle: *const fn (*ID2D1DeviceContext, *const D2D1_RECT_F, *ID2D1Brush, f32, ?*ID2D1StrokeStyle) callconv(.winapi) void, // 16
        FillRectangle: *const fn (*ID2D1DeviceContext, *const D2D1_RECT_F, *ID2D1Brush) callconv(.winapi) void, // 17
        DrawRoundedRectangle: *const fn (*ID2D1DeviceContext, *const D2D1_ROUNDED_RECT, *ID2D1Brush, f32, ?*ID2D1StrokeStyle) callconv(.winapi) void, // 18
        FillRoundedRectangle: *const fn (*ID2D1DeviceContext, *const D2D1_ROUNDED_RECT, *ID2D1Brush) callconv(.winapi) void, // 19
        DrawEllipse: *const fn (*ID2D1DeviceContext, *const D2D1_ELLIPSE, *ID2D1Brush, f32, ?*ID2D1StrokeStyle) callconv(.winapi) void, // 20
        FillEllipse: *const fn (*ID2D1DeviceContext, *const D2D1_ELLIPSE, *ID2D1Brush) callconv(.winapi) void, // 21
        DrawGeometry: *const fn (*ID2D1DeviceContext, *ID2D1PathGeometry, *ID2D1Brush, f32, ?*ID2D1StrokeStyle) callconv(.winapi) void, // 22
        FillGeometry: *const fn (*ID2D1DeviceContext, *ID2D1PathGeometry, *ID2D1Brush, ?*ID2D1Brush) callconv(.winapi) void, // 23
        FillMesh: *const anyopaque, // 24
        FillOpacityMask: *const anyopaque, // 25
        DrawBitmap: *const anyopaque, // 26
        DrawText: *const fn (*ID2D1DeviceContext, [*]const u16, u32, *anyopaque, *const D2D1_RECT_F, *ID2D1Brush, u32, u32) callconv(.winapi) void, // 27
        DrawTextLayout: *const fn (*ID2D1DeviceContext, D2D1_POINT_2F, *anyopaque, *ID2D1Brush, u32) callconv(.winapi) void, // 28
        DrawGlyphRun: *const anyopaque, // 29
        SetTransform: *const fn (*ID2D1DeviceContext, *const D2D1_MATRIX_3X2_F) callconv(.winapi) void, // 30
        GetTransform: *const anyopaque, // 31
        SetAntialiasMode: *const fn (*ID2D1DeviceContext, u32) callconv(.winapi) void, // 32
        GetAntialiasMode: *const anyopaque, // 33
        SetTextAntialiasMode: *const fn (*ID2D1DeviceContext, u32) callconv(.winapi) void, // 34
        GetTextAntialiasMode: *const anyopaque, // 35
        SetTextRenderingParams: *const anyopaque, // 36
        GetTextRenderingParams: *const anyopaque, // 37
        SetTags: *const anyopaque, // 38
        GetTags: *const anyopaque, // 39
        PushLayer: *const anyopaque, // 40
        PopLayer: *const anyopaque, // 41
        Flush: *const anyopaque, // 42
        SaveDrawingState: *const anyopaque, // 43
        RestoreDrawingState: *const anyopaque, // 44
        PushAxisAlignedClip: *const fn (*ID2D1DeviceContext, *const D2D1_RECT_F, u32) callconv(.winapi) void, // 45
        PopAxisAlignedClip: *const fn (*ID2D1DeviceContext) callconv(.winapi) void, // 46
        Clear: *const fn (*ID2D1DeviceContext, ?*const D2D1_COLOR_F) callconv(.winapi) void, // 47
        BeginDraw: *const fn (*ID2D1DeviceContext) callconv(.winapi) void, // 48
        EndDraw: *const fn (*ID2D1DeviceContext, ?*u64, ?*u64) callconv(.winapi) HRESULT, // 49
        GetPixelFormat: *const anyopaque, // 50
        SetDpi: *const fn (*ID2D1DeviceContext, f32, f32) callconv(.winapi) void, // 51
        GetDpi: *const anyopaque, // 52
        GetSize: *const anyopaque, // 53
        GetPixelSize: *const anyopaque, // 54
        GetMaximumBitmapSize: *const anyopaque, // 55
        IsSupported: *const anyopaque, // 56
        // ID2D1DeviceContext (57..74)
        _dc_57_61: [5]*const anyopaque,
        CreateBitmapFromDxgiSurface: *const fn (*ID2D1DeviceContext, *d3d.IDXGISurface, ?*const D2D1_BITMAP_PROPERTIES1, *?*ID2D1Bitmap1) callconv(.winapi) HRESULT, // 62
        _dc_63_73: [11]*const anyopaque,
        SetTarget: *const fn (*ID2D1DeviceContext, ?*ID2D1Bitmap1) callconv(.winapi) void, // 74
    };

    pub fn createSolidColorBrush(self: *ID2D1DeviceContext, color: D2D1_COLOR_F) ?*ID2D1SolidColorBrush {
        var out: ?*ID2D1SolidColorBrush = null;
        if (com.succeeded(self.vtbl.CreateSolidColorBrush(self, &color, null, &out))) return out;
        return null;
    }

    pub fn createLinearGradientBrush(
        self: *ID2D1DeviceContext,
        start: D2D1_POINT_2F,
        end: D2D1_POINT_2F,
        from: D2D1_COLOR_F,
        to: D2D1_COLOR_F,
    ) ?*ID2D1LinearGradientBrush {
        const stops = [_]D2D1_GRADIENT_STOP{
            .{ .position = 0.0, .color = from },
            .{ .position = 1.0, .color = to },
        };
        var coll: ?*ID2D1GradientStopCollection = null;
        if (com.failed(self.vtbl.CreateGradientStopCollection(self, &stops, 2, D2D1_GAMMA_2_2, D2D1_EXTEND_MODE_CLAMP, &coll))) {
            return null;
        }
        defer com.safeRelease(&coll);
        const props: D2D1_LINEAR_GRADIENT_BRUSH_PROPERTIES = .{ .startPoint = start, .endPoint = end };
        var brush: ?*ID2D1LinearGradientBrush = null;
        if (com.succeeded(self.vtbl.CreateLinearGradientBrush(self, &props, null, coll.?, &brush))) {
            return brush;
        }
        return null;
    }

    pub fn createBitmapFromDxgiSurface(self: *ID2D1DeviceContext, surface: *d3d.IDXGISurface, props: *const D2D1_BITMAP_PROPERTIES1) ?*ID2D1Bitmap1 {
        var out: ?*ID2D1Bitmap1 = null;
        if (com.succeeded(self.vtbl.CreateBitmapFromDxgiSurface(self, surface, props, &out))) return out;
        return null;
    }

    pub fn setTarget(self: *ID2D1DeviceContext, target: ?*ID2D1Bitmap1) void {
        self.vtbl.SetTarget(self, target);
    }
    pub fn setDpi(self: *ID2D1DeviceContext, dpi_x: f32, dpi_y: f32) void {
        self.vtbl.SetDpi(self, dpi_x, dpi_y);
    }
    pub fn setTransform(self: *ID2D1DeviceContext, m: D2D1_MATRIX_3X2_F) void {
        self.vtbl.SetTransform(self, &m);
    }
    pub fn setAntialiasMode(self: *ID2D1DeviceContext, mode: u32) void {
        self.vtbl.SetAntialiasMode(self, mode);
    }
    pub fn setTextAntialiasMode(self: *ID2D1DeviceContext, mode: u32) void {
        self.vtbl.SetTextAntialiasMode(self, mode);
    }
    pub fn beginDraw(self: *ID2D1DeviceContext) void {
        self.vtbl.BeginDraw(self);
    }
    pub fn endDraw(self: *ID2D1DeviceContext) HRESULT {
        return self.vtbl.EndDraw(self, null, null);
    }
    pub fn clear(self: *ID2D1DeviceContext, color: D2D1_COLOR_F) void {
        self.vtbl.Clear(self, &color);
    }
    pub fn pushAxisAlignedClip(self: *ID2D1DeviceContext, rect: D2D1_RECT_F) void {
        self.vtbl.PushAxisAlignedClip(self, &rect, D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
    }
    pub fn popAxisAlignedClip(self: *ID2D1DeviceContext) void {
        self.vtbl.PopAxisAlignedClip(self);
    }
    pub fn drawLine(self: *ID2D1DeviceContext, a: D2D1_POINT_2F, b: D2D1_POINT_2F, brush: *ID2D1Brush, width: f32, style: ?*ID2D1StrokeStyle) void {
        self.vtbl.DrawLine(self, a, b, brush, width, style);
    }
    pub fn drawRectangle(self: *ID2D1DeviceContext, rect: D2D1_RECT_F, brush: *ID2D1Brush, width: f32, style: ?*ID2D1StrokeStyle) void {
        self.vtbl.DrawRectangle(self, &rect, brush, width, style);
    }
    pub fn fillRectangle(self: *ID2D1DeviceContext, rect: D2D1_RECT_F, brush: *ID2D1Brush) void {
        self.vtbl.FillRectangle(self, &rect, brush);
    }
    pub fn drawRoundedRectangle(self: *ID2D1DeviceContext, rr: D2D1_ROUNDED_RECT, brush: *ID2D1Brush, width: f32, style: ?*ID2D1StrokeStyle) void {
        self.vtbl.DrawRoundedRectangle(self, &rr, brush, width, style);
    }
    pub fn fillRoundedRectangle(self: *ID2D1DeviceContext, rr: D2D1_ROUNDED_RECT, brush: *ID2D1Brush) void {
        self.vtbl.FillRoundedRectangle(self, &rr, brush);
    }
    pub fn drawEllipse(self: *ID2D1DeviceContext, el: D2D1_ELLIPSE, brush: *ID2D1Brush, width: f32, style: ?*ID2D1StrokeStyle) void {
        self.vtbl.DrawEllipse(self, &el, brush, width, style);
    }
    pub fn fillEllipse(self: *ID2D1DeviceContext, el: D2D1_ELLIPSE, brush: *ID2D1Brush) void {
        self.vtbl.FillEllipse(self, &el, brush);
    }
    pub fn drawGeometry(self: *ID2D1DeviceContext, geom: *ID2D1PathGeometry, brush: *ID2D1Brush, width: f32, style: ?*ID2D1StrokeStyle) void {
        self.vtbl.DrawGeometry(self, geom, brush, width, style);
    }
    pub fn fillGeometry(self: *ID2D1DeviceContext, geom: *ID2D1PathGeometry, brush: *ID2D1Brush) void {
        self.vtbl.FillGeometry(self, geom, brush, null);
    }
    pub fn drawTextLayout(self: *ID2D1DeviceContext, origin: D2D1_POINT_2F, layout: *anyopaque, brush: *ID2D1Brush) void {
        self.vtbl.DrawTextLayout(self, origin, layout, brush, D2D1_DRAW_TEXT_OPTIONS_ENABLE_COLOR_FONT);
    }
};

pub const ID2D1Device = extern struct {
    vtbl: *const VTable,

    pub const VTable = extern struct {
        base: IUnknownVTable,
        GetFactory: *const anyopaque,
        CreateDeviceContext: *const fn (*ID2D1Device, u32, *?*ID2D1DeviceContext) callconv(.winapi) HRESULT,
    };

    pub fn createDeviceContext(self: *ID2D1Device) ?*ID2D1DeviceContext {
        var out: ?*ID2D1DeviceContext = null;
        if (com.succeeded(self.vtbl.CreateDeviceContext(self, D2D1_DEVICE_CONTEXT_OPTIONS_NONE, &out))) return out;
        return null;
    }
};

pub const ID2D1Factory1 = extern struct {
    vtbl: *const VTable,

    pub const VTable = extern struct {
        base: IUnknownVTable,
        // ID2D1Factory (3..16)
        _pre_path: [7]*const anyopaque, // 3..9
        CreatePathGeometry: *const fn (*ID2D1Factory1, *?*ID2D1PathGeometry) callconv(.winapi) HRESULT, // 10
        CreateStrokeStyle: *const fn (*ID2D1Factory1, *const D2D1_STROKE_STYLE_PROPERTIES, ?[*]const f32, u32, *?*ID2D1StrokeStyle) callconv(.winapi) HRESULT, // 11
        _post_stroke: [5]*const anyopaque, // 12..16
        // ID2D1Factory1 (17)
        CreateDevice: *const fn (*ID2D1Factory1, *d3d.IDXGIDevice, *?*ID2D1Device) callconv(.winapi) HRESULT, // 17
    };

    pub fn createDevice(self: *ID2D1Factory1, dxgi_device: *d3d.IDXGIDevice) ?*ID2D1Device {
        var out: ?*ID2D1Device = null;
        if (com.succeeded(self.vtbl.CreateDevice(self, dxgi_device, &out))) return out;
        return null;
    }

    pub fn createPathGeometry(self: *ID2D1Factory1) ?*ID2D1PathGeometry {
        var out: ?*ID2D1PathGeometry = null;
        if (com.succeeded(self.vtbl.CreatePathGeometry(self, &out))) return out;
        return null;
    }

    pub fn createStrokeStyle(self: *ID2D1Factory1, props: *const D2D1_STROKE_STYLE_PROPERTIES) ?*ID2D1StrokeStyle {
        var out: ?*ID2D1StrokeStyle = null;
        if (com.succeeded(self.vtbl.CreateStrokeStyle(self, props, null, 0, &out))) return out;
        return null;
    }
};

pub extern "d2d1" fn D2D1CreateFactory(
    factoryType: u32,
    riid: *const GUID,
    pFactoryOptions: ?*const anyopaque,
    ppIFactory: *?*anyopaque,
) callconv(.winapi) HRESULT;

pub fn createFactory1() ?*ID2D1Factory1 {
    var out: ?*anyopaque = null;
    if (com.succeeded(D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, &IID_ID2D1Factory1, null, &out))) {
        return @ptrCast(@alignCast(out));
    }
    return null;
}
