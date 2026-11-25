//! Windows toast notifications for an unpackaged exe, through WinRT
//! (Windows.UI.Notifications) called directly over its ABI.
//!
//! An unpackaged app needs an AppUserModelID registered under
//! HKCU\Software\Classes\AppUserModelId (`registerApp`), otherwise Windows
//! drops its toasts. A click on a toast reaches the app in one of two ways:
//!   - `protocol = true`: Windows opens the `launch` URI, i.e. starts the
//!     registered exe with it (see `shell.registerProtocol`); a running
//!     instance gets it through `shell.forwardToFirst`. Works after a restart.
//!   - otherwise the in-process Activated event posts `launch` to
//!     `shell.postActivation` (only while this process runs).
//!
//! UI thread only (COM must be initialized, as `app.run` does).
const std = @import("std");
const com = @import("win32/com.zig");
const win32 = @import("win32/win32.zig");
const shell = @import("shell.zig");

const GUID = com.GUID;
const HRESULT = com.HRESULT;
const HSTRING = ?*opaque {};

pub const Toast = struct {
    title: []const u8,
    body: []const u8,
    /// Arguments handed back on click (an URI when `protocol`).
    launch: []const u8 = "",
    protocol: bool = false,
    /// Tag + group identify the toast for `remove` (e.g. one per chat).
    tag: []const u8 = "",
    group: []const u8 = "",
    /// Instant-message sound; false = silent.
    sound: bool = true,
};

/// Registers `app_id` for the current user (display name and icon shown on
/// the toasts) and makes it this process's AppUserModelID. Call once at
/// startup, before the window is created (taskbar grouping uses the id too).
pub fn registerApp(app_id: []const u8, display_name: []const u8, icon_path: ?[]const u8) bool {
    var key_buf: [300]u8 = undefined;
    const key = std.fmt.bufPrint(&key_buf, "Software\\Classes\\AppUserModelId\\{s}", .{app_id}) catch return false;
    var ok = shell.setUserString(key, "DisplayName", display_name);
    if (icon_path) |p| {
        ok = ok and shell.setUserString(key, "IconUri", p);
        ok = ok and shell.setUserString(key, "IconBackgroundColor", "FF4F46E5");
    }
    var id_w: [160]u16 = undefined;
    if (com.failed(SetCurrentProcessExplicitAppUserModelID(win32.utf8ToUtf16Z(&id_w, app_id).ptr))) ok = false;
    _ = win32.utf8ToUtf16Z(&g.app_id, app_id);
    return ok;
}

/// Shows a toast. False when toasts are unavailable (no WinRT, id not set).
pub fn show(t: Toast) bool {
    const n = create(t) orelse return false;
    const notifier = g.notifier.?;
    const ok = com.succeeded(method(fn (*Obj, *Obj) callconv(.winapi) HRESULT, notifier, 6)(notifier, n));
    if (ok and !t.protocol) {
        // Keep recent toasts referenced so their click events stay wired
        // while they sit in Action Center.
        if (g.keep[g.keep_next]) |old| release(old);
        g.keep[g.keep_next] = n;
        g.keep_next = (g.keep_next + 1) % g.keep.len;
    } else release(n);
    return ok;
}

/// Builds the ToastNotification (XML, tag / group, click handler) without
/// showing it.
fn create(t: Toast) ?*Obj {
    if (!ensure()) return null;
    var xml_buf: [8192]u8 = undefined;
    const xml = buildXml(&xml_buf, t) catch return null;

    const doc = activate("Windows.Data.Xml.Dom.XmlDocument") orelse return null;
    defer release(doc);
    const io = qi(doc, &IID_IXmlDocumentIO) orelse return null;
    defer release(io);
    const xml_h = HStr.init(xml) orelse return null;
    defer xml_h.deinit();
    if (com.failed(method(fn (*Obj, HSTRING) callconv(.winapi) HRESULT, io, 6)(io, xml_h.h))) return null;
    const xdoc = qi(doc, &IID_IXmlDocument) orelse return null;
    defer release(xdoc);

    const factory = getFactory("Windows.UI.Notifications.ToastNotification", &IID_IToastNotificationFactory) orelse return null;
    defer release(factory);
    var toast: ?*Obj = null;
    if (com.failed(method(fn (*Obj, *Obj, *?*Obj) callconv(.winapi) HRESULT, factory, 6)(factory, xdoc, &toast))) return null;
    const n = toast orelse return null;

    if (t.tag.len > 0 or t.group.len > 0) if (qi(n, &IID_IToastNotification2)) |n2| {
        defer release(n2);
        if (HStr.init(t.tag)) |h| {
            defer h.deinit();
            _ = method(fn (*Obj, HSTRING) callconv(.winapi) HRESULT, n2, 6)(n2, h.h);
        }
        if (HStr.init(t.group)) |h| {
            defer h.deinit();
            _ = method(fn (*Obj, HSTRING) callconv(.winapi) HRESULT, n2, 8)(n2, h.h);
        }
    };
    if (!t.protocol) {
        var token: i64 = 0;
        if (com.failed(method(fn (*Obj, *const ActivatedHandler, *i64) callconv(.winapi) HRESULT, n, 11)(n, &activated_handler, &token))) {
            release(n);
            return null;
        }
    }
    return n;
}

/// Removes this app's toast with `tag` / `group` from Action Center.
pub fn remove(tag: []const u8, group: []const u8) void {
    const hist = history() orelse return;
    defer release(hist);
    const ht = HStr.init(tag) orelse return;
    defer ht.deinit();
    const hg = HStr.init(group) orelse return;
    defer hg.deinit();
    const id = HStr.initW(appId()) orelse return;
    defer id.deinit();
    // IToastNotificationHistory::RemoveGroupedTagWithId
    _ = method(fn (*Obj, HSTRING, HSTRING, HSTRING) callconv(.winapi) HRESULT, hist, 8)(hist, ht.h, hg.h, id.h);
}

/// Removes all of this app's toasts from Action Center.
pub fn clear() void {
    const hist = history() orelse return;
    defer release(hist);
    const id = HStr.initW(appId()) orelse return;
    defer id.deinit();
    // IToastNotificationHistory::ClearWithId
    _ = method(fn (*Obj, HSTRING) callconv(.winapi) HRESULT, hist, 12)(hist, id.h);
}

/// Drops the cached WinRT objects (call before COM is uninitialized).
pub fn shutdown() void {
    for (&g.keep) |*k| if (k.*) |o| {
        release(o);
        k.* = null;
    };
    if (g.notifier) |n| release(n);
    g.notifier = null;
}

/// The toast XML (ToastGeneric: one-line title, body, IM sound).
pub fn buildXml(buf: []u8, t: Toast) ![]const u8 {
    var w: std.Io.Writer = .fixed(buf);
    try w.writeAll("<toast launch=\"");
    try escape(&w, t.launch);
    try w.writeAll("\"");
    if (t.protocol) try w.writeAll(" activationType=\"protocol\"");
    try w.writeAll("><visual><binding template=\"ToastGeneric\"><text hint-maxLines=\"1\">");
    try escape(&w, t.title);
    try w.writeAll("</text><text>");
    try escape(&w, t.body);
    try w.writeAll("</text></binding></visual>");
    try w.writeAll(if (t.sound) "<audio src=\"ms-winsoundevent:Notification.IM\"/>" else "<audio silent=\"true\"/>");
    try w.writeAll("</toast>");
    return w.buffered();
}

fn escape(w: *std.Io.Writer, s: []const u8) !void {
    for (s) |ch| switch (ch) {
        '&' => try w.writeAll("&amp;"),
        '<' => try w.writeAll("&lt;"),
        '>' => try w.writeAll("&gt;"),
        '"' => try w.writeAll("&quot;"),
        '\'' => try w.writeAll("&apos;"),
        // Control characters are not allowed in XML 1.0.
        0...8, 11, 12, 14...31 => try w.writeByte(' '),
        else => try w.writeByte(ch),
    };
}

// ------------------------------------------------------------ WinRT plumbing

const Obj = extern struct { vtbl: [*]const ?*const anyopaque };

fn method(comptime F: type, o: *Obj, index: usize) *const F {
    return @ptrCast(o.vtbl[index].?);
}

fn release(o: *Obj) void {
    _ = method(fn (*Obj) callconv(.winapi) u32, o, 2)(o);
}

fn qi(o: *Obj, iid: *const GUID) ?*Obj {
    var out: ?*Obj = null;
    if (com.failed(method(fn (*Obj, *const GUID, *?*Obj) callconv(.winapi) HRESULT, o, 0)(o, iid, &out))) return null;
    return out;
}

const State = struct {
    app_id: [160]u16 = @splat(0),
    loaded: bool = false,
    failed: bool = false,
    notifier: ?*Obj = null,
    keep: [32]?*Obj = @splat(null),
    keep_next: usize = 0,
    create_string: ?*const fn ([*]const u16, u32, *HSTRING) callconv(.winapi) HRESULT = null,
    delete_string: ?*const fn (HSTRING) callconv(.winapi) HRESULT = null,
    get_buffer: ?*const fn (HSTRING, ?*u32) callconv(.winapi) ?[*]const u16 = null,
    get_factory: ?*const fn (HSTRING, *const GUID, *?*Obj) callconv(.winapi) HRESULT = null,
    activate_instance: ?*const fn (HSTRING, *?*Obj) callconv(.winapi) HRESULT = null,
};
var g: State = .{};

fn appId() []const u16 {
    return std.mem.sliceTo(&g.app_id, 0);
}

const HStr = struct {
    h: HSTRING,

    fn init(utf8: []const u8) ?HStr {
        var buf: [4096]u16 = undefined;
        const n = std.unicode.utf8ToUtf16Le(&buf, utf8) catch return null;
        return initW(buf[0..n]);
    }
    fn initW(w: []const u16) ?HStr {
        var h: HSTRING = null;
        if (com.failed(g.create_string.?(w.ptr, @intCast(w.len), &h))) return null;
        return .{ .h = h };
    }
    fn deinit(s: HStr) void {
        if (s.h != null) _ = g.delete_string.?(s.h);
    }
};

/// Loads combase's WinRT entry points and the notifier for the app id.
fn ensure() bool {
    if (g.notifier != null) return true;
    if (g.failed or g.app_id[0] == 0) return false;
    if (!g.loaded) {
        g.loaded = true;
        const lib = LoadLibraryExW(std.unicode.utf8ToUtf16LeStringLiteral("combase.dll"), null, LOAD_LIBRARY_SEARCH_SYSTEM32) orelse {
            g.failed = true;
            return false;
        };
        g.create_string = @ptrCast(GetProcAddress(lib, "WindowsCreateString"));
        g.delete_string = @ptrCast(GetProcAddress(lib, "WindowsDeleteString"));
        g.get_buffer = @ptrCast(GetProcAddress(lib, "WindowsGetStringRawBuffer"));
        g.get_factory = @ptrCast(GetProcAddress(lib, "RoGetActivationFactory"));
        g.activate_instance = @ptrCast(GetProcAddress(lib, "RoActivateInstance"));
        if (g.create_string == null or g.delete_string == null or g.get_buffer == null or g.get_factory == null or g.activate_instance == null) {
            g.failed = true;
            return false;
        }
    }
    const statics = getFactory("Windows.UI.Notifications.ToastNotificationManager", &IID_IToastNotificationManagerStatics) orelse return false;
    defer release(statics);
    const id = HStr.initW(appId()) orelse return false;
    defer id.deinit();
    var notifier: ?*Obj = null;
    // CreateToastNotifierWithId
    if (com.failed(method(fn (*Obj, HSTRING, *?*Obj) callconv(.winapi) HRESULT, statics, 7)(statics, id.h, &notifier))) return false;
    g.notifier = notifier;
    return notifier != null;
}

fn getFactory(comptime class: []const u8, iid: *const GUID) ?*Obj {
    const name = HStr.initW(std.unicode.utf8ToUtf16LeStringLiteral(class)) orelse return null;
    defer name.deinit();
    var out: ?*Obj = null;
    if (com.failed(g.get_factory.?(name.h, iid, &out))) return null;
    return out;
}

fn activate(comptime class: []const u8) ?*Obj {
    const name = HStr.initW(std.unicode.utf8ToUtf16LeStringLiteral(class)) orelse return null;
    defer name.deinit();
    var out: ?*Obj = null;
    if (com.failed(g.activate_instance.?(name.h, &out))) return null;
    return out;
}

fn history() ?*Obj {
    if (!ensure()) return null;
    const statics = getFactory("Windows.UI.Notifications.ToastNotificationManager", &IID_IToastNotificationManagerStatics2) orelse return null;
    defer release(statics);
    var out: ?*Obj = null;
    if (com.failed(method(fn (*Obj, *?*Obj) callconv(.winapi) HRESULT, statics, 6)(statics, &out))) return null;
    return out;
}

// TypedEventHandler<ToastNotification, Object> for Activated. A static,
// agile object: it may be called on any thread and is never freed.
const ActivatedHandler = extern struct { vtbl: *const VTable };
const VTable = extern struct {
    QueryInterface: *const fn (*const ActivatedHandler, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    AddRef: *const fn (*const ActivatedHandler) callconv(.winapi) u32,
    Release: *const fn (*const ActivatedHandler) callconv(.winapi) u32,
    Invoke: *const fn (*const ActivatedHandler, ?*Obj, ?*Obj) callconv(.winapi) HRESULT,
};
const activated_vtbl: VTable = .{ .QueryInterface = handlerQi, .AddRef = handlerRef, .Release = handlerRef, .Invoke = handlerInvoke };
const activated_handler: ActivatedHandler = .{ .vtbl = &activated_vtbl };

fn handlerQi(self: *const ActivatedHandler, iid: *const GUID, out: *?*anyopaque) callconv(.winapi) HRESULT {
    if (guidEql(iid, &IID_IUnknown) or guidEql(iid, &IID_IAgileObject) or guidEql(iid, &IID_ActivatedHandler)) {
        out.* = @ptrCast(@constCast(self));
        return com.S_OK;
    }
    out.* = null;
    return E_NOINTERFACE;
}

fn handlerRef(_: *const ActivatedHandler) callconv(.winapi) u32 {
    return 1;
}

fn handlerInvoke(_: *const ActivatedHandler, _: ?*Obj, args: ?*Obj) callconv(.winapi) HRESULT {
    const a = args orelse return com.S_OK;
    const ev = qi(a, &IID_IToastActivatedEventArgs) orelse return com.S_OK;
    defer release(ev);
    var h: HSTRING = null;
    if (com.failed(method(fn (*Obj, *HSTRING) callconv(.winapi) HRESULT, ev, 6)(ev, &h))) return com.S_OK;
    defer _ = g.delete_string.?(h);
    var len: u32 = 0;
    const raw = g.get_buffer.?(h, &len) orelse return com.S_OK;
    var utf8: [4096]u8 = undefined;
    const n = std.unicode.utf16LeToUtf8(&utf8, raw[0..@min(len, 1300)]) catch return com.S_OK;
    shell.postActivation(utf8[0..n]);
    return com.S_OK;
}

fn guidEql(a: *const GUID, b: *const GUID) bool {
    return std.mem.eql(u8, std.mem.asBytes(a), std.mem.asBytes(b));
}

const E_NOINTERFACE: HRESULT = @bitCast(@as(u32, 0x80004002));
const LOAD_LIBRARY_SEARCH_SYSTEM32: u32 = 0x800;

const IID_IUnknown = GUID.init(0x00000000, 0x0000, 0x0000, .{ 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 });
const IID_IAgileObject = GUID.init(0x94ea2b94, 0xe9cc, 0x49e0, .{ 0xc0, 0xff, 0xee, 0x64, 0xca, 0x8f, 0x5b, 0x90 });
const IID_ActivatedHandler = GUID.init(0xab54de2d, 0x97d9, 0x5528, .{ 0xb6, 0xad, 0x10, 0x5a, 0xfe, 0x15, 0x65, 0x30 });
const IID_IToastNotificationManagerStatics = GUID.init(0x50ac103f, 0xd235, 0x4598, .{ 0xbb, 0xef, 0x98, 0xfe, 0x4d, 0x1a, 0x3a, 0xd4 });
const IID_IToastNotificationManagerStatics2 = GUID.init(0x7ab93c52, 0x0e48, 0x4750, .{ 0xba, 0x9d, 0x1a, 0x41, 0x13, 0x98, 0x18, 0x47 });
const IID_IToastNotificationFactory = GUID.init(0x04124b20, 0x82c6, 0x4229, .{ 0xb1, 0x09, 0xfd, 0x9e, 0xd4, 0x66, 0x2b, 0x53 });
const IID_IToastNotification2 = GUID.init(0x9dfb9fd1, 0x143a, 0x490e, .{ 0x90, 0xbf, 0xb9, 0xfb, 0xa7, 0x13, 0x2d, 0xe7 });
const IID_IToastActivatedEventArgs = GUID.init(0xe3bf92f3, 0xc197, 0x436f, .{ 0x82, 0x65, 0x06, 0x25, 0x82, 0x4f, 0x8d, 0xac });
const IID_IXmlDocument = GUID.init(0xf7f3a506, 0x1e87, 0x42d6, .{ 0xbc, 0xfb, 0xb8, 0xc8, 0x09, 0xfa, 0x54, 0x94 });
const IID_IXmlDocumentIO = GUID.init(0x6cd0e74e, 0xee65, 0x4489, .{ 0x9e, 0xbf, 0xca, 0x43, 0xe8, 0x7b, 0xa6, 0x37 });

extern "kernel32" fn LoadLibraryExW(name: [*:0]const u16, file: ?*anyopaque, flags: u32) callconv(.winapi) ?win32.HMODULE;
extern "kernel32" fn GetProcAddress(module: win32.HMODULE, name: [*:0]const u8) callconv(.winapi) ?*const anyopaque;
extern "shell32" fn SetCurrentProcessExplicitAppUserModelID(id: [*:0]const u16) callconv(.winapi) HRESULT;

test "toast xml escapes text and marks protocol activation" {
    var buf: [1024]u8 = undefined;
    const xml = try buildXml(&buf, .{ .title = "A & B", .body = "<b>\"hi\"\x01", .launch = "app://x?a=1&b=2", .protocol = true });
    try std.testing.expectEqualStrings(
        "<toast launch=\"app://x?a=1&amp;b=2\" activationType=\"protocol\"><visual><binding template=\"ToastGeneric\">" ++
            "<text hint-maxLines=\"1\">A &amp; B</text><text>&lt;b&gt;&quot;hi&quot; </text></binding></visual>" ++
            "<audio src=\"ms-winsoundevent:Notification.IM\"/></toast>",
        xml,
    );
    const quiet = try buildXml(&buf, .{ .title = "t", .body = "b", .sound = false });
    try std.testing.expect(std.mem.indexOf(u8, quiet, "activationType") == null);
    try std.testing.expect(std.mem.indexOf(u8, quiet, "<audio silent=\"true\"/>") != null);
    var small: [16]u8 = undefined;
    try std.testing.expectError(error.WriteFailed, buildXml(&small, .{ .title = "t", .body = "b" }));
}

test "pinterface IID of TypedEventHandler<ToastNotification, Object>" {
    // WinRT parameterized-interface GUID: SHA-1 (UUID v5) of the signature
    // in the WinRT namespace; must match the SDK header's uuid.
    const ns = [_]u8{ 0x11, 0xf4, 0x7a, 0xd5, 0x7b, 0x73, 0x42, 0xc0, 0xab, 0xae, 0x87, 0x8b, 0x1e, 0x16, 0xad, 0xee };
    const sig = "pinterface({9de1c534-6ae1-11e0-84e1-18a905bcc53f};rc(Windows.UI.Notifications.ToastNotification;{997e2675-059e-4e60-8b06-1760917c8b80});cinterface(IInspectable))";
    var h = std.crypto.hash.Sha1.init(.{});
    h.update(&ns);
    h.update(sig);
    var d: [20]u8 = undefined;
    h.final(&d);
    const d1 = std.mem.readInt(u32, d[0..4], .big);
    const d2 = std.mem.readInt(u16, d[4..6], .big);
    const d3 = (std.mem.readInt(u16, d[6..8], .big) & 0x0fff) | 0x5000;
    var d4: [8]u8 = d[8..16].*;
    d4[0] = (d4[0] & 0x3f) | 0x80;
    try std.testing.expect(guidEql(&GUID.init(d1, d2, d3, d4), &IID_ActivatedHandler));
}

test "toast object is built through WinRT (not shown)" {
    _ = com.CoInitializeEx(null, com.COINIT_APARTMENTTHREADED);
    defer com.CoUninitialize();
    const saved = g.app_id;
    defer {
        shutdown();
        g.app_id = saved;
    }
    // No registry write here: an unregistered id still yields a notifier.
    _ = win32.utf8ToUtf16Z(&g.app_id, "MoonUI.Test.Toast");
    const n = create(.{ .title = "标题", .body = "正文", .launch = "x", .tag = "1-2", .group = "chat" }) orelse return error.WinRtUnavailable;
    defer release(n);
    // Tag round trip through IToastNotification2::get_Tag.
    const n2 = qi(n, &IID_IToastNotification2) orelse return error.NoToast2;
    defer release(n2);
    var h: HSTRING = null;
    try std.testing.expect(com.succeeded(method(fn (*Obj, *HSTRING) callconv(.winapi) HRESULT, n2, 7)(n2, &h)));
    defer _ = g.delete_string.?(h);
    var len: u32 = 0;
    const raw = g.get_buffer.?(h, &len).?;
    try std.testing.expectEqualSlices(u16, std.unicode.utf8ToUtf16LeStringLiteral("1-2"), raw[0..len]);
    // Handler QI: the event source asks for the delegate and IAgileObject.
    var out: ?*anyopaque = null;
    try std.testing.expectEqual(com.S_OK, handlerQi(&activated_handler, &IID_IAgileObject, &out));
    try std.testing.expectEqual(E_NOINTERFACE, handlerQi(&activated_handler, &IID_IXmlDocument, &out));
}
