//! Native Direct2D + DirectWrite IM / Chat components matching MoonWin's chat skin:
//! conversation list rows, grouped message bubbles, reply quotes, time dividers,
//! system notices, search box, and message composer.
const std = @import("std");
const ui = @import("ui.zig");
const math = @import("math.zig");
const Color = @import("color.zig").Color;
const icons = @import("icons.zig");
const widgets = @import("widgets.zig");

const Vec2 = math.Vec2;
const Rect = math.Rect;
const v2 = math.v2;
const TextStyle = ui.TextStyle;

pub const GroupPos = enum { single, first, middle, last };
pub const MsgStatus = enum { none, sending, sent, read, failed };

pub const ConversationOptions = struct {
    name: []const u8,
    preview: []const u8 = "",
    time: []const u8 = "",
    unread: u32 = 0,
    muted: bool = false,
    pinned: bool = false,
    online: bool = false,
    selected: bool = false,
};

pub fn conversation(id_str: [:0]const u8, o: ConversationOptions) bool {
    const u = ui.get();
    const t = &u.theme;
    const p = &t.palette;
    const h: f32 = 62;
    const r = u.allocRect(v2(u.availW(), h));
    const id = u.hashId(id_str);
    const hit = u.buttonBehavior(id, r, false);
    const hover_t = u.anim.toggle(id, 1, hit.hovered, t.motion.fast);
    const sel_t = u.anim.toggle(id, 12, o.selected, t.motion.normal);

    const rounding = t.radius.md;
    u.dl().rectFilled(r, p.text.withAlpha(0.05 * hover_t * (1.0 - sel_t)), rounding);
    if (sel_t > 0.001) {
        u.dl().rectFilled(r, p.accent.withAlpha(0.15 * sel_t), rounding);
        const bar_h = (h - 24) * sel_t;
        u.dl().rectFilled(Rect.fromSize(v2(r.min.x, r.center().y - bar_h * 0.5), v2(3, bar_h)), p.accent, 2);
    }

    // Avatar
    const av_s: f32 = 38;
    const av_r = Rect.fromSize(v2(r.min.x + 10, r.center().y - av_s * 0.5), v2(av_s, av_s));
    drawAvatarAt(u, av_r, o.name, if (o.online) .success else null);

    const tx = av_r.max.x + 10;
    const right_edge = r.max.x - 10;

    // Top row: name + time
    const name_style: TextStyle = .{ .size = t.type.body, .weight = if (o.selected or o.unread > 0) .semibold else .medium };
    const time_style: TextStyle = .{ .size = t.type.caption, .weight = .regular };
    const time_w = if (o.time.len > 0) u.renderer.measureText(o.time, time_style, 0).x else 0;
    if (o.time.len > 0) {
        u.dl().text(v2(right_edge - time_w, r.min.y + 11), p.text_faint, o.time, time_style, 0);
    }
    const name_clip = Rect.xywh(tx, r.min.y + 9, @max(right_edge - tx - time_w - 8, 20), 22);
    u.dl().pushClip(name_clip);
    u.dl().text(v2(tx, r.min.y + 10), p.text, o.name, name_style, 0);
    u.dl().popClip();

    // Bottom row: preview + unread badge
    var badge_w: f32 = 0;
    if (o.unread > 0) {
        var bbuf: [12]u8 = undefined;
        const bs = if (o.unread > 99) "99+" else std.fmt.bufPrint(&bbuf, "{d}", .{o.unread}) catch "";
        const bstyle: TextStyle = .{ .size = t.type.caption - 1, .weight = .bold };
        const bts = u.renderer.measureText(bs, bstyle, 0);
        badge_w = @max(bts.x + 11, 18);
        const br = Rect.xywh(right_edge - badge_w, r.min.y + 34, badge_w, 18);
        const bcol = if (o.muted) p.border_strong else p.accent;
        u.dl().rectFilled(br, bcol, 9);
        u.dl().text(v2(br.min.x + (badge_w - bts.x) * 0.5, br.min.y + (18 - bts.y) * 0.5), if (o.muted) p.text_muted else p.on_accent, bs, bstyle, 0);
    }
    const prev_style: TextStyle = .{ .size = t.type.label, .weight = .regular };
    const prev_clip = Rect.xywh(tx, r.min.y + 32, @max(right_edge - tx - badge_w - 8, 20), 22);
    u.dl().pushClip(prev_clip);
    u.dl().text(v2(tx, r.min.y + 33), p.text_muted, o.preview, prev_style, 0);
    u.dl().popClip();

    return hit.clicked;
}

pub fn timeDivider(str: []const u8) void {
    const u = ui.get();
    const p = &u.theme.palette;
    const style: TextStyle = .{ .size = u.theme.type.caption, .weight = .medium };
    const ts = u.renderer.measureText(str, style, 0);
    const r = u.allocRect(v2(u.availW(), ts.y + 14));
    const pill = Rect.xywh(r.center().x - ts.x * 0.5 - 10, r.min.y + 4, ts.x + 20, ts.y + 6);
    u.dl().rectFilled(pill, p.surface_raised.withAlpha(0.75), pill.h() * 0.5);
    u.dl().text(v2(pill.min.x + 10, pill.min.y + 3), p.text_faint, str, style, 0);
}

pub fn systemNotice(str: []const u8) void {
    const u = ui.get();
    const style: TextStyle = .{ .size = u.theme.type.caption, .weight = .regular };
    const ts = u.renderer.measureText(str, style, 0);
    const r = u.allocRect(v2(u.availW(), ts.y + 8));
    u.dl().text(v2(r.center().x - ts.x * 0.5, r.min.y + 4), u.theme.palette.text_faint, str, style, 0);
}

pub const Message = struct {
    own: bool = false,
    author: []const u8 = "",
    text: []const u8 = "",
    time: []const u8 = "",
    quote_author: ?[]const u8 = null,
    quote_text: ?[]const u8 = null,
    status: MsgStatus = .none,
};

pub const MessageOptions = struct {
    pos: GroupPos = .single,
    show_author: bool = true,
    max_width_ratio: f32 = 0.68,
};

pub fn message(id_str: [:0]const u8, msg: Message, o: MessageOptions) void {
    _ = id_str;
    const u = ui.get();
    const t = &u.theme;
    const p = &t.palette;

    const avail = u.availW();
    const av_s: f32 = 32;
    const av_gap: f32 = 10;
    const show_av = !msg.own and (o.pos == .single or o.pos == .first);
    const show_name = !msg.own and o.show_author and msg.author.len > 0 and (o.pos == .single or o.pos == .first);

    const max_bubble_w = @max(avail * o.max_width_ratio, 180);
    const pad_x: f32 = 13;
    const pad_y: f32 = 9;
    const body_style: TextStyle = .{ .size = t.type.body, .weight = .regular, .wrap = true };
    const meta_style: TextStyle = .{ .size = t.type.caption - 1, .weight = .regular };

    const text_sz = u.renderer.measureText(msg.text, body_style, max_bubble_w - pad_x * 2);
    const meta_w = if (msg.time.len > 0) u.renderer.measureText(msg.time, meta_style, 0).x + (if (msg.own and msg.status != .none) @as(f32, 16) else 0) else 0;

    var quote_h: f32 = 0;
    var quote_w: f32 = 0;
    const q_style: TextStyle = .{ .size = t.type.caption, .weight = .regular };
    if (msg.quote_text) |qt| {
        const qa = msg.quote_author orelse "";
        const qaw = if (qa.len > 0) u.renderer.measureText(qa, .{ .size = t.type.caption, .weight = .semibold }, 0).x else 0;
        const qtw = u.renderer.measureText(qt, q_style, 0).x;
        quote_w = @min(@max(qaw, qtw) + 18, max_bubble_w - pad_x * 2);
        quote_h = 36;
    }

    const inner_w = @min(@max(@max(text_sz.x, quote_w), meta_w), max_bubble_w - pad_x * 2);
    const bubble_w = inner_w + pad_x * 2;
    const bubble_h = pad_y * 2 + quote_h + text_sz.y + (if (msg.time.len > 0) @as(f32, 16) else 0);
    const name_h: f32 = if (show_name) 18 else 0;
    const row_h = name_h + bubble_h + (if (o.pos == .single or o.pos == .last) @as(f32, 6) else 0);

    const row = u.allocRect(v2(avail, row_h));

    const bx = if (msg.own)
        row.max.x - bubble_w
    else
        row.min.x + av_s + av_gap;
    const by = row.min.y + name_h;

    if (show_av) {
        drawAvatarAt(u, Rect.xywh(row.min.x, by, av_s, av_s), msg.author, null);
    }
    if (show_name) {
        u.dl().text(v2(bx + 2, row.min.y), p.text_muted, msg.author, .{ .size = t.type.caption, .weight = .semibold }, 0);
    }

    const br = Rect.xywh(bx, by, bubble_w, bubble_h);
    const rounding = t.radius.lg;
    if (msg.own) {
        u.dl().gradient(br, p.accent.lighten(0.05), p.accent.darken(0.06), rounding, false);
    } else {
        u.dl().rectFilled(br, p.surface, rounding);
        u.dl().rectStroke(br, p.border, rounding, 1);
    }

    var cy = br.min.y + pad_y;
    const fg = if (msg.own) p.on_accent else p.text;
    const fg_muted = if (msg.own) p.on_accent.withAlpha(0.75) else p.text_faint;

    if (msg.quote_text) |qt| {
        const qr = Rect.xywh(br.min.x + pad_x, cy, inner_w, 30);
        u.dl().rectFilled(qr, if (msg.own) Color.black.withAlpha(0.16) else p.surface_raised, 6);
        u.dl().rectFilled(Rect.xywh(qr.min.x, qr.min.y + 4, 3, qr.h() - 8), if (msg.own) p.on_accent.withAlpha(0.8) else p.accent, 1.5);
        if (msg.quote_author) |qa| {
            u.dl().text(v2(qr.min.x + 10, qr.min.y + 2), if (msg.own) p.on_accent else p.accent, qa, .{ .size = t.type.caption - 1, .weight = .semibold }, inner_w - 14);
        }
        u.dl().pushClip(Rect.xywh(qr.min.x + 10, qr.min.y + 14, inner_w - 14, 16));
        u.dl().text(v2(qr.min.x + 10, qr.min.y + 14), fg_muted, qt, q_style, 0);
        u.dl().popClip();
        cy += quote_h;
    }

    u.dl().text(v2(br.min.x + pad_x, cy), fg, msg.text, body_style, inner_w + 1);

    if (msg.time.len > 0) {
        const my = br.max.y - 18;
        const tw = u.renderer.measureText(msg.time, meta_style, 0).x;
        const mx = br.max.x - pad_x - tw - (if (msg.own and msg.status != .none) @as(f32, 16) else 0);
        u.dl().text(v2(mx, my), fg_muted, msg.time, meta_style, 0);
        if (msg.own and msg.status != .none) {
            const ic: icons.Icon = switch (msg.status) {
                .sending => .refresh,
                .sent, .read => .check,
                .failed => .alert,
                .none => .check,
            };
            const sc = if (msg.status == .failed) p.danger else fg_muted;
            icons.draw(u.dl(), ic, v2(br.max.x - pad_x - 6, my + 7), 12, sc);
        }
    }
}

pub fn searchBox(id_str: [:0]const u8, buf: []u8, hint: [:0]const u8) bool {
    return widgets.textField(id_str, buf, .{
        .hint = hint,
        .icon = .search,
        .size = .sm,
    });
}

pub const ComposerEvent = struct {
    send: bool = false,
    attach: bool = false,
};

pub fn Composer(comptime capacity: usize) type {
    return struct {
        const Self = @This();
        buf: widgets.TextBuffer(capacity) = .{},

        pub fn text(self: *const Self) []const u8 {
            return self.buf.slice();
        }
        pub fn clear(self: *Self) void {
            self.buf.clear();
        }

        pub fn draw(self: *Self, id_str: [:0]const u8, hint: [:0]const u8) ComposerEvent {
            const u = ui.get();
            const avail = u.availW();
            const send_w: f32 = 84;
            const attach_w: f32 = 34;
            const gap: f32 = 8;
            const input_w = @max(avail - send_w - attach_w - gap * 2, 120);

            var ev: ComposerEvent = .{};
            if (widgets.iconButton("##attach", .plus, .{ .variant = .outline, .tooltip = "Attach file" })) {
                ev.attach = true;
            }
            u.placeSameLine(gap);
            if (widgets.textField(id_str, &self.buf.buf, .{
                .hint = hint,
                .width = .{ .px = input_w },
                .submit_on_enter = true,
            })) {
                if (self.buf.slice().len > 0) ev.send = true;
            }
            u.placeSameLine(gap);
            if (widgets.button("Send", .{
                .variant = .primary,
                .width = .{ .px = send_w },
                .disabled = self.buf.slice().len == 0,
            })) {
                ev.send = true;
            }
            return ev;
        }
    };
}

fn drawAvatarAt(u: *ui.UiContext, r: Rect, name: []const u8, status: ?ui.Tone) void {
    const palette = [_]Color{
        Color.hex(0x7C6CFF), Color.hex(0x2DD4BF), Color.hex(0xF59E0B), Color.hex(0xEC4899),
        Color.hex(0x60A5FA), Color.hex(0x34D399), Color.hex(0xF87171), Color.hex(0xA78BFA),
    };
    var h: u32 = 2166136261;
    for (name) |ch| h = (h ^ ch) *% 16777619;
    const base = palette[h % palette.len];
    const s = r.w();
    u.dl().gradient(r, base.lighten(0.18), base.darken(0.12), s * 0.5, false);

    var initials: [8]u8 = undefined;
    var n: usize = 0;
    const trimmed = std.mem.trimStart(u8, name, " ");
    if (trimmed.len > 0 and trimmed[0] >= 0x80) {
        const len = std.unicode.utf8ByteSequenceLength(trimmed[0]) catch 1;
        n = @min(len, trimmed.len);
        @memcpy(initials[0..n], trimmed[0..n]);
    } else {
        var take_next = true;
        for (trimmed) |ch| {
            if (ch == ' ') {
                take_next = true;
                continue;
            }
            if (take_next and n < 2 and ch < 0x80) {
                initials[n] = std.ascii.toUpper(ch);
                n += 1;
            }
            take_next = false;
        }
    }
    const style: TextStyle = .{ .size = s * 0.4, .weight = .semibold };
    const ts = u.renderer.measureText(initials[0..n], style, 0);
    u.dl().text(v2(r.min.x + (s - ts.x) * 0.5, r.min.y + (s - ts.y) * 0.5), base.contrastText(), initials[0..n], style, 0);

    if (status) |st| {
        const dr = s * 0.14;
        const dc = v2(r.max.x - dr * 1.1, r.max.y - dr * 1.1);
        u.dl().circleFilled(dc, dr + 2, u.theme.palette.bg);
        u.dl().circleFilled(dc, dr, u.theme.tone(st));
    }
}
