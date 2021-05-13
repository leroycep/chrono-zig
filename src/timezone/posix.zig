const std = @import("std");
const hhmmss_offset_to_s = @import("./util.zig").hhmmss_offset_to_s;
const testing = std.testing;

/// This is based on Posix definition of the TZ environment variable
pub const TZ = struct {
    std: []const u8,
    std_offset: i32,
    dst: ?[]const u8 = null,
    /// This field is ignored when dst is null
    dst_offset: i32 = 0,
    dst_range: ?Range = null,

    pub const Range = struct {
        start: Rule,
        end: Rule,
    };

    pub const Rule = union(enum) {
        JulianDay: struct {
            /// 1 <= day <= 365. Leap days are not counted and are impossible to refer to
            /// 0 <= day <= 365. Leap days are counted, and can be referred to.
            oneBased: bool,
            day: u16,
            time: i32,
        },
        MonthWeekDay: struct {
            /// 1 <= m <= 12
            m: u8,
            /// 1 <= n <= 5
            n: u8,
            /// 0 <= n <= 6
            d: u8,
            time: i32,
        },

        pub fn toSecs(this: @This(), year: i32) i64 {
            var is_leap: bool = undefined;
            var t = year_to_secs(year, &is_leap);

            switch (this) {
                .JulianDay => |j| {
                    var x: i64 = j.day;
                    if (j.oneBased and (x < 60 or !is_leap)) x -= 1;
                    t += std.time.s_per_day * x;
                    t += j.time;
                },
                .MonthWeekDay => |mwd| {
                    t += month_to_secs(mwd.m - 1, is_leap);
                    const wday = @divFloor(@mod((t + 4 * std.time.s_per_day), (7 * std.time.s_per_day)), std.time.s_per_day);
                    var days = mwd.d - wday;
                    if (days < 0) days += 7;
                    var n = mwd.n;
                    if (mwd.n == 5 and days + 28 >= days_in_month(mwd.m, is_leap)) n = 4;
                    t += std.time.s_per_day * (days + 7 * (n - 1));
                    t += mwd.time;
                },
            }
            return t;
        }
    };

    pub const OffsetResult = struct {
        offset: i32,
        designation: []const u8,
        dst: bool,
    };

    pub fn offset(this: @This(), utc: i64) OffsetResult {
        if (this.dst == null) {
            std.debug.assert(this.dst_range == null);
            return .{ .offset = this.std_offset, .designation = this.std, .dst = false };
        }
        if (this.dst_range) |range| {
            const utc_year = secs_to_year(utc);
            const start_dst = range.start.toSecs(utc_year);
            const end_dst = range.end.toSecs(utc_year);
            if (start_dst < end_dst) {
                if (utc >= start_dst and utc < end_dst) {
                    return .{ .offset = this.dst_offset, .designation = this.dst.?, .dst = true };
                } else {
                    return .{ .offset = this.std_offset, .designation = this.std, .dst = false };
                }
            } else {
                if (utc >= end_dst and utc < start_dst) {
                    return .{ .offset = this.dst_offset, .designation = this.dst.?, .dst = true };
                } else {
                    return .{ .offset = this.std_offset, .designation = this.std, .dst = false };
                }
            }
        } else {
            return .{ .offset = this.std_offset, .designation = this.std, .dst = false };
        }
    }
};

fn days_in_month(m: u8, is_leap: bool) i32 {
    if (m == 2) {
        return 28 + @as(i32, @boolToInt(is_leap));
    } else {
        return 30 + ((@as(i32, 0xad5) >> @intCast(u5, m - 1)) & 1);
    }
}

fn month_to_secs(m: u8, is_leap: bool) i32 {
    const d = std.time.s_per_day;
    const secs_though_month = [12]i32{
        0 * d,   31 * d,  59 * d,  90 * d,
        120 * d, 151 * d, 181 * d, 212 * d,
        243 * d, 273 * d, 304 * d, 334 * d,
    };
    var t = secs_though_month[m];
    if (is_leap and m >= 2) t += d;
    return t;
}

fn secs_to_year(secs: i64) i32 {
    // Copied from MUSL
    // TODO: make more efficient?
    var _is_leap: bool = undefined;
    var y = @intCast(i32, @divFloor(secs, 31556952) + 70);
    while (year_to_secs(y, &_is_leap) > secs) y -= 1;
    while (year_to_secs(y + 1, &_is_leap) < secs) y += 1;
    return y;
}

fn year_to_secs(year: i32, is_leap: *bool) i64 {
    if (year - 2 <= 136) {
        const y = year;
        var leaps = (y - 68) >> 2;
        if (((y - 68) & 3) != 0) {
            leaps -= 1;
            is_leap.* = true;
        } else is_leap.* = false;
        return 31536000 * (y - 70) + std.time.s_per_day * leaps;
    }

    is_leap.* = false;
    var centuries: i64 = undefined;
    var leaps: i64 = undefined;
    var cycles = @divFloor((year - 100), 400);
    var rem = @mod((year - 100), 400);
    if (rem < 0) {
        cycles -= 1;
        rem += 400;
    }
    if (rem != 0) {
        is_leap.* = true;
        centuries = 0;
        leaps = 0;
    } else {
        if (rem >= 200) {
            if (rem >= 300) {
                centuries = 3;
                rem -= 300;
            } else {
                centuries = 2;
                rem -= 200;
            }
        } else {
            if (rem >= 100) {
                centuries = 1;
                rem -= 100;
            } else {
                centuries = 0;
            }
        }
        if (rem != 0) {
            is_leap.* = false;
            leaps = 0;
        } else {
            leaps = @divFloor(rem, 4);
            rem = @mod(rem, 4);
            is_leap.* = rem != 0;
        }
    }

    leaps += 97 * cycles + 24 * centuries - @boolToInt(is_leap.*);

    return (year - 100) * 31536000 + leaps * std.time.s_per_day + 946684800 + std.time.s_per_day;
}

fn parse_rule(_string: []const u8) !TZ.Rule {
    var string = _string;
    if (string.len < 2) return error.InvalidFormat;

    const time: i32 = if (std.mem.indexOf(u8, string, "/")) |start_of_time| parse_time: {
        var _i: usize = 0;
        // This is ugly, should stick with one unit or the other for hhmmss offsets
        const time = try hhmmss_offset_to_s(string[start_of_time + 1 ..], &_i);
        string = string[0..start_of_time];
        break :parse_time time;
    } else 2 * std.time.s_per_hour;

    if (string[0] == 'J') {
        const julian_day1 = try std.fmt.parseInt(u16, string[1..], 10);
        if (julian_day1 < 1 or julian_day1 > 365) return error.InvalidFormat;
        return TZ.Rule{ .JulianDay = .{ .oneBased = true, .day = julian_day1, .time = time } };
    } else if (std.ascii.isDigit(string[0])) {
        const julian_day0 = try std.fmt.parseInt(u16, string[0..], 10);
        if (julian_day0 > 365) return error.InvalidFormat;
        return TZ.Rule{ .JulianDay = .{ .oneBased = false, .day = julian_day0, .time = time } };
    } else if (string[0] == 'M') {
        var split_iter = std.mem.split(string[1..], ".");
        const m_str = split_iter.next() orelse return error.InvalidFormat;
        const n_str = split_iter.next() orelse return error.InvalidFormat;
        const d_str = split_iter.next() orelse return error.InvalidFormat;

        const m = try std.fmt.parseInt(u8, m_str, 10);
        const n = try std.fmt.parseInt(u8, n_str, 10);
        const d = try std.fmt.parseInt(u8, d_str, 10);

        if (m < 1 or m > 12) return error.InvalidFormat;
        if (n < 1 or n > 5) return error.InvalidFormat;
        if (d > 6) return error.InvalidFormat;

        return TZ.Rule{ .MonthWeekDay = .{ .m = m, .n = n, .d = d, .time = time } };
    } else {
        return error.InvalidFormat;
    }
}

fn parse_designation(string: []const u8, idx: *usize) ![]const u8 {
    var quoted = string[idx.*] == '<';
    if (quoted) idx.* += 1;
    var start = idx.*;
    while (idx.* < string.len) : (idx.* += 1) {
        if ((quoted and string[idx.*] == '>') or
            (!quoted and !std.ascii.isAlpha(string[idx.*])))
        {
            const designation = string[start..idx.*];
            if (quoted) idx.* += 1;
            return designation;
        }
    }
    return error.InvalidFormat;
}

pub fn parse(string: []const u8) !TZ {
    var result = TZ{ .std = undefined, .std_offset = undefined };
    var idx: usize = 0;

    result.std = try parse_designation(string, &idx);

    result.std_offset = try hhmmss_offset_to_s(string[idx..], &idx);
    if (idx >= string.len) {
        return result;
    }

    if (string[idx] != ',') {
        result.dst = try parse_designation(string, &idx);

        if (idx < string.len and string[idx] != ',') {
            result.dst_offset = try hhmmss_offset_to_s(string[idx..], &idx);
        } else {
            result.dst_offset = result.std_offset + std.time.s_per_hour;
        }

        if (idx >= string.len) {
            return result;
        }
    }

    std.debug.assert(string[idx] == ',');
    idx += 1;

    if (std.mem.indexOf(u8, string[idx..], ",")) |_end_of_start_rule| {
        const end_of_start_rule = idx + _end_of_start_rule;
        result.dst_range = .{
            .start = try parse_rule(string[idx..end_of_start_rule]),
            .end = try parse_rule(string[end_of_start_rule + 1 ..]),
        };
    } else {
        return error.InvalidFormat;
    }

    return result;
}

test "posix TZ string" {
    const result = try parse("MST7MDT,M3.2.0,M11.1.0");

    try testing.expectEqualSlices(u8, "MST", result.std);
    try testing.expectEqual(@as(i32, 25200), result.std_offset);
    try testing.expectEqualSlices(u8, "MDT", result.dst.?);
    try testing.expectEqual(@as(i32, 28800), result.dst_offset);
    try testing.expectEqual(TZ.Rule{ .MonthWeekDay = .{ .m = 3, .n = 2, .d = 0, .time = 2 * std.time.s_per_hour } }, result.dst_range.?.start);
    try testing.expectEqual(TZ.Rule{ .MonthWeekDay = .{ .m = 11, .n = 1, .d = 0, .time = 2 * std.time.s_per_hour } }, result.dst_range.?.end);

    try testing.expectEqual(@as(i32, 25200), result.offset(1612734960).offset);
    try testing.expectEqual(@as(i32, 25200), result.offset(1615712399 - 7 * std.time.s_per_hour).offset);
    try testing.expectEqual(@as(i32, 28800), result.offset(1615712400 - 7 * std.time.s_per_hour).offset);
    try testing.expectEqual(@as(i32, 28800), result.offset(1620453601).offset);
    try testing.expectEqual(@as(i32, 28800), result.offset(1636275599 - 7 * std.time.s_per_hour).offset);
    try testing.expectEqual(@as(i32, 25200), result.offset(1636275600 - 7 * std.time.s_per_hour).offset);
}
