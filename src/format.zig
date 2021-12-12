const std = @import("std");
const NaiveDate = @import("./date.zig").NaiveDate;
const NaiveDateTime = @import("./datetime.zig").NaiveDateTime;
const internals = @import("./internals.zig");
const time = @import("./time.zig");

pub const Specifier = enum(u8) {
    weekday = 'a',
    full_weekday = 'A',

    month = 'b',
    full_month = 'B',
    month_number = 'm',

    full_year = 'Y',
    day = 'd',
    hour24 = 'H',
    min = 'M',
    sec = 'S',

    isoweek_year = 'G',
    isoweek_number = 'V',

    /// Same as %Y-%m-%d
    iso_date = 'F',
    iso_time = 'T',
    hour24_and_min = 'R',

    pub fn formatNaiveDateTime(
        this: @This(),
        writer: anytype,
        dt: NaiveDateTime,
    ) !void {
        switch (this) {
            .weekday => try writer.print("{d}", .{dt.weekday().shortName()}),
            .full_weekday => try writer.print("{d}", .{dt.weekday().fullName()}),

            .month => try writer.print("{d}", .{dt.month().shortName()}),
            .full_month => try writer.print("{d}", .{dt.month().fullName()}),
            .month_number => try writer.print("{d:0>2}", .{dt.month().number()}),

            .full_year => try writer.print("{d}", .{dt.year()}),
            .day => try writer.print("{d:0>2}", .{dt.day()}),

            // Time specifiers
            .hour24 => try writer.print("{d:0>2}", .{dt.hour()}),
            .min => try writer.print("{d:0>2}", .{dt.minute()}),
            .sec => try writer.print("{d:0>2}", .{dt.second()}),

            // ISOWeek specifiers
            .isoweek_year => try writer.print("{d:0>2}", .{dt.isoweek().year}),
            .isoweek_number => try writer.print("{d:0>2}", .{dt.isoweek().week}),

            // Combined time specifiers
            .iso_date => try writer.print("{d}-{d:0>2}-{d:0>2}", .{ dt.year(), dt.month().number(), dt.day() }),
            .hour24_and_min => try writer.print("{d:0>2}:{d:0>2}", .{ dt.hour(), dt.minute() }),
            .iso_time => try writer.print("{d:0>2}:{d:0>2}:{d:0>2}", .{ dt.hour(), dt.minute(), dt.second() }),
        }
    }
};

pub const Part = union(enum) {
    literal: u8,
    specifier: Specifier,

    pub fn formatNaiveDateTime(
        this: @This(),
        writer: anytype,
        dt: NaiveDateTime,
    ) !void {
        switch (this) {
            .literal => |b| try writer.writeByte(b),
            .specifier => |s| try s.formatNaiveDateTime(writer, dt),
        }
    }
};

pub fn parseFormatBuf(buf: []Part, format_str: []const u8) ![]Part {
    var parts_idx: usize = 0;

    var next_char_is_specifier = false;
    for (format_str) |fc| {
        if (next_char_is_specifier) {
            buf[parts_idx] = .{
                .specifier = std.meta.intToEnum(Specifier, fc) catch return error.InvalidSpecifier,
            };
            parts_idx += 1;
            next_char_is_specifier = false;
        } else {
            if (fc == '%') {
                next_char_is_specifier = true;
            } else {
                buf[parts_idx] = .{ .literal = fc };
                parts_idx += 1;
            }
        }
    }

    return buf[0..parts_idx];
}

pub fn parseFormatAlloc(allocator: *std.mem.Allocator, format_str: []const u8) ![]Part {
    var parts = std.ArrayList(Part).init(allocator);
    errdefer parts.deinit();

    var next_char_is_specifier = false;
    for (format_str) |fc| {
        if (next_char_is_specifier) {
            const specifier = std.meta.intToEnum(Specifier, fc) catch return error.InvalidSpecifier;
            try parts.append(.{ .specifier = specifier });
            next_char_is_specifier = false;
        } else {
            if (fc == '%') {
                next_char_is_specifier = true;
            } else {
                try parts.append(.{ .literal = fc });
            }
        }
    }

    return parts.toOwnedSlice();
}

pub fn formatNaiveDateTimeParts(writer: anytype, parts: []const Part, dt: NaiveDateTime) !void {
    for (parts) |part| {
        try part.formatNaiveDateTime(writer, dt);
    }
}

pub fn formatNaiveDateTime(writer: anytype, format: []const u8, dt: NaiveDateTime) !void {
    var next_char_is_specifier = false;
    for (format) |fc| {
        if (next_char_is_specifier) {
            const specifier = std.meta.intToEnum(Specifier, fc) catch return error.InvalidSpecifier;
            try specifier.formatNaiveDateTime(writer, dt);
            next_char_is_specifier = false;
        } else {
            if (fc == '%') {
                next_char_is_specifier = true;
            } else {
                try writer.writeByte(fc);
            }
        }
    }
}

test "parse format string" {
    const parts = try parseFormatAlloc(std.testing.allocator, "%Y-%m-%d %H:%M:%S");
    defer std.testing.allocator.free(parts);
    try std.testing.expectEqualSlices(Part, &[_]Part{
        .{ .specifier = .full_year },
        .{ .literal = '-' },
        .{ .specifier = .month_number },
        .{ .literal = '-' },
        .{ .specifier = .day },
        .{ .literal = ' ' },
        .{ .specifier = .hour24 },
        .{ .literal = ':' },
        .{ .specifier = .min },
        .{ .literal = ':' },
        .{ .specifier = .sec },
    }, parts);
}

test "format naive datetimes with parts api" {
    const Case = struct {
        datetime: NaiveDateTime,
        expected_string: []const u8,
    };

    const cases = [_]Case{
        .{ .datetime = NaiveDate.ymd(2021, 02, 18).?.hms(17, 00, 00).?, .expected_string = "2021-02-18 17:00:00" },
        .{ .datetime = NaiveDate.ymd(1970, 01, 01).?.hms(0, 0, 0).?, .expected_string = "1970-01-01 00:00:00" },
    };

    const parts = try parseFormatAlloc(std.testing.allocator, "%Y-%m-%d %H:%M:%S");
    defer std.testing.allocator.free(parts);

    for (cases) |case| {
        var str = std.ArrayList(u8).init(std.testing.allocator);
        defer str.deinit();

        try formatNaiveDateTimeParts(str.writer(), parts, case.datetime);

        try std.testing.expectEqualStrings(case.expected_string, str.items);
    }
}

test "format naive datetimes with format string api" {
    const Case = struct {
        datetime: NaiveDateTime,
        expected_string: []const u8,
    };

    const cases = [_]Case{
        .{ .datetime = NaiveDate.ymd(2021, 02, 18).?.hms(17, 00, 00).?, .expected_string = "2021-02-18 17:00:00" },
        .{ .datetime = NaiveDate.ymd(1970, 01, 01).?.hms(0, 0, 0).?, .expected_string = "1970-01-01 00:00:00" },
    };

    for (cases) |case| {
        var str = std.ArrayList(u8).init(std.testing.allocator);
        defer str.deinit();

        try formatNaiveDateTime(str.writer(), "%Y-%m-%d %H:%M:%S", case.datetime);

        try std.testing.expectEqualStrings(case.expected_string, str.items);
    }
}

pub fn parseNaiveDateTime(comptime format: []const u8, dtString: []const u8) !NaiveDateTime {
    var year: ?internals.YearInt = null;
    var month: ?internals.MonthInt = null;
    var day: ?internals.DayInt = null;
    var hour: ?time.HoursInt = null;
    var minute: ?time.MinutesInt = null;
    var second: ?time.SecondsInt = null;

    comptime var next_char_is_specifier = false;
    var dt_string_idx: usize = 0;
    inline for (format) |fc| {
        if (next_char_is_specifier) {
            switch (fc) {
                'F' => {
                    year = try parseDigits(internals.YearInt, dtString, &dt_string_idx, 4);
                    month = try parseDigits(internals.MonthInt, dtString, &dt_string_idx, 2);
                    day = try parseDigits(internals.DayInt, dtString, &dt_string_idx, 2);
                },

                'Y' => {
                    std.debug.assert(year == null);
                    // Read digits until: 1) there is four digits or 2) the next character is not a digit
                    year = try parseDigits(internals.YearInt, dtString, &dt_string_idx, 4);
                },
                'm' => {
                    std.debug.assert(month == null);
                    // Read 2 digits or just 1 if the digit after is not a digit
                    month = try parseDigits(internals.MonthInt, dtString, &dt_string_idx, 2);
                },
                'd' => {
                    std.debug.assert(day == null);
                    // Read 2 digits or just 1 if the digit after is not a digit
                    day = try parseDigits(internals.DayInt, dtString, &dt_string_idx, 2);
                },

                // Time specifiers
                'H' => {
                    std.debug.assert(hour == null);
                    hour = try parseDigits(time.HoursInt, dtString, &dt_string_idx, 2);
                },
                'M' => {
                    std.debug.assert(minute == null);
                    minute = try parseDigits(time.MinutesInt, dtString, &dt_string_idx, 2);
                },
                'S' => {
                    std.debug.assert(second == null);
                    second = try parseDigits(time.SecondsInt, dtString, &dt_string_idx, 2);
                },

                // Combined time specifiers
                'R' => {
                    std.debug.assert(hour == null and minute == null);
                    hour = try parseDigits(time.HoursInt, dtString, &dt_string_idx, 2);
                    minute = try parseDigits(time.MinutesInt, dtString, &dt_string_idx, 2);
                },
                'T' => {
                    std.debug.assert(hour == null and minute == null and second == null);
                    hour = try parseDigits(time.HoursInt, dtString, &dt_string_idx, 2);
                    minute = try parseDigits(time.MinutesInt, dtString, &dt_string_idx, 2);
                    second = try parseDigits(time.SecondsInt, dtString, &dt_string_idx, 2);
                },

                ';' => {
                    if (dtString[dt_string_idx] != ':') return error.InvalidFormat;
                    dt_string_idx += 1;
                },
                else => @compileError("Invalid date format specifier " ++ fc),
            }
            next_char_is_specifier = false;
        } else {
            if (fc == '%') {
                next_char_is_specifier = true;
            } else {
                if (dtString[dt_string_idx] != fc) {
                    return error.InvalidFormat;
                }
                dt_string_idx += 1;
            }
        }
    }

    std.debug.assert(year != null);
    std.debug.assert(month != null);
    std.debug.assert(day != null);
    std.debug.assert(hour != null);
    std.debug.assert(minute != null);

    return NaiveDate.ymd(year.?, month.?, day.?).?.hms(hour.?, minute.?, second orelse 0).?;
}

fn parseDigits(comptime T: type, dtString: []const u8, idx: *usize, maxDigits: usize) !T {
    const start_idx = idx.*;

    if (!std.ascii.isDigit(dtString[start_idx])) return error.InvalidFormat;

    idx.* += 1;
    while (idx.* < start_idx + maxDigits and std.ascii.isDigit(dtString[idx.*])) : (idx.* += 1) {}

    return try std.fmt.parseInt(T, dtString[start_idx..idx.*], 10);
}

test "comptime parse with comptime format string" {
    const Case = struct {
        string: []const u8,
        expected_datetime: NaiveDateTime,
    };

    const cases = [_]Case{
        .{ .string = "2021-02-18 17:00:00", .expected_datetime = NaiveDate.ymd(2021, 02, 18).?.hms(17, 00, 00).? },
        .{ .string = "1970-01-01 00:00:00", .expected_datetime = NaiveDate.ymd(1970, 01, 01).?.hms(0, 0, 0).? },
    };

    for (cases) |case| {
        const datetime = try parseNaiveDateTime("%Y-%m-%d %H:%M:%S", case.string);

        try std.testing.expectEqual(case.expected_datetime, datetime);
    }
}
