//! One-command project scaffolder for `moonui`:
//!   zig build new -- <output-dir> [--name my-app]
//!
//! Generates a ready-to-run pure Zig Direct2D + DirectComposition app wired to
//! `moonui` via relative path dependency (builds offline immediately).
const std = @import("std");

const tpl_gitignore =
    \\.zig-cache/
    \\zig-out/
    \\*.pdb
    \\
;

const tpl_build_zig =
    \\const std = @import("std");
    \\
    \\pub fn build(b: *std.Build) void {
    \\    const target = b.standardTargetOptions(.{});
    \\    const optimize = b.standardOptimizeOption(.{});
    \\
    \\    const moonui = b.dependency("moonui", .{ .target = target, .optimize = optimize });
    \\
    \\    const exe = b.addExecutable(.{
    \\        .name = "@NAME@",
    \\        .root_module = b.createModule(.{
    \\            .root_source_file = b.path("src/main.zig"),
    \\            .target = target,
    \\            .optimize = optimize,
    \\            .imports = &.{
    \\                .{ .name = "moonui", .module = moonui.module("moonui") },
    \\            },
    \\        }),
    \\    });
    \\    if (optimize != .debug and target.result.os.tag == .windows) {
    \\        exe.subsystem = .windows;
    \\    }
    \\    b.installArtifact(exe);
    \\
    \\    const run_cmd = b.addRunArtifact(exe);
    \\    run_cmd.step.dependOn(b.getInstallStep());
    \\    run_cmd.addPassthruArgs();
    \\    b.step("run", "Run @NAME@").dependOn(&run_cmd.step);
    \\}
    \\
;

const tpl_zon =
    \\.{
    \\    .name = .@IDENT@,
    \\    .version = "0.1.0",
    \\    .fingerprint = @FINGERPRINT@,
    \\    .minimum_zig_version = "0.17.1",
    \\    .dependencies = .{
    \\        .moonui = .{ .path = "@MOONUI_PATH@" },
    \\    },
    \\    .paths = .{ "build.zig", "build.zig.zon", "src" },
    \\}
    \\
;

const tpl_main =
    \\const std = @import("std");
    \\const ui = @import("moonui");
    \\
    \\const State = struct {
    \\    count: u32 = 0,
    \\    dark: bool = true,
    \\};
    \\
    \\pub fn main() !void {
    \\    var state: State = .{};
    \\    try ui.run(.{
    \\        .title = "@NAME@",
    \\        .width = 960,
    \\        .height = 640,
    \\    }, &state, frame);
    \\}
    \\
    \\fn frame(s: *State) void {
    \\    ui.beginMain(.{ .max_width = 720 });
    \\    defer ui.endMain();
    \\
    \\    ui.pageHeader("@NAME@", "Built with pure Zig + Direct2D + DirectComposition + DirectWrite.");
    \\    ui.space(.lg);
    \\
    \\    ui.beginCard("welcome", .{});
    \\    ui.section("Counter", "Zero Dear ImGui, zero C/C++ dependencies.");
    \\    ui.beginRow(.sm);
    \\    if (ui.button("Click me", .{ .variant = .primary, .icon = .sparkles })) s.count += 1;
    \\    ui.next();
    \\    if (ui.button("Reset", .{ .variant = .outline })) s.count = 0;
    \\    ui.endRow();
    \\    ui.space(.sm);
    \\    ui.text(ui.fmt("Clicked {d} times", .{s.count}), .{ .ink = .muted });
    \\    ui.space(.sm);
    \\    if (ui.toggle("Dark mode", &s.dark)) {
    \\        ui.setTheme(if (s.dark) ui.themes.midnight else ui.themes.daylight);
    \\    }
    \\    _ = ui.endCard();
    \\}
    \\
;

fn toIdent(gpa: std.mem.Allocator, name: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    for (name) |ch| {
        const lc = std.ascii.toLower(ch);
        try out.append(gpa, if (std.ascii.isAlphanumeric(lc)) lc else '_');
    }
    if (out.items.len == 0 or std.ascii.isDigit(out.items[0])) try out.insert(gpa, 0, '_');
    return out.toOwnedSlice(gpa);
}

fn calcFingerprint(ident: []const u8) u64 {
    var id: u32 = @truncate(std.hash.Wyhash.hash(0x6D6F6F6E, ident));
    if (id == 0 or id == 0xffffffff) id = 0x1234_5678;
    const checksum: u32 = std.hash.Crc32.hash(ident);
    return @as(u64, id) | (@as(u64, checksum) << 32);
}

fn replaceAll(gpa: std.mem.Allocator, input: []const u8, key: []const u8, value: []const u8) ![]u8 {
    const n = std.mem.replacementSize(u8, input, key, value);
    const out = try gpa.alloc(u8, n);
    _ = std.mem.replace(u8, input, key, value, out);
    return out;
}

fn nextComp(it: *std.mem.TokenIterator(u8, .any)) ?[]const u8 {
    while (it.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".")) continue;
        return part;
    }
    return null;
}

fn relativePath(gpa: std.mem.Allocator, from: []const u8, to: []const u8) ![]u8 {
    var a: std.ArrayList([]const u8) = .empty;
    var b: std.ArrayList([]const u8) = .empty;
    var ita = std.mem.tokenizeAny(u8, from, "/\\");
    while (nextComp(&ita)) |p| try a.append(gpa, p);
    var itb = std.mem.tokenizeAny(u8, to, "/\\");
    while (nextComp(&itb)) |p| try b.append(gpa, p);
    if (a.items.len == 0 or b.items.len == 0 or !std.ascii.eqlIgnoreCase(a.items[0], b.items[0])) {
        return replaceAll(gpa, to, "\\", "/");
    }
    var common: usize = 0;
    while (common < a.items.len and common < b.items.len and std.ascii.eqlIgnoreCase(a.items[common], b.items[common])) : (common += 1) {}
    var out: std.ArrayList(u8) = .empty;
    var idx = common;
    while (idx < a.items.len) : (idx += 1) {
        if (out.items.len > 0) try out.append(gpa, '/');
        try out.appendSlice(gpa, "..");
    }
    for (b.items[common..]) |p| {
        if (out.items.len > 0) try out.append(gpa, '/');
        try out.appendSlice(gpa, p);
    }
    if (out.items.len == 0) try out.append(gpa, '.');
    return out.toOwnedSlice(gpa);
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(gpa);

    var out_dir: ?[]const u8 = null;
    var name: ?[]const u8 = null;
    var moonui_path: []const u8 = ".";

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--name") and i + 1 < args.len) {
            i += 1;
            name = args[i];
        } else if (std.mem.eql(u8, a, "--moonui") and i + 1 < args.len) {
            i += 1;
            moonui_path = args[i];
        } else if (out_dir == null) {
            out_dir = a;
        }
    }

    const dir_path = out_dir orelse {
        std.debug.print("usage: zig build new -- <output-dir> [--name <app-name>]\n", .{});
        std.process.exit(2);
    };

    const app_name = name orelse std.fs.path.basename(dir_path);
    const ident = try toIdent(gpa, app_name);
    const fp = try std.fmt.allocPrint(gpa, "0x{x}", .{calcFingerprint(ident)});

    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, dir_path);
    var dst = try cwd.openDir(io, dir_path, .{});
    defer dst.close(io);
    try dst.createDirPath(io, "src");

    const abs_dst = try dst.realPathFileAlloc(io, ".", gpa);
    var src_dir = try cwd.openDir(io, moonui_path, .{});
    defer src_dir.close(io);
    const abs_src = try src_dir.realPathFileAlloc(io, ".", gpa);
    const norm_path = try relativePath(gpa, abs_dst, abs_src);

    const files = [_]struct { path: []const u8, data: []const u8 }{
        .{ .path = ".gitignore", .data = tpl_gitignore },
        .{ .path = "build.zig", .data = tpl_build_zig },
        .{ .path = "build.zig.zon", .data = tpl_zon },
        .{ .path = "src/main.zig", .data = tpl_main },
    };

    for (files) |f| {
        var content = try replaceAll(gpa, f.data, "@NAME@", app_name);
        content = try replaceAll(gpa, content, "@IDENT@", ident);
        content = try replaceAll(gpa, content, "@FINGERPRINT@", fp);
        content = try replaceAll(gpa, content, "@MOONUI_PATH@", norm_path);
        var file = try dst.createFile(io, f.path, .{});
        defer file.close(io);
        try file.writeStreamingAll(io, content);
    }

    std.debug.print("Created MoonUI app '{s}' at {s}\nRun:\n  cd {s}\n  zig build run\n", .{ app_name, dir_path, dir_path });
}
