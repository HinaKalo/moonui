//! MoonWin Native GUI — Pure Zig 0.17.1 + Win32 + Direct2D 1.1 + DirectComposition + DirectWrite.
//! Zero C/C++ dependencies; replicates the MoonWin component library skin with pure native Windows APIs.
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const moonwin = b.addModule("moonwin", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    if (target.result.os.tag == .windows) {
        const libs = [_][]const u8{
            "user32",
            "gdi32",
            "dwmapi",
            "d3d11",
            "dxgi",
            "d2d1",
            "dwrite",
            "dcomp",
            "ole32",
            "imm32",
        };
        for (libs) |lib| {
            moonwin.linkSystemLibrary(lib, .{});
        }
    }

    // ---- Component Gallery executable
    const gallery = b.addExecutable(.{
        .name = "moonwin-native-gallery",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/gallery/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "moonwin", .module = moonwin }},
        }),
    });
    if (optimize != .debug and target.result.os.tag == .windows) {
        gallery.subsystem = .windows;
    }
    const install_gallery = b.addInstallArtifact(gallery, .{});
    b.default_step.dependOn(&install_gallery.step);

    const run_gallery = b.addRunArtifact(gallery);
    run_gallery.step.dependOn(&install_gallery.step);
    run_gallery.addPassthruArgs();
    const run_step = b.step("run", "Run the native Direct2D component gallery");
    run_step.dependOn(&run_gallery.step);

    // ---- Unit tests
    const tests = b.addTest(.{ .root_module = moonwin });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
