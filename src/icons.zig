//! All 56 vector stroke icons from MoonWin on a 24x24 design grid,
//! rendered as crisp Direct2D path geometries with round caps & joins.
const std = @import("std");
const math = @import("math.zig");
const Color = @import("color.zig").Color;
const DrawList = @import("drawlist.zig").DrawList;

const Vec2 = math.Vec2;
const Rect = math.Rect;
const v2 = math.v2;
const pi = std.math.pi;

pub const Icon = enum {
    check,
    x,
    plus,
    minus,
    chevron_down,
    chevron_up,
    chevron_left,
    chevron_right,
    arrow_left,
    arrow_right,
    arrow_up,
    arrow_down,
    search,
    home,
    settings,
    user,
    users,
    bell,
    sun,
    moon,
    info,
    alert,
    circle_check,
    circle_x,
    menu,
    more,
    heart,
    star,
    folder,
    file,
    trash,
    edit,
    copy,
    download,
    upload,
    refresh,
    eye,
    lock,
    grid,
    list,
    chart,
    activity,
    bolt,
    sparkles,
    filter,
    calendar,
    mail,
    layers,
    terminal,
    palette,
    logout,
    external,
    play,
    pause,
    cpu,
    globe,
};

const Pen = struct {
    dl: *DrawList,
    origin: Vec2,
    k: f32,
    col: Color,
    th: f32,
    path_buf: [64]Vec2 = undefined,
    path_len: usize = 0,

    fn p(self: *const Pen, x: f32, y: f32) Vec2 {
        return v2(self.origin.x + x * self.k, self.origin.y + y * self.k);
    }

    fn line(self: *const Pen, x1: f32, y1: f32, x2: f32, y2: f32) void {
        self.dl.line(self.p(x1, y1), self.p(x2, y2), self.col, self.th);
    }

    fn poly(self: *const Pen, pts: []const [2]f32, closed: bool) void {
        var tmp: [48]Vec2 = undefined;
        const n = @min(pts.len, tmp.len);
        for (pts[0..n], 0..) |q, i| tmp[i] = self.p(q[0], q[1]);
        self.dl.polyline(tmp[0..n], closed, self.col, self.th);
    }

    fn circle(self: *const Pen, cx: f32, cy: f32, r: f32) void {
        self.dl.circleStroke(self.p(cx, cy), r * self.k, self.col, self.th);
    }

    fn dot(self: *const Pen, cx: f32, cy: f32, r: f32) void {
        self.dl.circleFilled(self.p(cx, cy), r * self.k, self.col);
    }

    fn arc(self: *const Pen, cx: f32, cy: f32, r: f32, a0: f32, a1: f32) void {
        self.dl.arc(self.p(cx, cy), r * self.k, a0 * pi / 180.0, a1 * pi / 180.0, self.col, self.th);
    }

    fn rrect(self: *const Pen, x: f32, y: f32, w: f32, h: f32, r: f32) void {
        const rect = Rect{ .min = self.p(x, y), .max = self.p(x + w, y + h) };
        self.dl.rectStroke(rect, self.col, r * self.k, self.th);
    }

    fn fillTri(self: *const Pen, x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32) void {
        const pts = [_]Vec2{ self.p(x1, y1), self.p(x2, y2), self.p(x3, y3) };
        self.dl.polygonFilled(&pts, self.col);
    }

    fn begin(self: *Pen) void {
        self.path_len = 0;
    }

    fn to(self: *Pen, x: f32, y: f32) void {
        if (self.path_len < self.path_buf.len) {
            self.path_buf[self.path_len] = self.p(x, y);
            self.path_len += 1;
        }
    }

    fn arcTo(self: *Pen, cx: f32, cy: f32, r: f32, a0: f32, a1: f32) void {
        const steps: usize = 12;
        const r0 = a0 * pi / 180.0;
        const r1 = a1 * pi / 180.0;
        var i: usize = 0;
        while (i <= steps) : (i += 1) {
            const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps));
            const a = r0 + (r1 - r0) * t;
            self.to(cx + @cos(a) * r, cy + @sin(a) * r);
        }
    }

    fn stroke(self: *Pen, closed: bool) void {
        if (self.path_len >= 2) {
            self.dl.polyline(self.path_buf[0..self.path_len], closed, self.col, self.th);
        }
        self.path_len = 0;
    }
};

pub fn drawEx(dl: *DrawList, icon: Icon, center: Vec2, size: f32, col: Color, stroke_w: f32) void {
    if (col.a <= 0.001 or size <= 0) return;
    const k = size / 24.0;
    var pen: Pen = .{
        .dl = dl,
        .origin = v2(center.x - size * 0.5, center.y - size * 0.5),
        .k = k,
        .col = col,
        .th = @max(stroke_w * k, 1.0),
    };
    switch (icon) {
        .check => pen.poly(&.{ .{ 5, 12.5 }, .{ 10, 17.5 }, .{ 19.5, 7 } }, false),
        .x => {
            pen.line(6, 6, 18, 18);
            pen.line(18, 6, 6, 18);
        },
        .plus => {
            pen.line(12, 5, 12, 19);
            pen.line(5, 12, 19, 12);
        },
        .minus => pen.line(5, 12, 19, 12),
        .chevron_down => pen.poly(&.{ .{ 6, 9 }, .{ 12, 15 }, .{ 18, 9 } }, false),
        .chevron_up => pen.poly(&.{ .{ 6, 15 }, .{ 12, 9 }, .{ 18, 15 } }, false),
        .chevron_left => pen.poly(&.{ .{ 15, 6 }, .{ 9, 12 }, .{ 15, 18 } }, false),
        .chevron_right => pen.poly(&.{ .{ 9, 6 }, .{ 15, 12 }, .{ 9, 18 } }, false),
        .arrow_left => {
            pen.line(19, 12, 5, 12);
            pen.poly(&.{ .{ 11, 6 }, .{ 5, 12 }, .{ 11, 18 } }, false);
        },
        .arrow_right => {
            pen.line(5, 12, 19, 12);
            pen.poly(&.{ .{ 13, 6 }, .{ 19, 12 }, .{ 13, 18 } }, false);
        },
        .arrow_up => {
            pen.line(12, 19, 12, 5);
            pen.poly(&.{ .{ 6, 11 }, .{ 12, 5 }, .{ 18, 11 } }, false);
        },
        .arrow_down => {
            pen.line(12, 5, 12, 19);
            pen.poly(&.{ .{ 6, 13 }, .{ 12, 19 }, .{ 18, 13 } }, false);
        },
        .search => {
            pen.circle(10.5, 10.5, 6.5);
            pen.line(15.3, 15.3, 20, 20);
        },
        .home => {
            pen.poly(&.{ .{ 3.5, 10.5 }, .{ 12, 3.5 }, .{ 20.5, 10.5 } }, false);
            pen.poly(&.{ .{ 5.5, 9 }, .{ 5.5, 20 }, .{ 18.5, 20 }, .{ 18.5, 9 } }, false);
            pen.poly(&.{ .{ 10, 20 }, .{ 10, 14 }, .{ 14, 14 }, .{ 14, 20 } }, false);
        },
        .settings => {
            var pts: [32][2]f32 = undefined;
            var n: usize = 0;
            var t: usize = 0;
            while (t < 8) : (t += 1) {
                const a = @as(f32, @floatFromInt(t)) * 45.0;
                const angs = [_]f32{ a - 22.5 + 4, a - 9, a + 9, a + 22.5 - 4 };
                const rads = [_]f32{ 7.2, 9.6, 9.6, 7.2 };
                for (angs, rads) |ang, rad| {
                    const r = ang * pi / 180.0;
                    pts[n] = .{ 12 + @cos(r) * rad, 12 + @sin(r) * rad };
                    n += 1;
                }
            }
            pen.poly(pts[0..n], true);
            pen.circle(12, 12, 3);
        },
        .user => {
            pen.circle(12, 8, 4);
            pen.arc(12, 21, 7.5, 200, 340);
        },
        .users => {
            pen.circle(9, 8, 3.5);
            pen.arc(9, 20.5, 6.5, 200, 340);
            pen.arc(16, 8, 3.5, 270, 450);
            pen.arc(16.5, 20.5, 5.5, 250, 340);
        },
        .bell => {
            pen.begin();
            pen.to(4.5, 17);
            pen.to(6, 15);
            pen.arcTo(12, 10, 6, 180, 360);
            pen.to(18, 15);
            pen.to(19.5, 17);
            pen.stroke(true);
            pen.arc(12, 17.2, 2.6, 15, 165);
        },
        .sun => {
            pen.circle(12, 12, 4);
            var i: usize = 0;
            while (i < 8) : (i += 1) {
                const r = @as(f32, @floatFromInt(i)) * pi / 4.0;
                pen.line(12 + @cos(r) * 7, 12 + @sin(r) * 7, 12 + @cos(r) * 9.5, 12 + @sin(r) * 9.5);
            }
        },
        .moon => {
            pen.begin();
            pen.arcTo(12, 12, 8.5, 10, 260);
            pen.arcTo(16, 8, 7, 218.6, 51.4);
            pen.stroke(true);
        },
        .info => {
            pen.circle(12, 12, 9);
            pen.line(12, 11, 12, 16.5);
            pen.dot(12, 7.8, 1.1);
        },
        .alert => {
            pen.poly(&.{ .{ 12, 3.5 }, .{ 21, 19.5 }, .{ 3, 19.5 } }, true);
            pen.line(12, 9.5, 12, 13.5);
            pen.dot(12, 16.4, 1.1);
        },
        .circle_check => {
            pen.circle(12, 12, 9);
            pen.poly(&.{ .{ 8, 12.3 }, .{ 11, 15.2 }, .{ 16.2, 9.4 } }, false);
        },
        .circle_x => {
            pen.circle(12, 12, 9);
            pen.line(9, 9, 15, 15);
            pen.line(15, 9, 9, 15);
        },
        .menu => {
            pen.line(4, 6.5, 20, 6.5);
            pen.line(4, 12, 20, 12);
            pen.line(4, 17.5, 20, 17.5);
        },
        .more => {
            pen.dot(6, 12, 1.5);
            pen.dot(12, 12, 1.5);
            pen.dot(18, 12, 1.5);
        },
        .heart => {
            pen.begin();
            pen.to(12, 19.5);
            pen.to(5.5, 11.6);
            pen.arcTo(8.25, 8.75, 3.9, 135, 344);
            pen.arcTo(15.75, 8.75, 3.9, 196, 405);
            pen.to(12, 19.5);
            pen.stroke(true);
        },
        .star => {
            var pts: [10][2]f32 = undefined;
            for (&pts, 0..) |*q, i| {
                const r: f32 = if (i % 2 == 0) 9.5 else 4.2;
                const a = (-90.0 + @as(f32, @floatFromInt(i)) * 36.0) * pi / 180.0;
                q.* = .{ 12 + @cos(a) * r, 12.8 + @sin(a) * r };
            }
            pen.poly(&pts, true);
        },
        .folder => pen.poly(&.{ .{ 3.5, 6 }, .{ 9.5, 6 }, .{ 11.5, 8 }, .{ 20.5, 8 }, .{ 20.5, 18.5 }, .{ 3.5, 18.5 } }, true),
        .file => {
            pen.poly(&.{ .{ 6, 3.5 }, .{ 14, 3.5 }, .{ 18.5, 8 }, .{ 18.5, 20.5 }, .{ 6, 20.5 } }, true);
            pen.poly(&.{ .{ 13.5, 3.5 }, .{ 13.5, 8.5 }, .{ 18.5, 8.5 } }, false);
        },
        .trash => {
            pen.line(4, 6.5, 20, 6.5);
            pen.poly(&.{ .{ 9, 6.5 }, .{ 9, 4 }, .{ 15, 4 }, .{ 15, 6.5 } }, false);
            pen.poly(&.{ .{ 6, 6.5 }, .{ 7, 20 }, .{ 17, 20 }, .{ 18, 6.5 } }, false);
            pen.line(10, 10.5, 10, 16);
            pen.line(14, 10.5, 14, 16);
        },
        .edit => {
            pen.poly(&.{ .{ 4.5, 19.5 }, .{ 5, 15.5 }, .{ 15.5, 5 }, .{ 19, 8.5 }, .{ 8.5, 19 } }, true);
            pen.line(13.5, 7, 17, 10.5);
        },
        .copy => {
            pen.rrect(8.5, 8.5, 12, 12, 2);
            pen.poly(&.{ .{ 5.5, 15.5 }, .{ 3.5, 15.5 }, .{ 3.5, 3.5 }, .{ 15.5, 3.5 }, .{ 15.5, 5.5 } }, false);
        },
        .download => {
            pen.line(12, 4, 12, 15);
            pen.poly(&.{ .{ 7, 10 }, .{ 12, 15 }, .{ 17, 10 } }, false);
            pen.poly(&.{ .{ 4, 15.5 }, .{ 4, 20 }, .{ 20, 20 }, .{ 20, 15.5 } }, false);
        },
        .upload => {
            pen.line(12, 15, 12, 4);
            pen.poly(&.{ .{ 7, 9 }, .{ 12, 4 }, .{ 17, 9 } }, false);
            pen.poly(&.{ .{ 4, 15.5 }, .{ 4, 20 }, .{ 20, 20 }, .{ 20, 15.5 } }, false);
        },
        .refresh => {
            pen.arc(12, 12, 7.5, -45, 225);
            pen.poly(&.{ .{ 17.3, 3.6 }, .{ 17.3, 6.7 }, .{ 14.2, 6.7 } }, false);
        },
        .eye => {
            pen.begin();
            pen.arcTo(12, 18.525, 11.525, 214.5, 325.5);
            pen.arcTo(12, 5.475, 11.525, 34.5, 145.5);
            pen.stroke(true);
            pen.circle(12, 12, 3);
        },
        .lock => {
            pen.rrect(5, 11, 14, 10, 2);
            pen.begin();
            pen.to(8, 11);
            pen.arcTo(12, 7.5, 4, 180, 360);
            pen.to(16, 11);
            pen.stroke(false);
        },
        .grid => {
            pen.rrect(4, 4, 7, 7, 1.5);
            pen.rrect(13, 4, 7, 7, 1.5);
            pen.rrect(4, 13, 7, 7, 1.5);
            pen.rrect(13, 13, 7, 7, 1.5);
        },
        .list => {
            pen.line(9, 6.5, 20, 6.5);
            pen.line(9, 12, 20, 12);
            pen.line(9, 17.5, 20, 17.5);
            pen.dot(4.8, 6.5, 1.2);
            pen.dot(4.8, 12, 1.2);
            pen.dot(4.8, 17.5, 1.2);
        },
        .chart => {
            pen.poly(&.{ .{ 4, 4 }, .{ 4, 20 }, .{ 20, 20 } }, false);
            pen.line(8.5, 16, 8.5, 12);
            pen.line(12.5, 16, 12.5, 8);
            pen.line(16.5, 16, 16.5, 10.5);
        },
        .activity => pen.poly(&.{ .{ 3, 12 }, .{ 7, 12 }, .{ 10, 4.5 }, .{ 14, 19.5 }, .{ 17, 12 }, .{ 21, 12 } }, false),
        .bolt => pen.poly(&.{ .{ 13.5, 3 }, .{ 5, 13.5 }, .{ 11.5, 13.5 }, .{ 10.5, 21 }, .{ 19, 10.5 }, .{ 12.5, 10.5 } }, true),
        .sparkles => {
            pen.poly(&.{ .{ 10, 3.5 }, .{ 11.8, 8.7 }, .{ 17, 10.5 }, .{ 11.8, 12.3 }, .{ 10, 17.5 }, .{ 8.2, 12.3 }, .{ 3, 10.5 }, .{ 8.2, 8.7 } }, true);
            pen.line(18, 15, 18, 21);
            pen.line(15, 18, 21, 18);
        },
        .filter => pen.poly(&.{ .{ 3.5, 5 }, .{ 20.5, 5 }, .{ 14, 12.5 }, .{ 14, 19 }, .{ 10, 20.5 }, .{ 10, 12.5 } }, true),
        .calendar => {
            pen.rrect(3.5, 5, 17, 15.5, 2);
            pen.line(3.5, 10, 20.5, 10);
            pen.line(8, 3, 8, 7);
            pen.line(16, 3, 16, 7);
        },
        .mail => {
            pen.rrect(3, 5.5, 18, 13, 2);
            pen.poly(&.{ .{ 3.5, 7 }, .{ 12, 13 }, .{ 20.5, 7 } }, false);
        },
        .layers => {
            pen.poly(&.{ .{ 12, 3.5 }, .{ 21, 8.5 }, .{ 12, 13.5 }, .{ 3, 8.5 } }, true);
            pen.poly(&.{ .{ 3, 12.5 }, .{ 12, 17.5 }, .{ 21, 12.5 } }, false);
            pen.poly(&.{ .{ 3, 16.5 }, .{ 12, 21.5 }, .{ 21, 16.5 } }, false);
        },
        .terminal => {
            pen.rrect(3, 4.5, 18, 15, 2);
            pen.poly(&.{ .{ 7, 9.5 }, .{ 10, 12 }, .{ 7, 14.5 } }, false);
            pen.line(12.5, 15, 16.5, 15);
        },
        .palette => {
            pen.begin();
            pen.arcTo(12, 12, 9, 80, 380);
            pen.to(16, 15.5);
            pen.to(14.2, 17.5);
            pen.stroke(true);
            pen.dot(8, 10, 1.3);
            pen.dot(12, 7.5, 1.3);
            pen.dot(16, 10, 1.3);
        },
        .logout => {
            pen.poly(&.{ .{ 9.5, 4 }, .{ 5, 4 }, .{ 5, 20 }, .{ 9.5, 20 } }, false);
            pen.line(10, 12, 20, 12);
            pen.poly(&.{ .{ 16, 8 }, .{ 20, 12 }, .{ 16, 16 } }, false);
        },
        .external => {
            pen.poly(&.{ .{ 11, 5 }, .{ 5, 5 }, .{ 5, 19 }, .{ 19, 19 }, .{ 19, 13 } }, false);
            pen.line(11, 13, 20, 4);
            pen.poly(&.{ .{ 14, 4 }, .{ 20, 4 }, .{ 20, 10 } }, false);
        },
        .play => pen.fillTri(7.5, 5, 7.5, 19, 19, 12),
        .pause => {
            pen.line(9, 5.5, 9, 18.5);
            pen.line(15, 5.5, 15, 18.5);
        },
        .cpu => {
            pen.rrect(6, 6, 12, 12, 2);
            pen.rrect(9.5, 9.5, 5, 5, 0.5);
            for ([_]f32{ 9.5, 14.5 }) |q| {
                pen.line(q, 2.5, q, 6);
                pen.line(q, 18, q, 21.5);
                pen.line(2.5, q, 6, q);
                pen.line(18, q, 21.5, q);
            }
        },
        .globe => {
            pen.circle(12, 12, 9);
            pen.line(3, 12, 21, 12);
            pen.begin();
            pen.arcTo(5.25, 12, 11.25, -53.1, 53.1);
            pen.stroke(false);
            pen.begin();
            pen.arcTo(18.75, 12, 11.25, 126.9, 233.1);
            pen.stroke(false);
        },
    }
}

pub fn draw(dl: *DrawList, icon: Icon, center: Vec2, size: f32, col: Color) void {
    drawEx(dl, icon, center, size, col, 1.8);
}
