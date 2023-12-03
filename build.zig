const std = @import("std");
const Builder = std.build.Builder;

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const test_exe = b.addTest(.{
        .root_source_file = .{ .path = "src/lib.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_tests = b.addRunArtifact(test_exe);

    const run_tests_step = b.step("test", "Test everything");
    run_tests_step.dependOn(&run_tests.step);
}
