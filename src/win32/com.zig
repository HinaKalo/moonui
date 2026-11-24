//! Minimal COM primitives for pure-Zig Windows API bindings.
const std = @import("std");

pub const HRESULT = i32;
pub const ULONG = u32;
pub const BOOL = i32;

pub const S_OK: HRESULT = 0;

pub inline fn succeeded(hr: HRESULT) bool {
    return hr >= 0;
}

pub inline fn failed(hr: HRESULT) bool {
    return hr < 0;
}

pub const GUID = extern struct {
    Data1: u32,
    Data2: u16,
    Data3: u16,
    Data4: [8]u8,

    pub fn init(d1: u32, d2: u16, d3: u16, d4: [8]u8) GUID {
        return .{ .Data1 = d1, .Data2 = d2, .Data3 = d3, .Data4 = d4 };
    }
};

pub const IUnknownVTable = extern struct {
    QueryInterface: *const fn (*anyopaque, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    AddRef: *const fn (*anyopaque) callconv(.winapi) ULONG,
    Release: *const fn (*anyopaque) callconv(.winapi) ULONG,
};

pub const IUnknown = extern struct {
    vtbl: *const IUnknownVTable,

    pub fn queryInterface(self: *IUnknown, comptime T: type, iid: *const GUID) ?*T {
        var out: ?*anyopaque = null;
        if (succeeded(self.vtbl.QueryInterface(self, iid, &out))) {
            return @ptrCast(@alignCast(out));
        }
        return null;
    }

    pub fn addRef(self: *IUnknown) ULONG {
        return self.vtbl.AddRef(self);
    }

    pub fn release(self: *IUnknown) ULONG {
        return self.vtbl.Release(self);
    }
};

pub fn safeRelease(ptr: anytype) void {
    if (ptr.*) |p| {
        const unk: *IUnknown = @ptrCast(@alignCast(p));
        _ = unk.release();
        ptr.* = null;
    }
}

pub const COINIT_APARTMENTTHREADED: u32 = 0x2;
pub const COINIT_DISABLE_OLE1DDE: u32 = 0x4;

pub extern "ole32" fn CoInitializeEx(pvReserved: ?*anyopaque, dwCoInit: u32) callconv(.winapi) HRESULT;
pub extern "ole32" fn CoUninitialize() callconv(.winapi) void;
