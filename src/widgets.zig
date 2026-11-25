//! Core MoonWin components implemented over pure Direct2D + DirectWrite.
const std = @import("std");
const ui = @import("ui.zig");
const math = @import("math.zig");
const Color = @import("color.zig").Color;
const theme_mod = @import("theme.zig");
const anim_mod = @import("anim.zig");
const icons = @import("icons.zig");
const layout = @import("layout.zig");
const textedit = @import("textedit.zig");
const clipboard = @import("clipboard.zig");
const Renderer = @import("renderer.zig").Renderer;

const Vec2 = math.Vec2;
const Rect = math.Rect;
const v2 = math.v2;
const Icon = icons.Icon;
const Tone = theme_mod.Tone;
const TextStyle = ui.TextStyle;
const TextWeight = ui.TextWeight;
const DrawList = ui.DrawList;

pub const TextSize = enum { caption, label, body, title, heading, display };
pub const Weight = TextWeight;
pub const Ink = enum { default, muted, faint, accent, success, warning, danger, info, on_accent };

pub fn inkColor(ink: Ink) Color {
    const p = &ui.get().theme.palette;
    return switch (ink) {
        .default => p.text,
        .muted => p.text_muted,
        .faint => p.text_faint,
        .accent => p.accent,
        .success => p.success,
        .warning => p.warning,
        .danger => p.danger,
        .info => p.info,
        .on_accent => p.on_accent,
    };
}

pub fn textSizePx(size: TextSize) f32 {
    const t = &ui.get().theme.type;
    return switch (size) {
        .caption => t.caption,
        .label => t.label,
        .body => t.body,
        .title => t.title,
        .heading => t.heading,
        .display => t.display,
    };
}

pub const Width = union(enum) {
    auto,
    fill,
    px: f32,

    pub fn resolve(self: Width, content: f32) f32 {
        return switch (self) {
            .auto => content,
            .fill => @max(ui.get().availW(), content * 0.5),
            .px => |w| w,
        };
    }
};

pub const ControlSize = enum {
    sm,
    md,
    lg,

    pub fn height(self: ControlSize) f32 {
        const base = ui.get().theme.control_height;
        return switch (self) {
            .sm => base - 6,
            .md => base,
            .lg => base + 8,
        };
    }
    fn padX(self: ControlSize) f32 {
        return switch (self) {
            .sm => 10,
            .md => 14,
            .lg => 18,
        };
    }
    fn iconSize(self: ControlSize) f32 {
        return switch (self) {
            .sm => 14,
            .md => 16,
            .lg => 18,
        };
    }
    fn textSize(self: ControlSize) TextSize {
        return switch (self) {
            .sm => .label,
            .md => .body,
            .lg => .title,
        };
    }
};

// =====================================================================
// Typography
// =====================================================================

pub const TextOptions = struct {
    size: TextSize = .body,
    weight: Weight = .regular,
    ink: Ink = .default,
    color: ?Color = null,
    wrap: bool = false,
    mono: bool = false,
};

pub fn text(str: []const u8, o: TextOptions) void {
    const u = ui.get();
    const style: TextStyle = .{
        .size = textSizePx(o.size),
        .weight = o.weight,
        .mono = o.mono,
        .wrap = o.wrap,
    };
    const max_w = if (o.wrap) u.availW() else 0;
    const ts = u.renderer.measureText(str, style, max_w);
    const r = u.allocRect(v2(if (o.wrap) @min(ts.x, max_w) else ts.x, ts.y));
    u.dl().text(r.min, o.color orelse inkColor(o.ink), str, style, max_w);
}

pub fn heading(str: []const u8) void {
    text(str, .{ .size = .heading, .weight = .semibold });
}
pub fn display(str: []const u8) void {
    text(str, .{ .size = .display, .weight = .bold });
}
pub fn muted(str: []const u8) void {
    text(str, .{ .ink = .muted });
}
pub fn caption(str: []const u8) void {
    text(str, .{ .size = .caption, .ink = .muted });
}
pub fn label(str: []const u8) void {
    text(str, .{ .size = .label, .weight = .medium, .ink = .muted });
}

pub fn link(lbl: [:0]const u8) bool {
    const u = ui.get();
    const vis = ui.UiContext.visibleLabel(lbl);
    const style: TextStyle = .{ .size = u.theme.type.body, .weight = .medium };
    const ts = u.renderer.measureText(vis, style, 0);
    const r = u.allocRect(v2(@max(ts.x, 1), ts.y));
    const hit = u.buttonBehavior(u.hashId(lbl), r, false);
    const col = if (hit.hovered) u.theme.palette.accent.lighten(0.15) else u.theme.palette.accent;
    u.dl().text(r.min, col, vis, style, 0);
    if (hit.hovered) u.dl().line(v2(r.min.x, r.max.y), v2(r.max.x, r.max.y), col, 1);
    return hit.clicked;
}

pub fn kbd(str: []const u8) void {
    const u = ui.get();
    const p = &u.theme.palette;
    const style: TextStyle = .{ .size = u.theme.type.caption, .weight = .regular, .mono = true };
    const ts = u.renderer.measureText(str, style, 0);
    const pad = v2(6, 2);
    const r = u.allocRect(v2(ts.x + pad.x * 2, ts.y + pad.y * 2 + 1));
    u.dl().rectFilled(r, p.surface_raised, 5);
    u.dl().rectFilled(Rect{ .min = v2(r.min.x, r.max.y - 2), .max = r.max }, p.border_strong, 5);
    u.dl().rectStroke(r, p.border_strong, 5, 1);
    u.dl().text(v2(r.min.x + pad.x, r.min.y + pad.y), p.text_muted, str, style, 0);
}

pub const IconOptions = struct {
    size: f32 = 18,
    ink: Ink = .default,
    color: ?Color = null,
    stroke: f32 = 1.8,
};

pub fn icon(ic: Icon, o: IconOptions) void {
    const u = ui.get();
    const r = u.allocRect(v2(o.size, o.size));
    const hovered = u.canInteract(r);
    u.last_hovered = hovered;
    icons.drawEx(u.dl(), ic, r.center(), o.size, o.color orelse inkColor(o.ink), o.stroke);
}

// =====================================================================
// Buttons
// =====================================================================

pub const Variant = enum { primary, secondary, outline, ghost, soft, danger };

pub const ButtonOptions = struct {
    variant: Variant = .secondary,
    size: ControlSize = .md,
    icon: ?Icon = null,
    icon_right: ?Icon = null,
    width: Width = .auto,
    disabled: bool = false,
    loading: bool = false,
    tooltip: ?[:0]const u8 = null,
};

const ButtonColors = struct { bg: Color, fg: Color, border: Color };

fn buttonColors(variant: Variant, hover: f32, press: f32) ButtonColors {
    const u = ui.get();
    const p = &u.theme.palette;
    return switch (variant) {
        .primary => .{
            .bg = p.accent.lighten(0.08 * hover).darken(0.10 * press),
            .fg = p.on_accent,
            .border = Color.transparent,
        },
        .secondary => .{
            .bg = Color.mix(p.surface_raised, p.border_strong, hover * 0.55).darken(0.05 * press),
            .fg = p.text,
            .border = p.border,
        },
        .outline => .{
            .bg = p.text.withAlpha(0.05 * hover + 0.04 * press),
            .fg = p.text,
            .border = Color.mix(p.border_strong, p.text_faint, hover),
        },
        .ghost => .{
            .bg = p.text.withAlpha(0.07 * hover + 0.05 * press),
            .fg = Color.mix(p.text_muted, p.text, hover),
            .border = Color.transparent,
        },
        .soft => .{
            .bg = p.accent.withAlpha(0.14 + 0.08 * hover + 0.06 * press),
            .fg = if (u.theme.dark) p.accent.lighten(0.25) else p.accent.darken(0.1),
            .border = Color.transparent,
        },
        .danger => .{
            .bg = p.danger.lighten(0.08 * hover).darken(0.12 * press),
            .fg = p.danger.contrastText(),
            .border = Color.transparent,
        },
    };
}

pub fn button(lbl: [:0]const u8, o: ButtonOptions) bool {
    const u = ui.get();
    const vis = ui.UiContext.visibleLabel(lbl);
    const style: TextStyle = .{ .size = textSizePx(o.size.textSize()), .weight = .medium };
    const h = o.size.height();
    const pad = o.size.padX();
    const isz = o.size.iconSize();
    const gap: f32 = 8;
    const ts = u.renderer.measureText(vis, style, 0);
    var content_w = ts.x;
    if (o.icon != null) content_w += isz + (if (vis.len > 0) gap else 0);
    if (o.icon_right != null) content_w += isz + (if (vis.len > 0) gap else 0);
    const w = o.width.resolve(content_w + pad * 2);

    const rect = u.allocRect(v2(w, h));
    const id = u.hashId(lbl);
    const hit = u.buttonBehavior(id, rect, o.disabled);
    const t = &u.theme;
    const hover_t = u.anim.toggle(id, 1, hit.hovered, t.motion.fast);
    const press_t = u.anim.toggle(id, 2, hit.held, t.motion.fast * 1.4);

    const prev_a = u.dl().alpha;
    if (o.disabled) u.dl().alpha *= 0.48;
    defer u.dl().alpha = prev_a;

    const cols = buttonColors(o.variant, hover_t, press_t);
    const r = rect.expand(-press_t * 1.0);
    const rounding = t.radius.md;

    if (o.variant == .primary or o.variant == .danger) {
        u.dl().shadow(r, rounding, t.palette.shadow.fade(0.35 + 0.25 * hover_t), 6, 2);
        u.dl().gradient(r, cols.bg.lighten(0.06), cols.bg.darken(0.04), rounding, false);
        u.dl().rectStroke(r, Color.white.withAlpha(0.08), rounding, 1);
    } else {
        u.dl().rectFilled(r, cols.bg, rounding);
        u.dl().rectStroke(r, cols.border, rounding, t.border_width);
    }

    var x = r.min.x + (r.w() - content_w) * 0.5;
    const cy = r.center().y;
    if (o.loading) {
        spinnerAt(u.dl(), v2(r.center().x, cy), isz * 0.5, cols.fg);
    } else {
        if (o.icon) |ic| {
            icons.draw(u.dl(), ic, v2(x + isz * 0.5, cy), isz, cols.fg);
            x += isz + gap;
        }
        if (vis.len > 0) {
            u.dl().text(v2(@floor(x), @floor(cy - ts.y * 0.5)), cols.fg, vis, style, 0);
            x += ts.x + gap;
        }
        if (o.icon_right) |ic| {
            icons.draw(u.dl(), ic, v2(x + isz * 0.5, cy), isz, cols.fg);
        }
    }
    if (o.tooltip) |tip| u.setTooltip(tip);
    return hit.clicked and !o.loading and !o.disabled;
}

pub const IconButtonOptions = struct {
    variant: Variant = .ghost,
    size: ControlSize = .md,
    active: bool = false,
    disabled: bool = false,
    tooltip: ?[:0]const u8 = null,
};

pub fn iconButton(id_str: [:0]const u8, ic: Icon, o: IconButtonOptions) bool {
    const u = ui.get();
    const h = o.size.height();
    const rect = u.allocRect(v2(h, h));
    const id = u.hashId(id_str);
    const hit = u.buttonBehavior(id, rect, o.disabled);
    const t = &u.theme;
    const hover_t = u.anim.toggle(id, 1, hit.hovered, t.motion.fast);
    const press_t = u.anim.toggle(id, 2, hit.held, t.motion.fast * 1.4);
    const active_t = u.anim.toggle(id, 4, o.active, t.motion.normal);

    const prev_a = u.dl().alpha;
    if (o.disabled) u.dl().alpha *= 0.48;
    defer u.dl().alpha = prev_a;

    var cols = buttonColors(o.variant, hover_t, press_t);
    if (active_t > 0.001) {
        cols.bg = Color.mix(cols.bg, t.palette.accent.withAlpha(0.16), active_t);
        cols.fg = Color.mix(cols.fg, t.palette.accent, active_t);
    }
    const r = rect.expand(-press_t * 1.0);
    const rounding = t.radius.md;
    u.dl().rectFilled(r, cols.bg, rounding);
    u.dl().rectStroke(r, cols.border, rounding, 1);
    icons.draw(u.dl(), ic, r.center(), o.size.iconSize() + 1, cols.fg);
    if (o.tooltip) |tip| u.setTooltip(tip);
    return hit.clicked and !o.disabled;
}

// =====================================================================
// Toggles: switch, checkbox, radio
// =====================================================================

pub fn toggle(lbl: [:0]const u8, value: *bool) bool {
    const u = ui.get();
    const vis = ui.UiContext.visibleLabel(lbl);
    const tw: f32 = 36;
    const th: f32 = 20;
    const gap: f32 = 10;
    const style: TextStyle = .{ .size = u.theme.type.body, .weight = .regular };
    const ts = u.renderer.measureText(vis, style, 0);
    const row_h = @max(th, ts.y);
    const w = tw + (if (vis.len > 0) gap + ts.x else 0);
    const r = u.allocRect(v2(w, row_h));
    const id = u.hashId(lbl);
    const hit = u.buttonBehavior(id, r, false);
    if (hit.clicked) value.* = !value.*;

    const t = &u.theme;
    const p = &t.palette;
    const hover_t = u.anim.toggle(id, 1, hit.hovered, t.motion.fast);
    const press_t = u.anim.toggle(id, 2, hit.held, t.motion.fast * 1.4);
    const on_t = u.anim.spring(id, 5, if (value.*) 1.0 else 0.0, 420);

    const track = Rect.fromSize(v2(r.min.x, r.min.y + (row_h - th) * 0.5), v2(tw, th));
    const off_bg = Color.mix(p.border_strong, p.text_faint, hover_t * 0.4);
    const on_bg = p.accent.lighten(0.06 * hover_t);
    u.dl().rectFilled(track, Color.mix(off_bg, on_bg, std.math.clamp(on_t, 0, 1)), th * 0.5);

    const knob_r = th * 0.5 - 2.5;
    const stretch = press_t * 4.0;
    const kx = track.min.x + th * 0.5 + (tw - th) * on_t;
    const krect = Rect{
        .min = v2(kx - knob_r - stretch * (1 - on_t), track.center().y - knob_r),
        .max = v2(kx + knob_r + stretch * on_t, track.center().y + knob_r),
    };
    u.dl().shadow(krect, knob_r, p.shadow.fade(0.5), 3, 1);
    u.dl().rectFilled(krect, Color.white, knob_r);

    if (vis.len > 0) u.dl().text(v2(track.max.x + gap, r.min.y + (row_h - ts.y) * 0.5), p.text, vis, style, 0);
    return hit.clicked;
}

pub fn checkbox(lbl: [:0]const u8, value: *bool) bool {
    const u = ui.get();
    const vis = ui.UiContext.visibleLabel(lbl);
    const bs: f32 = 18;
    const gap: f32 = 10;
    const style: TextStyle = .{ .size = u.theme.type.body, .weight = .regular };
    const ts = u.renderer.measureText(vis, style, 0);
    const row_h = @max(bs, ts.y);
    const w = bs + (if (vis.len > 0) gap + ts.x else 0);
    const r = u.allocRect(v2(w, row_h));
    const id = u.hashId(lbl);
    const hit = u.buttonBehavior(id, r, false);
    if (hit.clicked) value.* = !value.*;

    const t = &u.theme;
    const p = &t.palette;
    const hover_t = u.anim.toggle(id, 1, hit.hovered, t.motion.fast);
    const on_t = u.anim.toggle(id, 5, value.*, t.motion.normal);

    const box = Rect.fromSize(v2(r.min.x, r.min.y + (row_h - bs) * 0.5), v2(bs, bs));
    const rounding: f32 = 5;
    u.dl().rectFilled(box, Color.mix(p.surface, p.accent, on_t), rounding);
    u.dl().rectStroke(box, Color.mix(Color.mix(p.border_strong, p.text_faint, hover_t), p.accent, on_t), rounding, 1.5);

    if (on_t > 0.01) {
        const k = bs / 24.0;
        const p0 = v2(box.min.x + 6 * k, box.min.y + 12.5 * k);
        const p1 = v2(box.min.x + 10 * k, box.min.y + 16.5 * k);
        const p2 = v2(box.min.x + 18 * k, box.min.y + 8 * k);
        const prog = anim_mod.ease.outCubic(on_t);
        const first = @min(prog / 0.4, 1.0);
        const mid = v2(p0.x + (p1.x - p0.x) * first, p0.y + (p1.y - p0.y) * first);
        if (prog > 0.4) {
            const sec = (prog - 0.4) / 0.6;
            const end = v2(p1.x + (p2.x - p1.x) * sec, p1.y + (p2.y - p1.y) * sec);
            u.dl().polyline(&.{ p0, mid, end }, false, p.on_accent, 2.0);
        } else {
            u.dl().polyline(&.{ p0, mid }, false, p.on_accent, 2.0);
        }
    }
    if (vis.len > 0) u.dl().text(v2(box.max.x + gap, r.min.y + (row_h - ts.y) * 0.5), p.text, vis, style, 0);
    return hit.clicked;
}

pub fn radio(lbl: [:0]const u8, selected: bool) bool {
    const u = ui.get();
    const vis = ui.UiContext.visibleLabel(lbl);
    const bs: f32 = 18;
    const gap: f32 = 10;
    const style: TextStyle = .{ .size = u.theme.type.body, .weight = .regular };
    const ts = u.renderer.measureText(vis, style, 0);
    const row_h = @max(bs, ts.y);
    const w = bs + (if (vis.len > 0) gap + ts.x else 0);
    const r = u.allocRect(v2(w, row_h));
    const id = u.hashId(lbl);
    const hit = u.buttonBehavior(id, r, false);

    const t = &u.theme;
    const p = &t.palette;
    const hover_t = u.anim.toggle(id, 1, hit.hovered, t.motion.fast);
    const on_t = u.anim.spring(id, 5, if (selected) 1.0 else 0.0, 380);

    const ctr = v2(r.min.x + bs * 0.5, r.min.y + row_h * 0.5);
    const ring_col = Color.mix(Color.mix(p.border_strong, p.text_faint, hover_t), p.accent, std.math.clamp(on_t, 0, 1));
    u.dl().circleFilled(ctr, bs * 0.5, p.surface);
    u.dl().circleStroke(ctr, bs * 0.5 - 0.75, ring_col, 1.5);
    if (on_t > 0.01) u.dl().circleFilled(ctr, bs * 0.27 * on_t, p.accent);
    if (vis.len > 0) u.dl().text(v2(r.min.x + bs + gap, r.min.y + (row_h - ts.y) * 0.5), p.text, vis, style, 0);
    return hit.clicked;
}

pub fn radioGroup(id_str: [:0]const u8, comptime E: type, value: *E, o: struct {
    labels: ?[]const [:0]const u8 = null,
    horizontal: bool = false,
}) bool {
    const u = ui.get();
    u.pushId(id_str);
    defer u.popId();
    var changed = false;
    inline for (@typeInfo(E).@"enum".field_names, 0..) |name, i| {
        if (o.horizontal and i > 0) u.placeSameLine(18);
        const lbl: [:0]const u8 = if (o.labels) |ls| (if (i < ls.len) ls[i] else name) else name;
        u.pushIdInt(i);
        if (radio(lbl, value.* == @field(E, name))) {
            if (value.* != @field(E, name)) changed = true;
            value.* = @field(E, name);
        }
        u.popId();
    }
    return changed;
}

// =====================================================================
// Sliders
// =====================================================================

pub const SliderOptions = struct {
    decimals: u8 = 0,
    suffix: []const u8 = "",
    step: f32 = 0,
    width: Width = .fill,
    show_value: bool = true,
    disabled: bool = false,
};

pub fn slider(lbl: [:0]const u8, value: *f32, min: f32, max: f32, o: SliderOptions) bool {
    const u = ui.get();
    const vis = ui.UiContext.visibleLabel(lbl);
    const t = &u.theme;
    const p = &t.palette;
    u.pushId(lbl);
    defer u.popId();

    const w = o.width.resolve(200);
    if (o.show_value and vis.len > 0) {
        var buf: [64]u8 = undefined;
        const val_txt = formatValue(&buf, value.*, o.decimals, o.suffix);
        const style: TextStyle = .{ .size = t.type.label, .weight = .medium };
        const ts = u.renderer.measureText(val_txt, style, 0);
        const row_r = u.allocRect(v2(w, ts.y));
        u.dl().text(row_r.min, p.text_muted, vis, style, 0);
        u.dl().text(v2(row_r.max.x - ts.x, row_r.min.y), p.text, val_txt, style, 0);
        u.box().cursor_y -= 4;
    }

    const h: f32 = 22;
    const r = u.allocRect(v2(w, h));
    const id = u.hashId("##track");
    const hit = u.buttonBehavior(id, r, o.disabled);
    if (hit.held) u.focused_id = id;

    const thumb_r: f32 = 8;
    const x0 = r.min.x + thumb_r;
    const x1 = r.max.x - thumb_r;
    const range = max - min;
    var changed = false;

    if (hit.held and range != 0) {
        var frac = std.math.clamp((u.input.mouse_pos.x - x0) / @max(x1 - x0, 1), 0.0, 1.0);
        var nv = min + frac * range;
        if (o.step > 0) nv = min + @round((nv - min) / o.step) * o.step;
        nv = std.math.clamp(nv, @min(min, max), @max(min, max));
        frac = (nv - min) / range;
        if (nv != value.*) {
            value.* = nv;
            changed = true;
        }
    }
    if (hit.focused and range != 0) {
        const step = if (o.step > 0) o.step else range / 100.0;
        if (u.input.key_left) {
            value.* = std.math.clamp(value.* - step, @min(min, max), @max(min, max));
            changed = true;
        }
        if (u.input.key_right) {
            value.* = std.math.clamp(value.* + step, @min(min, max), @max(min, max));
            changed = true;
        }
    }

    const hover_t = u.anim.toggle(id, 1, hit.hovered, t.motion.fast);
    const press_t = u.anim.toggle(id, 2, hit.held, t.motion.fast * 1.4);
    const target_t = if (range != 0) std.math.clamp((value.* - min) / range, 0.0, 1.0) else 0.0;
    const shown_t = if (hit.held) u.anim.smooth(id, 6, target_t, 60) else u.anim.smooth(id, 6, target_t, t.motion.normal);

    const cy = r.center().y;
    const track_h = 4.0 + 1.0 * hover_t;
    const track = Rect{ .min = v2(x0, cy - track_h * 0.5), .max = v2(x1, cy + track_h * 0.5) };
    u.dl().rectFilled(track, p.border_strong, track_h * 0.5);
    const fill = Rect{ .min = track.min, .max = v2(x0 + (x1 - x0) * shown_t, track.max.y) };
    if (fill.w() > 0.5) u.dl().gradient(fill, p.accent.darken(0.1), p.accent.lighten(0.1), track_h * 0.5, true);

    const tx = x0 + (x1 - x0) * shown_t;
    const grow = thumb_r * (1.0 + 0.12 * hover_t + 0.08 * press_t);
    if (hover_t > 0.01 or press_t > 0.01) {
        const m = @max(hover_t, press_t);
        u.dl().circleFilled(v2(tx, cy), grow + 6 * m, p.accent.withAlpha(0.16 * m));
    }
    u.dl().shadow(Rect{ .min = v2(tx - grow, cy - grow), .max = v2(tx + grow, cy + grow) }, grow, p.shadow.fade(0.6), 4, 1);
    u.dl().circleFilled(v2(tx, cy), grow, Color.white);
    u.dl().circleFilled(v2(tx, cy), grow * 0.42, p.accent);
    return changed;
}

pub fn sliderInt(lbl: [:0]const u8, value: *i32, min: i32, max: i32, o: SliderOptions) bool {
    var f: f32 = @floatFromInt(value.*);
    var oo = o;
    if (oo.step == 0) oo.step = 1;
    const changed = slider(lbl, &f, @floatFromInt(min), @floatFromInt(max), oo);
    value.* = @intFromFloat(@round(f));
    return changed;
}

fn formatValue(buf: []u8, v: f32, decimals: u8, suffix: []const u8) []const u8 {
    return switch (decimals) {
        0 => std.fmt.bufPrint(buf, "{d:.0}{s}", .{ v, suffix }),
        1 => std.fmt.bufPrint(buf, "{d:.1}{s}", .{ v, suffix }),
        2 => std.fmt.bufPrint(buf, "{d:.2}{s}", .{ v, suffix }),
        else => std.fmt.bufPrint(buf, "{d:.3}{s}", .{ v, suffix }),
    } catch "?";
}

// =====================================================================
// Text Input (native UTF-8 editing, focus glow, password mask, caret)
// =====================================================================

pub const InputOptions = struct {
    hint: [:0]const u8 = "",
    icon: ?Icon = null,
    width: Width = .fill,
    password: bool = false,
    read_only: bool = false,
    submit_on_enter: bool = false,
    size: ControlSize = .md,
    disabled: bool = false,
};

pub fn TextBuffer(comptime capacity: usize) type {
    return struct {
        const Self = @This();
        buf: [capacity]u8 = @splat(0),

        pub fn init(initial: []const u8) Self {
            var self: Self = .{};
            self.set(initial);
            return self;
        }
        pub fn set(self: *Self, s: []const u8) void {
            var n = @min(s.len, capacity - 1);
            while (n > 0 and n < s.len and (s[n] & 0xC0) == 0x80) n -= 1;
            @memcpy(self.buf[0..n], s[0..n]);
            self.buf[n] = 0;
        }
        pub fn slice(self: *const Self) []const u8 {
            return std.mem.sliceTo(&self.buf, 0);
        }
        pub fn clear(self: *Self) void {
            self.buf[0] = 0;
        }
    };
}

const EditKeys = struct {
    edited: bool = false,
    submitted: bool = false,
    moved_up: bool = false,
    moved_down: bool = false,
    page_up: bool = false,
    page_down: bool = false,
};

/// Keyboard editing of the focused buffer (caret / selection live in the UiContext).
fn handleEditKeys(u: *ui.UiContext, buf: []u8, len: *usize, multiline: bool, read_only: bool, secret: bool) EditKeys {
    var r: EditKeys = .{};
    const in = &u.input;
    var sel = textedit.selection(u.caret_pos, u.sel_anchor);

    if (in.shortcut_select_all) {
        u.sel_anchor = 0;
        u.caret_pos = len.*;
        return r;
    }
    if ((in.shortcut_copy or in.shortcut_cut) and !sel.empty() and !secret) {
        _ = clipboard.setText(buf[sel.lo..sel.hi]);
    }
    if (read_only) {
        moveCaret(u, buf[0..len.*], multiline, &r);
        return r;
    }
    if (in.shortcut_cut and !sel.empty() and !secret) {
        len.* = textedit.deleteRange(buf, len.*, sel.lo, sel.hi);
        u.caret_pos = sel.lo;
        u.sel_anchor = sel.lo;
        r.edited = true;
        sel = textedit.selection(u.caret_pos, u.sel_anchor);
    }
    if (in.shortcut_paste) {
        if (clipboard.getText(u.allocator)) |pasted| {
            defer u.allocator.free(pasted);
            const txt = if (multiline) clipboard.normalizeNewlines(pasted) else clipboard.singleLine(pasted);
            replaceSelection(u, buf, len, txt);
            r.edited = true;
        }
        sel = textedit.selection(u.caret_pos, u.sel_anchor);
    }
    const typed = in.typed();
    if (typed.len > 0) {
        replaceSelection(u, buf, len, typed);
        r.edited = true;
        sel = textedit.selection(u.caret_pos, u.sel_anchor);
    }
    if (in.key_backspace) {
        if (!sel.empty()) {
            len.* = textedit.deleteRange(buf, len.*, sel.lo, sel.hi);
            u.caret_pos = sel.lo;
        } else if (u.caret_pos > 0) {
            const from = if (in.ctrl_down) textedit.prevWord(buf[0..len.*], u.caret_pos) else textedit.prevBoundary(buf[0..len.*], u.caret_pos);
            len.* = textedit.deleteRange(buf, len.*, from, u.caret_pos);
            u.caret_pos = from;
        }
        u.sel_anchor = u.caret_pos;
        r.edited = true;
    }
    if (in.key_delete) {
        if (!sel.empty()) {
            len.* = textedit.deleteRange(buf, len.*, sel.lo, sel.hi);
            u.caret_pos = sel.lo;
        } else if (u.caret_pos < len.*) {
            const to = if (in.ctrl_down) textedit.nextWord(buf[0..len.*], u.caret_pos) else textedit.nextBoundary(buf[0..len.*], u.caret_pos);
            len.* = textedit.deleteRange(buf, len.*, u.caret_pos, to);
        }
        u.sel_anchor = u.caret_pos;
        r.edited = true;
    }
    if (in.key_enter) {
        if (multiline and (in.shift_down or in.ctrl_down)) {
            replaceSelection(u, buf, len, "\n");
            r.edited = true;
        } else {
            r.submitted = true;
        }
    }
    moveCaret(u, buf[0..len.*], multiline, &r);
    return r;
}

fn replaceSelection(u: *ui.UiContext, buf: []u8, len: *usize, txt: []const u8) void {
    const sel = textedit.selection(u.caret_pos, u.sel_anchor);
    if (!sel.empty()) {
        len.* = textedit.deleteRange(buf, len.*, sel.lo, sel.hi);
        u.caret_pos = sel.lo;
    }
    const n = textedit.insert(buf, len.*, u.caret_pos, txt);
    len.* += n;
    u.caret_pos += n;
    u.sel_anchor = u.caret_pos;
}

fn moveCaret(u: *ui.UiContext, txt: []const u8, multiline: bool, r: *EditKeys) void {
    const in = &u.input;
    const sel = textedit.selection(u.caret_pos, u.sel_anchor);
    var moved = false;
    if (in.key_left) {
        if (!in.shift_down and !sel.empty()) {
            u.caret_pos = sel.lo;
        } else if (in.ctrl_down) {
            u.caret_pos = textedit.prevWord(txt, u.caret_pos);
        } else {
            u.caret_pos = textedit.prevBoundary(txt, u.caret_pos);
        }
        moved = true;
    }
    if (in.key_right) {
        if (!in.shift_down and !sel.empty()) {
            u.caret_pos = sel.hi;
        } else if (in.ctrl_down) {
            u.caret_pos = textedit.nextWord(txt, u.caret_pos);
        } else {
            u.caret_pos = textedit.nextBoundary(txt, u.caret_pos);
        }
        moved = true;
    }
    if (in.key_home) {
        u.caret_pos = if (multiline and !in.ctrl_down) textedit.lineStart(txt, u.caret_pos) else 0;
        moved = true;
    }
    if (in.key_end) {
        u.caret_pos = if (multiline and !in.ctrl_down) textedit.lineEnd(txt, u.caret_pos) else txt.len;
        moved = true;
    }
    if (multiline) {
        r.moved_up = in.key_up;
        r.moved_down = in.key_down;
        r.page_up = in.key_page_up;
        r.page_down = in.key_page_down;
    }
    if (moved and !in.shift_down) u.sel_anchor = u.caret_pos;
}

/// Byte offset of the `n`th code point of `s`.
fn byteOfCodepoint(s: []const u8, n: usize) usize {
    var i: usize = 0;
    var k: usize = 0;
    while (i < s.len and k < n) : (k += 1) i = textedit.nextBoundary(s, i);
    return i;
}

fn codepointCount(s: []const u8) usize {
    return std.unicode.utf8CountCodepoints(s) catch s.len;
}

fn maskText(out: []u8, s: []const u8) []const u8 {
    var mlen: usize = 0;
    var idx: usize = 0;
    while (idx < s.len and mlen + 3 <= out.len) {
        idx = textedit.nextBoundary(s, idx);
        // UTF-8 bullet '•' (E2 80 A2)
        out[mlen] = 0xE2;
        out[mlen + 1] = 0x80;
        out[mlen + 2] = 0xA2;
        mlen += 3;
    }
    return out[0..mlen];
}

/// Single-line text input: caret, mouse selection (drag / double-click /
/// shift-click), clipboard (Ctrl+A/C/X/V), word jumps, horizontal scrolling
/// and IME placement. Returns true when edited (or on Enter with `submit_on_enter`).
pub fn textField(lbl: [:0]const u8, buf: []u8, o: InputOptions) bool {
    const u = ui.get();
    const t = &u.theme;
    const p = &t.palette;
    const h = o.size.height();
    const w = o.width.resolve(220);
    const isz = o.size.iconSize();
    const pad_x: f32 = 12 + (if (o.icon != null) isz + 8 else 0);

    const r = u.allocRect(v2(w, h));
    const id = u.hashId(lbl);
    const style: TextStyle = .{ .size = textSizePx(o.size.textSize()), .weight = .regular };
    const text_clip = Rect{ .min = v2(r.min.x + pad_x, r.min.y + 2), .max = v2(r.max.x - 10, r.max.y - 2) };
    var len = std.mem.sliceTo(buf, 0).len;

    var mask_buf: [768]u8 = undefined;
    const hovered = !o.disabled and u.canInteract(r);
    if (hovered) {
        u.hot_id = id;
        u.cursor_kind = .ibeam;
    }

    var focused = !o.disabled and u.focused_id == id;
    syncCaret(u, id, focused, buf[0..len]);

    // Mouse: place caret, drag-select, double-click selects a word.
    const scroll_x = if (focused) u.edit_scroll else 0;
    const origin_x = text_clip.min.x - scroll_x;
    if (hovered and u.input.mouse_pressed) {
        const was_focused = focused;
        u.focused_id = id;
        u.active_id = id;
        u.caret_id = id;
        focused = true;
        if (!was_focused) u.edit_scroll = 0;
        const pos = caretFromMouse(u, buf[0..len], style, o.password, &mask_buf, u.input.mouse_pos.x - origin_x);
        if (u.input.mouse_double_clicked and !o.password) {
            u.sel_anchor = textedit.prevWord(buf[0..len], pos);
            u.caret_pos = textedit.nextWord(buf[0..len], pos);
        } else {
            u.caret_pos = pos;
            if (!u.input.shift_down or !was_focused) u.sel_anchor = pos;
        }
    } else if (focused and u.active_id == id and u.input.mouse_down and !u.input.mouse_pressed) {
        u.caret_pos = caretFromMouse(u, buf[0..len], style, o.password, &mask_buf, u.input.mouse_pos.x - origin_x);
    }

    var edited = false;
    var submitted = false;
    if (focused) {
        const keys = handleEditKeys(u, buf, &len, false, o.read_only, o.password);
        edited = keys.edited;
        submitted = keys.submitted;
    }

    const hover_t = u.anim.toggle(id, 1, hovered, t.motion.fast);
    const focus_t = u.anim.toggle(id, 3, focused, t.motion.normal);
    const rounding = t.radius.md;

    if (focus_t > 0.01) {
        u.dl().rectStroke(r.expand(2.5), p.accent.withAlpha(0.22 * focus_t), rounding + 2.5, 3.0);
    }
    u.dl().rectFilled(r, p.surface, rounding);
    const border = Color.mix(Color.mix(p.border, p.border_strong, hover_t), p.accent, focus_t);
    u.dl().rectStroke(r, border, rounding, 1);

    if (o.icon) |ic| {
        icons.draw(u.dl(), ic, v2(r.min.x + 12 + isz * 0.5, r.center().y), isz, Color.mix(p.text_faint, p.accent, focus_t));
    }

    const shown: []const u8 = if (len == 0) o.hint else if (o.password) maskText(&mask_buf, buf[0..len]) else buf[0..len];
    const line_h = u.renderer.measureText("A", style, 0).y;
    const ty = r.center().y - line_h * 0.5;

    // Keep the caret inside the visible part of the field.
    const vis_w = text_clip.w();
    if (focused) {
        const caret_x = displayX(u, buf[0..len], style, o.password, &mask_buf, u.caret_pos);
        if (caret_x - u.edit_scroll > vis_w - 2) u.edit_scroll = caret_x - vis_w + 2;
        if (caret_x - u.edit_scroll < 0) u.edit_scroll = caret_x;
        const full_w = if (len > 0) u.renderer.measureText(shown, style, 0).x else 0;
        if (full_w - u.edit_scroll < vis_w - 2) u.edit_scroll = @max(full_w - vis_w + 2, 0);
    }
    const x0 = text_clip.min.x - (if (focused) u.edit_scroll else 0);

    u.dl().pushClip(text_clip);
    if (focused and u.caret_pos != u.sel_anchor and len > 0) {
        const sel = textedit.selection(u.caret_pos, u.sel_anchor);
        const sx = displayX(u, buf[0..len], style, o.password, &mask_buf, sel.lo);
        const ex = displayX(u, buf[0..len], style, o.password, &mask_buf, sel.hi);
        u.dl().rectFilled(Rect.xywh(x0 + sx, ty, ex - sx, line_h), p.accent.withAlpha(0.30), 2);
    }
    if (shown.len > 0) {
        u.dl().text(v2(x0, ty), if (len == 0) p.text_faint else p.text, shown, style, 0);
    }
    if (focused) {
        const cx = x0 + displayX(u, buf[0..len], style, o.password, &mask_buf, u.caret_pos);
        u.ime_caret = Rect.xywh(cx, ty, 1, line_h);
        const blink = @mod(u.anim.time, 1.0) < 0.55;
        if (blink) u.dl().line(v2(cx, r.min.y + 7), v2(cx, r.max.y - 7), p.accent, 1.5);
        u.anim.keepAlive(0.6);
    }
    u.dl().popClip();

    if (focused) u.caret_text_hash = textHash(buf[0..len]);
    return if (o.submit_on_enter) submitted else edited;
}

fn textHash(txt: []const u8) u64 {
    return std.hash.Wyhash.hash(0x63617265, txt);
}

/// Puts the caret at the end when an editor gains focus, or when the app
/// replaced its text since it last drew (the caret would otherwise keep an
/// offset into the old text, e.g. 0 after a cleared draft was restored).
fn syncCaret(u: *ui.UiContext, id: u64, focused: bool, txt: []const u8) void {
    // The caret is shared by all editors: an unfocused one must not touch
    // it (clamping it to an empty search box reset the composer's caret to 0
    // every frame).
    if (!focused) return;
    if (u.caret_id != id or u.caret_text_hash != textHash(txt)) {
        u.caret_id = id;
        u.caret_pos = txt.len;
        u.sel_anchor = txt.len;
        u.edit_scroll = 0;
    }
    if (u.caret_pos > txt.len) u.caret_pos = txt.len;
    if (u.sel_anchor > txt.len) u.sel_anchor = txt.len;
}

/// X offset (from the text origin) of byte offset `byte` as displayed (masked for passwords).
fn displayX(u: *ui.UiContext, txt: []const u8, style: TextStyle, password: bool, mask_buf: []u8, byte: usize) f32 {
    if (byte == 0 or txt.len == 0) return 0;
    if (password) {
        const shown = maskText(mask_buf, txt);
        const n = codepointCount(txt[0..@min(byte, txt.len)]);
        return u.renderer.caretAt(shown, style, 0, @min(n * 3, shown.len)).pos.x;
    }
    return u.renderer.caretAt(txt, style, 0, byte).pos.x;
}

fn caretFromMouse(u: *ui.UiContext, txt: []const u8, style: TextStyle, password: bool, mask_buf: []u8, x: f32) usize {
    if (txt.len == 0) return 0;
    if (password) {
        const shown = maskText(mask_buf, txt);
        const mpos = u.renderer.caretFromPoint(shown, style, 0, v2(x, 2));
        return byteOfCodepoint(txt, mpos / 3);
    }
    return u.renderer.caretFromPoint(txt, style, 0, v2(x, 2));
}

pub const TextAreaOptions = struct {
    hint: [:0]const u8 = "",
    width: Width = .fill,
    min_lines: u32 = 1,
    max_lines: u32 = 6,
    /// Enter submits (Shift/Ctrl+Enter inserts a line break). false: Enter inserts.
    submit_on_enter: bool = true,
    disabled: bool = false,
    read_only: bool = false,
    /// Draw the field chrome (border + background).
    chrome: bool = true,
    size: TextSize = .body,
};

pub const TextAreaResult = struct {
    edited: bool = false,
    submitted: bool = false,
    focused: bool = false,
    height: f32 = 0,
};

/// Multi-line, word-wrapping text editor that grows from `min_lines` to
/// `max_lines` and scrolls beyond that. Used for chat composers.
pub fn textArea(lbl: [:0]const u8, buf: []u8, o: TextAreaOptions) TextAreaResult {
    const u = ui.get();
    const t = &u.theme;
    const p = &t.palette;
    const style: TextStyle = .{ .size = textSizePx(o.size), .weight = .regular, .wrap = true };
    const pad_x: f32 = 12;
    const pad_y: f32 = 8;
    const w = o.width.resolve(240);
    const inner_w = @max(w - pad_x * 2, 20);
    const line_h = u.renderer.measureText("A", style, 0).y;
    const id = u.hashId(lbl);

    var len = std.mem.sliceTo(buf, 0).len;
    var focused = !o.disabled and u.focused_id == id;
    syncCaret(u, id, focused, buf[0..len]);

    var res: TextAreaResult = .{};
    if (focused) {
        const keys = handleEditKeys(u, buf, &len, true, o.read_only, false);
        res.edited = keys.edited;
        res.submitted = keys.submitted and o.submit_on_enter;
        if (keys.submitted and !o.submit_on_enter and !o.read_only) {
            replaceSelection(u, buf, &len, "\n");
            res.edited = true;
        }
        if (keys.moved_up or keys.moved_down or keys.page_up or keys.page_down) {
            const c = caretPos(u, buf[0..len], style, inner_w, u.caret_pos, line_h);
            const dy: f32 = if (keys.moved_up) -line_h else if (keys.moved_down) line_h else if (keys.page_up) -line_h * 5 else line_h * 5;
            const ty = c.pos.y + line_h * 0.5 + dy;
            if (ty < 0) {
                u.caret_pos = 0;
            } else {
                u.caret_pos = u.renderer.caretFromPoint(buf[0..len], style, inner_w, v2(c.pos.x, ty));
            }
            if (!u.input.shift_down) u.sel_anchor = u.caret_pos;
        }
    }

    // Size: content height clamped to [min_lines, max_lines].
    const txt = buf[0..len];
    // DirectWrite counts the empty line after a trailing '\n' in the height.
    const content_h = if (len > 0) u.renderer.measureText(txt, style, inner_w).y else line_h;
    const min_h = line_h * @as(f32, @floatFromInt(@max(o.min_lines, 1)));
    const max_h = line_h * @as(f32, @floatFromInt(@max(o.max_lines, o.min_lines)));
    const view_h = std.math.clamp(content_h, min_h, max_h);
    const r = u.allocRect(v2(w, view_h + pad_y * 2));
    res.height = r.h();
    const view = Rect{ .min = v2(r.min.x + pad_x, r.min.y + pad_y), .max = v2(r.max.x - pad_x, r.max.y - pad_y) };

    const hovered = !o.disabled and u.canInteract(r);
    if (hovered) {
        u.hot_id = id;
        u.cursor_kind = .ibeam;
    }

    // Mouse.
    const scroll_now = if (focused) u.edit_scroll else 0;
    if (hovered and u.input.mouse_pressed) {
        const was_focused = focused;
        u.focused_id = id;
        u.active_id = id;
        u.caret_id = id;
        focused = true;
        if (!was_focused) u.edit_scroll = 0;
        const pt = v2(u.input.mouse_pos.x - view.min.x, u.input.mouse_pos.y - view.min.y + scroll_now);
        const pos = u.renderer.caretFromPoint(txt, style, inner_w, pt);
        if (u.input.mouse_double_clicked) {
            u.sel_anchor = textedit.prevWord(txt, pos);
            u.caret_pos = textedit.nextWord(txt, pos);
        } else {
            u.caret_pos = pos;
            if (!u.input.shift_down or !was_focused) u.sel_anchor = pos;
        }
    } else if (focused and u.active_id == id and u.input.mouse_down and !u.input.mouse_pressed) {
        const pt = v2(u.input.mouse_pos.x - view.min.x, u.input.mouse_pos.y - view.min.y + scroll_now);
        u.caret_pos = u.renderer.caretFromPoint(txt, style, inner_w, pt);
    }
    if (hovered and u.input.mouse_wheel != 0 and content_h > view_h) {
        if (focused) u.edit_scroll = std.math.clamp(u.edit_scroll - u.input.mouse_wheel * line_h * 2, 0, content_h - view_h);
        u.input.mouse_wheel = 0;
    }
    res.focused = focused;

    // Keep the caret visible.
    const caret = caretPos(u, txt, style, inner_w, u.caret_pos, line_h);
    if (focused) {
        if (caret.pos.y + caret.height - u.edit_scroll > view_h) u.edit_scroll = caret.pos.y + caret.height - view_h;
        if (caret.pos.y - u.edit_scroll < 0) u.edit_scroll = caret.pos.y;
        u.edit_scroll = std.math.clamp(u.edit_scroll, 0, @max(content_h - view_h, 0));
    }
    const scroll = if (focused) u.edit_scroll else 0;

    const hover_t = u.anim.toggle(id, 1, hovered, t.motion.fast);
    const focus_t = u.anim.toggle(id, 3, focused, t.motion.normal);
    const rounding = t.radius.md;
    if (o.chrome) {
        if (focus_t > 0.01) u.dl().rectStroke(r.expand(2.5), p.accent.withAlpha(0.22 * focus_t), rounding + 2.5, 3.0);
        u.dl().rectFilled(r, p.surface, rounding);
        u.dl().rectStroke(r, Color.mix(Color.mix(p.border, p.border_strong, hover_t), p.accent, focus_t), rounding, 1);
    }

    u.dl().pushClip(view.expand(1));
    const origin = v2(view.min.x, view.min.y - scroll);
    if (focused and u.caret_pos != u.sel_anchor and len > 0) {
        const sel = textedit.selection(u.caret_pos, u.sel_anchor);
        const a = caretPos(u, txt, style, inner_w, sel.lo, line_h);
        const b = caretPos(u, txt, style, inner_w, sel.hi, line_h);
        const col = p.accent.withAlpha(0.30);
        if (@abs(a.pos.y - b.pos.y) < 1) {
            u.dl().rectFilled(Rect.xywh(origin.x + a.pos.x, origin.y + a.pos.y, b.pos.x - a.pos.x, a.height), col, 2);
        } else {
            u.dl().rectFilled(Rect.xywh(origin.x + a.pos.x, origin.y + a.pos.y, inner_w - a.pos.x, a.height), col, 2);
            const mid_top = a.pos.y + a.height;
            if (b.pos.y - mid_top > 1) u.dl().rectFilled(Rect.xywh(origin.x, origin.y + mid_top, inner_w, b.pos.y - mid_top), col, 2);
            u.dl().rectFilled(Rect.xywh(origin.x, origin.y + b.pos.y, b.pos.x, b.height), col, 2);
        }
    }
    if (len > 0) {
        u.dl().text(origin, p.text, txt, style, inner_w + 1);
    } else if (o.hint.len > 0) {
        u.dl().text(origin, p.text_faint, o.hint, .{ .size = style.size, .weight = .regular }, 0);
    }
    if (focused) {
        const cx = origin.x + caret.pos.x;
        const cy = origin.y + caret.pos.y;
        u.ime_caret = Rect.xywh(cx, cy, 1, caret.height);
        if (@mod(u.anim.time, 1.0) < 0.55) u.dl().line(v2(cx, cy + 2), v2(cx, cy + caret.height - 2), p.accent, 1.5);
        u.anim.keepAlive(0.6);
    }
    u.dl().popClip();
    if (focused) u.caret_text_hash = textHash(buf[0..len]);
    return res;
}

/// Caret position inside a wrapped layout, including after a trailing newline
/// (which DirectWrite reports at the end of the previous line).
fn caretPos(u: *ui.UiContext, txt: []const u8, style: TextStyle, wrap_w: f32, byte: usize, line_h: f32) Renderer.Caret {
    if (txt.len > 0 and byte == txt.len and txt[txt.len - 1] == '\n') {
        const prev = u.renderer.caretAt(txt, style, wrap_w, txt.len - 1);
        return .{ .pos = v2(0, prev.pos.y + prev.height), .height = prev.height };
    }
    const c = u.renderer.caretAt(txt, style, wrap_w, byte);
    return .{ .pos = c.pos, .height = if (c.height > 0) c.height else line_h };
}

// =====================================================================
// Segmented Control, Tabs & Select Dropdown
// =====================================================================

pub const SegmentedOptions = struct {
    width: Width = .auto,
    size: ControlSize = .md,
};

pub fn segmented(id_str: [:0]const u8, items: []const [:0]const u8, index: *usize, o: SegmentedOptions) bool {
    if (items.len == 0) return false;
    const u = ui.get();
    const t = &u.theme;
    const p = &t.palette;
    u.pushId(id_str);
    defer u.popId();

    const style: TextStyle = .{ .size = textSizePx(o.size.textSize()), .weight = .medium };
    const h = o.size.height();
    const inner_pad: f32 = 3;
    var max_w: f32 = 0;
    for (items) |it| max_w = @max(max_w, u.renderer.measureText(ui.UiContext.visibleLabel(it), style, 0).x);
    const seg_min = max_w + o.size.padX() * 2;
    const total = o.width.resolve(seg_min * @as(f32, @floatFromInt(items.len)) + inner_pad * 2);
    const seg_w = (total - inner_pad * 2) / @as(f32, @floatFromInt(items.len));

    const outer = u.allocRect(v2(total, h));
    u.dl().rectFilled(outer, p.bg_subtle, t.radius.md);
    u.dl().rectStroke(outer, p.border, t.radius.md, 1);

    const gid = u.hashId("##seg_group");
    const ind_x = u.anim.spring(gid, 7, @floatFromInt(@min(index.*, items.len - 1)), 300);
    const ind = Rect.fromSize(v2(outer.min.x + inner_pad + seg_w * ind_x, outer.min.y + inner_pad), v2(seg_w, h - inner_pad * 2));
    u.dl().shadow(ind, t.radius.sm, p.shadow.fade(0.45), 4, 1);
    u.dl().rectFilled(ind, if (t.dark) p.surface_raised.lighten(0.04) else p.surface, t.radius.sm);
    u.dl().rectStroke(ind, p.border_strong.fade(0.6), t.radius.sm, 1);

    var changed = false;
    for (items, 0..) |item, i| {
        const fi: f32 = @floatFromInt(i);
        const seg = Rect.fromSize(v2(outer.min.x + inner_pad + seg_w * fi, outer.min.y + inner_pad), v2(seg_w, h - inner_pad * 2));
        const sid = u.hashInt(i);
        const hit = u.buttonBehavior(sid, seg, false);
        if (hit.clicked) {
            if (index.* != i) changed = true;
            index.* = i;
        }
        const hover_t = u.anim.toggle(sid, 1, hit.hovered, t.motion.fast);
        const sel = 1.0 - std.math.clamp(@abs(ind_x - fi), 0.0, 1.0);
        const col = Color.mix(Color.mix(p.text_muted, p.text, hover_t * 0.6), p.text, sel);
        const vis = ui.UiContext.visibleLabel(item);
        const ts = u.renderer.measureText(vis, style, 0);
        u.dl().text(v2(seg.min.x + (seg.w() - ts.x) * 0.5, seg.min.y + (seg.h() - ts.y) * 0.5), col, vis, style, 0);
    }
    return changed;
}

pub fn tabs(id_str: [:0]const u8, items: []const [:0]const u8, index: *usize) bool {
    if (items.len == 0) return false;
    const u = ui.get();
    const t = &u.theme;
    const p = &t.palette;
    u.pushId(id_str);
    defer u.popId();

    const style: TextStyle = .{ .size = t.type.body, .weight = .medium };
    const h: f32 = 38;
    const gap: f32 = 22;
    const avail = u.availW();
    const outer = u.allocRect(v2(avail, h));
    u.dl().line(v2(outer.min.x, outer.max.y - 0.5), v2(outer.max.x, outer.max.y - 0.5), p.border, 1);

    var x = outer.min.x;
    var sel_x = outer.min.x;
    var sel_w: f32 = 0;
    var changed = false;

    for (items, 0..) |item, i| {
        const vis = ui.UiContext.visibleLabel(item);
        const ts = u.renderer.measureText(vis, style, 0);
        const tr = Rect.fromSize(v2(x, outer.min.y), v2(ts.x, h));
        const tid = u.hashInt(i);
        const hit = u.buttonBehavior(tid, tr, false);
        if (hit.clicked) {
            if (index.* != i) changed = true;
            index.* = i;
        }
        const hover_t = u.anim.toggle(tid, 1, hit.hovered, t.motion.fast);
        const is_sel = index.* == i;
        if (is_sel) {
            sel_x = x;
            sel_w = ts.x;
        }
        const col = if (is_sel) p.text else Color.mix(p.text_muted, p.text, hover_t);
        u.dl().text(v2(x, outer.min.y + (h - ts.y) * 0.5 - 1), col, vis, style, 0);
        x += ts.x + gap;
    }

    const gid = u.hashId("##tab_ind");
    const ax = u.anim.spring(gid, 8, sel_x - outer.min.x, 320);
    const aw = u.anim.spring(gid, 9, sel_w, 320);
    u.dl().rectFilled(Rect{ .min = v2(outer.min.x + ax, outer.max.y - 2), .max = v2(outer.min.x + ax + aw, outer.max.y) }, p.accent, 1);
    return changed;
}

pub const SelectOptions = struct {
    width: Width = .fill,
    size: ControlSize = .md,
    placeholder: [:0]const u8 = "Select...",
};

pub fn select(lbl: [:0]const u8, items: []const [:0]const u8, index: *usize, o: SelectOptions) bool {
    const u = ui.get();
    const t = &u.theme;
    const p = &t.palette;
    const h = o.size.height();
    const w = o.width.resolve(200);
    const r = u.allocRect(v2(w, h));
    const id = u.hashId(lbl);
    const hit = u.buttonBehavior(id, r, false);
    if (hit.clicked) {
        u.open_popup_id = if (u.open_popup_id == id) 0 else id;
        u.popup_anchor = r;
    }
    const open = u.open_popup_id == id;
    const hover_t = u.anim.toggle(id, 1, hit.hovered, t.motion.fast);
    const open_t = u.anim.toggle(id, 2, open, t.motion.normal);

    u.dl().rectFilled(r, p.surface, t.radius.md);
    u.dl().rectStroke(r, Color.mix(Color.mix(p.border, p.border_strong, hover_t), p.accent, open_t), t.radius.md, 1);

    const style: TextStyle = .{ .size = textSizePx(o.size.textSize()), .weight = .regular };
    const preview: []const u8 = if (index.* < items.len) ui.UiContext.visibleLabel(items[index.*]) else o.placeholder;
    const ts = u.renderer.measureText(preview, style, 0);
    u.dl().text(v2(r.min.x + 12, r.center().y - ts.y * 0.5), p.text, preview, style, 0);

    const ic_c = v2(r.max.x - 18, r.center().y);
    icons.draw(u.dl(), .chevron_down, ic_c, 16, p.text_muted.fade(1 - open_t));
    icons.draw(u.dl(), .chevron_up, ic_c, 16, p.text_muted.fade(open_t));

    var changed = false;
    if (open) {
        const prev_ov = u.using_overlay;
        u.using_overlay = true;
        defer u.using_overlay = prev_ov;

        const row_h: f32 = 30;
        const pad: f32 = 6;
        const pop_h = @as(f32, @floatFromInt(items.len)) * row_h + pad * 2;
        const pop_r = Rect.xywh(r.min.x, r.max.y + 4, w, pop_h);
        u.popup_rect = pop_r;
        u.popup_drawn = true;

        u.dl().shadow(pop_r, t.radius.md, p.shadow.fade(0.75), 14, 4);
        u.dl().rectFilled(pop_r, p.surface_raised, t.radius.md);
        u.dl().rectStroke(pop_r, p.border_strong, t.radius.md, 1);

        for (items, 0..) |item, i| {
            const rr = Rect.xywh(pop_r.min.x + pad, pop_r.min.y + pad + @as(f32, @floatFromInt(i)) * row_h, w - pad * 2, row_h);
            const rid = u.hashInt(i) ^ id;
            const rhit = u.buttonBehavior(rid, rr, false);
            const rh = u.anim.toggle(rid, 1, rhit.hovered, t.motion.fast);
            u.dl().rectFilled(rr, p.text.withAlpha(0.07 * rh), t.radius.sm);
            const is_sel = i == index.*;
            if (is_sel) icons.draw(u.dl(), .check, v2(rr.min.x + 16, rr.center().y), 15, p.accent);
            const vis = ui.UiContext.visibleLabel(item);
            const its = u.renderer.measureText(vis, style, 0);
            u.dl().text(v2(rr.min.x + 34, rr.center().y - its.y * 0.5), p.text, vis, style, 0);
            if (rhit.clicked) {
                if (!is_sel) changed = true;
                index.* = i;
                u.open_popup_id = 0;
            }
        }
    }
    return changed;
}

// =====================================================================
// Display: badge, progress, spinner, avatar, divider, tooltip, sparkline, stat
// =====================================================================

pub const BadgeOptions = struct {
    tone: Tone = .neutral,
    solid: bool = false,
    dot: bool = false,
};

pub fn badge(str: []const u8, o: BadgeOptions) void {
    const u = ui.get();
    const t = &u.theme;
    const p = &t.palette;
    const style: TextStyle = .{ .size = t.type.caption, .weight = .semibold };
    const base = if (o.tone == .neutral) p.text_muted else t.tone(o.tone);
    const ts = u.renderer.measureText(str, style, 0);
    const pad = v2(8, 3);
    const dot_w: f32 = if (o.dot) 10 else 0;
    const r = u.allocRect(v2(ts.x + pad.x * 2 + dot_w, ts.y + pad.y * 2));

    const bg = if (o.solid) base else base.withAlpha(if (t.dark) 0.16 else 0.12);
    const fg = if (o.solid) base.contrastText() else if (t.dark) base.lighten(0.15) else base.darken(0.15);
    u.dl().rectFilled(r, bg, r.h() * 0.5);
    if (!o.solid) u.dl().rectStroke(r, base.withAlpha(0.22), r.h() * 0.5, 1);
    if (o.dot) u.dl().circleFilled(v2(r.min.x + pad.x + 3, r.center().y), 3, fg);
    u.dl().text(v2(r.min.x + pad.x + dot_w, r.min.y + pad.y), fg, str, style, 0);
}

pub const ProgressOptions = struct {
    tone: Tone = .accent,
    height: f32 = 6,
    width: Width = .fill,
};

pub fn progress(id_str: [:0]const u8, value: f32, o: ProgressOptions) void {
    const u = ui.get();
    const t = &u.theme;
    const w = o.width.resolve(160);
    const r = u.allocRect(v2(w, o.height));
    const id = u.hashId(id_str);
    const frac = u.anim.smoothFrom(id, 10, std.math.clamp(value, 0, 1), t.motion.slow, 0);
    u.dl().rectFilled(r, t.palette.border, o.height * 0.5);
    const col = t.tone(o.tone);
    if (frac > 0.001) {
        const fr = Rect{ .min = r.min, .max = v2(r.min.x + @max(w * frac, o.height), r.max.y) };
        u.dl().gradient(fr, col.darken(0.08), col.lighten(0.12), o.height * 0.5, true);
    }
}

pub fn progressIndeterminate(o: ProgressOptions) void {
    const u = ui.get();
    const t = &u.theme;
    const w = o.width.resolve(160);
    const r = u.allocRect(v2(w, o.height));
    if (u.isCulled(r) or (u.scroll_depth == 0 and u.main_view_rect.w() > 0 and !r.intersects(u.main_view_rect))) return;
    u.dl().rectFilled(r, t.palette.border, o.height * 0.5);
    const phase = u.anim.loop(1.4);
    const seg = w * 0.35;
    const x = r.min.x - seg + (w + seg) * anim_mod.ease.inOutCubic(phase);
    u.dl().pushClip(r);
    u.dl().rectFilled(Rect{ .min = v2(x, r.min.y), .max = v2(x + seg, r.max.y) }, t.tone(o.tone), o.height * 0.5);
    u.dl().popClip();
}

pub fn spinnerAt(dl: *DrawList, center: Vec2, radius: f32, col: Color) void {
    const phase = ui.get().anim.loop(0.9);
    const a0 = phase * std.math.tau;
    const sweep = std.math.pi * (0.6 + 0.4 * @sin(phase * std.math.tau));
    const th = @max(radius * 0.22, 1.5);
    dl.circleStroke(center, radius, col.fade(0.18), th);
    dl.arc(center, radius, a0, a0 + sweep, col, th);
}

pub const SpinnerOptions = struct {
    size: f32 = 20,
    tone: Tone = .accent,
};

pub fn spinner(o: SpinnerOptions) void {
    const u = ui.get();
    const r = u.allocRect(v2(o.size, o.size));
    if (u.isCulled(r) or (u.scroll_depth == 0 and u.main_view_rect.w() > 0 and !r.intersects(u.main_view_rect))) return;
    spinnerAt(u.dl(), r.center(), o.size * 0.42, u.theme.tone(o.tone));
}

pub const AvatarOptions = struct {
    size: f32 = 36,
    color: ?Color = null,
    status: ?Tone = null,
};

pub fn avatar(name: []const u8, o: AvatarOptions) void {
    const u = ui.get();
    const s = o.size;
    const r = u.allocRect(v2(s, s));
    const base = o.color orelse hashColor(name);
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

    if (o.status) |st| {
        const dr = s * 0.14;
        const dc = v2(r.max.x - dr * 1.1, r.max.y - dr * 1.1);
        u.dl().circleFilled(dc, dr + 2, u.theme.palette.bg);
        u.dl().circleFilled(dc, dr, u.theme.tone(st));
    }
}

fn hashColor(s: []const u8) Color {
    const palette = [_]Color{
        Color.hex(0x7C6CFF), Color.hex(0x2DD4BF), Color.hex(0xF59E0B), Color.hex(0xEC4899),
        Color.hex(0x60A5FA), Color.hex(0x34D399), Color.hex(0xF87171), Color.hex(0xA78BFA),
    };
    var h: u32 = 2166136261;
    for (s) |ch| h = (h ^ ch) *% 16777619;
    return palette[h % palette.len];
}

pub fn divider() void {
    const u = ui.get();
    const r = u.allocRect(v2(u.availW(), 12));
    u.dl().line(v2(r.min.x, r.center().y), v2(r.max.x, r.center().y), u.theme.palette.border, 1);
}

pub fn dividerText(str: []const u8) void {
    const u = ui.get();
    const p = &u.theme.palette;
    const style: TextStyle = .{ .size = u.theme.type.caption, .weight = .medium };
    const ts = u.renderer.measureText(str, style, 0);
    const r = u.allocRect(v2(u.availW(), ts.y + 8));
    const y = r.center().y;
    const tx = r.min.x + (r.w() - ts.x) * 0.5;
    u.dl().line(v2(r.min.x, y), v2(tx - 10, y), p.border, 1);
    u.dl().line(v2(tx + ts.x + 10, y), v2(r.max.x, y), p.border, 1);
    u.dl().text(v2(tx, y - ts.y * 0.5), p.text_faint, str, style, 0);
}

pub fn tooltip(str: [:0]const u8) void {
    ui.get().setTooltip(str);
}

pub const SparklineOptions = struct {
    height: f32 = 48,
    width: Width = .fill,
    tone: Tone = .accent,
    fill: bool = true,
    thickness: f32 = 2,
};

pub fn sparkline(values: []const f32, o: SparklineOptions) void {
    const u = ui.get();
    const w = o.width.resolve(120);
    const r = u.allocRect(v2(w, o.height));
    if (values.len < 2) return;

    var lo = values[0];
    var hi = values[0];
    for (values) |v| {
        lo = @min(lo, v);
        hi = @max(hi, v);
    }
    if (hi - lo < 1e-6) hi = lo + 1;

    const col = u.theme.tone(o.tone);
    const pad = o.thickness + 2;
    const step = w / @as(f32, @floatFromInt(values.len - 1));

    var pts: [64]Vec2 = undefined;
    const n = @min(values.len, pts.len - 2);
    for (0..n) |i| {
        const frac = (values[i] - lo) / (hi - lo);
        pts[i] = v2(r.min.x + step * @as(f32, @floatFromInt(i)), r.min.y + pad + (o.height - pad * 2) * (1.0 - frac));
    }

    if (o.fill) {
        pts[n] = v2(pts[n - 1].x, r.max.y);
        pts[n + 1] = v2(pts[0].x, r.max.y);
        u.dl().polygonGradient(pts[0 .. n + 2], r.min.y, r.max.y, col.withAlpha(0.28), col.withAlpha(0.0));
    }
    u.dl().polyline(pts[0..n], false, col, o.thickness);
    const last = pts[n - 1];
    u.dl().circleFilled(last, 3.5, col);
    u.dl().circleFilled(last, 1.6, u.theme.palette.surface);
}

pub fn stat(lbl: []const u8, value: []const u8, delta_pct: ?f32) void {
    text(lbl, .{ .size = .label, .weight = .medium, .ink = .muted });
    ui.get().box().cursor_y -= 4;
    text(value, .{ .size = .display, .weight = .bold });
    if (delta_pct) |d| {
        var buf: [32]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "{s}{d:.1}%", .{ if (d >= 0) "+" else "", d }) catch "";
        badge(s, .{ .tone = if (d >= 0) .success else .danger });
    }
}

// =====================================================================
// Overlays: Toast, Menu, Dialog
// =====================================================================

pub const ToastOptions = struct {
    description: ?[]const u8 = null,
};

pub fn toast(tone: Tone, title: []const u8, o: ToastOptions) void {
    ui.get().addToast(tone, title, o.description);
}

pub fn openMenu(id_str: [:0]const u8) void {
    const u = ui.get();
    u.open_popup_id = u.hashId(id_str);
    u.popup_anchor = u.box().last_rect;
}

/// Opens the menu `id_str` below `anchor` (e.g. a 1x1 rect at the mouse for context menus).
pub fn openMenuAt(id_str: [:0]const u8, anchor: Rect) void {
    const u = ui.get();
    u.open_popup_id = u.hashId(id_str);
    u.popup_anchor = anchor;
    u.anim.markActive();
}

pub fn isMenuOpen(id_str: [:0]const u8) bool {
    const u = ui.get();
    return u.open_popup_id == u.hashId(id_str);
}

pub fn closeMenu() void {
    ui.get().open_popup_id = 0;
}

var menu_origin: Vec2 = v2(0, 0);
var menu_cmd_index: usize = 0;
/// Height of the last drawn menu (used to flip menus that would leave the window).
var menu_last_h: f32 = 0;
const menu_w: f32 = 200;

pub fn beginMenu(id_str: [:0]const u8) bool {
    const u = ui.get();
    const id = u.hashId(id_str);
    if (u.open_popup_id != id) return false;

    u.using_overlay = true;
    var ox = u.popup_anchor.min.x;
    var oy = u.popup_anchor.max.y + 4;
    if (ox + menu_w > u.viewport.x - 8) ox = @max(u.viewport.x - menu_w - 8, 8);
    if (menu_last_h > 0 and oy + menu_last_h > u.viewport.y - 8) oy = @max(u.popup_anchor.min.y - 4 - menu_last_h, 8);
    menu_origin = v2(ox, oy);
    menu_cmd_index = u.dl().cmds.items.len;
    u.pushBox(.{
        .origin_x = menu_origin.x + 6,
        .origin_y = menu_origin.y + 6,
        .avail_w = 188,
        .cursor_x = menu_origin.x + 6,
        .cursor_y = menu_origin.y + 6,
        .max_x = menu_origin.x + 6,
        .max_y = menu_origin.y + 6,
        .spacing_x = 4,
        .spacing_y = 2,
    });
    return true;
}

pub fn menuLabel(title: []const u8) void {
    const u = ui.get();
    const style: TextStyle = .{ .size = u.theme.type.caption, .weight = .semibold };
    const r = u.allocRect(v2(u.availW(), 22));
    u.dl().text(v2(r.min.x + 8, r.min.y + 4), u.theme.palette.text_faint, title, style, 0);
}

pub const MenuItemOptions = struct {
    icon: ?Icon = null,
    shortcut: ?[]const u8 = null,
    danger: bool = false,
};

pub fn menuItem(lbl: [:0]const u8, o: MenuItemOptions) bool {
    const u = ui.get();
    const t = &u.theme;
    const p = &t.palette;
    const r = u.allocRect(v2(u.availW(), 30));
    const id = u.hashId(lbl);
    const hit = u.buttonBehavior(id, r, false);
    const hover_t = u.anim.toggle(id, 1, hit.hovered, t.motion.fast);

    const fg = if (o.danger) p.danger else p.text;
    u.dl().rectFilled(r, (if (o.danger) p.danger else p.text).withAlpha(0.08 * hover_t), t.radius.sm);

    var x = r.min.x + 10;
    if (o.icon) |ic| {
        icons.draw(u.dl(), ic, v2(x + 7, r.center().y), 15, if (o.danger) p.danger else p.text_muted);
        x += 24;
    }
    const style: TextStyle = .{ .size = t.type.label, .weight = .regular };
    const vis = ui.UiContext.visibleLabel(lbl);
    const ts = u.renderer.measureText(vis, style, 0);
    u.dl().text(v2(x, r.center().y - ts.y * 0.5), fg, vis, style, 0);

    if (o.shortcut) |sc| {
        const sc_style: TextStyle = .{ .size = t.type.caption, .weight = .regular, .mono = true };
        const sc_ts = u.renderer.measureText(sc, sc_style, 0);
        u.dl().text(v2(r.max.x - sc_ts.x - 8, r.center().y - sc_ts.y * 0.5), p.text_faint, sc, sc_style, 0);
    }

    if (hit.clicked) u.open_popup_id = 0;
    return hit.clicked;
}

pub fn menuSeparator() void {
    const u = ui.get();
    const r = u.allocRect(v2(u.availW(), 8));
    u.dl().line(v2(r.min.x + 4, r.center().y), v2(r.max.x - 4, r.center().y), u.theme.palette.border, 1);
}

pub fn endMenu() void {
    const u = ui.get();
    const b = u.popBox();
    const w: f32 = menu_w;
    const h = (b.max_y - menu_origin.y) + 6;
    if (@abs(h - menu_last_h) > 0.5) u.anim.markActive();
    menu_last_h = h;
    const pop_r = Rect.xywh(menu_origin.x, menu_origin.y, w, h);
    u.popup_rect = pop_r;
    u.popup_drawn = true;

    const t = &u.theme;
    const p = &t.palette;
    const bg_cmds = [_]ui.DrawCmd{
        .{ .shadow = .{ .rect = pop_r, .rounding = t.radius.md, .color = p.shadow.fade(0.75), .blur = 14, .offset_y = 4 } },
        .{ .rect_filled = .{ .rect = pop_r, .color = p.surface_raised, .rounding = t.radius.md } },
        .{ .rect_stroke = .{ .rect = pop_r, .color = p.border_strong, .rounding = t.radius.md, .thickness = 1 } },
    };
    u.dl().insertCmds(menu_cmd_index, &bg_cmds);
    u.using_overlay = false;
}

pub const DialogOptions = struct {
    description: ?[]const u8 = null,
    width: f32 = 420,
};

var dialog_cmd_index: usize = 0;
var dialog_origin: Vec2 = v2(0, 0);
var dialog_width: f32 = 420;

pub fn beginDialog(title: []const u8, open: *bool, o: DialogOptions) bool {
    if (!open.*) return false;
    const u = ui.get();
    const t = &u.theme;
    const p = &t.palette;

    u.modal_active = true;
    u.using_overlay = true;
    const screen = Rect.xywh(0, 0, u.viewport.x, u.viewport.y);
    u.dl().rectFilled(screen, p.scrim, 0);

    dialog_width = o.width;
    dialog_origin = v2((u.viewport.x - o.width) * 0.5, (u.viewport.y - 210) * 0.45);
    dialog_cmd_index = u.dl().cmds.items.len;

    const pad: f32 = 24;
    u.pushBox(.{
        .origin_x = dialog_origin.x + pad,
        .origin_y = dialog_origin.y + pad,
        .avail_w = o.width - pad * 2,
        .cursor_x = dialog_origin.x + pad,
        .cursor_y = dialog_origin.y + pad,
        .max_x = dialog_origin.x + pad,
        .max_y = dialog_origin.y + pad,
        .spacing_x = 8,
        .spacing_y = 10,
    });
    text(title, .{ .size = .heading, .weight = .semibold });
    if (o.description) |desc| {
        u.box().cursor_y -= 4;
        text(desc, .{ .size = .body, .ink = .muted, .wrap = true });
    }
    layout.space(.sm);
    if (u.input.key_escape) open.* = false;
    return true;
}

pub fn beginDialogActions(width: f32) void {
    layout.alignRight(width);
    layout.beginRow(.sm);
}

pub fn endDialogActions() void {
    layout.endRow();
}

pub fn endDialog() void {
    const u = ui.get();
    const b = u.popBox();
    const h = (b.max_y - dialog_origin.y) + 24;
    const r = Rect.xywh(dialog_origin.x, dialog_origin.y, dialog_width, h);
    const t = &u.theme;
    const p = &t.palette;

    const chrome = [_]ui.DrawCmd{
        .{ .shadow = .{ .rect = r, .rounding = t.radius.xl, .color = p.shadow.fade(0.85), .blur = 28, .offset_y = 10 } },
        .{ .rect_filled = .{ .rect = r, .color = p.surface, .rounding = t.radius.xl } },
        .{ .rect_stroke = .{ .rect = r, .color = p.border_strong, .rounding = t.radius.xl, .thickness = 1 } },
    };
    u.dl().insertCmds(dialog_cmd_index, &chrome);
    u.using_overlay = false;
}
