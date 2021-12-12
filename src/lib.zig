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

    pub fn fullName(this: @This()) []const u8 {
        return switch (this) {
            .mon => "Monday",
            .tue => "Tuesday",
            .wed => "Wednesday",
            .thu => "Thursday",
            .fri => "Friday",
            .sat => "Saturday",
            .sun => "Sunday",
        };
    }

    pub fn shortName(this: @This()) [3:0]u8 {
        return (switch (this) {
            .mon => "Mon",
            .tue => "Tue",
            .wed => "Wed",
            .thu => "Thu",
            .fri => "Fri",
            .sat => "Sat",
            .sun => "Sun",
        }).*;
    }
};

pub const Month = enum(u4) {
    jan = 1,
    feb,
    mar,
    apr,
    may,
    jun,
    jul,
    aug,
    sep,
    oct,
    nov,
    dec,

    pub fn fullName(this: @This()) []const u8 {
        return switch (this) {
            .jan => "January",
            .feb => "Febuary",
            .mar => "March",
            .apr => "April",
            .may => "May",
            .jun => "June",
            .jul => "July",
            .aug => "August",
            .sep => "September",
            .oct => "October",
            .nov => "November",
            .dec => "December",
        };
    }

    pub fn shortName(this: @This()) [3:0]u8 {
        return (switch (this) {
            .jan => "Jan",
            .feb => "Feb",
            .mar => "Mar",
            .apr => "Apr",
            .may => "May",
            .jun => "Jun",
            .jul => "Jul",
            .aug => "Aug",
            .sep => "Sep",
            .oct => "Oct",
            .nov => "Nov",
            .dec => "Dec",
        }).*;
    }

    pub fn number(this: @This()) u4 {
        return @enumToInt(this);
    }
};

comptime {
    @import("std").testing.refAllDecls(@This());
}

pub fn installJS(dir: std.fs.Dir) !void {
    try dir.writeFile("chrono.js", @embedFile("chrono.js"));
}
