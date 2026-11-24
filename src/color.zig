//! Linear-friendly RGBA colour type matching MoonWin's design system.
const std = @import("std");
const d2d = @import("win32/d2d1.zig");

pub const Color = extern struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32 = 1.0,

    pub const transparent: Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 };
    pub const white: Color = .{ .r = 1, .g = 1, .b = 1 };
    pub const black: Color = .{ .r = 0, .g = 0, .b = 0 };

    pub fn hex(comptime rgb: u24) Color {
        return .{
            .r = @as(f32, @floatFromInt((rgb >> 16) & 0xFF)) / 255.0,
            .g = @as(f32, @floatFromInt((rgb >> 8) & 0xFF)) / 255.0,
            .b = @as(f32, @floatFromInt(rgb & 0xFF)) / 255.0,
            .a = 1.0,
        };
    }

    pub fn hexa(v: u32) Color {
        return .{
            .r = @as(f32, @floatFromInt((v >> 24) & 0xFF)) / 255.0,
            .g = @as(f32, @floatFromInt((v >> 16) & 0xFF)) / 255.0,
            .b = @as(f32, @floatFromInt((v >> 8) & 0xFF)) / 255.0,
            .a = @as(f32, @floatFromInt(v & 0xFF)) / 255.0,
        };
    }

    pub fn parse(text: []const u8) error{InvalidColor}!Color {
        var s = text;
        if (s.len > 0 and s[0] == '#') s = s[1..];
        switch (s.len) {
            3 => {
                var v: [3]f32 = undefined;
                for (s, 0..) |ch, i| {
                    const n = std.fmt.charToDigit(ch, 16) catch return error.InvalidColor;
                    v[i] = @as(f32, @floatFromInt(n * 17)) / 255.0;
                }
                return .{ .r = v[0], .g = v[1], .b = v[2] };
            },
            6, 8 => {
                const n = std.fmt.parseInt(u32, s, 16) catch return error.InvalidColor;
                return if (s.len == 6) hexa((n << 8) | 0xFF) else hexa(n);
            },
            else => return error.InvalidColor,
        }
    }

    pub fn rgba(r: f32, g: f32, b: f32, a: f32) Color {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    pub fn withAlpha(self: Color, a: f32) Color {
        return .{ .r = self.r, .g = self.g, .b = self.b, .a = a };
    }

    pub fn fade(self: Color, factor: f32) Color {
        return self.withAlpha(self.a * factor);
    }

    pub fn mix(a: Color, b: Color, t: f32) Color {
        const k = std.math.clamp(t, 0.0, 1.0);
        return .{
            .r = a.r + (b.r - a.r) * k,
            .g = a.g + (b.g - a.g) * k,
            .b = a.b + (b.b - a.b) * k,
            .a = a.a + (b.a - a.a) * k,
        };
    }

    pub fn lighten(self: Color, t: f32) Color {
        return mix(self, white.withAlpha(self.a), t);
    }

    pub fn darken(self: Color, t: f32) Color {
        return mix(self, black.withAlpha(self.a), t);
    }

    pub fn luminance(self: Color) f32 {
        const lin = struct {
            fn f(v: f32) f32 {
                return if (v <= 0.04045) v / 12.92 else std.math.pow(f32, (v + 0.055) / 1.055, 2.4);
            }
        }.f;
        return 0.2126 * lin(self.r) + 0.7152 * lin(self.g) + 0.0722 * lin(self.b);
    }

    pub fn contrastText(self: Color) Color {
        return if (self.luminance() > 0.42) hex(0x0B0B0F) else white;
    }

    pub fn d2dColor(self: Color) d2d.D2D1_COLOR_F {
        return .{ .r = self.r, .g = self.g, .b = self.b, .a = self.a };
    }

    /// Windows COLORREF (0x00BBGGRR), used for DWM titlebar caption tinting.
    pub fn colorref(self: Color) u32 {
        const q = struct {
            fn f(v: f32) u32 {
                return @intFromFloat(@round(std.math.clamp(v, 0.0, 1.0) * 255.0));
            }
        }.f;
        return (q(self.b) << 16) | (q(self.g) << 8) | q(self.r);
    }
};

test "hex and colorref" {
    const col = Color.hex(0xFF8000);
    try std.testing.expectEqual(@as(u32, 0x000080FF), col.colorref());
}

test "parse" {
    const a = try Color.parse("#fff");
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), a.r, 1e-5);
    const b = try Color.parse("10203040");
    try std.testing.expectApproxEqAbs(@as(f32, 0x40) / 255.0, b.a, 1e-5);
    try std.testing.expectError(error.InvalidColor, Color.parse("#12"));
}

test "mix and contrast" {
    const m = Color.mix(Color.black, Color.white, 2.0);
    try std.testing.expectEqual(@as(f32, 1.0), m.r);
    try std.testing.expectEqual(Color.white.r, Color.hex(0x4F46E5).contrastText().r);
    try std.testing.expect(Color.hex(0xFDE047).contrastText().r < 0.1);
}
