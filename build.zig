const std = @import("std");
const Builder = std.build.Builder;

pub fn build(b: *Builder) void {
    const tests = b.addTest("src/lib.zig");

    const run_tests = b.step("test", "Test everything");
    run_tests.dependOn(&tests.step);
}
