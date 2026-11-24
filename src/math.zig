//! 2D geometry primitives in DIPs (logical pixels).
const d2d = @import("win32/d2d1.zig");

pub const Vec2 = extern struct {
    x: f32,
    y: f32,

    pub fn add(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x + b.x, .y = a.y + b.y };
    }
    pub fn sub(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x - b.x, .y = a.y - b.y };
    }
    pub fn d2dPt(self: Vec2) d2d.D2D1_POINT_2F {
        return .{ .x = self.x, .y = self.y };
    }
};

pub inline fn v2(x: f32, y: f32) Vec2 {
    return .{ .x = x, .y = y };
}

pub const Rect = struct {
    min: Vec2,
    max: Vec2,

    pub fn fromSize(pos: Vec2, sz: Vec2) Rect {
        return .{ .min = pos, .max = .{ .x = pos.x + sz.x, .y = pos.y + sz.y } };
    }
    pub fn xywh(x: f32, y: f32, width: f32, height: f32) Rect {
        return .{ .min = .{ .x = x, .y = y }, .max = .{ .x = x + width, .y = y + height } };
    }
    pub fn w(self: Rect) f32 {
        return self.max.x - self.min.x;
    }
    pub fn h(self: Rect) f32 {
        return self.max.y - self.min.y;
    }
    pub fn size(self: Rect) Vec2 {
        return .{ .x = self.w(), .y = self.h() };
    }
    pub fn center(self: Rect) Vec2 {
        return .{ .x = (self.min.x + self.max.x) * 0.5, .y = (self.min.y + self.max.y) * 0.5 };
    }
    pub fn expand(self: Rect, d: f32) Rect {
        return .{
            .min = .{ .x = self.min.x - d, .y = self.min.y - d },
            .max = .{ .x = self.max.x + d, .y = self.max.y + d },
        };
    }
    pub fn translate(self: Rect, d: Vec2) Rect {
        return .{
            .min = .{ .x = self.min.x + d.x, .y = self.min.y + d.y },
            .max = .{ .x = self.max.x + d.x, .y = self.max.y + d.y },
        };
    }
    pub fn contains(self: Rect, p: Vec2) bool {
        return p.x >= self.min.x and p.x < self.max.x and p.y >= self.min.y and p.y < self.max.y;
    }
    pub fn intersects(self: Rect, other: Rect) bool {
        return self.min.x < other.max.x and self.max.x > other.min.x and
            self.min.y < other.max.y and self.max.y > other.min.y;
    }
    pub fn d2dRect(self: Rect) d2d.D2D1_RECT_F {
        return .{ .left = self.min.x, .top = self.min.y, .right = self.max.x, .bottom = self.max.y };
    }
    pub fn d2dRounded(self: Rect, r: f32) d2d.D2D1_ROUNDED_RECT {
        return .{ .rect = self.d2dRect(), .radiusX = r, .radiusY = r };
    }
};
