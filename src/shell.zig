//! Desktop shell integration: single instance with activation forwarding, a
//! hidden host window (tray callbacks, forwarded launches, toast clicks), the
//! notification-area (tray) icon and its menu, taskbar flashing and overlay
//! badge, badge icons drawn in code, and per-user registration of a URL
//! protocol. Toast notifications live in `toast.zig`.
//!
//! Everything except `postActivation` runs on the UI thread (the thread that
//! runs the message loop). The host window is never shown.
const std = @import("std");
const com = @import("win32/com.zig");
const win32 = @import("win32/win32.zig");
const app = @import("app.zig");

const HWND = win32.HWND;
const HICON = win32.HICON;
const HANDLE = win32.HANDLE;
const HMENU = win32.HMENU;
const HDC = win32.HDC;
const BOOL = win32.BOOL;
const DWORD = win32.DWORD;
const UINT = win32.UINT;
const WPARAM = win32.WPARAM;
const LPARAM = win32.LPARAM;
const LRESULT = win32.LRESULT;
const HBITMAP = *opaque {};
const HKEY = *opaque {};

pub const Icon = HICON;

// ------------------------------------------------------------ single instance

pub const Instance = struct {
    mutex: ?HANDLE,
    /// No other process holds the same key.
    first: bool,

    pub fn release(i: *Instance) void {
        if (i.mutex) |h| _ = CloseHandle(h);
        i.mutex = null;
    }
};

/// Claims the per-session single-instance mutex `Local\<key>.SingleInstance`.
/// The first process keeps it until it exits. When the mutex cannot be
/// created at all the process counts as first (never refuse to start).
pub fn acquireInstance(key: []const u8) Instance {
    var name_buf: [300]u8 = undefined;
    const name = std.fmt.bufPrint(&name_buf, "Local\\{s}.SingleInstance", .{key}) catch return .{ .mutex = null, .first = true };
    var wide: [300]u16 = undefined;
    const h = CreateMutexW(null, 0, win32.utf8ToUtf16Z(&wide, name).ptr);
    const exists = h != null and GetLastError() == ERROR_ALREADY_EXISTS;
    return .{ .mutex = h, .first = !exists };
}

/// Hands `args` to the first instance's host window (WM_COPYDATA) and lets it
/// take the foreground. Waits up to `timeout_ms` for that window to appear
/// (the first instance may still be starting). False when nobody answered.
pub fn forwardToFirst(key: []const u8, args: []const u8, timeout_ms: u32) bool {
    if (args.len > max_args) return false;
    var class_buf: [160]u16 = undefined;
    const class = hostClassName(&class_buf, key) orelse return false;
    var waited: u32 = 0;
    while (true) {
        if (FindWindowW(class.ptr, null)) |h| {
            var pid: DWORD = 0;
            _ = GetWindowThreadProcessId(h, &pid);
            if (pid != 0) _ = AllowSetForegroundWindow(pid);
            var cds: COPYDATASTRUCT = .{ .dwData = copydata_magic, .cbData = @intCast(args.len), .lpData = @ptrCast(@constCast(args.ptr)) };
            var result: usize = 0;
            const ok = SendMessageTimeoutW(h, WM_COPYDATA, 0, @bitCast(@intFromPtr(&cds)), SMTO_ABORTIFHUNG, 5000, &result);
            if (ok != 0 and result == 1) return true;
        }
        if (waited >= timeout_ms) return false;
        Sleep(100);
        waited += 100;
    }
}

// ------------------------------------------------------------ host window

pub const Handlers = struct {
    ctx: ?*anyopaque = null,
    /// Another launch forwarded its argument, or a toast was clicked.
    /// `args` is "" when there is nothing to open (just show the window).
    on_activate: ?*const fn (?*anyopaque, []const u8) void = null,
    /// Left click (or Enter) on the tray icon.
    on_tray_click: ?*const fn (?*anyopaque) void = null,
    /// A tray menu item was chosen.
    on_menu: ?*const fn (?*anyopaque, u32) void = null,
};

/// Tray context menu entry; `id` 0 is a separator.
pub const MenuItem = struct {
    id: u32 = 0,
    label: []const u8 = "",
};

const max_args = 4096;
const copydata_magic: usize = 0x4D4F_4F4E; // "MOON"
const WM_TRAY = win32.WM_APP + 0x50;
const WM_POSTED_ACTIVATION = win32.WM_APP + 0x51;

var g_host: ?HWND = null;
var g_handlers: Handlers = .{};
var g_class: [160]u16 = undefined;
var g_menu: []const MenuItem = &.{};
var g_taskbar_created: UINT = 0;

fn hostClassName(buf: []u16, key: []const u8) ?[:0]const u16 {
    var tmp: [160]u8 = undefined;
    const s = std.fmt.bufPrint(&tmp, "MoonUI.Host.{s}", .{key}) catch return null;
    return win32.utf8ToUtf16Z(buf, s);
}

/// Creates the hidden host window for `key` (the same key the second
/// instance forwards to). Call once on the UI thread before `run`.
pub fn createHost(key: []const u8, handlers: Handlers) !void {
    if (g_host != null) return error.AlreadyCreated;
    const class = hostClassName(&g_class, key) orelse return error.KeyTooLong;
    const hinst = win32.GetModuleHandleW(null);
    const wc: win32.WNDCLASSEXW = .{ .lpfnWndProc = hostProc, .hInstance = hinst, .lpszClassName = class.ptr };
    _ = win32.RegisterClassExW(&wc);
    g_handlers = handlers;
    g_taskbar_created = RegisterWindowMessageW(std.unicode.utf8ToUtf16LeStringLiteral("TaskbarCreated"));
    // A hidden top-level window (not message-only): it receives the
    // TaskbarCreated broadcast and can own the tray menu.
    g_host = win32.CreateWindowExW(0, class.ptr, class.ptr, WS_POPUP, 0, 0, 0, 0, null, null, hinst, null) orelse
        return error.CreateWindowFailed;
}

pub fn destroyHost() void {
    trayRemove();
    if (g_host) |h| _ = win32.DestroyWindow(h);
    g_host = null;
    _ = UnregisterClassW(@ptrCast(&g_class), win32.GetModuleHandleW(null));
    g_handlers = .{};
}

pub fn hostWindow() ?HWND {
    return g_host;
}

/// Delivers `args` to `Handlers.on_activate` on the UI thread. Safe from any
/// thread (toast activations arrive on a thread-pool thread).
pub fn postActivation(args: []const u8) void {
    const h = g_host orelse return;
    if (args.len > max_args) return;
    const mem = std.heap.page_allocator.alloc(u8, args.len + @sizeOf(usize)) catch return;
    std.mem.writeInt(usize, mem[0..@sizeOf(usize)], args.len, .little);
    @memcpy(mem[@sizeOf(usize)..], args);
    if (win32.PostMessageW(h, WM_POSTED_ACTIVATION, 0, @bitCast(@intFromPtr(mem.ptr))) == 0) std.heap.page_allocator.free(mem);
}

/// Renders one more frame after `ms` (a deadline while the UI loop sleeps).
/// A later call replaces the pending one.
pub fn wakeAfter(ms: u32) void {
    const h = g_host orelse return;
    _ = SetTimer(h, wake_timer, @max(ms, 1), null);
}

const wake_timer: usize = 1;

fn hostProc(hwnd: HWND, msg: UINT, wp: WPARAM, lp: LPARAM) callconv(.winapi) LRESULT {
    switch (msg) {
        WM_TIMER => if (wp == wake_timer) {
            _ = KillTimer(hwnd, wake_timer);
            app.wake();
            return 0;
        },
        WM_COPYDATA => {
            const cds: *const COPYDATASTRUCT = @ptrFromInt(@as(usize, @bitCast(lp)));
            if (cds.dwData != copydata_magic or cds.cbData > max_args) return 0;
            const bytes: []const u8 = if (cds.cbData == 0) "" else @as([*]const u8, @ptrCast(cds.lpData.?))[0..cds.cbData];
            if (!std.unicode.utf8ValidateSlice(bytes)) return 0;
            if (g_handlers.on_activate) |f| f(g_handlers.ctx, bytes);
            return 1;
        },
        WM_POSTED_ACTIVATION => {
            const base: [*]u8 = @ptrFromInt(@as(usize, @bitCast(lp)));
            const len = std.mem.readInt(usize, base[0..@sizeOf(usize)], .little);
            const mem = base[0 .. len + @sizeOf(usize)];
            defer std.heap.page_allocator.free(mem);
            const bytes = mem[@sizeOf(usize)..];
            if (std.unicode.utf8ValidateSlice(bytes)) if (g_handlers.on_activate) |f| f(g_handlers.ctx, bytes);
            return 0;
        },
        WM_TRAY => {
            switch (win32.loWord(lp)) {
                NIN_SELECT, NIN_KEYSELECT, win32.WM_LBUTTONDBLCLK => if (g_handlers.on_tray_click) |f| f(g_handlers.ctx),
                WM_CONTEXTMENU => showMenu(hwnd, win32.getXParam(@bitCast(wp)), win32.getYParam(@bitCast(wp))),
                else => {},
            }
            return 0;
        },
        else => {
            // Explorer restarted: the notification area forgot our icon.
            if (msg == g_taskbar_created and g_taskbar_created != 0 and g_tray.added) {
                g_tray.added = false;
                _ = trayApply();
                return 0;
            }
        },
    }
    return win32.DefWindowProcW(hwnd, msg, wp, lp);
}

fn showMenu(hwnd: HWND, x: i32, y: i32) void {
    if (g_menu.len == 0) return;
    const menu = CreatePopupMenu() orelse return;
    defer _ = DestroyMenu(menu);
    for (g_menu) |item| {
        if (item.id == 0) {
            _ = AppendMenuW(menu, MF_SEPARATOR, 0, null);
        } else {
            var buf: [128]u16 = undefined;
            _ = AppendMenuW(menu, MF_STRING, item.id, win32.utf8ToUtf16Z(&buf, item.label).ptr);
        }
    }
    // Required for the menu to close when the user clicks elsewhere.
    _ = win32.SetForegroundWindow(hwnd);
    const cmd = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_NONOTIFY | TPM_BOTTOMALIGN, x, y, 0, hwnd, null);
    _ = win32.PostMessageW(hwnd, WM_NULL, 0, 0);
    if (cmd > 0) if (g_handlers.on_menu) |f| f(g_handlers.ctx, @intCast(cmd));
}

// ------------------------------------------------------------ tray icon

const Tray = struct {
    added: bool = false,
    wanted: bool = false,
    icon: ?HICON = null,
    tip: [128]u16 = @splat(0),
};
var g_tray: Tray = .{};

/// Shows (or updates) the tray icon. `menu` must outlive the icon (a static
/// array). Needs `createHost` first.
pub fn trayShow(icon: HICON, tip: []const u8, menu: []const MenuItem) bool {
    g_menu = menu;
    g_tray.wanted = true;
    g_tray.icon = icon;
    _ = win32.utf8ToUtf16Z(&g_tray.tip, tip);
    return trayApply();
}

pub fn trayRemove() void {
    g_tray.wanted = false;
    if (!g_tray.added) return;
    var nid = trayData();
    _ = Shell_NotifyIconW(NIM_DELETE, &nid);
    g_tray.added = false;
}

fn trayData() NOTIFYICONDATAW {
    var nid: NOTIFYICONDATAW = .{ .hWnd = g_host, .uID = 1 };
    nid.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP;
    nid.uCallbackMessage = WM_TRAY;
    nid.hIcon = g_tray.icon;
    nid.szTip = g_tray.tip;
    return nid;
}

fn trayApply() bool {
    if (g_host == null or !g_tray.wanted) return false;
    var nid = trayData();
    if (g_tray.added) return Shell_NotifyIconW(NIM_MODIFY, &nid) != 0;
    if (Shell_NotifyIconW(NIM_ADD, &nid) == 0) return false;
    nid.uVersion = NOTIFYICON_VERSION_4;
    _ = Shell_NotifyIconW(NIM_SETVERSION, &nid);
    g_tray.added = true;
    return true;
}

// ------------------------------------------------------------ taskbar

/// Flashes the taskbar button until the window comes to the foreground.
/// Does nothing for a hidden window (it has no taskbar button).
pub fn flash(hwnd: HWND) void {
    if (IsWindowVisible(hwnd) == 0) return;
    var info: FLASHWINFO = .{ .hwnd = hwnd, .dwFlags = FLASHW_TRAY | FLASHW_TIMERNOFG, .uCount = std.math.maxInt(u32) };
    _ = FlashWindowEx(&info);
}

pub fn stopFlash(hwnd: HWND) void {
    var info: FLASHWINFO = .{ .hwnd = hwnd, .dwFlags = FLASHW_STOP };
    _ = FlashWindowEx(&info);
}

var g_taskbar: ?*com.IUnknown = null;
var g_overlay: ?HICON = null;
var g_overlay_desc: [64]u16 = @splat(0);

/// Sets (icon) or clears (null) the overlay badge on the taskbar button. The
/// caller keeps owning `icon`; it is applied again when the taskbar button is
/// (re)created, so keep it alive until replaced.
pub fn setOverlay(hwnd: HWND, icon: ?HICON, description: []const u8) void {
    g_overlay = icon;
    _ = win32.utf8ToUtf16Z(&g_overlay_desc, description);
    reapplyOverlay(hwnd);
}

/// Called by the app runner on "TaskbarButtonCreated".
pub fn reapplyOverlay(hwnd: HWND) void {
    if (g_taskbar == null) {
        var out: ?*anyopaque = null;
        if (com.failed(CoCreateInstance(&CLSID_TaskbarList, null, CLSCTX_INPROC_SERVER, &IID_ITaskbarList3, &out))) return;
        const tb: *com.IUnknown = @ptrCast(@alignCast(out.?));
        const vt: [*]const ?*const anyopaque = @ptrCast(tb.vtbl);
        const hr_init: *const fn (*com.IUnknown) callconv(.winapi) com.HRESULT = @ptrCast(vt[3].?);
        if (com.failed(hr_init(tb))) {
            _ = tb.release();
            return;
        }
        g_taskbar = tb;
    }
    const tb = g_taskbar.?;
    const vt: [*]const ?*const anyopaque = @ptrCast(tb.vtbl);
    // ITaskbarList3::SetOverlayIcon (IUnknown 3 + ITaskbarList 5 + ITaskbarList2 1 + 9).
    const set_overlay: *const fn (*com.IUnknown, HWND, ?HICON, ?[*:0]const u16) callconv(.winapi) com.HRESULT = @ptrCast(vt[18].?);
    _ = set_overlay(tb, hwnd, g_overlay, if (g_overlay != null) @ptrCast(&g_overlay_desc) else null);
}

/// Releases the taskbar COM object (before CoUninitialize).
pub fn releaseTaskbar() void {
    if (g_taskbar) |tb| _ = tb.release();
    g_taskbar = null;
    g_overlay = null;
}

// ------------------------------------------------------------ icons

/// Small icon size for the tray and overlays (16 px at 100 % scaling).
pub fn smallIconSize() i32 {
    const n = GetSystemMetrics(SM_CXSMICON);
    return if (n > 0) n else 16;
}

/// Loads an icon resource of the executable at exactly `size` px.
pub fn loadIcon(resource_id: u16, size: i32) ?HICON {
    const h = LoadImageW(win32.GetModuleHandleW(null), resource_id, IMAGE_ICON, size, size, 0) orelse return null;
    return @ptrCast(h);
}

pub fn destroyIcon(icon: ?HICON) void {
    if (icon) |i| _ = DestroyIcon(i);
}

pub const badge_red: u32 = 0xFFE5_2B3C;
const white: u32 = 0xFFFF_FFFF;
pub const max_icon = 256;

/// `base` with a red dot in the top-right corner (unread indicator).
/// The caller owns (and destroys) the new icon.
pub fn badgedIcon(base: HICON, size: i32) ?HICON {
    if (size < 8 or size > max_icon) return null;
    const s: usize = @intCast(size);
    var px: [max_icon * max_icon]u32 = undefined;
    if (!iconPixels(base, size, px[0 .. s * s])) return null;
    paintBadgeDot(px[0 .. s * s], s);
    return iconFromPixels(px[0 .. s * s], size);
}

/// Places the unread dot: radius ~22 % of the icon, white ring, top right.
pub fn paintBadgeDot(px: []u32, s: usize) void {
    const sf: f32 = @floatFromInt(s);
    const r = @max(sf * 0.22, 2.5);
    const ring = @max(sf * 0.06, 1.0);
    const cx = sf - r - ring * 0.5;
    const cy = r + ring * 0.5;
    paintCircle(px, s, cx, cy, r + ring, white);
    paintCircle(px, s, cx, cy, r, badge_red);
}

/// A red disc with `count` in white (taskbar overlay). "99+" above 99.
pub fn countIcon(count: u32, size: i32) ?HICON {
    if (size < 8 or size > max_icon or count == 0) return null;
    const s: usize = @intCast(size);
    var px: [max_icon * max_icon]u32 = undefined;
    const out = px[0 .. s * s];
    @memset(out, 0);
    const sf: f32 = @floatFromInt(s);
    paintCircle(out, s, sf * 0.5, sf * 0.5, sf * 0.5, badge_red);

    var label_buf: [8]u8 = undefined;
    const label = if (count > 99) "99+" else std.fmt.bufPrint(&label_buf, "{d}", .{count}) catch "!";
    var cov: [max_icon * max_icon]u8 = undefined;
    if (renderTextCoverage(label, size, cov[0 .. s * s])) {
        for (out, cov[0 .. s * s]) |*p, c| {
            if (c == 0) continue;
            p.* = blendOver(p.*, (@as(u32, c) << 24) | 0x00FF_FFFF);
        }
    }
    return iconFromPixels(out, size);
}

/// Anti-aliased filled circle, composited over the pixels (straight alpha BGRA).
pub fn paintCircle(px: []u32, s: usize, cx: f32, cy: f32, r: f32, color: u32) void {
    const a_color: f32 = @floatFromInt(color >> 24);
    for (0..s) |y| for (0..s) |x| {
        const dx = @as(f32, @floatFromInt(x)) + 0.5 - cx;
        const dy = @as(f32, @floatFromInt(y)) + 0.5 - cy;
        const cov = std.math.clamp(r + 0.5 - @sqrt(dx * dx + dy * dy), 0.0, 1.0);
        if (cov <= 0) continue;
        const a: u32 = @intFromFloat(@round(a_color * cov));
        px[y * s + x] = blendOver(px[y * s + x], (a << 24) | (color & 0x00FF_FFFF));
    };
}

/// Source-over for straight (non-premultiplied) alpha 0xAARRGGBB.
pub fn blendOver(dst: u32, src: u32) u32 {
    const sa: f32 = @as(f32, @floatFromInt(src >> 24)) / 255.0;
    const da: f32 = @as(f32, @floatFromInt(dst >> 24)) / 255.0;
    const oa = sa + da * (1 - sa);
    if (oa <= 0) return 0;
    var out: u32 = @as(u32, @intFromFloat(@round(oa * 255.0))) << 24;
    inline for (.{ 16, 8, 0 }) |shift| {
        const sc: f32 = @floatFromInt((src >> shift) & 0xFF);
        const dc: f32 = @floatFromInt((dst >> shift) & 0xFF);
        const c = (sc * sa + dc * da * (1 - sa)) / oa;
        out |= @as(u32, @intFromFloat(std.math.clamp(@round(c), 0, 255))) << shift;
    }
    return out;
}

/// Renders `label` centered, bold, white on black with grayscale
/// anti-aliasing and returns per-pixel coverage.
fn renderTextCoverage(label: []const u8, size: i32, cov: []u8) bool {
    const s: usize = @intCast(size);
    var bits: ?*anyopaque = null;
    const bmi = dibInfo(size);
    const dc = CreateCompatibleDC(null) orelse return false;
    defer _ = DeleteDC(dc);
    const bmp = CreateDIBSection(dc, &bmi, DIB_RGB_COLORS, &bits, null, 0) orelse return false;
    defer _ = DeleteObject(bmp);
    const old_bmp = SelectObject(dc, bmp);
    defer _ = SelectObject(dc, old_bmp.?);
    const pixels: [*]u32 = @ptrCast(@alignCast(bits.?));
    @memset(pixels[0 .. s * s], 0);

    const sf: f32 = @floatFromInt(size);
    const scale: f32 = switch (label.len) {
        1 => 0.78,
        2 => 0.62,
        else => 0.46,
    };
    const font = CreateFontW(-@as(i32, @intFromFloat(@round(sf * scale))), 0, 0, 0, 700, 0, 0, 0, 1, 0, 0, ANTIALIASED_QUALITY, 0, std.unicode.utf8ToUtf16LeStringLiteral("Segoe UI")) orelse return false;
    defer _ = DeleteObject(font);
    const old_font = SelectObject(dc, font);
    defer _ = SelectObject(dc, old_font.?);
    _ = SetTextColor(dc, 0x00FF_FFFF);
    _ = SetBkMode(dc, TRANSPARENT);
    var wide: [8]u16 = undefined;
    const w = win32.utf8ToUtf16Z(&wide, label);
    var rc: win32.RECT = .{ .left = 0, .top = 0, .right = size, .bottom = size };
    _ = DrawTextW(dc, w.ptr, @intCast(w.len), &rc, DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
    _ = GdiFlush();
    for (cov, pixels[0 .. s * s]) |*c, p| {
        const r: u8 = @truncate(p >> 16);
        const g: u8 = @truncate(p >> 8);
        const b: u8 = @truncate(p);
        c.* = @max(r, @max(g, b));
    }
    return true;
}

fn dibInfo(size: i32) BITMAPINFO {
    return .{ .bmiHeader = .{ .biWidth = size, .biHeight = -size, .biPlanes = 1, .biBitCount = 32 } };
}

/// Creates an alpha icon from top-down 0xAARRGGBB pixels.
pub fn iconFromPixels(px: []const u32, size: i32) ?HICON {
    if (size < 1 or size > max_icon) return null;
    const s: usize = @intCast(size);
    if (px.len < s * s) return null;
    var bits: ?*anyopaque = null;
    const bmi = dibInfo(size);
    const color = CreateDIBSection(null, &bmi, DIB_RGB_COLORS, &bits, null, 0) orelse return null;
    defer _ = DeleteObject(color);
    const dst: [*]u32 = @ptrCast(@alignCast(bits.?));
    @memcpy(dst[0 .. s * s], px[0 .. s * s]);
    _ = GdiFlush();
    // Monochrome mask rows are WORD aligned; all zero (alpha decides).
    var mask_bits: [((max_icon + 15) / 16) * 2 * max_icon]u8 = undefined;
    const stride = ((s + 15) / 16) * 2;
    @memset(mask_bits[0 .. stride * s], 0);
    const mask = CreateBitmap(size, size, 1, 1, &mask_bits) orelse return null;
    defer _ = DeleteObject(mask);
    var ii: ICONINFO = .{ .fIcon = 1, .xHotspot = 0, .yHotspot = 0, .hbmMask = mask, .hbmColor = color };
    return CreateIconIndirect(&ii);
}

/// Reads an icon's pixels (top-down 0xAARRGGBB). The icon must be exactly
/// `size` px (see `loadIcon`). Icons without alpha come back opaque.
pub fn iconPixels(icon: HICON, size: i32, out: []u32) bool {
    if (size < 1 or size > max_icon) return false;
    const s: usize = @intCast(size);
    if (out.len < s * s) return false;
    var ii: ICONINFO = undefined;
    if (GetIconInfo(icon, &ii) == 0) return false;
    defer {
        if (ii.hbmColor) |b| _ = DeleteObject(b);
        if (ii.hbmMask) |b| _ = DeleteObject(b);
    }
    const color = ii.hbmColor orelse return false;
    var bm: BITMAP = undefined;
    if (GetObjectW(color, @sizeOf(BITMAP), &bm) == 0 or bm.bmWidth != size or bm.bmHeight != size) return false;
    const dc = CreateCompatibleDC(null) orelse return false;
    defer _ = DeleteDC(dc);
    var bmi = dibInfo(size);
    if (GetDIBits(dc, color, 0, @intCast(size), out.ptr, &bmi, DIB_RGB_COLORS) != size) return false;
    var any_alpha = false;
    for (out[0 .. s * s]) |p| if (p >> 24 != 0) {
        any_alpha = true;
        break;
    };
    if (!any_alpha) for (out[0 .. s * s]) |*p| {
        p.* |= 0xFF00_0000;
    };
    return true;
}

// ------------------------------------------------------------ registration

/// Registers `scheme:` for the current user so that opening such a link runs
/// this executable with the link as its only argument. Overwrites what the
/// key held before; only call it for a scheme this app owns.
pub fn registerProtocol(scheme: []const u8, description: []const u8) bool {
    var exe_w: [1024]u16 = undefined;
    const n = GetModuleFileNameW(null, &exe_w, exe_w.len);
    if (n == 0 or n >= exe_w.len) return false;
    var exe: [3072]u8 = undefined;
    const exe_len = std.unicode.utf16LeToUtf8(&exe, exe_w[0..n]) catch return false;

    var key_buf: [256]u8 = undefined;
    const key = std.fmt.bufPrint(&key_buf, "Software\\Classes\\{s}", .{scheme}) catch return false;
    var cmd_key_buf: [300]u8 = undefined;
    const cmd_key = std.fmt.bufPrint(&cmd_key_buf, "{s}\\shell\\open\\command", .{key}) catch return false;
    var cmd_buf: [3200]u8 = undefined;
    const cmd = std.fmt.bufPrint(&cmd_buf, "\"{s}\" \"%1\"", .{exe[0..exe_len]}) catch return false;
    var desc_buf: [200]u8 = undefined;
    const desc = std.fmt.bufPrint(&desc_buf, "URL:{s}", .{description}) catch return false;
    return setUserString(key, "", desc) and setUserString(key, "URL Protocol", "") and setUserString(cmd_key, "", cmd);
}

/// Writes a REG_SZ value below HKEY_CURRENT_USER (creating the key).
pub fn setUserString(subkey: []const u8, name: []const u8, value: []const u8) bool {
    var key_w: [512]u16 = undefined;
    var name_w: [128]u16 = undefined;
    var value_w: [4096]u16 = undefined;
    const k = win32.utf8ToUtf16Z(&key_w, subkey);
    const nm = win32.utf8ToUtf16Z(&name_w, name);
    const v = win32.utf8ToUtf16Z(&value_w, value);
    var hkey: ?HKEY = null;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, k.ptr, 0, null, 0, KEY_WRITE, null, &hkey, null) != 0) return false;
    defer _ = RegCloseKey(hkey.?);
    const bytes: [*]const u8 = @ptrCast(v.ptr);
    return RegSetValueExW(hkey.?, nm.ptr, 0, REG_SZ, bytes, @intCast((v.len + 1) * 2)) == 0;
}

// ------------------------------------------------------------ Win32

const ERROR_ALREADY_EXISTS: DWORD = 183;
const WS_POPUP: DWORD = 0x80000000;
const WM_NULL: UINT = 0x0000;
const WM_COPYDATA: UINT = 0x004A;
const WM_TIMER: UINT = 0x0113;
const WM_CONTEXTMENU: u16 = 0x007B;
const NIN_SELECT: u16 = 0x0400;
const NIN_KEYSELECT: u16 = 0x0401;
const SMTO_ABORTIFHUNG: UINT = 0x0002;
const MF_STRING: UINT = 0x0000;
const MF_SEPARATOR: UINT = 0x0800;
const TPM_RIGHTBUTTON: UINT = 0x0002;
const TPM_BOTTOMALIGN: UINT = 0x0020;
const TPM_NONOTIFY: UINT = 0x0080;
const TPM_RETURNCMD: UINT = 0x0100;
const NIM_ADD: DWORD = 0;
const NIM_MODIFY: DWORD = 1;
const NIM_DELETE: DWORD = 2;
const NIM_SETVERSION: DWORD = 4;
const NIF_MESSAGE: UINT = 0x01;
const NIF_ICON: UINT = 0x02;
const NIF_TIP: UINT = 0x04;
const NIF_SHOWTIP: UINT = 0x80;
const NOTIFYICON_VERSION_4: UINT = 4;
const FLASHW_STOP: DWORD = 0;
const FLASHW_TRAY: DWORD = 0x2;
const FLASHW_TIMERNOFG: DWORD = 0xC;
const SM_CXSMICON: i32 = 49;
const IMAGE_ICON: UINT = 1;
const DIB_RGB_COLORS: UINT = 0;
const ANTIALIASED_QUALITY: DWORD = 4;
const TRANSPARENT: i32 = 1;
const DT_CENTER: UINT = 0x01;
const DT_VCENTER: UINT = 0x04;
const DT_SINGLELINE: UINT = 0x20;
const DT_NOPREFIX: UINT = 0x800;
const HKEY_CURRENT_USER: HKEY = @ptrFromInt(0x80000001);
const KEY_WRITE: DWORD = 0x20006;
const REG_SZ: DWORD = 1;
const CLSCTX_INPROC_SERVER: DWORD = 1;

const CLSID_TaskbarList = com.GUID.init(0x56FDF344, 0xFD6D, 0x11d0, .{ 0x95, 0x8A, 0x00, 0x60, 0x97, 0xC9, 0xA0, 0x90 });
const IID_ITaskbarList3 = com.GUID.init(0xea1afb91, 0x9e28, 0x4b86, .{ 0x90, 0xe9, 0x9e, 0x9f, 0x8a, 0x5e, 0xef, 0xaf });

const COPYDATASTRUCT = extern struct {
    dwData: usize,
    cbData: DWORD,
    lpData: ?*anyopaque,
};

const NOTIFYICONDATAW = extern struct {
    cbSize: DWORD = @sizeOf(NOTIFYICONDATAW),
    hWnd: ?HWND = null,
    uID: UINT = 0,
    uFlags: UINT = 0,
    uCallbackMessage: UINT = 0,
    hIcon: ?HICON = null,
    szTip: [128]u16 = @splat(0),
    dwState: DWORD = 0,
    dwStateMask: DWORD = 0,
    szInfo: [256]u16 = @splat(0),
    uVersion: UINT = 0,
    szInfoTitle: [64]u16 = @splat(0),
    dwInfoFlags: DWORD = 0,
    guidItem: com.GUID = com.GUID.init(0, 0, 0, .{ 0, 0, 0, 0, 0, 0, 0, 0 }),
    hBalloonIcon: ?HICON = null,
};

const FLASHWINFO = extern struct {
    cbSize: UINT = @sizeOf(FLASHWINFO),
    hwnd: HWND,
    dwFlags: DWORD,
    uCount: UINT = 0,
    dwTimeout: DWORD = 0,
};

const ICONINFO = extern struct {
    fIcon: BOOL,
    xHotspot: DWORD,
    yHotspot: DWORD,
    hbmMask: ?HBITMAP,
    hbmColor: ?HBITMAP,
};

const BITMAP = extern struct {
    bmType: i32,
    bmWidth: i32,
    bmHeight: i32,
    bmWidthBytes: i32,
    bmPlanes: u16,
    bmBitsPixel: u16,
    bmBits: ?*anyopaque,
};

const BITMAPINFOHEADER = extern struct {
    biSize: DWORD = @sizeOf(BITMAPINFOHEADER),
    biWidth: i32 = 0,
    biHeight: i32 = 0,
    biPlanes: u16 = 1,
    biBitCount: u16 = 0,
    biCompression: DWORD = 0,
    biSizeImage: DWORD = 0,
    biXPelsPerMeter: i32 = 0,
    biYPelsPerMeter: i32 = 0,
    biClrUsed: DWORD = 0,
    biClrImportant: DWORD = 0,
};

const BITMAPINFO = extern struct {
    bmiHeader: BITMAPINFOHEADER,
    bmiColors: [1]u32 = .{0},
};

extern "kernel32" fn CreateMutexW(attrs: ?*anyopaque, initial_owner: BOOL, name: [*:0]const u16) callconv(.winapi) ?HANDLE;
extern "kernel32" fn CloseHandle(h: HANDLE) callconv(.winapi) BOOL;
extern "kernel32" fn GetLastError() callconv(.winapi) DWORD;
extern "kernel32" fn Sleep(ms: DWORD) callconv(.winapi) void;
extern "kernel32" fn GetModuleFileNameW(module: ?win32.HMODULE, buf: [*]u16, size: DWORD) callconv(.winapi) DWORD;

extern "user32" fn FindWindowW(class: ?[*:0]const u16, title: ?[*:0]const u16) callconv(.winapi) ?HWND;
extern "user32" fn GetWindowThreadProcessId(hwnd: HWND, pid: ?*DWORD) callconv(.winapi) DWORD;
extern "user32" fn AllowSetForegroundWindow(pid: DWORD) callconv(.winapi) BOOL;
extern "user32" fn SendMessageTimeoutW(hwnd: HWND, msg: UINT, wp: WPARAM, lp: LPARAM, flags: UINT, timeout: UINT, result: ?*usize) callconv(.winapi) LRESULT;
extern "user32" fn RegisterWindowMessageW(name: [*:0]const u16) callconv(.winapi) UINT;
extern "user32" fn UnregisterClassW(class: [*:0]const u16, hinst: ?win32.HINSTANCE) callconv(.winapi) BOOL;
extern "user32" fn CreatePopupMenu() callconv(.winapi) ?HMENU;
extern "user32" fn SetTimer(hwnd: ?HWND, id: usize, ms: UINT, func: ?*const anyopaque) callconv(.winapi) usize;
extern "user32" fn KillTimer(hwnd: ?HWND, id: usize) callconv(.winapi) BOOL;
extern "user32" fn AppendMenuW(menu: HMENU, flags: UINT, id: usize, item: ?[*:0]const u16) callconv(.winapi) BOOL;
extern "user32" fn TrackPopupMenu(menu: HMENU, flags: UINT, x: i32, y: i32, reserved: i32, hwnd: HWND, rect: ?*const win32.RECT) callconv(.winapi) BOOL;
extern "user32" fn DestroyMenu(menu: HMENU) callconv(.winapi) BOOL;
extern "user32" fn FlashWindowEx(info: *const FLASHWINFO) callconv(.winapi) BOOL;
extern "user32" fn IsWindowVisible(hwnd: HWND) callconv(.winapi) BOOL;
extern "user32" fn GetSystemMetrics(index: i32) callconv(.winapi) i32;
extern "user32" fn LoadImageW(hinst: ?win32.HINSTANCE, name: usize, kind: UINT, cx: i32, cy: i32, flags: UINT) callconv(.winapi) ?HANDLE;
extern "user32" fn CreateIconIndirect(info: *ICONINFO) callconv(.winapi) ?HICON;
extern "user32" fn GetIconInfo(icon: HICON, info: *ICONINFO) callconv(.winapi) BOOL;
extern "user32" fn DestroyIcon(icon: HICON) callconv(.winapi) BOOL;
extern "user32" fn DrawTextW(dc: HDC, text: [*]const u16, len: i32, rect: *win32.RECT, format: UINT) callconv(.winapi) i32;

extern "gdi32" fn CreateCompatibleDC(dc: ?HDC) callconv(.winapi) ?HDC;
extern "gdi32" fn DeleteDC(dc: HDC) callconv(.winapi) BOOL;
extern "gdi32" fn CreateDIBSection(dc: ?HDC, bmi: *const BITMAPINFO, usage: UINT, bits: *?*anyopaque, section: ?HANDLE, offset: DWORD) callconv(.winapi) ?HBITMAP;
extern "gdi32" fn CreateBitmap(w: i32, h: i32, planes: UINT, bpp: UINT, bits: ?*const anyopaque) callconv(.winapi) ?HBITMAP;
extern "gdi32" fn SelectObject(dc: HDC, obj: *anyopaque) callconv(.winapi) ?*anyopaque;
extern "gdi32" fn DeleteObject(obj: *anyopaque) callconv(.winapi) BOOL;
extern "gdi32" fn GetObjectW(obj: *anyopaque, size: i32, out: *anyopaque) callconv(.winapi) i32;
extern "gdi32" fn GetDIBits(dc: HDC, bmp: HBITMAP, start: UINT, lines: UINT, bits: ?*anyopaque, bmi: *BITMAPINFO, usage: UINT) callconv(.winapi) i32;
extern "gdi32" fn GdiFlush() callconv(.winapi) BOOL;
extern "gdi32" fn CreateFontW(h: i32, w: i32, esc: i32, orient: i32, weight: i32, italic: DWORD, underline: DWORD, strike: DWORD, charset: DWORD, out_prec: DWORD, clip_prec: DWORD, quality: DWORD, pitch: DWORD, face: [*:0]const u16) callconv(.winapi) ?*anyopaque;
extern "gdi32" fn SetTextColor(dc: HDC, color: u32) callconv(.winapi) u32;
extern "gdi32" fn SetBkMode(dc: HDC, mode: i32) callconv(.winapi) i32;

extern "shell32" fn Shell_NotifyIconW(msg: DWORD, data: *NOTIFYICONDATAW) callconv(.winapi) BOOL;

extern "advapi32" fn RegCreateKeyExW(key: HKEY, subkey: [*:0]const u16, reserved: DWORD, class: ?[*:0]const u16, options: DWORD, sam: DWORD, attrs: ?*anyopaque, result: *?HKEY, disposition: ?*DWORD) callconv(.winapi) i32;
extern "advapi32" fn RegSetValueExW(key: HKEY, name: [*:0]const u16, reserved: DWORD, kind: DWORD, data: [*]const u8, size: DWORD) callconv(.winapi) i32;
extern "advapi32" fn RegCloseKey(key: HKEY) callconv(.winapi) i32;

extern "ole32" fn CoCreateInstance(clsid: *const com.GUID, outer: ?*anyopaque, ctx: DWORD, iid: *const com.GUID, out: *?*anyopaque) callconv(.winapi) com.HRESULT;

// ------------------------------------------------------------ tests

test "blendOver: opaque source wins, transparent source keeps the destination" {
    try std.testing.expectEqual(@as(u32, 0xFF112233), blendOver(0xFFAABBCC, 0xFF112233));
    try std.testing.expectEqual(@as(u32, 0xFFAABBCC), blendOver(0xFFAABBCC, 0x00112233));
    try std.testing.expectEqual(@as(u32, 0xFF112233), blendOver(0x00000000, 0xFF112233));
}

test "badged icon: red dot top right, rest of the icon untouched" {
    const size = 32;
    var px: [size * size]u32 = undefined;
    @memset(&px, 0xFF2060C0);
    const base = iconFromPixels(&px, size) orelse return error.IconFailed;
    defer destroyIcon(base);
    const badged = badgedIcon(base, size) orelse return error.BadgeFailed;
    defer destroyIcon(badged);
    var out: [size * size]u32 = undefined;
    try std.testing.expect(iconPixels(badged, size, &out));
    try std.testing.expectEqual(@as(u32, 0xFF2060C0), out[(size - 2) * size + 1]); // bottom left
    // Dot center: radius 7.04, ring 1.92 → center (23.9, 8.0).
    try std.testing.expectEqual(badge_red, out[8 * size + 24]);
}

test "count icon: red disc with a white digit" {
    const size = 32;
    const icon = countIcon(7, size) orelse return error.IconFailed;
    defer destroyIcon(icon);
    var out: [size * size]u32 = undefined;
    try std.testing.expect(iconPixels(icon, size, &out));
    try std.testing.expectEqual(@as(u32, 0), out[0] >> 24); // corner outside the disc
    try std.testing.expectEqual(badge_red, out[16 * size + 2]); // left edge of the disc
    var white_px: usize = 0;
    for (out) |p| if (p >> 24 == 0xFF and (p >> 16) & 0xFF > 0xE0 and p & 0xFF > 0xE0) {
        white_px += 1;
    };
    try std.testing.expect(white_px >= 10);
    try std.testing.expect(countIcon(0, size) == null);
}

test "single instance: second claim sees the first; forwarded args reach the host" {
    var key_buf: [64]u8 = undefined;
    var seed: u64 = 0;
    _ = win32.QueryPerformanceCounter(@ptrCast(&seed));
    const key = try std.fmt.bufPrint(&key_buf, "MoonUI.Test.{x}", .{seed});

    var a = acquireInstance(key);
    defer a.release();
    try std.testing.expect(a.first);
    var b = acquireInstance(key);
    defer b.release();
    try std.testing.expect(!b.first);

    const Got = struct {
        var buf: [64]u8 = undefined;
        var len: usize = 0;
        var calls: usize = 0;
        fn onActivate(_: ?*anyopaque, args: []const u8) void {
            @memcpy(buf[0..args.len], args);
            len = args.len;
            calls += 1;
        }
    };
    try createHost(key, .{ .on_activate = Got.onActivate });
    defer destroyHost();
    try std.testing.expect(forwardToFirst(key, "moonui-test://open/1", 0));
    try std.testing.expectEqualStrings("moonui-test://open/1", Got.buf[0..Got.len]);
    try std.testing.expect(forwardToFirst(key, "", 0));
    try std.testing.expectEqual(@as(usize, 0), Got.len);
    try std.testing.expectEqual(@as(usize, 2), Got.calls);
    // A key nobody listens on.
    try std.testing.expect(!forwardToFirst("MoonUI.Test.nobody", "x", 0));

    // Posted activation (toast clicks) arrives through the message queue.
    postActivation("posted");
    var msg: win32.MSG = undefined;
    while (win32.PeekMessageW(&msg, hostWindow(), 0, 0, win32.PM_REMOVE) != 0) _ = win32.DispatchMessageW(&msg);
    try std.testing.expectEqualStrings("posted", Got.buf[0..Got.len]);
}
