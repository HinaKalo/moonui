//! Event-driven Win32 + DirectComposition application runner.
//! Sleeps in MsgWaitForMultipleObjectsEx at ~0% CPU when no animations are active.
const std = @import("std");
const com = @import("win32/com.zig");
const win32 = @import("win32/win32.zig");
const renderer_mod = @import("renderer.zig");
const ui = @import("ui.zig");
const theme_mod = @import("theme.zig");

pub const AppOptions = struct {
    title: []const u8 = "MoonWin Native",
    width: u32 = 1320,
    height: u32 = 860,
    min_width: u32 = 640,
    min_height: u32 = 420,
    theme: theme_mod.Theme = theme_mod.presets.midnight,
    vsync: bool = true,
    capture_path: ?[]const u8 = null,
};

const WM_WAKE = win32.WM_APP + 1;

const WindowState = struct {
    ui_ctx: *ui.UiContext,
    renderer: *renderer_mod.Renderer,
    min_w: i32,
    min_h: i32,
    dpi: f32,
    pending_resize: bool = false,
    new_w: u32 = 0,
    new_h: u32 = 0,
    needs_render: bool = true,
    running: bool = true,
    high_surrogate: u16 = 0,
    cursor_arrow: ?win32.HCURSOR = null,
    cursor_hand: ?win32.HCURSOR = null,
    cursor_ibeam: ?win32.HCURSOR = null,
    tracking_leave: bool = false,
};

var g_hwnd: ?win32.HWND = null;

pub fn wake() void {
    if (g_hwnd) |h| {
        _ = win32.PostMessageW(h, WM_WAKE, 0, 0);
    }
}

pub fn quit() void {
    win32.PostQuitMessage(0);
}

pub fn run(opts: AppOptions, state_ptr: anytype, comptime frame_fn: fn (@TypeOf(state_ptr)) void) !void {
    _ = com.CoInitializeEx(null, com.COINIT_APARTMENTTHREADED | com.COINIT_DISABLE_OLE1DDE);
    defer com.CoUninitialize();

    _ = win32.SetProcessDpiAwarenessContext(win32.DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);

    var gpa_inst: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_inst.deinit();
    const allocator = gpa_inst.allocator();

    const hinst = win32.GetModuleHandleW(null);
    const class_name = std.unicode.utf8ToUtf16LeStringLiteral("MoonWinNativeWnd");

    const wc: win32.WNDCLASSEXW = .{
        .style = win32.CS_HREDRAW | win32.CS_VREDRAW | win32.CS_DBLCLKS,
        .lpfnWndProc = wndProc,
        .hInstance = hinst,
        .hCursor = win32.LoadCursorW(null, win32.IDC_ARROW),
        .lpszClassName = class_name,
    };
    _ = win32.RegisterClassExW(&wc);

    var title_buf: [256]u16 = undefined;
    const title_w = win32.utf8ToUtf16Z(&title_buf, opts.title);

    // WS_EX_NOREDIRECTIONBITMAP is the modern DirectComposition window style (no GDI redirection surface!)
    const ex_style: win32.DWORD = win32.WS_EX_NOREDIRECTIONBITMAP;
    const style: win32.DWORD = win32.WS_OVERLAPPEDWINDOW;

    var wr: win32.RECT = .{ .left = 0, .top = 0, .right = @intCast(opts.width), .bottom = @intCast(opts.height) };
    _ = win32.AdjustWindowRectExForDpi(&wr, style, 0, ex_style, 96);

    const hwnd = win32.CreateWindowExW(
        ex_style,
        class_name,
        title_w.ptr,
        style,
        win32.CW_USEDEFAULT,
        win32.CW_USEDEFAULT,
        wr.right - wr.left,
        wr.bottom - wr.top,
        null,
        null,
        hinst,
        null,
    ) orelse return error.CreateWindowFailed;
    defer _ = win32.DestroyWindow(hwnd);
    g_hwnd = hwnd;
    defer g_hwnd = null;

    const dpi: f32 = @floatFromInt(@max(win32.GetDpiForWindow(hwnd), 96));
    // Re-adjust initial window size for actual monitor DPI if not capturing at 1:1
    if (opts.capture_path == null and dpi != 96.0) {
        const scale = dpi / 96.0;
        var wr_dpi: win32.RECT = .{
            .left = 0,
            .top = 0,
            .right = @intFromFloat(@round(@as(f32, @floatFromInt(opts.width)) * scale)),
            .bottom = @intFromFloat(@round(@as(f32, @floatFromInt(opts.height)) * scale)),
        };
        _ = win32.AdjustWindowRectExForDpi(&wr_dpi, style, 0, ex_style, @intFromFloat(dpi));
        _ = win32.SetWindowPos(hwnd, null, 0, 0, wr_dpi.right - wr_dpi.left, wr_dpi.bottom - wr_dpi.top, win32.SWP_NOZORDER | win32.SWP_NOACTIVATE);
    }

    win32.setDarkTitleBar(hwnd, opts.theme.dark, opts.theme.palette.bg_subtle.colorref());

    var cr: win32.RECT = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 };
    _ = win32.GetClientRect(hwnd, &cr);
    const client_w: u32 = @intCast(@max(cr.right - cr.left, 1));
    const client_h: u32 = @intCast(@max(cr.bottom - cr.top, 1));

    var renderer = try renderer_mod.Renderer.init(allocator, hwnd, client_w, client_h, if (opts.capture_path != null) 96.0 else dpi);
    defer renderer.deinit();

    var ui_ctx = ui.UiContext.init(allocator, &renderer, opts.theme);
    defer ui_ctx.deinit();
    ui.ctx = &ui_ctx;
    defer ui.ctx = null;

    var wstate: WindowState = .{
        .ui_ctx = &ui_ctx,
        .renderer = &renderer,
        .min_w = @intCast(opts.min_width),
        .min_h = @intCast(opts.min_height),
        .dpi = if (opts.capture_path != null) 96.0 else dpi,
        .cursor_arrow = win32.LoadCursorW(null, win32.IDC_ARROW),
        .cursor_hand = win32.LoadCursorW(null, win32.IDC_HAND),
        .cursor_ibeam = win32.LoadCursorW(null, win32.IDC_IBEAM),
    };
    _ = win32.SetWindowLongPtrW(hwnd, win32.GWLP_USERDATA, @intCast(@intFromPtr(&wstate)));

    if (opts.capture_path == null) {
        _ = win32.ShowWindow(hwnd, win32.SW_SHOW);
        _ = win32.UpdateWindow(hwnd);
    }

    var freq: i64 = 1;
    var t_start: i64 = 0;
    _ = win32.QueryPerformanceFrequency(&freq);
    _ = win32.QueryPerformanceCounter(&t_start);
    var t_prev = t_start;
    var settle_frames: u8 = 4;

    // Headless capture mode: render a few frames so animations settle, dump BMP, exit.
    if (opts.capture_path) |cap_path| {
        ui_ctx.theme.motion.enabled = false;
        var f: usize = 0;
        while (f < 3) : (f += 1) {
            ui_ctx.beginFrame(@as(f64, @floatFromInt(f)) * 0.016, 0.016);
            frame_fn(state_ptr);
            ui_ctx.endFrame();
            renderer.render(ui_ctx.theme.palette.bg, &ui_ctx.main_dl, &ui_ctx.overlay_dl, false);
            ui_ctx.input.endFrame();
            ui_ctx.stats.frames_presented += 1;
        }
        if (!renderer.captureBmp(cap_path)) return error.CaptureFailed;
        return;
    }

    // Event-driven message + render loop (0% CPU when idle!)
    var msg: win32.MSG = undefined;
    while (wstate.running) {
        if (!wstate.needs_render and settle_frames == 0 and !ui_ctx.anim.isAnimating()) {
            _ = win32.MsgWaitForMultipleObjectsEx(0, null, win32.INFINITE, win32.QS_ALLINPUT, win32.MWMO_INPUTAVAILABLE);
        }

        while (win32.PeekMessageW(&msg, null, 0, 0, win32.PM_REMOVE) != 0) {
            if (msg.message == win32.WM_QUIT) {
                wstate.running = false;
                break;
            }
            _ = win32.TranslateMessage(&msg);
            _ = win32.DispatchMessageW(&msg);
        }
        if (!wstate.running) break;

        if (wstate.pending_resize) {
            wstate.pending_resize = false;
            renderer.resize(wstate.new_w, wstate.new_h, wstate.dpi);
            wstate.needs_render = true;
        }

        if (wstate.needs_render or settle_frames > 0 or ui_ctx.anim.isAnimating()) {
            var t_now: i64 = 0;
            _ = win32.QueryPerformanceCounter(&t_now);
            const now_s = @as(f64, @floatFromInt(t_now - t_start)) / @as(f64, @floatFromInt(freq));
            const dt_s = @as(f32, @floatCast(@as(f64, @floatFromInt(t_now - t_prev)) / @as(f64, @floatFromInt(freq))));
            t_prev = t_now;

            if (dt_s > 0.0001 and dt_s < 0.5) {
                const inst_fps = 1.0 / dt_s;
                ui_ctx.stats.fps = if (ui_ctx.stats.fps == 0) inst_fps else ui_ctx.stats.fps * 0.9 + inst_fps * 0.1;
            }

            ui_ctx.beginFrame(now_s, dt_s);
            frame_fn(state_ptr);
            ui_ctx.endFrame();

            if (ui_ctx.theme_changed) {
                ui_ctx.theme_changed = false;
                win32.setDarkTitleBar(hwnd, ui_ctx.theme.dark, ui_ctx.theme.palette.bg_subtle.colorref());
            }

            ui_ctx.stats.animating = ui_ctx.anim.isAnimating();
            renderer.render(ui_ctx.theme.palette.bg, &ui_ctx.main_dl, &ui_ctx.overlay_dl, opts.vsync);
            ui_ctx.stats.frames_presented += 1;
            ui_ctx.input.endFrame();

            if (wstate.needs_render) {
                wstate.needs_render = false;
                settle_frames = 2;
            } else if (settle_frames > 0) {
                settle_frames -= 1;
            }
        }
    }
}

fn wndProc(hwnd: win32.HWND, msg: win32.UINT, wp: win32.WPARAM, lp: win32.LPARAM) callconv(.winapi) win32.LRESULT {
    const raw = win32.GetWindowLongPtrW(hwnd, win32.GWLP_USERDATA);
    if (raw == 0) return win32.DefWindowProcW(hwnd, msg, wp, lp);
    const ws: *WindowState = @ptrFromInt(@as(usize, @intCast(raw)));
    const scale = ws.dpi / 96.0;

    switch (msg) {
        win32.WM_DESTROY => {
            ws.running = false;
            win32.PostQuitMessage(0);
            return 0;
        },
        win32.WM_ERASEBKGND => return 1,
        win32.WM_PAINT => {
            _ = win32.ValidateRect(hwnd, null);
            ws.needs_render = true;
            return 0;
        },
        win32.WM_SIZE => {
            ws.new_w = @max(@as(u32, win32.loWord(lp)), 1);
            ws.new_h = @max(@as(u32, win32.hiWord(lp)), 1);
            ws.pending_resize = true;
            ws.needs_render = true;
            return 0;
        },
        win32.WM_DPICHANGED => {
            ws.dpi = @floatFromInt(@max(win32.hiWord(@bitCast(wp)), 96));
            const suggested: *const win32.RECT = @ptrFromInt(@as(usize, @bitCast(lp)));
            _ = win32.SetWindowPos(
                hwnd,
                null,
                suggested.left,
                suggested.top,
                suggested.right - suggested.left,
                suggested.bottom - suggested.top,
                win32.SWP_NOZORDER | win32.SWP_NOACTIVATE,
            );
            ws.pending_resize = true;
            ws.needs_render = true;
            return 0;
        },
        win32.WM_GETMINMAXINFO => {
            const mmi: *win32.MINMAXINFO = @ptrFromInt(@as(usize, @bitCast(lp)));
            mmi.ptMinTrackSize.x = @intFromFloat(@as(f32, @floatFromInt(ws.min_w)) * scale);
            mmi.ptMinTrackSize.y = @intFromFloat(@as(f32, @floatFromInt(ws.min_h)) * scale);
            return 0;
        },
        win32.WM_MOUSEMOVE => {
            if (!ws.tracking_leave) {
                var tme: win32.TRACKMOUSEEVENT = .{ .dwFlags = win32.TME_LEAVE, .hwndTrack = hwnd };
                _ = win32.TrackMouseEvent(&tme);
                ws.tracking_leave = true;
            }
            ws.ui_ctx.input.mouse_pos = .{
                .x = @as(f32, @floatFromInt(win32.getXParam(lp))) / scale,
                .y = @as(f32, @floatFromInt(win32.getYParam(lp))) / scale,
            };
            ws.needs_render = true;
            return 0;
        },
        win32.WM_MOUSELEAVE => {
            ws.tracking_leave = false;
            ws.ui_ctx.input.mouse_pos = .{ .x = -1000, .y = -1000 };
            ws.needs_render = true;
            return 0;
        },
        win32.WM_LBUTTONDOWN => {
            _ = win32.SetCapture(hwnd);
            ws.ui_ctx.input.mouse_pos = .{
                .x = @as(f32, @floatFromInt(win32.getXParam(lp))) / scale,
                .y = @as(f32, @floatFromInt(win32.getYParam(lp))) / scale,
            };
            ws.ui_ctx.input.mouse_down = true;
            ws.ui_ctx.input.mouse_pressed = true;
            ws.needs_render = true;
            return 0;
        },
        win32.WM_LBUTTONUP => {
            _ = win32.ReleaseCapture();
            ws.ui_ctx.input.mouse_pos = .{
                .x = @as(f32, @floatFromInt(win32.getXParam(lp))) / scale,
                .y = @as(f32, @floatFromInt(win32.getYParam(lp))) / scale,
            };
            ws.ui_ctx.input.mouse_down = false;
            ws.ui_ctx.input.mouse_released = true;
            ws.needs_render = true;
            return 0;
        },
        win32.WM_MOUSEWHEEL => {
            const delta = win32.getWheelDelta(wp);
            ws.ui_ctx.input.mouse_wheel += @as(f32, @floatFromInt(delta)) / 120.0;
            ws.needs_render = true;
            return 0;
        },
        win32.WM_SETCURSOR => {
            if (win32.loWord(lp) == win32.HTCLIENT) {
                const cur = switch (ws.ui_ctx.cursor_kind) {
                    .arrow => ws.cursor_arrow,
                    .hand => ws.cursor_hand,
                    .ibeam => ws.cursor_ibeam,
                };
                _ = win32.SetCursor(cur);
                return 1;
            }
        },
        win32.WM_KEYDOWN => {
            const vk: u32 = @truncate(wp);
            switch (vk) {
                win32.VK_LEFT => ws.ui_ctx.input.key_left = true,
                win32.VK_RIGHT => ws.ui_ctx.input.key_right = true,
                win32.VK_UP => ws.ui_ctx.input.key_up = true,
                win32.VK_DOWN => ws.ui_ctx.input.key_down = true,
                win32.VK_BACK => ws.ui_ctx.input.key_backspace = true,
                win32.VK_DELETE => ws.ui_ctx.input.key_delete = true,
                win32.VK_RETURN => ws.ui_ctx.input.key_enter = true,
                win32.VK_ESCAPE => ws.ui_ctx.input.key_escape = true,
                win32.VK_HOME => ws.ui_ctx.input.key_home = true,
                win32.VK_END => ws.ui_ctx.input.key_end = true,
                win32.VK_TAB => ws.ui_ctx.input.key_tab = true,
                else => {},
            }
            ws.ui_ctx.input.ctrl_down = (win32.GetKeyState(@intCast(win32.VK_CONTROL)) & @as(i16, -32768)) != 0;
            ws.ui_ctx.input.shift_down = (win32.GetKeyState(@intCast(win32.VK_SHIFT)) & @as(i16, -32768)) != 0;
            ws.needs_render = true;
            return 0;
        },
        win32.WM_CHAR => {
            const ch: u16 = @truncate(wp);
            if (ch >= 0xD800 and ch <= 0xDBFF) {
                ws.high_surrogate = ch;
            } else if (ch >= 0xDC00 and ch <= 0xDFFF and ws.high_surrogate != 0) {
                const cp: u21 = 0x10000 + ((@as(u21, ws.high_surrogate - 0xD800) << 10) | @as(u21, ch - 0xDC00));
                ws.high_surrogate = 0;
                var utf8: [4]u8 = undefined;
                const n = std.unicode.utf8Encode(cp, &utf8) catch 0;
                if (n > 0) ws.ui_ctx.input.pushUtf8(utf8[0..n]);
                ws.needs_render = true;
            } else if (ch >= 0x20 and ch != 0x7F) {
                ws.high_surrogate = 0;
                var utf8: [4]u8 = undefined;
                const n = std.unicode.utf8Encode(@as(u21, ch), &utf8) catch 0;
                if (n > 0) ws.ui_ctx.input.pushUtf8(utf8[0..n]);
                ws.needs_render = true;
            }
            return 0;
        },
        WM_WAKE => {
            ws.needs_render = true;
            return 0;
        },
        else => {},
    }
    return win32.DefWindowProcW(hwnd, msg, wp, lp);
}
