//! Design tokens replicated 1:1 from MoonWin GUI.
const std = @import("std");
const Color = @import("color.zig").Color;

pub const Palette = struct {
    bg: Color,
    bg_subtle: Color,
    surface: Color,
    surface_raised: Color,
    border: Color,
    border_strong: Color,
    text: Color,
    text_muted: Color,
    text_faint: Color,
    accent: Color,
    on_accent: Color,
    success: Color,
    warning: Color,
    danger: Color,
    info: Color,
    shadow: Color,
    scrim: Color,
};

pub const Radius = struct {
    sm: f32 = 6,
    md: f32 = 8,
    lg: f32 = 12,
    xl: f32 = 16,
    full: f32 = 999,
};

pub const Space = struct {
    xs: f32 = 4,
    sm: f32 = 8,
    md: f32 = 12,
    lg: f32 = 16,
    xl: f32 = 24,
    xxl: f32 = 32,
};

pub const TypeScale = struct {
    caption: f32 = 12,
    body: f32 = 14,
    label: f32 = 13,
    title: f32 = 16,
    heading: f32 = 20,
    display: f32 = 28,
};

pub const Motion = struct {
    fast: f32 = 22,
    normal: f32 = 14,
    slow: f32 = 9,
    enabled: bool = true,
};

pub const Tone = enum { neutral, accent, success, warning, danger, info };

pub const Theme = struct {
    name: []const u8,
    dark: bool,
    palette: Palette,
    radius: Radius = .{},
    space: Space = .{},
    type: TypeScale = .{},
    motion: Motion = .{},
    control_height: f32 = 34,
    border_width: f32 = 1,

    pub fn withAccent(self: Theme, accent: Color) Theme {
        var t = self;
        t.palette.accent = accent;
        t.palette.on_accent = accent.contrastText();
        return t;
    }

    pub fn withRadius(self: Theme, scale: f32) Theme {
        var t = self;
        t.radius.sm *= scale;
        t.radius.md *= scale;
        t.radius.lg *= scale;
        t.radius.xl *= scale;
        return t;
    }

    pub fn tone(self: *const Theme, t: Tone) Color {
        return switch (t) {
            .neutral => self.palette.text_muted,
            .accent => self.palette.accent,
            .success => self.palette.success,
            .warning => self.palette.warning,
            .danger => self.palette.danger,
            .info => self.palette.info,
        };
    }
};

pub const presets = struct {
    pub const midnight: Theme = .{
        .name = "Midnight",
        .dark = true,
        .palette = .{
            .bg = Color.hex(0x0E0F13),
            .bg_subtle = Color.hex(0x131419),
            .surface = Color.hex(0x181A20),
            .surface_raised = Color.hex(0x20232B),
            .border = Color.hex(0x262932),
            .border_strong = Color.hex(0x353946),
            .text = Color.hex(0xECEEF3),
            .text_muted = Color.hex(0x9AA0AE),
            .text_faint = Color.hex(0x646A78),
            .accent = Color.hex(0x7C6CFF),
            .on_accent = Color.white,
            .success = Color.hex(0x34D399),
            .warning = Color.hex(0xFBBF24),
            .danger = Color.hex(0xF87171),
            .info = Color.hex(0x60A5FA),
            .shadow = Color.rgba(0, 0, 0, 0.55),
            .scrim = Color.rgba(0.02, 0.02, 0.04, 0.62),
        },
    };

    pub const daylight: Theme = .{
        .name = "Daylight",
        .dark = false,
        .palette = .{
            .bg = Color.hex(0xF6F7F9),
            .bg_subtle = Color.hex(0xEEF0F3),
            .surface = Color.hex(0xFFFFFF),
            .surface_raised = Color.hex(0xF1F3F6),
            .border = Color.hex(0xE3E6EB),
            .border_strong = Color.hex(0xCDD2DA),
            .text = Color.hex(0x14161B),
            .text_muted = Color.hex(0x5B6270),
            .text_faint = Color.hex(0x9097A3),
            .accent = Color.hex(0x5B4DF0),
            .on_accent = Color.white,
            .success = Color.hex(0x16A34A),
            .warning = Color.hex(0xD97706),
            .danger = Color.hex(0xDC2626),
            .info = Color.hex(0x2563EB),
            .shadow = Color.rgba(0.06, 0.08, 0.14, 0.16),
            .scrim = Color.rgba(0.05, 0.06, 0.09, 0.38),
        },
    };

    pub const ember: Theme = blk: {
        var t = midnight.withAccent(Color.hex(0xF59E0B));
        t.name = "Ember";
        t.palette.bg = Color.hex(0x110F0E);
        t.palette.bg_subtle = Color.hex(0x171412);
        t.palette.surface = Color.hex(0x1D1916);
        t.palette.surface_raised = Color.hex(0x26211D);
        t.palette.border = Color.hex(0x2E2823);
        t.palette.border_strong = Color.hex(0x3D352F);
        break :blk t;
    };

    pub const aurora: Theme = blk: {
        var t = midnight.withAccent(Color.hex(0x2DD4BF));
        t.name = "Aurora";
        t.palette.bg = Color.hex(0x0B1114);
        t.palette.bg_subtle = Color.hex(0x0F171B);
        t.palette.surface = Color.hex(0x131D22);
        t.palette.surface_raised = Color.hex(0x1A262C);
        t.palette.border = Color.hex(0x1F2D33);
        t.palette.border_strong = Color.hex(0x2B3D45);
        break :blk t;
    };

    pub const all = [_]*const Theme{ &midnight, &daylight, &ember, &aurora };
};

test "presets are distinct" {
    try std.testing.expect(presets.midnight.dark);
    try std.testing.expect(!presets.daylight.dark);
    try std.testing.expect(presets.ember.palette.accent.r > 0.9);
    try std.testing.expect(presets.aurora.palette.accent.g > 0.7);
}
