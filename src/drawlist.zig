//! Lightweight immediate-mode draw command list flushed to Direct2D + DirectWrite.
//! Supports deferred command insertion (so cards can draw shadow/background behind
//! auto-measured children) and a separate overlay list (popups, tooltips, modals, toasts).
const std = @import("std");
const math = @import("math.zig");
const Color = @import("color.zig").Color;

pub const Vec2 = math.Vec2;
pub const Rect = math.Rect;
pub const v2 = math.v2;

pub const TextWeight = enum(u8) {
    regular = 0,
    medium = 1,
    semibold = 2,
    bold = 3,
};

pub const TextStyle = struct {
    size: f32 = 14,
    weight: TextWeight = .regular,
    mono: bool = false,
    wrap: bool = false,
};

pub const DrawCmd = union(enum) {
    rect_filled: struct { rect: Rect, color: Color, rounding: f32 },
    rect_stroke: struct { rect: Rect, color: Color, rounding: f32, thickness: f32 },
    gradient_rect: struct { rect: Rect, from: Color, to: Color, rounding: f32, horizontal: bool },
    shadow: struct { rect: Rect, rounding: f32, color: Color, blur: f32, offset_y: f32 },
    circle_filled: struct { center: Vec2, radius: f32, color: Color },
    circle_stroke: struct { center: Vec2, radius: f32, color: Color, thickness: f32 },
    line: struct { a: Vec2, b: Vec2, color: Color, thickness: f32 },
    arc: struct { center: Vec2, radius: f32, a0: f32, a1: f32, color: Color, thickness: f32 },
    polyline: struct { start: u32, count: u32, closed: bool, color: Color, thickness: f32 },
    polygon_filled: struct { start: u32, count: u32, color: Color },
    polygon_gradient: struct { start: u32, count: u32, y0: f32, y1: f32, from: Color, to: Color },
    text: struct { pos: Vec2, max_w: f32, color: Color, style: TextStyle, start: u32, len: u32 },
    /// A bitmap from `Renderer.createImage`, stretched to `rect`.
    image: struct { rect: Rect, id: u32, rounding: f32, opacity: f32 },
    push_clip: Rect,
    pop_clip: void,
};

pub const DrawList = struct {
    allocator: std.mem.Allocator,
    cmds: std.ArrayList(DrawCmd) = .empty,
    points: std.ArrayList(Vec2) = .empty,
    text_buf: std.ArrayList(u8) = .empty,
    alpha: f32 = 1.0,

    pub fn init(allocator: std.mem.Allocator) DrawList {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *DrawList) void {
        self.cmds.deinit(self.allocator);
        self.points.deinit(self.allocator);
        self.text_buf.deinit(self.allocator);
    }

    pub fn clear(self: *DrawList) void {
        self.cmds.clearRetainingCapacity();
        self.points.clearRetainingCapacity();
        self.text_buf.clearRetainingCapacity();
        self.alpha = 1.0;
    }

    fn applyAlpha(self: *const DrawList, c: Color) Color {
        return if (self.alpha >= 0.999) c else c.fade(self.alpha);
    }

    pub fn pushCmd(self: *DrawList, cmd: DrawCmd) void {
        self.cmds.append(self.allocator, cmd) catch {};
    }

    pub fn insertCmds(self: *DrawList, index: usize, slice: []const DrawCmd) void {
        self.cmds.insertSlice(self.allocator, index, slice) catch {};
    }

    pub fn rectFilled(self: *DrawList, r: Rect, col: Color, rounding: f32) void {
        const c = self.applyAlpha(col);
        if (c.a <= 0.001) return;
        self.pushCmd(.{ .rect_filled = .{ .rect = r, .color = c, .rounding = rounding } });
    }

    pub fn rectStroke(self: *DrawList, r: Rect, col: Color, rounding: f32, thickness: f32) void {
        const c = self.applyAlpha(col);
        if (c.a <= 0.001 or thickness <= 0) return;
        self.pushCmd(.{ .rect_stroke = .{ .rect = r, .color = c, .rounding = rounding, .thickness = thickness } });
    }

    pub fn gradient(self: *DrawList, r: Rect, from: Color, to: Color, rounding: f32, horizontal: bool) void {
        self.pushCmd(.{ .gradient_rect = .{
            .rect = r,
            .from = self.applyAlpha(from),
            .to = self.applyAlpha(to),
            .rounding = rounding,
            .horizontal = horizontal,
        } });
    }

    pub fn shadow(self: *DrawList, r: Rect, rounding: f32, col: Color, blur: f32, offset_y: f32) void {
        const c = self.applyAlpha(col);
        if (c.a <= 0.001 or blur <= 0) return;
        self.pushCmd(.{ .shadow = .{ .rect = r, .rounding = rounding, .color = c, .blur = blur, .offset_y = offset_y } });
    }

    pub fn focusRing(self: *DrawList, r: Rect, rounding: f32, col: Color, strength: f32) void {
        if (strength <= 0.001) return;
        const ring = r.expand(3.0);
        self.rectStroke(ring, col.fade(strength), rounding + 3.0, 2.0);
    }

    pub fn circleFilled(self: *DrawList, center: Vec2, radius: f32, col: Color) void {
        const c = self.applyAlpha(col);
        if (c.a <= 0.001 or radius <= 0) return;
        self.pushCmd(.{ .circle_filled = .{ .center = center, .radius = radius, .color = c } });
    }

    pub fn circleStroke(self: *DrawList, center: Vec2, radius: f32, col: Color, thickness: f32) void {
        const c = self.applyAlpha(col);
        if (c.a <= 0.001 or radius <= 0 or thickness <= 0) return;
        self.pushCmd(.{ .circle_stroke = .{ .center = center, .radius = radius, .color = c, .thickness = thickness } });
    }

    pub fn line(self: *DrawList, a: Vec2, b: Vec2, col: Color, thickness: f32) void {
        const c = self.applyAlpha(col);
        if (c.a <= 0.001 or thickness <= 0) return;
        self.pushCmd(.{ .line = .{ .a = a, .b = b, .color = c, .thickness = thickness } });
    }

    pub fn arc(self: *DrawList, center: Vec2, radius: f32, a0: f32, a1: f32, col: Color, thickness: f32) void {
        const c = self.applyAlpha(col);
        if (c.a <= 0.001 or radius <= 0 or thickness <= 0) return;
        self.pushCmd(.{ .arc = .{ .center = center, .radius = radius, .a0 = a0, .a1 = a1, .color = c, .thickness = thickness } });
    }

    pub fn polyline(self: *DrawList, pts: []const Vec2, closed: bool, col: Color, thickness: f32) void {
        const c = self.applyAlpha(col);
        if (c.a <= 0.001 or pts.len < 2 or thickness <= 0) return;
        const start: u32 = @intCast(self.points.items.len);
        self.points.appendSlice(self.allocator, pts) catch return;
        self.pushCmd(.{ .polyline = .{
            .start = start,
            .count = @intCast(pts.len),
            .closed = closed,
            .color = c,
            .thickness = thickness,
        } });
    }

    pub fn polygonFilled(self: *DrawList, pts: []const Vec2, col: Color) void {
        const c = self.applyAlpha(col);
        if (c.a <= 0.001 or pts.len < 3) return;
        const start: u32 = @intCast(self.points.items.len);
        self.points.appendSlice(self.allocator, pts) catch return;
        self.pushCmd(.{ .polygon_filled = .{
            .start = start,
            .count = @intCast(pts.len),
            .color = c,
        } });
    }

    pub fn polygonGradient(self: *DrawList, pts: []const Vec2, y0: f32, y1: f32, from: Color, to: Color) void {
        if (pts.len < 3) return;
        const start: u32 = @intCast(self.points.items.len);
        self.points.appendSlice(self.allocator, pts) catch return;
        self.pushCmd(.{ .polygon_gradient = .{
            .start = start,
            .count = @intCast(pts.len),
            .y0 = y0,
            .y1 = y1,
            .from = self.applyAlpha(from),
            .to = self.applyAlpha(to),
        } });
    }

    pub fn text(self: *DrawList, pos: Vec2, col: Color, str: []const u8, style: TextStyle, max_w: f32) void {
        const c = self.applyAlpha(col);
        if (c.a <= 0.001 or str.len == 0) return;
        const start: u32 = @intCast(self.text_buf.items.len);
        self.text_buf.appendSlice(self.allocator, str) catch return;
        self.pushCmd(.{ .text = .{
            .pos = pos,
            .max_w = max_w,
            .color = c,
            .style = style,
            .start = start,
            .len = @intCast(str.len),
        } });
    }

    /// Draws image `id` (see `Renderer.createImage`) stretched to `r`.
    pub fn image(self: *DrawList, r: Rect, id: u32, rounding: f32, opacity: f32) void {
        const a = opacity * self.alpha;
        if (id == 0 or a <= 0.001 or r.w() <= 0 or r.h() <= 0) return;
        self.pushCmd(.{ .image = .{ .rect = r, .id = id, .rounding = rounding, .opacity = @min(a, 1.0) } });
    }

    pub fn pushClip(self: *DrawList, r: Rect) void {
        self.pushCmd(.{ .push_clip = r });
    }

    pub fn popClip(self: *DrawList) void {
        self.pushCmd(.pop_clip);
    }
};
