//! Moon Ecosystem IM Demo — combines `moonui` (pure Direct2D + DirectComposition)
//! with `mooncore` (OS thread pool + UI dispatcher + crypto) and `moonchat` (LumenIM SDK).
const std = @import("std");
const ui = @import("moonui");
const core = @import("mooncore");
const moonchat = @import("moonchat");

const ChatMsg = struct {
    id: [32]u8,
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
            .id = moonchat.newRequestId(),
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
    sdk_ready: bool = true,
};

const ReplyJob = struct {
    state: *State,
    conv_idx: usize,
    msg_idx: usize,
};

fn asyncAckWork(job: *ReplyJob) void {
    // Simulate network RTT on Windows OS thread pool via mooncore.os.runAsync
    core.os.sleepMs(260);
    core.os.post(job, asyncAckDone);
}

fn asyncAckDone(job: *ReplyJob) void {
    const s = job.state;
    const conv = &s.convs[job.conv_idx];
    if (job.msg_idx < conv.msg_count) {
        conv.msgs[job.msg_idx].status = .read;
    }
    std.heap.page_allocator.destroy(job);
}

fn drainMoonCore() void {
    _ = core.os.drain();
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

    // Wire mooncore background dispatcher to moonui's event loop!
    core.os.setWakeHandler(ui.wake);

    var state: State = .{ .theme_idx = theme_idx };
    seedData(&state);

    try ui.run(.{
        .title = "MoonChat Native (moonui + mooncore + moonchat)",
        .width = 1280,
        .height = 820,
        .theme = ui.themes.all[theme_idx].*,
        .capture_path = capture,
        .on_frame_start = drainMoonCore,
    }, &state, frame);
}

fn seedData(s: *State) void {
    s.convs[0] = .{ .name = "Moon Ecosystem", .role = "4 members · Direct2D + moon-sdk", .time = "14:32", .unread = 0, .online = true };
    s.convs[0].push(ChatMsg.init(false, "Grace Hopper", "纯 Zig 原生 Direct2D + DirectComposition 皮肤已经跑通了！零 ImGui 依赖，空闲 CPU 占用 0%。", "14:28", null, null));
    s.convs[0].push(ChatMsg.init(false, "Alan Turing", "而且 moon-sdk（mooncore + moonchat）也彻底解耦成独立包了，WinHTTP / DPAPI / SQLite / WebSocket 全套可用。", "14:30", "Grace Hopper", "纯 Zig 原生 Direct2D + DirectComposition 皮肤已经跑通了！"));
    s.convs[0].push(ChatMsg.init(true, "Me", "太棒了！其他项目只要一条 zig fetch --save 就能同时组合 moonui 和 moon_sdk。", "14:32", null, null));

    s.convs[1] = .{ .name = "Ada Lovelace", .role = "Online · Graphics Engineer", .time = "13:15", .unread = 2, .online = true };
    s.convs[1].push(ChatMsg.init(false, "Ada Lovelace", "DirectWrite 的中文字体回退（Segoe UI + 微软雅黑）在 150% DPI 下非常锐利。", "13:15", null, null));

    s.convs[2] = .{ .name = "Design System", .role = "Midnight · Daylight · Ember · Aurora", .time = "Yesterday", .unread = 0, .online = false };
    s.convs[2].push(ChatMsg.init(false, "Margaret H.", "四套内置主题色板与 56 个矢量图标已全部 1:1 对齐。", "Yesterday", null, null));

    s.convs[3] = .{ .name = "Build Bot", .role = "CI / zig build test", .time = "Tue", .unread = 1, .online = true };
    s.convs[3].push(ChatMsg.init(false, "Build Bot", "mooncore (7/7) + moonchat + moonui (6/6) 全部测试通过。", "Tue", null, null));
}

fn frame(s: *State) void {
    const u = ui.ui.get();
    const p = ui.palette();
    const vp = u.viewport;
    const sidebar_w: f32 = 300;

    // ---- Left conversation sidebar
    ui.beginSidebar(.{ .width = sidebar_w, .padding = 12 });
    ui.sidebarBrand("MoonChat", "moonui + moon-sdk", .layers);
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
    ui.badge("SDK Connected", .{ .tone = .success, .dot = true });
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
    ui.chat.systemNotice("End-to-end connected via mooncore (WinHTTP / CNG) + moonchat SDK");
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
        ui.toast(.info, "Attachment", .{ .description = "Attach files via mooncore / Win32 dialogs." });
    }
    if (ev.send and s.composer.text().len > 0) {
        var msg = ChatMsg.init(true, "Me", s.composer.text(), "Now", null, null);
        msg.status = .sending;
        const msg_idx = conv.msg_count;
        conv.push(msg);
        s.composer.clear();
        if (std.heap.page_allocator.create(ReplyJob)) |job| {
            job.* = .{ .state = s, .conv_idx = s.selected, .msg_idx = msg_idx };
            _ = core.os.runAsync(job, asyncAckWork);
        } else |_| {}
    }
    _ = u.popBox();
}
