const std = @import("std");
const NaiveDate = @import("./date.zig").NaiveDate;
const NaiveDateTime = @import("./datetime.zig").NaiveDateTime;
const internals = @import("./internals.zig");
const time = @import("./time.zig");

pub const Specifier = enum {
    FullYear,
    MonthNumber,
    DayNumber,
    HourNumber24,
    MinuteNumber,
    SecondNumber,
};

pub const Part = union(enum) {
    Literal: u8,
    Specifier: Specifier,
};

pub const Formatter = struct {
    allocator: *std.mem.Allocator,
    parts: []Part,

    pub fn parse(allocator: *std.mem.Allocator, format_str: []const u8) !@This() {
        var parts = std.ArrayList(Part).init(allocator);
        errdefer parts.deinit();

        var next_char_is_specifier = false;
        for (format_str) |fc| {
            if (next_char_is_specifier) {
                const specifier: Specifier = switch (fc) {
                    'Y' => .FullYear,
                    'm' => .MonthNumber,
                    'd' => .DayNumber,
                    'H' => .HourNumber24,
                    'M' => .MinuteNumber,
                    'S' => .SecondNumber,
                    else => return error.InvalidFormat,
                };
                try parts.append(.{ .Specifier = specifier });
                next_char_is_specifier = false;
            } else {
                if (fc == '%') {
                    next_char_is_specifier = true;
                } else {
                    try parts.append(.{ .Literal = fc });
                }
            }
        }

        return @This(){
            .allocator = allocator,
            .parts = parts.toOwnedSlice(),
        };
    }

    pub fn deinit(this: @This()) void {
        this.allocator.free(this.parts);
    }

    pub fn formatNaiveDateTime(this: @This(), writer: anytype, dt: NaiveDateTime) !void {
        for (this.parts) |part| {
            switch (part) {
                .Literal => |lit| try writer.writeByte(lit),
                .Specifier => |specifier| switch (specifier) {
                    .FullYear => try writer.print("{d}", .{dt.year()}),
                    .MonthNumber => try writer.print("{d:0>2}", .{dt.month()}),
                    .DayNumber => try writer.print("{d:0>2}", .{dt.day()}),
                    .HourNumber24 => try writer.print("{d:0>2}", .{dt.hour()}),
                    .MinuteNumber => try writer.print("{d:0>2}", .{dt.minute()}),
                    .SecondNumber => try writer.print("{d:0>2}", .{dt.second()}),
                },
            }
        }
    }
};

pub fn formatNaiveDateTime(writer: anytype, comptime format: []const u8, dt: NaiveDateTime) !void {
    comptime var next_char_is_specifier = false;
    inline for (format) |fc| {
        if (next_char_is_specifier) {
            switch (fc) {
                'F' => try writer.print("{d}-{d:0>2}-{d:0>2}", .{ dt.year(), dt.month(), dt.day() }),
                'Y' => try writer.print("{d}", .{dt.year()}),
                'm' => try writer.print("{d:0>2}", .{dt.month()}),
                'd' => try writer.print("{d:0>2}", .{dt.day()}),

                // Time specifiers
                'H' => try writer.print("{d:0>2}", .{dt.hour()}),
                'M' => try writer.print("{d:0>2}", .{dt.minute()}),
                'S' => try writer.print("{d:0>2}", .{dt.second()}),

                // Combined time specifiers
                'R' => try writer.print("{d:0>2}:{d:0>2}", .{ dt.hour(), dt.minute() }),
                'T' => try writer.print("{d:0>2}:{d:0>2}:{d:0>2}", .{ dt.hour(), dt.minute(), dt.second() }),

                ';' => try writer.writeByte(':'),
                else => @compileError("Invalid date format specifier " ++ fc),
            }
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
    const formatter = try Formatter.parse(std.testing.allocator, "%Y-%m-%d %H:%M:%S");
    defer formatter.deinit();
    try std.testing.expectEqualSlices(Part, &[_]Part{
        .{ .Specifier = .FullYear },
        .{ .Literal = '-' },
        .{ .Specifier = .MonthNumber },
        .{ .Literal = '-' },
        .{ .Specifier = .DayNumber },
        .{ .Literal = ' ' },
        .{ .Specifier = .HourNumber24 },
        .{ .Literal = ':' },
        .{ .Specifier = .MinuteNumber },
        .{ .Literal = ':' },
        .{ .Specifier = .SecondNumber },
    }, formatter.parts);
}

test "format naive datetimes" {
    const Case = struct {
        datetime: NaiveDateTime,
        expected_string: []const u8,
    };

    const cases = [_]Case{
        .{ .datetime = NaiveDate.ymd(2021, 02, 18).?.hms(17, 00, 00).?, .expected_string = "2021-02-18 17:00:00" },
        .{ .datetime = NaiveDate.ymd(1970, 01, 01).?.hms(0, 0, 0).?, .expected_string = "1970-01-01 00:00:00" },
    };

    const formatter = try Formatter.parse(std.testing.allocator, "%Y-%m-%d %H:%M:%S");
    defer formatter.deinit();

    for (cases) |case| {
        var str = std.ArrayList(u8).init(std.testing.allocator);
        defer str.deinit();

        try formatter.formatNaiveDateTime(str.writer(), case.datetime);

        try std.testing.expectEqualSlices(u8, case.expected_string, str.items);
    }
}

test "comptime format naive datetimes" {
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

        try std.testing.expectEqualSlices(u8, case.expected_string, str.items);
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
