//! MoonUI — Pure Zig 0.17.1 Native Windows UI Library (Direct2D 1.1 + DirectComposition + DirectWrite).
//!
//! Consumers:
//!   zig fetch --save=moonui <path-or-git-url>
//!   const moonui = b.dependency("moonui", .{ .target = target, .optimize = optimize });
//!   exe.root_module.addImport("moonui", moonui.module("moonui"));
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const moonui = b.addModule("moonui", .{
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
            moonui.linkSystemLibrary(lib, .{});
        }
    }

    // ---- Component Gallery executable (`zig build run`)
    const gallery = b.addExecutable(.{
        .name = "moonui-gallery",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/gallery/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "moonui", .module = moonui }},
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
    b.step("run", "Run the native Direct2D component gallery").dependOn(&run_gallery.step);

    // ---- MoonChat IM demo (`zig build chat`, combines moonui + moon_sdk)
    const chat_step = b.step("chat", "Run the MoonChat Direct2D IM demo (moonui + mooncore + moonchat)");
    if (b.lazyDependency("moon_sdk", .{ .target = target, .optimize = optimize })) |sdk| {
        const chat_exe = b.addExecutable(.{
            .name = "moonui-chat",
            .root_module = b.createModule(.{
                .root_source_file = b.path("examples/chat/main.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "moonui", .module = moonui },
                    .{ .name = "mooncore", .module = sdk.module("mooncore") },
                    .{ .name = "moonchat", .module = sdk.module("moonchat") },
                },
            }),
        });
        if (optimize != .debug and target.result.os.tag == .windows) {
            chat_exe.subsystem = .windows;
        }
        const install_chat = b.addInstallArtifact(chat_exe, .{});
        const run_chat = b.addRunArtifact(chat_exe);
        run_chat.step.dependOn(&install_chat.step);
        run_chat.addPassthruArgs();
        chat_step.dependOn(&run_chat.step);
    }

    // ---- One-command project scaffolder (`zig build new -- <dir> [--name app]`)
    const scaffolder = b.addExecutable(.{
        .name = "moonui-new",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/new.zig"),
            .target = b.graph.host,
            .optimize = .debug,
        }),
    });
    const run_new = b.addRunArtifact(scaffolder);
    run_new.addArg("--moonui");
    run_new.addDirectoryArg(b.path("."));
    run_new.addPassthruArgs();
    b.step("new", "Scaffold a new MoonUI app: zig build new -- <dir> [--name app]").dependOn(&run_new.step);

    // ---- Unit tests (`zig build test`)
    const tests = b.addTest(.{ .root_module = moonui });
    b.step("test", "Run unit tests").dependOn(&b.addRunArtifact(tests).step);
}
