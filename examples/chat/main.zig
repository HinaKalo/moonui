//! MoonUI IM demo: conversation list, grouped message bubbles, quotes,
//! delivery status and a growing composer, all drawn with Direct2D.
//! A background thread simulates the server acknowledging each sent message
//! and wakes the UI loop with `ui.wake()`.
const std = @import("std");
const ui = @import("moonui");

extern "kernel32" fn Sleep(ms: u32) callconv(.winapi) void;

const ChatMsg = struct {
    own: bool,
    author: []const u8,
    text_buf: [256]u8 = undefined,
    text_len: usize = 0,
    time: []const u8,
    quote_author: ?[]const u8 = null,
    quote_text: ?[]const u8 = null,
    status: ui.chat.MsgStatus = .read,

    fn init(own: bool, author: []const u8, txt: []const u8, time: []const u8, qa: ?[]const u8, qt: ?[]const u8) ChatMsg {
        var m: ChatMsg = .{
            .own = own,
            .author = author,
            .time = time,
            .quote_author = qa,
            .quote_text = qt,
        };
        const n = @min(txt.len, m.text_buf.len);
        @memcpy(m.text_buf[0..n], txt[0..n]);
        m.text_len = n;
        return m;
    }

    fn text(self: *const ChatMsg) []const u8 {
        return self.text_buf[0..self.text_len];
    }
};

const Conversation = struct {
    name: []const u8,
    role: []const u8,
    time: []const u8,
    unread: u32,
    online: bool,
    msgs: [32]ChatMsg = undefined,
    msg_count: usize = 0,

    fn push(self: *Conversation, m: ChatMsg) void {
        if (self.msg_count < self.msgs.len) {
            self.msgs[self.msg_count] = m;
            self.msg_count += 1;
        }
    }

    fn preview(self: *const Conversation) []const u8 {
        if (self.msg_count == 0) return "";
        return self.msgs[self.msg_count - 1].text();
    }
};

const State = struct {
    convs: [4]Conversation = undefined,
    selected: usize = 0,
    search: ui.TextBuffer(64) = .{},
    composer: ui.chat.Composer(512) = .{},
    theme_idx: usize = 0,
    acks: [16]Ack = @splat(.{}),
};

/// A sent message waiting for its (simulated) server acknowledgement.
/// Only `done` is shared with the worker thread.
const Ack = struct {
    active: bool = false,
    conv_idx: usize = 0,
    msg_idx: usize = 0,
    done: std.atomic.Value(bool) = .init(false),
};

fn ackWorker(ack: *Ack) void {
    Sleep(260); // simulated network round trip
    ack.done.store(true, .release);
    ui.wake(); // thread-safe: renders one more frame
}

fn startAck(s: *State, conv_idx: usize, msg_idx: usize) void {
    for (&s.acks) |*a| {
        if (a.active) continue;
        a.* = .{ .active = true, .conv_idx = conv_idx, .msg_idx = msg_idx };
        const t = std.Thread.spawn(.{}, ackWorker, .{a}) catch {
            a.active = false;
            s.convs[conv_idx].msgs[msg_idx].status = .failed;
            return;
        };
        t.detach();
        return;
    }
    s.convs[conv_idx].msgs[msg_idx].status = .sent;
}

/// Runs on the UI thread at the start of every frame.
fn collectAcks(s: *State) void {
    for (&s.acks) |*a| {
        if (!a.active or !a.done.load(.acquire)) continue;
        const conv = &s.convs[a.conv_idx];
        if (a.msg_idx < conv.msg_count) conv.msgs[a.msg_idx].status = .read;
        a.active = false;
    }
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[i .. i + needle.len], needle)) return true;
    }
    return false;
}

pub fn main(init: std.process.Init) !void {
    var capture: ?[]const u8 = null;
    var theme_idx: usize = 0;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var i: usize = 1;
    while (i + 1 < args.len) : (i += 2) {
        if (std.mem.eql(u8, args[i], "--capture")) {
            capture = args[i + 1];
        } else if (std.mem.eql(u8, args[i], "--theme")) {
            theme_idx = @min(std.fmt.parseInt(usize, args[i + 1], 10) catch 0, ui.themes.all.len - 1);
        }
    }

    var state: State = .{ .theme_idx = theme_idx };
    seedData(&state);

    try ui.run(.{
        .title = "MoonChat (moonui demo)",
        .width = 1280,
        .height = 820,
        .theme = ui.themes.all[theme_idx].*,
        .capture_path = capture,
    }, &state, frame);
}

fn seedData(s: *State) void {
    s.convs[0] = .{ .name = "Moon Ecosystem", .role = "4 members · Direct2D + DirectWrite", .time = "14:32", .unread = 0, .online = true };
    s.convs[0].push(ChatMsg.init(false, "Grace Hopper", "纯 Zig 原生 Direct2D + DirectComposition 皮肤已经跑通了！零 ImGui 依赖，空闲 CPU 占用 0%。", "14:28", null, null));
    s.convs[0].push(ChatMsg.init(false, "Alan Turing", "长聊天记录也不卡：DirectWrite 排版跨帧缓存，屏幕外的消息直接剔除。", "14:30", "Grace Hopper", "纯 Zig 原生 Direct2D + DirectComposition 皮肤已经跑通了！"));
    s.convs[0].push(ChatMsg.init(true, "Me", "太棒了！其他项目只要一条 zig fetch --save 就能用上 moonui。", "14:32", null, null));

    s.convs[1] = .{ .name = "Ada Lovelace", .role = "Online · Graphics Engineer", .time = "13:15", .unread = 2, .online = true };
    s.convs[1].push(ChatMsg.init(false, "Ada Lovelace", "DirectWrite 的中文字体回退（Segoe UI + 微软雅黑）在 150% DPI 下非常锐利。", "13:15", null, null));

    s.convs[2] = .{ .name = "Design System", .role = "Midnight · Daylight · Ember · Aurora", .time = "Yesterday", .unread = 0, .online = false };
    s.convs[2].push(ChatMsg.init(false, "Margaret H.", "四套内置主题色板与 58 个矢量图标已全部对齐。", "Yesterday", null, null));

    s.convs[3] = .{ .name = "Build Bot", .role = "CI / zig build test", .time = "Tue", .unread = 1, .online = true };
    s.convs[3].push(ChatMsg.init(false, "Build Bot", "zig build test 全部通过。", "Tue", null, null));
}

fn frame(s: *State) void {
    collectAcks(s);
    const u = ui.ui.get();
    const p = ui.palette();
    const vp = u.viewport;
    const sidebar_w: f32 = 300;

    // ---- Left conversation sidebar
    ui.beginSidebar(.{ .width = sidebar_w, .padding = 12 });
    ui.sidebarBrand("MoonChat", "moonui demo", .layers);
    _ = ui.searchBox("##conv_search", &s.search.buf, "Search conversations...");
    ui.space(.sm);

    const q = s.search.slice();
    for (&s.convs, 0..) |*c, idx| {
        if (q.len > 0 and !containsIgnoreCase(c.name, q)) continue;
        if (ui.chat.conversation(ui.fmt("conv-{d}", .{idx}), .{
            .name = c.name,
            .preview = c.preview(),
            .time = c.time,
            .unread = c.unread,
            .online = c.online,
            .selected = s.selected == idx,
        })) {
            s.selected = idx;
            c.unread = 0;
        }
    }

    ui.sidebarFooter(48);
    ui.beginRow(.sm);
    if (ui.button(ui.fmt("Theme: {s}", .{ui.themes.all[s.theme_idx].name}), .{ .variant = .soft, .size = .sm, .icon = .palette })) {
        s.theme_idx = (s.theme_idx + 1) % ui.themes.all.len;
        ui.setTheme(ui.themes.all[s.theme_idx].*);
    }
    ui.endRow();
    ui.endSidebar();

    // ---- Right chat pane: Header + Timeline + Composer
    const pane_x = sidebar_w;
    const pane_w = @max(vp.x - sidebar_w, 200);
    const header_h: f32 = 64;
    const composer_h: f32 = 66;
    const conv = &s.convs[s.selected];

    // Top Header bar
    const hdr_r = ui.Rect.xywh(pane_x, 0, pane_w, header_h);
    u.dl().rectFilled(hdr_r, p.bg_subtle.withAlpha(0.7), 0);
    u.dl().line(ui.v2(pane_x, header_h - 0.5), ui.v2(vp.x, header_h - 0.5), p.border, 1);
    u.pushBox(.{
        .origin_x = pane_x + 20,
        .origin_y = 12,
        .avail_w = pane_w - 40,
        .cursor_x = pane_x + 20,
        .cursor_y = 12,
        .max_x = pane_x + 20,
        .max_y = 12,
        .spacing_y = 2,
    });
    ui.beginRow(.md);
    ui.avatar(conv.name, .{ .size = 38, .status = if (conv.online) .success else null });
    ui.next();
    ui.beginGroup();
    ui.text(conv.name, .{ .size = .title, .weight = .semibold });
    ui.text(conv.role, .{ .size = .caption, .ink = .muted });
    ui.endGroup();
    ui.endRow();
    ui.sameLine(.sm);
    ui.alignRight(110);
    ui.badge("Connected", .{ .tone = .success, .dot = true });
    _ = u.popBox();

    // Middle Message Timeline
    const list_r = ui.Rect.xywh(pane_x, header_h, pane_w, @max(vp.y - header_h - composer_h, 60));
    u.dl().pushClip(list_r);
    u.pushBox(.{
        .origin_x = pane_x + 24,
        .origin_y = header_h + 16,
        .avail_w = pane_w - 48,
        .cursor_x = pane_x + 24,
        .cursor_y = header_h + 16,
        .max_x = pane_x + 24,
        .max_y = header_h + 16,
        .spacing_y = 6,
    });
    ui.chat.timeDivider("Today");
    ui.chat.systemNotice("Messages are acknowledged by a simulated server thread");
    ui.space(.xs);
    for (conv.msgs[0..conv.msg_count], 0..) |*m, mi| {
        const prev_same = mi > 0 and conv.msgs[mi - 1].own == m.own and std.mem.eql(u8, conv.msgs[mi - 1].author, m.author);
        const next_same = mi + 1 < conv.msg_count and conv.msgs[mi + 1].own == m.own and std.mem.eql(u8, conv.msgs[mi + 1].author, m.author);
        const pos: ui.chat.GroupPos = if (!prev_same and !next_same) .single else if (!prev_same) .first else if (!next_same) .last else .middle;
        _ = ui.chat.message(ui.fmt("m-{d}-{d}", .{ s.selected, mi }), .{
            .own = m.own,
            .author = m.author,
            .text = m.text(),
            .time = m.time,
            .quote_author = m.quote_author,
            .quote_text = m.quote_text,
            .status = m.status,
        }, .{ .pos = pos });
    }
    _ = u.popBox();
    u.dl().popClip();

    // Bottom Composer bar
    const comp_y = vp.y - composer_h;
    const comp_r = ui.Rect.xywh(pane_x, comp_y, pane_w, composer_h);
    u.dl().rectFilled(comp_r, p.bg_subtle.withAlpha(0.75), 0);
    u.dl().line(ui.v2(pane_x, comp_y + 0.5), ui.v2(vp.x, comp_y + 0.5), p.border, 1);
    u.pushBox(.{
        .origin_x = pane_x + 20,
        .origin_y = comp_y + 16,
        .avail_w = pane_w - 40,
        .cursor_x = pane_x + 20,
        .cursor_y = comp_y + 16,
        .max_x = pane_x + 20,
        .max_y = comp_y + 16,
    });
    const ev = s.composer.draw("##composer", .{ .hint = "Message (Enter to send, Shift+Enter for a new line)" });
    if (ev.attach) {
        ui.toast(.info, "Attachment", .{ .description = "Hook up a file picker or AppOptions.accept_files here." });
    }
    if (ev.send and s.composer.text().len > 0) {
        var msg = ChatMsg.init(true, "Me", s.composer.text(), "Now", null, null);
        msg.status = .sending;
        const msg_idx = conv.msg_count;
        conv.push(msg);
        s.composer.clear();
        startAck(s, s.selected, msg_idx);
    }
    _ = u.popBox();
}
