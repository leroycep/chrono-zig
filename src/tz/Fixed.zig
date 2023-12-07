offset: i32,
designation: []const u8,

pub fn init(offset: i32, designation: []const u8) @This() {
    return @This(){
        .offset = offset,
        .designation = designation,
    };
}

pub const TIMEZONE_VTABLE = chrono.tz.TimeZone.VTable.eraseTypes(@This(), .{
    .offsetAtTimestamp = offsetAtTimestamp,
});

pub fn timeZone(this: *@This()) chrono.tz.TimeZone {
    return chrono.tz.TimeZone{
        .ptr = this,
        .vtable = &TIMEZONE_VTABLE,
    };
}

pub fn offsetAtTimestamp(this: *const @This(), utc: i64) ?chrono.tz.TimeZone.Offset {
    _ = utc;
    return chrono.tz.TimeZone.Offset{
        .offset = this.offset,
        .designation = this.designation,
        .is_daylight_saving_time = false,
    };
}

const chrono = @import("../lib.zig");
const Posix = @import("./Posix.zig");
const testing = std.testing;
const std = @import("std");
