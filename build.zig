const std = @import("std");
const Builder = std.build.Builder;

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const should_install_examples = b.option(bool, "examples", "Whether to install the examples or not") orelse true;

    const chrono = b.addModule("chrono", .{
        .source_file = .{ .path = "src/lib.zig" },
    });

    const test_exe = b.addTest(.{
        .root_source_file = .{ .path = "src/lib.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_tests = b.addRunArtifact(test_exe);

    const run_tests_step = b.step("test", "Test everything");
    run_tests_step.dependOn(&run_tests.step);

    addExample(b, .{
        .name = "print-local-datetime",
        .target = target,
        .optimize = optimize,
        .chrono = chrono,
        .should_install = should_install_examples,
    });
}

const ExampleOptions = struct {
    name: []const u8,
    target: std.zig.CrossTarget,
    optimize: std.builtin.OptimizeMode,
    chrono: *std.Build.Module,
    should_install: bool,
};
pub fn addExample(b: *Builder, options: ExampleOptions) void {
    const exe = b.addExecutable(.{
        .name = options.name,
        .root_source_file = .{ .path = b.pathJoin(&.{ "examples", b.fmt("{s}.zig", .{options.name}) }) },
        .target = options.target,
        .optimize = options.optimize,
    });
    exe.addModule("chrono", options.chrono);

    if (options.should_install) {
        b.installArtifact(exe);
    }
}
