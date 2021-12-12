const std = @import("std");

pub const date = @import("./date.zig");
pub const time = @import("./time.zig");
pub const datetime = @import("./datetime.zig");
pub const timezone = @import("./timezone.zig");
pub const format = @import("./format.zig");

pub const IsoWeek = @import("./IsoWeek.zig");

pub const Weekday = enum(u3) {
    mon = 0,
    tue = 1,
    wed = 2,
    thu = 3,
    fri = 4,
    sat = 5,
    sun = 6,
};

comptime {
    @import("std").testing.refAllDecls(@This());
}

pub fn installJS(dir: std.fs.Dir) !void {
    try dir.writeFile("chrono.js", @embedFile("chrono.js"));
}
