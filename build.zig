const std = @import("std");
const ResolvedTarget = std.Build.ResolvedTarget;
const Compile = std.Build.Step.Compile;
const OptimizationMode = std.builtin.OptimizeMode;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "gtk4-binding-generator",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    g_imports(b, exe, target, optimize);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const lib_test = b.addTest(.{
        .name = "test",
        .root_source_file = b.path("src/test.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_test = b.addRunArtifact(lib_test);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_test.step);

    check(b, &[_]*Compile{ exe, lib_test });
}

fn g_imports(b: *std.Build, compile: *Compile, target: ResolvedTarget, mode: OptimizationMode) void {
    const gobject = b.dependency("gobject", .{
        .target = target,
        .optimize = mode,
    });

    compile.root_module.addImport("gtk", gobject.module("gtk4"));
    compile.root_module.addImport("glib", gobject.module("glib2"));
    compile.root_module.addImport("gobject", gobject.module("gobject2"));
    compile.root_module.addImport("gio", gobject.module("gio2"));
    compile.root_module.addImport("gdk", gobject.module("gdk4"));
    compile.root_module.addImport("secrets", gobject.module("secret1"));

    compile.linkSystemLibrary("gtk4-layer-shell-0");
}

fn check(b: *std.Build, compiles: []const *Compile) void {
    const step = b.step("check", "zls compile check");

    for (compiles) |c| {
        step.dependOn(&c.step);
    }
}
