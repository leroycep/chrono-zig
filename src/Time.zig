secs: SecsInt,
frac: FracInt,

const Time = @This();

pub fn hms(hr: u32, min: u32, sec: u32) !@This() {
    return hmsNano(hr, min, sec, 0);
}

pub fn hmsNano(hr: u32, min: u32, sec: u32, nano: u32) !@This() {
    if (hr >= MAX_HOURS or min >= min_per_hour or sec >= std.time.s_per_min or nano >= MAX_FRAC) {
        return error.InvalidTime;
    }
    return Time{
        .secs = @as(SecsInt, @intCast(hr * std.time.s_per_hour + min * std.time.s_per_min + sec)),
        .frac = @as(FracInt, @intCast(nano)),
    };
}

pub fn hour(this: @This()) HoursInt {
    const mins = this.secs / std.time.s_per_min;
    const hr = mins / min_per_hour;
    return @as(HoursInt, @intCast(hr));
}

pub fn withHour(this: @This(), hr: HoursInt) !@This() {
    if (hr >= MAX_HOURS) {
        return error.InvalidTime;
    }
    const secs = @as(u32, @intCast(hr)) * s_per_hour + @as(u32, @intCast(this.secs)) % s_per_hour;
    return @This(){
        .secs = @as(SecsInt, @intCast(secs)),
        .frac = this.frac,
    };
}

pub fn minute(this: @This()) MinutesInt {
    const mins = this.secs / std.time.s_per_min;
    const min = mins % min_per_hour;
    return @as(MinutesInt, @intCast(min));
}

pub fn withMinute(this: @This(), min: MinutesInt) !@This() {
    if (min >= min_per_hour) {
        return error.InvalidTime;
    }
    const secs = (@as(u32, @intCast(this.secs)) / s_per_hour * s_per_hour) + (@as(u32, @intCast(min)) * s_per_min) + (this.secs % s_per_min);
    return @This(){
        .secs = @as(SecsInt, @intCast(secs)),
        .frac = this.frac,
    };
}

pub fn second(this: @This()) SecondsInt {
    return @as(SecondsInt, @intCast(this.secs % (s_per_min)));
}

pub fn withSecond(this: @This(), sec: SecondsInt) !@This() {
    if (sec >= s_per_min) {
        return error.InvalidTime;
    }
    const secs = @as(u32, @intCast(this.secs)) / s_per_min * s_per_min + sec;
    return @This(){
        .secs = @as(SecsInt, @intCast(secs)),
        .frac = this.frac,
    };
}

pub fn fromNumSecondsFromMidnight(secs: u32, nano: u32) !@This() {
    if (secs >= std.time.s_per_day or nano >= MAX_FRAC) {
        return error.InvalidTime;
    }
    return @This(){ .secs = @as(SecsInt, @intCast(secs)), .frac = @as(FracInt, @intCast(nano)) };
}

pub fn signedDurationSince(this: @This(), other: @This()) i64 {
    const secs = @as(i64, @intCast(this.secs)) - @as(i64, @intCast(other.secs));
    // TODO: Return some kind of duration that includes nanoseconds
    //const frac = @intCast(i64, this.frac) - @intCast(i64, other.frac);

    const adjust = if (this.secs > other.secs) gt: {
        if (other.frac >= 1_000_000_000) {
            break :gt @as(i64, 1);
        } else {
            break :gt @as(i64, 0);
        }
    } else if (this.secs < other.secs) lt: {
        if (other.frac >= 1_000_000_000) {
            break :lt @as(i64, -1);
        } else {
            break :lt @as(i64, 0);
        }
    } else eq: {
        break :eq @as(i64, 0);
    };

    return secs + adjust;
}

pub fn format(
    this: @This(),
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = fmt;
    _ = options;

    try std.fmt.format(writer, "{:0>2}:{:0>2}:{:0>2}", .{ this.hour(), this.minute(), this.second() });
}

pub const MAX_HOURS = 24;

pub const HoursInt = @Type(.{
    .Int = .{
        .bits = std.math.log2_int_ceil(u64, MAX_HOURS),
        .signedness = .unsigned,
    },
});

pub const MinutesInt = @Type(.{
    .Int = .{
        .bits = std.math.log2_int_ceil(u64, min_per_hour),
        .signedness = .unsigned,
    },
});

pub const SecondsInt = @Type(.{
    .Int = .{
        .bits = std.math.log2_int_ceil(u64, s_per_min),
        .signedness = .unsigned,
    },
});

/// The number of seconds in a day
pub const SECONDS_PER_DAY = MAX_HOURS * std.time.s_per_hour;
pub const SecsInt = @Type(.{
    .Int = .{
        .bits = std.math.log2_int_ceil(u64, SECONDS_PER_DAY),
        .signedness = .unsigned,
    },
});

/// Frac can be up to two seconds to represent leap seconds
pub const MAX_FRAC = 2 * std.time.ns_per_s;
pub const FracInt = @Type(.{
    .Int = .{
        .bits = std.math.log2_int_ceil(u64, MAX_FRAC),
        .signedness = .unsigned,
    },
});

test "time hour, minute, second" {
    try std.testing.expectEqual(@as(HoursInt, 3), (try Time.hms(3, 5, 7)).hour());
    try std.testing.expectEqual((try Time.hms(0, 5, 7)), (try (try Time.hms(3, 5, 7)).withHour(0)));
    try std.testing.expectEqual((try Time.hms(23, 5, 7)), (try (try Time.hms(3, 5, 7)).withHour(23)));
    try std.testing.expectError(error.InvalidTime, (try Time.hms(3, 5, 7)).withHour(24));
    try std.testing.expectError(error.InvalidTime, (try Time.hms(3, 5, 7)).withHour(std.math.maxInt(HoursInt)));

    try std.testing.expectEqual(@as(MinutesInt, 5), (try Time.hms(3, 5, 7)).minute());
    try std.testing.expectEqual((try Time.hms(3, 0, 7)), try (try Time.hms(3, 5, 7)).withMinute(0));
    try std.testing.expectEqual((try Time.hms(3, 59, 7)), try (try Time.hms(3, 5, 7)).withMinute(59));
    try std.testing.expectError(error.InvalidTime, (try Time.hms(3, 5, 7)).withMinute(60));
    try std.testing.expectError(error.InvalidTime, (try Time.hms(3, 5, 7)).withMinute(std.math.maxInt(MinutesInt)));

    try std.testing.expectEqual(@as(MinutesInt, 7), (try Time.hms(3, 5, 7)).second());
    try std.testing.expectEqual((try Time.hms(3, 5, 0)), try (try Time.hms(3, 5, 7)).withSecond(0));
    try std.testing.expectEqual((try Time.hms(3, 5, 59)), try (try Time.hms(3, 5, 7)).withSecond(59));
    try std.testing.expectError(error.InvalidTime, (try Time.hms(3, 5, 7)).withSecond(60));
    try std.testing.expectError(error.InvalidTime, (try Time.hms(3, 5, 7)).withSecond(std.math.maxInt(MinutesInt)));
}

test "time signed duration since" {
    try std.testing.expectEqual(@as(i64, 3600), (try hms(23, 0, 0)).signedDurationSince((try hms(22, 0, 0))));
    try std.testing.expectEqual(@as(i64, 79_200), (try hms(22, 0, 0)).signedDurationSince((try hms(0, 0, 0))));
}

const min_per_hour = std.time.s_per_hour / std.time.s_per_min;
const s_per_hour = std.time.s_per_hour;
const s_per_min = std.time.s_per_min;

const std = @import("std");
