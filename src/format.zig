const std = @import("std");
const NaiveDate = @import("./date.zig").NaiveDate;
const NaiveDateTime = @import("./datetime.zig").NaiveDateTime;

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
                'Y' => try writer.print("{d}", .{dt.year()}),
                'm' => try writer.print("{d:0>2}", .{dt.month()}),
                'd' => try writer.print("{d:0>2}", .{dt.day()}),
                'H' => try writer.print("{d:0>2}", .{dt.hour()}),
                'M' => try writer.print("{d:0>2}", .{dt.minute()}),
                'S' => try writer.print("{d:0>2}", .{dt.second()}),
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
    std.testing.expectEqualSlices(Part, &[_]Part{
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

        std.testing.expectEqualSlices(u8, case.expected_string, str.items);
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
        
        std.testing.expectEqualSlices(u8, case.expected_string, str.items);
    }
}
