//! Framerate-independent animation store (exponential smoothing & critically-damped springs).
//! Reports convergence so the native Win32 loop sleeps at ~0% CPU when idle.
const std = @import("std");

pub const AnimStore = struct {
    values: std.AutoHashMap(u64, f32),
    animating_now: bool = false,
    animating_prev: bool = false,
    keep_alive_until: f64 = 0,
    time: f64 = 0,
    delta_time: f32 = 1.0 / 60.0,
    enabled: bool = true,

    pub fn init(allocator: std.mem.Allocator) AnimStore {
        return .{ .values = std.AutoHashMap(u64, f32).init(allocator) };
    }

    pub fn deinit(self: *AnimStore) void {
        self.values.deinit();
    }

    pub fn beginFrame(self: *AnimStore, now: f64, dt_raw: f32, enabled: bool) void {
        self.animating_prev = self.animating_now;
        self.animating_now = false;
        self.time = now;
        self.delta_time = std.math.clamp(dt_raw, 0.0, 1.0 / 30.0);
        self.enabled = enabled;
    }

    pub fn isAnimating(self: *const AnimStore) bool {
        return self.animating_now or self.animating_prev or self.time < self.keep_alive_until;
    }

    pub fn markActive(self: *AnimStore) void {
        self.animating_now = true;
    }

    pub fn keepAlive(self: *AnimStore, seconds: f64) void {
        const until = self.time + seconds;
        if (until > self.keep_alive_until) self.keep_alive_until = until;
    }

    fn mixKey(id: u64, salt: u32) u64 {
        var h: u64 = id ^ 0xA5C3_9E37_79B9_7F4A;
        h = (h ^ @as(u64, salt)) *% 0x9E37_79B1_85EB_CA87;
        h ^= h >> 30;
        return h;
    }

    fn getOrPut(self: *AnimStore, k: u64, initial: f32) *f32 {
        const gop = self.values.getOrPut(k) catch unreachable;
        if (!gop.found_existing) gop.value_ptr.* = initial;
        return gop.value_ptr;
    }

    pub fn smooth(self: *AnimStore, id: u64, salt: u32, target: f32, rate: f32) f32 {
        return self.smoothFrom(id, salt, target, rate, target);
    }

    pub fn smoothFrom(self: *AnimStore, id: u64, salt: u32, target: f32, rate: f32, initial: f32) f32 {
        const ptr = self.getOrPut(mixKey(id, salt), initial);
        if (!self.enabled) {
            ptr.* = target;
            return target;
        }
        const cur = ptr.*;
        const diff = target - cur;
        if (@abs(diff) < 0.0015) {
            ptr.* = target;
            return target;
        }
        const k = 1.0 - @exp(-rate * self.delta_time);
        const next = cur + diff * k;
        ptr.* = next;
        self.animating_now = true;
        return next;
    }

    pub fn toggle(self: *AnimStore, id: u64, salt: u32, on: bool, rate: f32) f32 {
        return self.smooth(id, salt, if (on) 1.0 else 0.0, rate);
    }

    pub fn spring(self: *AnimStore, id: u64, salt: u32, target: f32, stiffness: f32) f32 {
        const pos_ptr = self.getOrPut(mixKey(id, salt), target);
        const vel_ptr = self.getOrPut(mixKey(id, salt +% 0x51ED), 0.0);
        if (!self.enabled) {
            pos_ptr.* = target;
            vel_ptr.* = 0;
            return target;
        }
        const omega = @sqrt(stiffness);
        const t = self.delta_time;
        const x = pos_ptr.* - target;
        const v = vel_ptr.*;
        const e = @exp(-omega * t);
        const new_x = (x + (v + omega * x) * t) * e;
        const new_v = (v - omega * (v + omega * x) * t) * e;
        if (@abs(new_x) < 0.001 and @abs(new_v) < 0.01) {
            pos_ptr.* = target;
            vel_ptr.* = 0;
            return target;
        }
        pos_ptr.* = target + new_x;
        vel_ptr.* = new_v;
        self.animating_now = true;
        return pos_ptr.*;
    }

    pub fn loop(self: *AnimStore, period: f32) f32 {
        self.animating_now = true;
        const t: f32 = @floatCast(@mod(self.time, @as(f64, period)));
        return t / period;
    }
};

pub const ease = struct {
    pub fn outCubic(t: f32) f32 {
        const u = 1.0 - t;
        return 1.0 - u * u * u;
    }
    pub fn inOutCubic(t: f32) f32 {
        return if (t < 0.5) 4 * t * t * t else 1 - std.math.pow(f32, -2 * t + 2, 3) / 2;
    }
    pub fn outBack(t: f32) f32 {
        const c1: f32 = 1.70158;
        const c3: f32 = c1 + 1;
        const u = t - 1;
        return 1 + c3 * u * u * u + c1 * u * u;
    }
};

test "easing endpoints" {
    try std.testing.expectApproxEqAbs(@as(f32, 0), ease.outCubic(0), 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 1), ease.outCubic(1), 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 1), ease.inOutCubic(1), 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 1), ease.outBack(1), 1e-6);
}
