const std = @import("std");
const Builder = std.Build;

const SUPPORTED_TARGETS = [_]std.Target.Query{
    .{ .cpu_arch = .x86_64, .cpu_model = .baseline, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .x86_64, .cpu_model = .baseline, .os_tag = .linux, .abi = .musl },
    .{ .cpu_arch = .x86_64, .cpu_model = .baseline, .os_tag = .linux, .abi = .none },

    .{ .cpu_arch = .x86_64, .cpu_model = .baseline, .os_tag = .windows, .abi = .gnu },
    .{ .cpu_arch = .x86_64, .cpu_model = .baseline, .os_tag = .windows, .abi = .msvc },
};

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const should_install_examples = b.option(bool, "examples", "Whether to install the examples or not") orelse true;
    const skip_non_native = b.option(bool, "skip-non-native", "Whether to skip building non-native tests and examples. Only applies to `run-tests-and-build-examples`") orelse false;

    const chrono = b.addModule("chrono", .{
        .root_source_file = .{ .path = "src/lib.zig" },
    });

    const test_step = b.step("test", "Run tests for the current target");
    const check_step = b.step("run-tests-and-build-examples", "Runs tests and builds examples; run this to make sure everything works");

    buildTestsAndExamplesForTarget(b, .{
        .target = target,
        .optimize = optimize,
        .chrono = chrono,
        .should_install_examples = should_install_examples,
        .test_step = test_step,
        .check_step = check_step,
    });

    if (!skip_non_native) {
        for (SUPPORTED_TARGETS) |target_query| {
            buildTestsAndExamplesForTarget(b, .{
                .target = b.resolveTargetQuery(target_query),
                .optimize = optimize,
                .chrono = chrono,
                .should_install_examples = should_install_examples,
                .test_step = null,
                .check_step = check_step,
            });
        }
    }
}

const TestsAndExamplesOptions = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    chrono: *std.Build.Module,
    should_install_examples: bool,
    test_step: ?*std.Build.Step,
    check_step: *std.Build.Step,
};

pub fn buildTestsAndExamplesForTarget(b: *Builder, options: TestsAndExamplesOptions) void {
    const test_exe = b.addTest(.{
        .root_source_file = .{ .path = "src/lib.zig" },
        .target = options.target,
        .optimize = options.optimize,
    });

    const run_tests = b.addRunArtifact(test_exe);

    if (options.test_step) |test_step| {
        test_step.dependOn(&run_tests.step);
    }

    options.check_step.dependOn(&run_tests.step);

    addExample(b, .{
        .name = "print-local-datetime",
        .target = options.target,
        .optimize = options.optimize,
        .chrono = options.chrono,
        .should_install = options.should_install_examples,
        .check_step = options.check_step,
    });
}

const ExampleOptions = struct {
    name: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    chrono: *std.Build.Module,
    should_install: bool,
    check_step: ?*std.Build.Step,
};
pub fn addExample(b: *Builder, options: ExampleOptions) void {
    const exe = b.addExecutable(.{
        .name = options.name,
        .root_source_file = .{ .path = b.pathJoin(&.{ "examples", b.fmt("{s}.zig", .{options.name}) }) },
        .target = options.target,
        .optimize = options.optimize,
    });
    exe.root_module.addImport("chrono", options.chrono);

    if (options.check_step) |check_step| {
        check_step.dependOn(&exe.step);
    }
    if (options.should_install) {
        b.installArtifact(exe);
    }
}
