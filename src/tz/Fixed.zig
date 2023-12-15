offset: i32,
is_daylight_saving_time: bool = false,
designation: ?[]const u8,
iana_identifier: ?chrono.tz.Identifier,

pub const TIMEZONE_VTABLE = chrono.tz.TimeZone.VTable.eraseTypes(@This(), .{
    .offsetAtTimestamp = offsetAtTimestamp,
    .isDaylightSavingTimeAtTimestamp = isDaylightSavingTimeAtTimestamp,
    .designationAtTimestamp = designationAtTimestamp,
    .identifier = identifier,
});

pub fn timeZone(this: *const @This()) chrono.tz.TimeZone {
    return chrono.tz.TimeZone{
        .ptr = this,
        .vtable = &TIMEZONE_VTABLE,
    };
}

pub fn offsetAtTimestamp(this: *const @This(), utc: i64) ?i32 {
    _ = utc;
    return this.offset;
}

pub fn isDaylightSavingTimeAtTimestamp(this: *const @This(), utc: i64) ?bool {
    _ = this;
    _ = utc;
    return false;
}

pub fn designationAtTimestamp(this: *const @This(), utc: i64) ?[]const u8 {
    _ = utc;
    return this.designation;
}

pub fn identifier(this: *const @This()) ?chrono.tz.Identifier {
    return this.iana_identifier;
}

const chrono = @import("../lib.zig");
const Posix = @import("./Posix.zig");
const testing = std.testing;
const std = @import("std");
