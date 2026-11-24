//! Pure Zig Direct3D 11 & DXGI 1.2 COM bindings for Direct2D + DirectComposition.
const com = @import("com.zig");
const HRESULT = com.HRESULT;
const GUID = com.GUID;
const IUnknownVTable = com.IUnknownVTable;

pub const IID_IDXGIDevice = GUID.init(0x54ec77fa, 0x1377, 0x44e6, .{ 0x8c, 0x32, 0x88, 0xfd, 0x5f, 0x44, 0xc8, 0x4c });
pub const IID_IDXGIAdapter = GUID.init(0x2411e7e1, 0x12ac, 0x4ccf, .{ 0xbd, 0x14, 0x97, 0x98, 0xe8, 0x53, 0x4d, 0xc0 });
pub const IID_IDXGIFactory2 = GUID.init(0x50c83a1c, 0xe072, 0x4c48, .{ 0x87, 0xb0, 0x36, 0x30, 0xfa, 0x36, 0xa6, 0xd0 });
pub const IID_IDXGISurface = GUID.init(0xcafcb56c, 0x6ac3, 0x4889, .{ 0xbf, 0x47, 0x9e, 0x23, 0xbb, 0xd2, 0x60, 0xec });
pub const IID_ID3D11Texture2D = GUID.init(0x6f15aaf2, 0xd208, 0x4e89, .{ 0x9a, 0xb4, 0x48, 0x95, 0x35, 0xd3, 0x4f, 0x9c });

pub const D3D_DRIVER_TYPE_HARDWARE: u32 = 1;
pub const D3D_DRIVER_TYPE_WARP: u32 = 5;
pub const D3D11_CREATE_DEVICE_BGRA_SUPPORT: u32 = 0x20;
pub const D3D11_SDK_VERSION: u32 = 7;

pub const DXGI_FORMAT_UNKNOWN: u32 = 0;
pub const DXGI_FORMAT_B8G8R8A8_UNORM: u32 = 87;

pub const DXGI_USAGE_RENDER_TARGET_OUTPUT: u32 = 1 << (1 + 4);
pub const DXGI_SCALING_STRETCH: u32 = 0;
pub const DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL: u32 = 3;
pub const DXGI_ALPHA_MODE_PREMULTIPLIED: u32 = 1;
pub const DXGI_ALPHA_MODE_IGNORE: u32 = 3;

pub const D3D11_USAGE_STAGING: u32 = 3;
pub const D3D11_CPU_ACCESS_READ: u32 = 0x20000;
pub const D3D11_MAP_READ: u32 = 1;

pub const DXGI_SAMPLE_DESC = extern struct {
    Count: u32 = 1,
    Quality: u32 = 0,
};

pub const DXGI_SWAP_CHAIN_DESC1 = extern struct {
    Width: u32 = 0,
    Height: u32 = 0,
    Format: u32 = DXGI_FORMAT_B8G8R8A8_UNORM,
    Stereo: i32 = 0,
    SampleDesc: DXGI_SAMPLE_DESC = .{},
    BufferUsage: u32 = DXGI_USAGE_RENDER_TARGET_OUTPUT,
    BufferCount: u32 = 2,
    Scaling: u32 = DXGI_SCALING_STRETCH,
    SwapEffect: u32 = DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL,
    AlphaMode: u32 = DXGI_ALPHA_MODE_PREMULTIPLIED,
    Flags: u32 = 0,
};

pub const D3D11_TEXTURE2D_DESC = extern struct {
    Width: u32,
    Height: u32,
    MipLevels: u32 = 1,
    ArraySize: u32 = 1,
    Format: u32 = DXGI_FORMAT_B8G8R8A8_UNORM,
    SampleDesc: DXGI_SAMPLE_DESC = .{},
    Usage: u32 = D3D11_USAGE_STAGING,
    BindFlags: u32 = 0,
    CPUAccessFlags: u32 = D3D11_CPU_ACCESS_READ,
    MiscFlags: u32 = 0,
};

pub const D3D11_MAPPED_SUBRESOURCE = extern struct {
    pData: ?*anyopaque = null,
    RowPitch: u32 = 0,
    DepthPitch: u32 = 0,
};

pub const ID3D11Texture2D = extern struct {
    vtbl: *const IUnknownVTable,
};

pub const ID3D11Device = extern struct {
    vtbl: *const VTable,

    pub const VTable = extern struct {
        base: IUnknownVTable,
        CreateBuffer: *const anyopaque,
        CreateTexture1D: *const anyopaque,
        CreateTexture2D: *const fn (*ID3D11Device, *const D3D11_TEXTURE2D_DESC, ?*const anyopaque, *?*ID3D11Texture2D) callconv(.winapi) HRESULT,
    };

    pub fn createTexture2D(self: *ID3D11Device, desc: *const D3D11_TEXTURE2D_DESC) ?*ID3D11Texture2D {
        var out: ?*ID3D11Texture2D = null;
        if (com.succeeded(self.vtbl.CreateTexture2D(self, desc, null, &out))) return out;
        return null;
    }
};

pub const ID3D11DeviceContext = extern struct {
    vtbl: *const VTable,

    pub const VTable = extern struct {
        base: IUnknownVTable,
        // ID3D11DeviceChild (3..6)
        _child: [4]*const anyopaque,
        // ID3D11DeviceContext (7..13)
        _pre_map: [7]*const anyopaque,
        // 14, 15
        Map: *const fn (*ID3D11DeviceContext, *anyopaque, u32, u32, u32, *D3D11_MAPPED_SUBRESOURCE) callconv(.winapi) HRESULT,
        Unmap: *const fn (*ID3D11DeviceContext, *anyopaque, u32) callconv(.winapi) void,
        // 16..46 (31 slots)
        _mid: [31]*const anyopaque,
        // 47
        CopyResource: *const fn (*ID3D11DeviceContext, *anyopaque, *anyopaque) callconv(.winapi) void,
    };

    pub fn copyResource(self: *ID3D11DeviceContext, dst: *ID3D11Texture2D, src: *ID3D11Texture2D) void {
        self.vtbl.CopyResource(self, dst, src);
    }

    pub fn mapRead(self: *ID3D11DeviceContext, tex: *ID3D11Texture2D, mapped: *D3D11_MAPPED_SUBRESOURCE) HRESULT {
        return self.vtbl.Map(self, tex, 0, D3D11_MAP_READ, 0, mapped);
    }

    pub fn unmap(self: *ID3D11DeviceContext, tex: *ID3D11Texture2D) void {
        self.vtbl.Unmap(self, tex, 0);
    }
};

pub const IDXGISurface = extern struct {
    vtbl: *const IUnknownVTable,
};

pub const IDXGIAdapter = extern struct {
    vtbl: *const VTable,

    pub const VTable = extern struct {
        base: IUnknownVTable,
        SetPrivateData: *const anyopaque,
        SetPrivateDataInterface: *const anyopaque,
        GetPrivateData: *const anyopaque,
        GetParent: *const fn (*IDXGIAdapter, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    };

    pub fn getParentFactory2(self: *IDXGIAdapter) ?*IDXGIFactory2 {
        var out: ?*anyopaque = null;
        if (com.succeeded(self.vtbl.GetParent(self, &IID_IDXGIFactory2, &out))) {
            return @ptrCast(@alignCast(out));
        }
        return null;
    }
};

pub const IDXGIDevice = extern struct {
    vtbl: *const VTable,

    pub const VTable = extern struct {
        base: IUnknownVTable,
        SetPrivateData: *const anyopaque,
        SetPrivateDataInterface: *const anyopaque,
        GetPrivateData: *const anyopaque,
        GetParent: *const anyopaque,
        GetAdapter: *const fn (*IDXGIDevice, *?*IDXGIAdapter) callconv(.winapi) HRESULT,
    };

    pub fn getAdapter(self: *IDXGIDevice) ?*IDXGIAdapter {
        var out: ?*IDXGIAdapter = null;
        if (com.succeeded(self.vtbl.GetAdapter(self, &out))) return out;
        return null;
    }
};

pub const IDXGISwapChain1 = extern struct {
    vtbl: *const VTable,

    pub const VTable = extern struct {
        base: IUnknownVTable,
        // IDXGIObject (3..6)
        _obj: [4]*const anyopaque,
        // IDXGIDeviceSubObject (7)
        GetDevice: *const anyopaque,
        // IDXGISwapChain (8..13)
        Present: *const fn (*IDXGISwapChain1, u32, u32) callconv(.winapi) HRESULT,
        GetBuffer: *const fn (*IDXGISwapChain1, u32, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        SetFullscreenState: *const anyopaque,
        GetFullscreenState: *const anyopaque,
        GetDesc: *const anyopaque,
        ResizeBuffers: *const fn (*IDXGISwapChain1, u32, u32, u32, u32, u32) callconv(.winapi) HRESULT,
    };

    pub fn present(self: *IDXGISwapChain1, sync_interval: u32, flags: u32) HRESULT {
        return self.vtbl.Present(self, sync_interval, flags);
    }

    pub fn getBufferSurface(self: *IDXGISwapChain1) ?*IDXGISurface {
        var out: ?*anyopaque = null;
        if (com.succeeded(self.vtbl.GetBuffer(self, 0, &IID_IDXGISurface, &out))) {
            return @ptrCast(@alignCast(out));
        }
        return null;
    }

    pub fn getBufferTexture2D(self: *IDXGISwapChain1) ?*ID3D11Texture2D {
        var out: ?*anyopaque = null;
        if (com.succeeded(self.vtbl.GetBuffer(self, 0, &IID_ID3D11Texture2D, &out))) {
            return @ptrCast(@alignCast(out));
        }
        return null;
    }

    pub fn resizeBuffers(self: *IDXGISwapChain1, width: u32, height: u32) HRESULT {
        return self.vtbl.ResizeBuffers(self, 0, width, height, DXGI_FORMAT_UNKNOWN, 0);
    }
};

pub const IDXGIFactory2 = extern struct {
    vtbl: *const VTable,

    pub const VTable = extern struct {
        base: IUnknownVTable,
        // IDXGIObject (3..6)
        _obj: [4]*const anyopaque,
        // IDXGIFactory (7..11)
        _fac0: [5]*const anyopaque,
        // IDXGIFactory1 (12..13)
        _fac1: [2]*const anyopaque,
        // IDXGIFactory2 (14..23)
        _fac2_pre: [10]*const anyopaque,
        // 24
        CreateSwapChainForComposition: *const fn (
            *IDXGIFactory2,
            *anyopaque,
            *const DXGI_SWAP_CHAIN_DESC1,
            ?*anyopaque,
            *?*IDXGISwapChain1,
        ) callconv(.winapi) HRESULT,
    };

    pub fn createSwapChainForComposition(
        self: *IDXGIFactory2,
        device: *IDXGIDevice,
        desc: *const DXGI_SWAP_CHAIN_DESC1,
    ) ?*IDXGISwapChain1 {
        var out: ?*IDXGISwapChain1 = null;
        if (com.succeeded(self.vtbl.CreateSwapChainForComposition(self, device, desc, null, &out))) {
            return out;
        }
        return null;
    }
};

pub extern "d3d11" fn D3D11CreateDevice(
    pAdapter: ?*anyopaque,
    DriverType: u32,
    Software: ?*anyopaque,
    Flags: u32,
    pFeatureLevels: ?[*]const u32,
    FeatureLevels: u32,
    SDKVersion: u32,
    ppDevice: *?*ID3D11Device,
    pFeatureLevel: ?*u32,
    ppImmediateContext: *?*ID3D11DeviceContext,
) callconv(.winapi) HRESULT;
