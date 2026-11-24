//! Pure Zig DirectComposition COM bindings.
const com = @import("com.zig");
const win32 = @import("win32.zig");
const d3d = @import("d3d_dxgi.zig");

const HRESULT = com.HRESULT;
const GUID = com.GUID;
const IUnknownVTable = com.IUnknownVTable;

pub const IID_IDCompositionDevice = GUID.init(0xC37EA93A, 0xE7AA, 0x450D, .{ 0xB1, 0x6F, 0x97, 0x46, 0xCB, 0x04, 0x07, 0xF3 });

pub const IDCompositionVisual = extern struct {
    vtbl: *const VTable,

    pub const VTable = extern struct {
        base: IUnknownVTable,
        // Slots 3..14: SetOffsetX(2), SetOffsetY(2), SetTransform(2), SetTransformParent,
        // SetEffect, SetBitmapInterpolationMode, SetBorderMode, SetClip(2)
        _pre_content: [12]*const anyopaque,
        // Slot 15
        SetContent: *const fn (*IDCompositionVisual, ?*anyopaque) callconv(.winapi) HRESULT,
    };

    pub fn setContent(self: *IDCompositionVisual, content: ?*anyopaque) HRESULT {
        return self.vtbl.SetContent(self, content);
    }
};

pub const IDCompositionTarget = extern struct {
    vtbl: *const VTable,

    pub const VTable = extern struct {
        base: IUnknownVTable,
        SetRoot: *const fn (*IDCompositionTarget, ?*IDCompositionVisual) callconv(.winapi) HRESULT,
    };

    pub fn setRoot(self: *IDCompositionTarget, visual: ?*IDCompositionVisual) HRESULT {
        return self.vtbl.SetRoot(self, visual);
    }
};

pub const IDCompositionDevice = extern struct {
    vtbl: *const VTable,

    pub const VTable = extern struct {
        base: IUnknownVTable,
        Commit: *const fn (*IDCompositionDevice) callconv(.winapi) HRESULT,
        WaitForCommitCompletion: *const anyopaque,
        GetFrameStatistics: *const anyopaque,
        CreateTargetForHwnd: *const fn (*IDCompositionDevice, win32.HWND, i32, *?*IDCompositionTarget) callconv(.winapi) HRESULT,
        CreateVisual: *const fn (*IDCompositionDevice, *?*IDCompositionVisual) callconv(.winapi) HRESULT,
    };

    pub fn commit(self: *IDCompositionDevice) HRESULT {
        return self.vtbl.Commit(self);
    }

    pub fn createTargetForHwnd(self: *IDCompositionDevice, hwnd: win32.HWND, topmost: bool) ?*IDCompositionTarget {
        var out: ?*IDCompositionTarget = null;
        if (com.succeeded(self.vtbl.CreateTargetForHwnd(self, hwnd, if (topmost) 1 else 0, &out))) return out;
        return null;
    }

    pub fn createVisual(self: *IDCompositionDevice) ?*IDCompositionVisual {
        var out: ?*IDCompositionVisual = null;
        if (com.succeeded(self.vtbl.CreateVisual(self, &out))) return out;
        return null;
    }
};

pub extern "dcomp" fn DCompositionCreateDevice(
    dxgiDevice: *d3d.IDXGIDevice,
    iid: *const GUID,
    dcompositionDevice: *?*anyopaque,
) callconv(.winapi) HRESULT;

pub fn createDevice(dxgi_device: *d3d.IDXGIDevice) ?*IDCompositionDevice {
    var out: ?*anyopaque = null;
    if (com.succeeded(DCompositionCreateDevice(dxgi_device, &IID_IDCompositionDevice, &out))) {
        return @ptrCast(@alignCast(out));
    }
    return null;
}
