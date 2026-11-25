//! Opt-in input trace for diagnosing real-world input bugs.
//!
//! Set `MOONUI_TRACE=<file>` before starting the app: every mouse, keyboard,
//! focus, capture and IME message plus every caret / selection change of the
//! focused text editor is appended to that file, one line each, with a
//! millisecond timestamp. Text content is never written (only lengths), so a
//! trace can be shared. Without the variable nothing is opened or formatted.
const std = @import("std");
const win32 = @import("win32/win32.zig");

const HANDLE = win32.HANDLE;
const GENERIC_WRITE: u32 = 0x40000000;
const FILE_SHARE_READ: u32 = 0x1;
const CREATE_ALWAYS: u32 = 2;
const FILE_ATTRIBUTE_NORMAL: u32 = 0x80;
const INVALID_HANDLE: usize = std.math.maxInt(usize);

extern "kernel32" fn GetEnvironmentVariableW(name: [*:0]const u16, buf: ?[*]u16, size: u32) callconv(.winapi) u32;
extern "kernel32" fn CreateFileW(name: [*:0]const u16, access: u32, share: u32, sa: ?*anyopaque, disposition: u32, flags: u32, template: ?HANDLE) callconv(.winapi) usize;
extern "kernel32" fn WriteFile(h: HANDLE, buf: [*]const u8, len: u32, written: ?*u32, overlapped: ?*anyopaque) callconv(.winapi) win32.BOOL;

var handle: ?HANDLE = null;
var t0: i64 = 0;
var freq: i64 = 1;

pub fn enabled() bool {
    return handle != null;
}

/// Opens the trace file named by MOONUI_TRACE, if set. Call once at startup.
pub fn init() void {
    if (handle != null) return;
    var path: [520]u16 = undefined;
    const name = std.unicode.utf8ToUtf16LeStringLiteral("MOONUI_TRACE");
    const n = GetEnvironmentVariableW(name, &path, path.len);
    if (n == 0 or n >= path.len) return;
    path[n] = 0;
    const h = CreateFileW(@ptrCast(&path), GENERIC_WRITE, FILE_SHARE_READ, null, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, null);
    if (h == 0 or h == INVALID_HANDLE) return;
    handle = @ptrFromInt(h);
    _ = win32.QueryPerformanceFrequency(&freq);
    _ = win32.QueryPerformanceCounter(&t0);
    log("trace start", .{});
}

/// Appends one line (`<ms> <message>`). No-op unless tracing is on.
pub fn log(comptime fmt: []const u8, args: anytype) void {
    const h = handle orelse return;
    var now: i64 = 0;
    _ = win32.QueryPerformanceCounter(&now);
    const ms = @divTrunc((now - t0) * 1000, @max(freq, 1));
    var buf: [600]u8 = undefined;
    const line = std.fmt.bufPrint(&buf, "{d:>8} " ++ fmt ++ "\r\n", .{ms} ++ args) catch return;
    _ = WriteFile(h, line.ptr, @intCast(line.len), null, null);
}

pub fn messageName(msg: u32) ?[]const u8 {
    return switch (msg) {
        0x0006 => "WM_ACTIVATE",
        0x0007 => "WM_SETFOCUS",
        0x0008 => "WM_KILLFOCUS",
        0x0021 => "WM_MOUSEACTIVATE",
        0x0100 => "WM_KEYDOWN",
        0x0101 => "WM_KEYUP",
        0x0102 => "WM_CHAR",
        0x0104 => "WM_SYSKEYDOWN",
        0x010D => "WM_IME_STARTCOMPOSITION",
        0x010E => "WM_IME_ENDCOMPOSITION",
        0x010F => "WM_IME_COMPOSITION",
        0x0281 => "WM_IME_SETCONTEXT",
        0x0282 => "WM_IME_NOTIFY",
        0x0286 => "WM_IME_CHAR",
        0x0200 => "WM_MOUSEMOVE",
        0x0201 => "WM_LBUTTONDOWN",
        0x0202 => "WM_LBUTTONUP",
        0x0203 => "WM_LBUTTONDBLCLK",
        0x0204 => "WM_RBUTTONDOWN",
        0x0205 => "WM_RBUTTONUP",
        0x020A => "WM_MOUSEWHEEL",
        0x0215 => "WM_CAPTURECHANGED",
        0x02A3 => "WM_MOUSELEAVE",
        0x0245 => "WM_POINTERUPDATE",
        0x0246 => "WM_POINTERDOWN",
        0x0247 => "WM_POINTERUP",
        else => null,
    };
}
