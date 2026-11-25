//! Layout building blocks matching MoonWin's exact visual proportions and API.
const std = @import("std");
const ui = @import("ui.zig");
const math = @import("math.zig");
const Color = @import("color.zig").Color;
const icons = @import("icons.zig");
const widgets = @import("widgets.zig");

const Vec2 = math.Vec2;
const Rect = math.Rect;
const v2 = math.v2;
const Icon = icons.Icon;
const DrawCmd = ui.DrawCmd;
const TextStyle = ui.TextStyle;

pub const Gap = enum {
    xs,
    sm,
    md,
    lg,
    xl,
    xxl,

    pub fn value(self: Gap) f32 {
        const s = ui.get().theme.space;
        return switch (self) {
            .xs => s.xs,
            .sm => s.sm,
            .md => s.md,
            .lg => s.lg,
            .xl => s.xl,
            .xxl => s.xxl,
        };
    }
};

pub fn space(gap: Gap) void {
    const u = ui.get();
    const b = u.box();
    b.same_line = false;
    b.cursor_y += gap.value();
    b.max_y = @max(b.max_y, b.cursor_y);
}

pub fn sameLine(gap: Gap) void {
    ui.get().placeSameLine(gap.value());
}

pub fn alignRight(width: f32) void {
    ui.get().alignRight(width);
}

// ---- Horizontal Row ----

pub fn beginRow(gap: Gap) void {
    const u = ui.get();
    u.row_gaps[u.row_depth] = gap.value();
    u.row_depth += 1;
    beginGroup();
}

pub fn next() void {
    const u = ui.get();
    u.placeSameLine(u.row_gaps[u.row_depth - 1]);
}

pub fn endRow() void {
    const u = ui.get();
    u.row_depth -= 1;
    endGroup();
}

// ---- Vertical Group (inline block inside a row or column) ----

pub fn beginGroup() void {
    const u = ui.get();
    const parent = u.box();
    var x = parent.cursor_x;
    var y = parent.cursor_y;
    if (parent.same_line) {
        y = parent.row_y;
    } else {
        x = parent.origin_x;
    }
    const avail = @max(parent.origin_x + parent.avail_w - x, 0);
    u.pushBox(.{
        .origin_x = x,
        .origin_y = y,
        .avail_w = avail,
        .cursor_x = x,
        .cursor_y = y,
        .max_x = x,
        .max_y = y,
        .spacing_x = parent.spacing_x,
        .spacing_y = parent.spacing_y,
    });
}

pub fn endGroup() void {
    const u = ui.get();
    const g = u.popBox();
    const w = @max(g.max_x - g.origin_x, 0);
    const h = @max(g.max_y - g.origin_y, 0);
    _ = u.allocRect(v2(w, h));
}

// ---- Cards (auto-sized with deferred shadow + surface + border + glass highlight) ----

pub const CardOptions = ui.CardOptions;

pub fn beginCard(id_str: [:0]const u8, o: CardOptions) void {
    const u = ui.get();
    const parent = u.box();
    const w = o.width orelse parent.avail_w;
    var x = parent.cursor_x;
    var y = parent.cursor_y;
    if (parent.same_line) {
        y = parent.row_y;
        parent.same_line = false;
    } else {
        x = parent.origin_x;
        parent.row_y = y;
        parent.row_max_h = 0;
    }
    const id = u.hashId(id_str);
    u.pushId(id_str);
    u.card_stack[u.card_depth] = .{
        .id = id,
        .opts = o,
        .cmd_index = u.dl().cmds.items.len,
        .origin = v2(x, y),
        .width = w,
    };
    u.card_depth += 1;

    const pad = o.padding;
    u.pushBox(.{
        .origin_x = x + pad,
        .origin_y = y + pad,
        .avail_w = @max(w - pad * 2, 0),
        .cursor_x = x + pad,
        .cursor_y = y + pad,
        .max_x = x + pad,
        .max_y = y + pad,
        .spacing_x = 8,
        .spacing_y = 10,
    });
}

pub fn endCard() bool {
    const u = ui.get();
    const inner = u.popBox();
    u.card_depth -= 1;
    const cs = u.card_stack[u.card_depth];
    u.popId();

    const o = cs.opts;
    const content_h = @max(inner.max_y - inner.origin_y, 0);
    const total_h = o.height orelse (content_h + o.padding * 2);
    const r = Rect.fromSize(cs.origin, v2(cs.width, total_h));

    // Advance parent layout box
    const parent = u.box();
    parent.last_rect = r;
    parent.row_max_h = @max(parent.row_max_h, total_h);
    parent.max_x = @max(parent.max_x, r.max.x);
    parent.max_y = @max(parent.max_y, r.max.y);
    parent.cursor_x = r.max.x;
    parent.cursor_y = parent.row_y + parent.row_max_h + parent.spacing_y;

    // Hover/click interaction for hoverable cards
    const hovered = o.hoverable and u.canInteract(r);
    const clicked = o.hoverable and hovered and u.input.mouse_released and u.active_id == 0;
    if (hovered) u.cursor_kind = .hand;

    const t = &u.theme;
    const p = &t.palette;
    const hover_t = if (o.hoverable) u.anim.toggle(cs.id, 11, hovered, t.motion.normal) else 0;
    const rounding = t.radius.lg;
    const lift = hover_t * 2.0;
    const rr = r.translate(v2(0, -lift));

    // Insert card chrome commands right BEFORE card's children!
    var chrome: [5]DrawCmd = undefined;
    var n: usize = 0;
    if (o.elevated) {
        const strength: f32 = if (t.dark) 0.7 else 1.0;
        chrome[n] = .{ .shadow = .{
            .rect = rr,
            .rounding = rounding,
            .color = p.shadow.fade(strength * (0.55 + 0.45 * hover_t)),
            .blur = 14 + 8 * hover_t,
            .offset_y = 4 + 4 * hover_t,
        } };
        n += 1;
    }
    chrome[n] = .{ .rect_filled = .{
        .rect = rr,
        .color = o.background orelse p.surface,
        .rounding = rounding,
    } };
    n += 1;
    if (o.border) {
        const bcol = Color.mix(p.border, p.accent.withAlpha(0.55), hover_t);
        chrome[n] = .{ .rect_stroke = .{
            .rect = rr,
            .color = bcol,
            .rounding = rounding,
            .thickness = t.border_width,
        } };
        n += 1;
    }
    if (t.dark) {
        chrome[n] = .{ .line = .{
            .a = v2(rr.min.x + rounding, rr.min.y + 1),
            .b = v2(rr.max.x - rounding, rr.min.y + 1),
            .color = Color.white.withAlpha(0.04),
            .thickness = 1,
        } };
        n += 1;
    }
    u.dl().insertCmds(cs.cmd_index, chrome[0..n]);
    return clicked;
}

// ---- Grid (equal-width columns) ----

pub const GridOptions = struct {
    gap: Gap = .lg,
};

pub fn beginGrid(id_str: [:0]const u8, columns: u32, o: GridOptions) bool {
    const u = ui.get();
    u.pushId(id_str);
    const parent = u.box();
    parent.same_line = false;
    const cols = @max(columns, 1);
    const gap = o.gap.value();
    const col_w = (parent.avail_w - gap * @as(f32, @floatFromInt(cols - 1))) / @as(f32, @floatFromInt(cols));
    u.grid_stack[u.grid_depth] = .{
        .cols = cols,
        .col_index = -1,
        .gap = gap,
        .origin_x = parent.origin_x,
        .start_y = parent.cursor_y,
        .col_w = @max(col_w, 10),
        .max_bottom = parent.cursor_y,
    };
    u.grid_depth += 1;
    return true;
}

pub fn gridNext() void {
    const u = ui.get();
    const g = &u.grid_stack[u.grid_depth - 1];
    if (g.col_index >= 0) {
        const prev = u.popBox();
        g.max_bottom = @max(g.max_bottom, prev.max_y);
    }
    g.col_index += 1;
    if (g.col_index >= @as(i32, @intCast(g.cols))) {
        g.col_index = 0;
        g.start_y = g.max_bottom + g.gap;
    }
    const x = g.origin_x + @as(f32, @floatFromInt(g.col_index)) * (g.col_w + g.gap);
    u.pushBox(.{
        .origin_x = x,
        .origin_y = g.start_y,
        .avail_w = g.col_w,
        .cursor_x = x,
        .cursor_y = g.start_y,
        .max_x = x,
        .max_y = g.start_y,
        .spacing_x = 8,
        .spacing_y = 10,
    });
}

pub fn endGrid() void {
    const u = ui.get();
    const g = &u.grid_stack[u.grid_depth - 1];
    if (g.col_index >= 0) {
        const prev = u.popBox();
        g.max_bottom = @max(g.max_bottom, prev.max_y);
    }
    u.grid_depth -= 1;
    u.popId();

    const parent = u.box();
    parent.max_x = @max(parent.max_x, parent.origin_x + parent.avail_w);
    parent.max_y = @max(parent.max_y, g.max_bottom);
    parent.cursor_x = parent.origin_x;
    parent.cursor_y = g.max_bottom + parent.spacing_y;
}

// ---- App Shell: Sidebar + Main ----

pub const SidebarOptions = struct {
    width: f32 = 240,
    padding: f32 = 14,
};

pub fn beginSidebar(o: SidebarOptions) void {
    const u = ui.get();
    const p = &u.theme.palette;
    u.sidebar_w = o.width;
    const h = u.viewport.y;
    const r = Rect.xywh(0, 0, o.width, h);
    u.dl().rectFilled(r, p.bg_subtle, 0);
    u.dl().pushClip(r);
    u.pushBox(.{
        .origin_x = o.padding,
        .origin_y = o.padding + 4,
        .avail_w = o.width - o.padding * 2,
        .cursor_x = o.padding,
        .cursor_y = o.padding + 4,
        .max_x = o.padding,
        .max_y = o.padding + 4,
        .spacing_x = 6,
        .spacing_y = 2,
    });
}

pub fn endSidebar() void {
    const u = ui.get();
    _ = u.popBox();
    u.dl().popClip();
    const x = u.sidebar_w - 0.5;
    u.dl().line(v2(x, 0), v2(x, u.viewport.y), u.theme.palette.border, 1);
}

pub fn sidebarFooter(height: f32) void {
    const u = ui.get();
    const b = u.box();
    const target_y = u.viewport.y - height - 14;
    if (target_y > b.cursor_y) b.cursor_y = target_y;
}

pub fn sidebarBrand(title: []const u8, subtitle: ?[]const u8, ic: Icon) void {
    const u = ui.get();
    const p = &u.theme.palette;
    const s: f32 = 34;
    const r = u.allocRect(v2(u.availW(), s));
    const badge_r = Rect.fromSize(r.min, v2(s, s));
    u.dl().shadow(badge_r, 10, p.accent.withAlpha(0.35), 10, 3);
    u.dl().gradient(badge_r, p.accent.lighten(0.15), p.accent.darken(0.15), 10, false);
    icons.draw(u.dl(), ic, badge_r.center(), 18, p.on_accent);

    const tx = r.min.x + s + 10;
    const title_style: TextStyle = .{ .size = u.theme.type.title, .weight = .bold };
    const th = u.renderer.measureText(title, title_style, 0).y;
    if (subtitle) |sub| {
        u.dl().text(v2(tx, r.min.y), p.text, title, title_style, 0);
        const sub_style: TextStyle = .{ .size = u.theme.type.caption, .weight = .regular };
        u.dl().text(v2(tx, r.min.y + th - 1), p.text_faint, sub, sub_style, 0);
    } else {
        u.dl().text(v2(tx, r.min.y + (s - th) * 0.5), p.text, title, title_style, 0);
    }
    u.box().cursor_y += 14;
}

pub fn navSection(title: []const u8) void {
    const u = ui.get();
    u.box().cursor_y += 10;
    const style: TextStyle = .{ .size = u.theme.type.caption, .weight = .semibold };
    const ts = u.renderer.measureText(title, style, 0);
    const r = u.allocRect(v2(u.availW(), ts.y));
    u.dl().text(v2(r.min.x + 10, r.min.y), u.theme.palette.text_faint, title, style, 0);
    u.box().cursor_y += 2;
}

pub const NavItemOptions = struct {
    count: u32 = 0,
    tooltip: ?[:0]const u8 = null,
};

pub fn navItem(ic: Icon, lbl: [:0]const u8, active: bool, o: NavItemOptions) bool {
    const u = ui.get();
    const p = &u.theme.palette;
    const t = &u.theme;
    const vis = ui.UiContext.visibleLabel(lbl);
    const r = u.allocRect(v2(u.availW(), 36));
    const id = u.hashId(lbl);
    const hit = u.buttonBehavior(id, r, false);
    const hover_t = u.anim.toggle(id, 1, hit.hovered, t.motion.fast);
    const act_t = u.anim.toggle(id, 12, active, t.motion.normal);

    const rounding = t.radius.md;
    u.dl().rectFilled(r, p.text.withAlpha(0.05 * hover_t * (1.0 - act_t)), rounding);
    if (act_t > 0.001) {
        u.dl().rectFilled(r, p.accent.withAlpha(0.14 * act_t), rounding);
        const bar_h = (r.h() - 16) * act_t;
        u.dl().rectFilled(Rect.fromSize(v2(r.min.x, r.center().y - bar_h * 0.5), v2(3, bar_h)), p.accent, 2);
    }
    const fg = Color.mix(Color.mix(p.text_muted, p.text, hover_t), if (t.dark) p.accent.lighten(0.3) else p.accent, act_t);
    icons.draw(u.dl(), ic, v2(r.min.x + 22, r.center().y), 18, fg);

    const style: TextStyle = .{ .size = t.type.body, .weight = if (active) .semibold else .medium };
    const ts = u.renderer.measureText(vis, style, 0);
    u.dl().text(v2(r.min.x + 42, r.center().y - ts.y * 0.5), fg, vis, style, 0);

    if (o.count > 0) {
        var buf: [12]u8 = undefined;
        const s = if (o.count > 99) "99+" else std.fmt.bufPrint(&buf, "{d}", .{o.count}) catch "";
        const cstyle: TextStyle = .{ .size = t.type.caption, .weight = .bold };
        const cs = u.renderer.measureText(s, cstyle, 0);
        const bw = @max(cs.x + 12, 20);
        const br = Rect.fromSize(v2(r.max.x - bw - 8, r.center().y - 10), v2(bw, 20));
        u.dl().rectFilled(br, p.accent, 10);
        u.dl().text(v2(br.min.x + (bw - cs.x) * 0.5, br.min.y + (20 - cs.y) * 0.5), p.on_accent, s, cstyle, 0);
    }
    if (o.tooltip) |tip| u.setTooltip(tip);
    return hit.clicked;
}

pub const MainOptions = struct {
    padding: f32 = 32,
    max_width: ?f32 = null,
};

pub fn beginMain(o: MainOptions) void {
    const u = ui.get();
    const x0 = u.sidebar_w;
    const view_w = @max(u.viewport.x - x0, 1);
    const view_h = u.viewport.y;
    const view_r = Rect.xywh(x0, 0, view_w, view_h);
    u.main_view_rect = view_r;
    u.main_padding = o.padding;

    u.dl().pushClip(view_r);

    var inner_w = @max(view_w - o.padding * 2, 100);
    var inner_x = x0 + o.padding;
    if (o.max_width) |mw| {
        if (inner_w > mw) {
            inner_x += (inner_w - mw) * 0.5;
            inner_w = mw;
        }
    }
    const start_y = o.padding - u.scroll_y;
    u.main_content_start_y = start_y;

    u.pushBox(.{
        .origin_x = inner_x,
        .origin_y = start_y,
        .avail_w = inner_w,
        .cursor_x = inner_x,
        .cursor_y = start_y,
        .max_x = inner_x,
        .max_y = start_y,
        .spacing_x = 10,
        .spacing_y = 10,
    });
}

pub fn endMain() void {
    const u = ui.get();
    // Mouse wheel (nested scroll areas consumed theirs already).
    if (u.input.mouse_wheel != 0 and !u.modal_active and u.main_view_rect.contains(u.input.mouse_pos)) {
        u.scroll_target_y = std.math.clamp(u.scroll_target_y - u.input.mouse_wheel * 48.0, 0, u.scroll_max_y);
        u.input.mouse_wheel = 0;
        u.anim.markActive();
    }
    const b = u.popBox();
    const content_h = (b.max_y - u.main_content_start_y) + u.main_padding * 2;
    const view_h = u.main_view_rect.h();
    u.scroll_max_y = @max(content_h - view_h, 0);
    if (u.scroll_target_y > u.scroll_max_y) u.scroll_target_y = u.scroll_max_y;
    if (u.scroll_y > u.scroll_max_y) u.scroll_y = u.scroll_max_y;

    // Draw custom rounded scrollbar if content overflows
    if (u.scroll_max_y > 1.0) {
        const track_h = view_h - 16;
        const thumb_h = @max(track_h * (view_h / content_h), 32);
        const frac = u.scroll_y / u.scroll_max_y;
        const ty = 8 + (track_h - thumb_h) * frac;
        const tr = Rect.xywh(u.main_view_rect.max.x - 10, ty, 6, thumb_h);
        u.dl().rectFilled(tr, u.theme.palette.border_strong.withAlpha(0.75), 3);
    }

    u.dl().popClip();
}

// ---- Scroll areas (independent vertical scrolling regions) ----

pub const ScrollOptions = struct {
    /// Inner padding on all sides.
    padding: f32 = 0,
    spacing_y: f32 = 10,
    /// Keep following new content while scrolled to the bottom (chat timelines).
    stick_to_bottom: bool = false,
    /// Start at the bottom the first time this area is shown.
    start_at_bottom: bool = false,
    scrollbar: bool = true,
};

/// Begins a scroll area filling `rect`. Content is laid out top-down inside
/// it; call `endScroll` after. Returns the persistent state (y, max, ...).
pub fn beginScroll(id_str: []const u8, rect: Rect, o: ScrollOptions) *ui.ScrollState {
    const u = ui.get();
    const id = u.hashId(id_str);
    const st = u.scrollState(id);
    st.stick_bottom = o.stick_to_bottom;
    if (!st.initialized) {
        st.initialized = true;
        if (o.start_at_bottom) st.pending_bottom = true;
    }
    st.view_h = rect.h();

    // Smooth scrolling towards the target.
    if (@abs(st.target - st.y) > 0.25) {
        const k = if (u.theme.motion.enabled) 1.0 - @exp(-20.0 * u.anim.delta_time) else 1.0;
        st.y += (st.target - st.y) * k;
        u.anim.markActive();
    } else {
        st.y = st.target;
    }

    if (u.scroll_depth < u.scroll_stack.len) {
        u.scroll_stack[u.scroll_depth] = .{
            .id = id,
            .rect = rect,
            .origin_y = rect.min.y + o.padding - @round(st.y),
            .padding = o.padding,
            .scrollbar = o.scrollbar,
        };
        u.scroll_depth += 1;
    }
    u.dl().pushClip(rect);
    u.pushId(id_str);
    const sb_w: f32 = if (o.scrollbar) 10 else 0;
    const origin_y = rect.min.y + o.padding - @round(st.y);
    u.pushBox(.{
        .origin_x = rect.min.x + o.padding,
        .origin_y = origin_y,
        .avail_w = @max(rect.w() - o.padding * 2 - sb_w, 10),
        .cursor_x = rect.min.x + o.padding,
        .cursor_y = origin_y,
        .max_x = rect.min.x + o.padding,
        .max_y = origin_y,
        .spacing_x = 8,
        .spacing_y = o.spacing_y,
    });
    return st;
}

pub fn endScroll() void {
    const u = ui.get();
    const b = u.popBox();
    u.popId();
    if (u.scroll_depth == 0) {
        u.dl().popClip();
        return;
    }
    u.scroll_depth -= 1;
    const f = u.scroll_stack[u.scroll_depth];
    const st = u.scrollState(f.id);
    const view_h = f.rect.h();

    const was_bottom = st.atBottom();
    const prev_from_bottom = st.max - st.y;
    st.content_h = @max(b.max_y - f.origin_y, 0) + f.padding * 2;
    st.max = @max(st.content_h - view_h, 0);

    if (st.keep_from_bottom) {
        st.keep_from_bottom = false;
        st.y = @max(st.max - st.from_bottom, 0);
        st.target = st.y;
    } else if (st.pending_bottom or (st.stick_bottom and was_bottom and prev_from_bottom <= 2.0)) {
        st.pending_bottom = false;
        st.target = st.max;
        st.y = st.max;
    }
    st.target = std.math.clamp(st.target, 0, st.max);
    st.y = std.math.clamp(st.y, 0, st.max);

    // Mouse wheel (innermost area under the pointer wins).
    if (u.input.mouse_wheel != 0 and !u.modal_active and f.rect.contains(u.input.mouse_pos)) {
        st.target = std.math.clamp(st.target - u.input.mouse_wheel * 56.0, 0, st.max);
        u.input.mouse_wheel = 0;
        u.anim.markActive();
    }

    // Scrollbar with a draggable thumb.
    if (f.scrollbar and st.max > 1.0) {
        const track = Rect.xywh(f.rect.max.x - 9, f.rect.min.y + 6, 6, view_h - 12);
        const thumb_h = @max(track.h() * (view_h / @max(st.content_h, 1)), 28);
        const frac = st.y / st.max;
        const thumb = Rect.xywh(track.min.x, track.min.y + (track.h() - thumb_h) * frac, 6, thumb_h);
        const sid = f.id +% 0x5C201;
        const hit = u.buttonBehavior(sid, thumb.expand(3), false);
        if (hit.held) {
            const rel = (u.input.mouse_pos.y - track.min.y - thumb_h * 0.5) / @max(track.h() - thumb_h, 1);
            st.target = std.math.clamp(rel, 0, 1) * st.max;
            st.y = st.target;
        }
        const hover_t = u.anim.toggle(sid, 1, hit.hovered or hit.held, u.theme.motion.fast);
        u.dl().rectFilled(thumb, u.theme.palette.border_strong.withAlpha(0.55 + 0.35 * hover_t), 3);
    }
    u.dl().popClip();

    // Advance the parent layout past the area.
    const parent = u.box();
    parent.max_y = @max(parent.max_y, f.rect.max.y);
}

/// Scrolls the area `id_str` to the bottom at the end of the next frame.
pub fn scrollToBottom(id_str: []const u8) void {
    const u = ui.get();
    u.scrollState(u.hashId(id_str)).pending_bottom = true;
}

/// Call right before older items are inserted above the visible ones: the
/// view keeps its distance from the bottom instead of jumping.
pub fn keepScrollFromBottom(id_str: []const u8) void {
    const u = ui.get();
    const st = u.scrollState(u.hashId(id_str));
    st.keep_from_bottom = true;
    st.from_bottom = st.max - st.y;
}

pub fn pageHeader(title: []const u8, subtitle: ?[]const u8) void {
    widgets.text(title, .{ .size = .display, .weight = .bold });
    if (subtitle) |s| {
        ui.get().box().cursor_y -= 4;
        widgets.text(s, .{ .ink = .muted });
    }
}

pub fn section(title: []const u8, subtitle: ?[]const u8) void {
    const u = ui.get();
    u.box().cursor_y += 2;
    widgets.text(title, .{ .size = .title, .weight = .semibold });
    if (subtitle) |s| {
        u.box().cursor_y -= 4;
        widgets.text(s, .{ .size = .label, .ink = .muted, .wrap = true });
    }
    u.box().cursor_y += 4;
}

pub fn field(lbl: []const u8) void {
    widgets.text(lbl, .{ .size = .label, .weight = .medium, .ink = .muted });
    ui.get().box().cursor_y -= 4;
}

pub fn fieldHint(hint: []const u8) void {
    ui.get().box().cursor_y -= 4;
    widgets.text(hint, .{ .size = .caption, .ink = .faint, .wrap = true });
}
