//! Immediate-mode UI core context: input state, hit-testing, ID stack,
//! layout cursor/containers (sidebar, main scroll, cards, grids, rows, groups),
//! toasts, menus, dialogs, and per-frame scratch formatting.
const std = @import("std");
const math = @import("math.zig");
const Color = @import("color.zig").Color;
const theme_mod = @import("theme.zig");
const anim_mod = @import("anim.zig");
const dl_mod = @import("drawlist.zig");
const renderer_mod = @import("renderer.zig");
const win32 = @import("win32/win32.zig");

pub const Vec2 = math.Vec2;
pub const Rect = math.Rect;
pub const v2 = math.v2;
pub const Theme = theme_mod.Theme;
pub const Tone = theme_mod.Tone;
pub const DrawList = dl_mod.DrawList;
pub const DrawCmd = dl_mod.DrawCmd;
pub const TextStyle = dl_mod.TextStyle;
pub const TextWeight = dl_mod.TextWeight;
pub const Renderer = renderer_mod.Renderer;

pub const CursorKind = enum { arrow, hand, ibeam };

pub const InputState = struct {
    mouse_pos: Vec2 = v2(-1000, -1000),
    mouse_down: bool = false,
    mouse_pressed: bool = false,
    mouse_released: bool = false,
    mouse_wheel: f32 = 0,
    key_left: bool = false,
    key_right: bool = false,
    key_up: bool = false,
    key_down: bool = false,
    key_backspace: bool = false,
    key_delete: bool = false,
    key_enter: bool = false,
    key_escape: bool = false,
    key_home: bool = false,
    key_end: bool = false,
    key_tab: bool = false,
    ctrl_down: bool = false,
    shift_down: bool = false,
    typed_buf: [128]u8 = undefined,
    typed_len: usize = 0,

    pub fn pushUtf8(self: *InputState, bytes: []const u8) void {
        if (self.typed_len + bytes.len <= self.typed_buf.len) {
            @memcpy(self.typed_buf[self.typed_len .. self.typed_len + bytes.len], bytes);
            self.typed_len += bytes.len;
        }
    }

    pub fn typed(self: *const InputState) []const u8 {
        return self.typed_buf[0..self.typed_len];
    }

    pub fn endFrame(self: *InputState) void {
        self.mouse_pressed = false;
        self.mouse_released = false;
        self.mouse_wheel = 0;
        self.key_left = false;
        self.key_right = false;
        self.key_up = false;
        self.key_down = false;
        self.key_backspace = false;
        self.key_delete = false;
        self.key_enter = false;
        self.key_escape = false;
        self.key_home = false;
        self.key_end = false;
        self.key_tab = false;
        self.typed_len = 0;
    }
};

pub const Stats = struct {
    frames_presented: u64 = 0,
    fps: f32 = 0,
    animating: bool = false,
};

pub const LayoutBox = struct {
    origin_x: f32,
    origin_y: f32,
    avail_w: f32,
    cursor_x: f32,
    cursor_y: f32,
    max_x: f32,
    max_y: f32,
    spacing_x: f32 = 8,
    spacing_y: f32 = 10,
    same_line: bool = false,
    same_line_gap: f32 = 0,
    row_y: f32 = 0,
    row_max_h: f32 = 0,
    last_rect: Rect = .{ .min = v2(0, 0), .max = v2(0, 0) },
};

pub const GridState = struct {
    cols: u32,
    col_index: i32,
    gap: f32,
    origin_x: f32,
    start_y: f32,
    col_w: f32,
    max_bottom: f32,
};

pub const CardOptions = struct {
    padding: f32 = 20,
    width: ?f32 = null,
    height: ?f32 = null,
    elevated: bool = true,
    hoverable: bool = false,
    border: bool = true,
    background: ?Color = null,
};

pub const CardState = struct {
    id: u64,
    opts: CardOptions,
    cmd_index: usize,
    origin: Vec2,
    width: f32,
};

pub const ToastItem = struct {
    tone: Tone,
    title_buf: [96]u8 = undefined,
    title_len: usize = 0,
    desc_buf: [192]u8 = undefined,
    desc_len: usize = 0,
    created_at: f64,
    duration: f64 = 3.6,
};

pub const TooltipPending = struct {
    text_buf: [128]u8 = undefined,
    text_len: usize = 0,
    anchor: Rect,
};

pub const UiContext = struct {
    allocator: std.mem.Allocator,
    renderer: *Renderer,
    theme: Theme,
    theme_changed: bool = false,
    main_dl: DrawList,
    overlay_dl: DrawList,
    anim: anim_mod.AnimStore,
    input: InputState = .{},
    stats: Stats = .{},

    viewport: Vec2 = v2(1320, 860),
    cursor_kind: CursorKind = .arrow,
    using_overlay: bool = false,

    // Interaction state
    hot_id: u64 = 0,
    active_id: u64 = 0,
    focused_id: u64 = 0,
    last_id: u64 = 0,
    last_hovered: bool = false,
    modal_active: bool = false,
    open_popup_id: u64 = 0,
    popup_anchor: Rect = .{ .min = v2(0, 0), .max = v2(0, 0) },
    popup_rect: Rect = .{ .min = v2(0, 0), .max = v2(0, 0) },
    popup_drawn: bool = false,

    // Text editing caret (byte offset in active TextBuffer)
    caret_pos: usize = 0,
    caret_id: u64 = 0,

    // Main area scroll
    sidebar_w: f32 = 0,
    scroll_y: f32 = 0,
    scroll_target_y: f32 = 0,
    scroll_max_y: f32 = 0,
    main_view_rect: Rect = .{ .min = v2(0, 0), .max = v2(0, 0) },
    main_content_start_y: f32 = 0,
    main_padding: f32 = 32,

    // Stacks
    id_stack: [32]u64 = undefined,
    id_depth: usize = 0,
    box_stack: [32]LayoutBox = undefined,
    box_depth: usize = 0,
    row_gaps: [16]f32 = undefined,
    row_depth: usize = 0,
    grid_stack: [8]GridState = undefined,
    grid_depth: usize = 0,
    card_stack: [16]CardState = undefined,
    card_depth: usize = 0,

    // Scratch formatting buffer (reset every frame)
    scratch: [16384]u8 = undefined,
    scratch_pos: usize = 0,

    // Overlays
    toasts: [8]ToastItem = undefined,
    toast_count: usize = 0,
    tooltip_pending: ?TooltipPending = null,

    pub fn init(allocator: std.mem.Allocator, renderer: *Renderer, initial_theme: Theme) UiContext {
        return .{
            .allocator = allocator,
            .renderer = renderer,
            .theme = initial_theme,
            .main_dl = DrawList.init(allocator),
            .overlay_dl = DrawList.init(allocator),
            .anim = anim_mod.AnimStore.init(allocator),
        };
    }

    pub fn deinit(self: *UiContext) void {
        self.main_dl.deinit();
        self.overlay_dl.deinit();
        self.anim.deinit();
    }

    pub fn dl(self: *UiContext) *DrawList {
        return if (self.using_overlay) &self.overlay_dl else &self.main_dl;
    }

    pub fn beginFrame(self: *UiContext, now: f64, dt: f32) void {
        self.viewport = self.renderer.logicalSize();
        self.main_dl.clear();
        self.overlay_dl.clear();
        self.anim.beginFrame(now, dt, self.theme.motion.enabled);
        self.scratch_pos = 0;
        self.cursor_kind = .arrow;
        self.hot_id = 0;
        self.using_overlay = false;
        self.modal_active = false;
        self.popup_drawn = false;
        self.tooltip_pending = null;
        self.sidebar_w = 0;
        self.id_depth = 0;
        self.box_depth = 0;
        self.row_depth = 0;
        self.grid_depth = 0;
        self.card_depth = 0;

        // Smooth scroll interpolation
        if (@abs(self.scroll_target_y - self.scroll_y) > 0.25) {
            const k = if (self.theme.motion.enabled) 1.0 - @exp(-20.0 * self.anim.delta_time) else 1.0;
            self.scroll_y += (self.scroll_target_y - self.scroll_y) * k;
            self.anim.markActive();
        } else {
            self.scroll_y = self.scroll_target_y;
        }

        // Root layout box
        self.pushBox(.{
            .origin_x = 0,
            .origin_y = 0,
            .avail_w = self.viewport.x,
            .cursor_x = 0,
            .cursor_y = 0,
            .max_x = 0,
            .max_y = 0,
        });
    }

    pub fn endFrame(self: *UiContext) void {
        // Close popup if clicked outside or Escape pressed
        if (self.open_popup_id != 0) {
            if (self.input.key_escape) {
                self.open_popup_id = 0;
            } else if (self.input.mouse_pressed and self.popup_drawn and !self.popup_rect.contains(self.input.mouse_pos) and !self.popup_anchor.contains(self.input.mouse_pos)) {
                self.open_popup_id = 0;
            }
        }
        // Clear active on mouse release
        if (!self.input.mouse_down and self.active_id != 0) {
            self.active_id = 0;
        }
        // Clear text focus if clicking outside any text field
        if (self.input.mouse_pressed and self.hot_id == 0 and !self.modal_active) {
            self.focused_id = 0;
        }
        if (self.input.key_escape) {
            self.focused_id = 0;
        }

        self.drawTooltipOverlay();
        self.drawToastsOverlay();
    }

    // ---- ID hashing ----

    pub fn hashId(self: *const UiContext, str: []const u8) u64 {
        var h: u64 = if (self.id_depth > 0) self.id_stack[self.id_depth - 1] else 14695981039346656037;
        for (str) |b| {
            h ^= b;
            h *%= 1099511628211;
        }
        return h;
    }

    pub fn hashInt(self: *const UiContext, val: usize) u64 {
        var h: u64 = if (self.id_depth > 0) self.id_stack[self.id_depth - 1] else 14695981039346656037;
        h ^= @as(u64, val) +% 0x9E3779B97F4A7C15;
        h *%= 1099511628211;
        return h;
    }

    pub fn pushId(self: *UiContext, str: []const u8) void {
        if (self.id_depth < self.id_stack.len) {
            self.id_stack[self.id_depth] = self.hashId(str);
            self.id_depth += 1;
        }
    }

    pub fn pushIdInt(self: *UiContext, val: usize) void {
        if (self.id_depth < self.id_stack.len) {
            self.id_stack[self.id_depth] = self.hashInt(val);
            self.id_depth += 1;
        }
    }

    pub fn popId(self: *UiContext) void {
        if (self.id_depth > 0) self.id_depth -= 1;
    }

    // ---- Scratch formatting ----

    pub fn fmt(self: *UiContext, comptime format: []const u8, args: anytype) [:0]const u8 {
        const rem = self.scratch[self.scratch_pos..];
        const res = std.fmt.bufPrintSentinel(rem, format, args, 0) catch return "";
        self.scratch_pos += res.len + 1;
        return res;
    }

    // ---- Label helper (Dear ImGui ## convention) ----

    pub fn visibleLabel(lbl: []const u8) []const u8 {
        if (std.mem.indexOf(u8, lbl, "##")) |idx| return lbl[0..idx];
        return lbl;
    }

    // ---- Layout box management ----

    pub fn box(self: *UiContext) *LayoutBox {
        return &self.box_stack[self.box_depth - 1];
    }

    pub fn pushBox(self: *UiContext, b: LayoutBox) void {
        if (self.box_depth < self.box_stack.len) {
            self.box_stack[self.box_depth] = b;
            self.box_depth += 1;
        }
    }

    pub fn popBox(self: *UiContext) LayoutBox {
        self.box_depth -= 1;
        return self.box_stack[self.box_depth];
    }

    pub fn availW(self: *UiContext) f32 {
        const b = self.box();
        if (b.same_line) {
            return @max(b.origin_x + b.avail_w - b.cursor_x, 0);
        }
        return b.avail_w;
    }

    /// Allocates a rect of size `sz` in the current layout box and advances cursor.
    pub fn allocRect(self: *UiContext, sz: Vec2) Rect {
        const b = self.box();
        var x = b.cursor_x;
        var y = b.cursor_y;
        if (b.same_line) {
            y = b.row_y;
            b.same_line = false;
        } else {
            x = b.origin_x;
            b.row_y = y;
            b.row_max_h = 0;
        }
        const r = Rect.fromSize(v2(x, y), sz);
        b.last_rect = r;
        b.row_max_h = @max(b.row_max_h, sz.y);
        b.max_x = @max(b.max_x, r.max.x);
        b.max_y = @max(b.max_y, r.max.y);
        b.cursor_x = r.max.x;
        b.cursor_y = b.row_y + b.row_max_h + b.spacing_y;
        return r;
    }

    pub fn placeSameLine(self: *UiContext, gap: f32) void {
        const b = self.box();
        b.same_line = true;
        b.cursor_x = b.last_rect.max.x + gap;
    }

    pub fn alignRight(self: *UiContext, width: f32) void {
        const b = self.box();
        const right_x = b.origin_x + b.avail_w - width;
        if (b.same_line) {
            if (right_x > b.cursor_x) b.cursor_x = right_x;
        } else {
            b.cursor_x = @max(right_x, b.origin_x);
        }
    }

    // ---- Hit testing ----

    pub fn canInteract(self: *const UiContext, r: Rect) bool {
        if (self.modal_active and !self.using_overlay) return false;
        if (self.open_popup_id != 0 and !self.using_overlay and self.popup_rect.contains(self.input.mouse_pos)) return false;
        return r.contains(self.input.mouse_pos);
    }

    pub const HitResult = struct {
        id: u64,
        hovered: bool,
        held: bool,
        clicked: bool,
        focused: bool,
    };

    pub fn buttonBehavior(self: *UiContext, id: u64, r: Rect, disabled: bool) HitResult {
        const hovered = !disabled and self.canInteract(r) and (self.active_id == 0 or self.active_id == id);
        if (hovered) {
            self.hot_id = id;
            self.cursor_kind = .hand;
            if (self.input.mouse_pressed) {
                self.active_id = id;
            }
        }
        const held = !disabled and self.active_id == id and self.input.mouse_down;
        const clicked = !disabled and self.active_id == id and self.input.mouse_released and self.canInteract(r);
        self.last_id = id;
        self.last_hovered = hovered;
        return .{
            .id = id,
            .hovered = hovered,
            .held = held,
            .clicked = clicked,
            .focused = self.focused_id == id,
        };
    }

    // ---- Toasts & Tooltips ----

    pub fn addToast(self: *UiContext, tone: Tone, title: []const u8, desc: ?[]const u8) void {
        if (self.toast_count >= self.toasts.len) {
            // Drop oldest
            for (0..self.toasts.len - 1) |i| self.toasts[i] = self.toasts[i + 1];
            self.toast_count = self.toasts.len - 1;
        }
        var item: ToastItem = .{
            .tone = tone,
            .created_at = self.anim.time,
        };
        const tn = @min(title.len, item.title_buf.len);
        @memcpy(item.title_buf[0..tn], title[0..tn]);
        item.title_len = tn;
        if (desc) |d| {
            const dn = @min(d.len, item.desc_buf.len);
            @memcpy(item.desc_buf[0..dn], d[0..dn]);
            item.desc_len = dn;
        }
        self.toasts[self.toast_count] = item;
        self.toast_count += 1;
        self.anim.markActive();
    }

    pub fn setTooltip(self: *UiContext, text_str: []const u8) void {
        if (!self.last_hovered) return;
        var tp: TooltipPending = .{ .anchor = self.box().last_rect };
        const n = @min(text_str.len, tp.text_buf.len);
        @memcpy(tp.text_buf[0..n], text_str[0..n]);
        tp.text_len = n;
        self.tooltip_pending = tp;
    }

    fn drawTooltipOverlay(self: *UiContext) void {
        const tp = self.tooltip_pending orelse return;
        const str = tp.text_buf[0..tp.text_len];
        const style: TextStyle = .{ .size = self.theme.type.label, .weight = .regular };
        const ts = self.renderer.measureText(str, style, 0);
        const pad_x: f32 = 10;
        const pad_y: f32 = 6;
        const w = ts.x + pad_x * 2;
        const h = ts.y + pad_y * 2;
        var x = tp.anchor.center().x - w * 0.5;
        var y = tp.anchor.min.y - h - 8;
        if (y < 8) y = tp.anchor.max.y + 8;
        x = std.math.clamp(x, 8, @max(self.viewport.x - w - 8, 8));
        const r = Rect.xywh(x, y, w, h);
        const p = &self.theme.palette;
        const bg = if (self.theme.dark) p.surface_raised.lighten(0.05) else Color.hex(0x1D1F25);
        const fg = if (self.theme.dark) p.text else Color.hex(0xF3F4F6);
        self.overlay_dl.shadow(r, self.theme.radius.sm, p.shadow.fade(0.6), 10, 3);
        self.overlay_dl.rectFilled(r, bg, self.theme.radius.sm);
        self.overlay_dl.rectStroke(r, p.border_strong, self.theme.radius.sm, 1);
        self.overlay_dl.text(v2(x + pad_x, y + pad_y), fg, str, style, 0);
    }

    fn drawToastsOverlay(self: *UiContext) void {
        if (self.toast_count == 0) return;
        const p = &self.theme.palette;
        const now = self.anim.time;
        var dst: usize = 0;
        var y = self.viewport.y - 24;
        var i: usize = 0;
        while (i < self.toast_count) : (i += 1) {
            const item = self.toasts[i];
            const age = now - item.created_at;
            if (age > item.duration) continue;
            self.toasts[dst] = item;
            dst += 1;

            const enter_t = @min(@as(f32, @floatCast(age / 0.22)), 1.0);
            const exit_t = @min(@as(f32, @floatCast((item.duration - age) / 0.25)), 1.0);
            const alpha = anim_mod.ease.outCubic(@min(enter_t, exit_t));
            if (enter_t < 1.0 or exit_t < 1.0) self.anim.markActive();
            self.anim.keepAlive(item.duration - age);

            const title = item.title_buf[0..item.title_len];
            const desc = item.desc_buf[0..item.desc_len];
            const tw: f32 = 320;
            const title_style: TextStyle = .{ .size = self.theme.type.label, .weight = .semibold };
            const desc_style: TextStyle = .{ .size = self.theme.type.caption, .weight = .regular, .wrap = true };
            const tsz = self.renderer.measureText(title, title_style, tw - 44);
            const dsz = if (desc.len > 0) self.renderer.measureText(desc, desc_style, tw - 44) else v2(0, 0);
            const th = 22 + tsz.y + (if (desc.len > 0) dsz.y + 4 else 0);
            const slide = (1.0 - alpha) * 18.0;
            const r = Rect.xywh(self.viewport.x - tw - 24 + slide, y - th, tw, th);
            y -= th + 10;

            const prev_a = self.overlay_dl.alpha;
            self.overlay_dl.alpha = alpha;
            self.overlay_dl.shadow(r, self.theme.radius.md, p.shadow.fade(0.75), 14, 4);
            self.overlay_dl.rectFilled(r, p.surface_raised, self.theme.radius.md);
            self.overlay_dl.rectStroke(r, p.border_strong, self.theme.radius.md, 1);
            const accent = self.theme.tone(item.tone);
            self.overlay_dl.rectFilled(Rect.xywh(r.min.x + 1, r.min.y + 8, 3, th - 16), accent, 1.5);
            self.overlay_dl.text(v2(r.min.x + 16, r.min.y + 11), p.text, title, title_style, tw - 32);
            if (desc.len > 0) {
                self.overlay_dl.text(v2(r.min.x + 16, r.min.y + 11 + tsz.y + 3), p.text_muted, desc, desc_style, tw - 32);
            }
            self.overlay_dl.alpha = prev_a;
        }
        self.toast_count = dst;
    }
};

/// Active global UI context (matches MoonWin's concise `mw.button(...)` API).
pub var ctx: ?*UiContext = null;

pub inline fn get() *UiContext {
    return ctx.?;
}
