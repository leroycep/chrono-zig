pub const HoursMinutesSeconds = packed struct(i32) {
    negative: bool,
    hours: u19,
    minutes: u6,
    seconds: u6,

    pub fn new(hours: i20, minutes: u6, seconds: u6) @This() {
        std.debug.assert(minutes < 60);
        std.debug.assert(seconds < 60);
        return @This(){
            .negative = hours < 0,
            .hours = if (hours < 0) @intCast(-hours) else @intCast(hours),
            .minutes = minutes,
            .seconds = seconds,
        };
    }

    pub const ParseError = error{ InvalidFormat, Overflow };

    // TODO: Put information about error into diagnostics on parsing error
    pub const Diagnostics = struct {};

    /// Parses a duration hh:mm:ss string.
    pub fn parse(hhmmss_string: []const u8, diagnostics: ?*Diagnostics) ParseError!@This() {
        _ = diagnostics;

        if (hhmmss_string.len == 0) return error.InvalidFormat;

        const is_sign = hhmmss_string[0] == '-' or hhmmss_string[0] == '+';
        const is_negative = hhmmss_string[0] == '-';

        if (!(std.ascii.isDigit(hhmmss_string[0]) or is_sign)) {
            return error.InvalidFormat;
        }

        const string = if (is_sign) hhmmss_string[1..] else hhmmss_string;

        var segment_iter = std.mem.split(u8, string, ":");
        const hour_string = segment_iter.next() orelse return error.InvalidFormat;
        const hours = std.fmt.parseInt(u19, hour_string, 10) catch |err| switch (err) {
            error.InvalidCharacter => return error.InvalidFormat,
            else => |e| return e,
        };

        const minutes = if (segment_iter.next()) |minute_string| parse_minutes: {
            if (minute_string.len != 2) return error.InvalidFormat;
            const minutes = std.fmt.parseInt(u6, minute_string, 10) catch return error.InvalidFormat;
            if (minutes > 59) return error.InvalidFormat;
            break :parse_minutes minutes;
        } else 0;

        const seconds = if (segment_iter.next()) |second_string| parse_seconds: {
            if (second_string.len != 2) return error.InvalidFormat;
            const seconds = std.fmt.parseInt(u6, second_string, 10) catch return error.InvalidFormat;
            if (seconds > 59) return error.InvalidFormat;
            break :parse_seconds seconds;
        } else 0;

        return @This(){
            .negative = is_negative,
            .hours = hours,
            .minutes = minutes,
            .seconds = seconds,
        };
    }

    pub fn toSeconds(this: @This()) i64 {
        const sign: i32 = if (this.negative) -1 else 1;
        const duration_unsigned = (@as(i64, this.hours) * std.time.s_per_hour) + (@as(i64, this.minutes) * std.time.s_per_min) + this.seconds;
        return sign * duration_unsigned;
    }

    pub fn format(
        this: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try std.fmt.format(writer, "{s}{}", .{
            if (this.negative) "-" else "",
            this.hours,
        });
        if (this.minutes != 0 or this.seconds != 0) {
            try std.fmt.format(writer, ":{}", .{this.minutes});
        }
        if (this.seconds != 0) {
            try std.fmt.format(writer, ":{}", .{this.seconds});
        }
    }
};

const std = @import("std");
