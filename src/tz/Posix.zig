///! This is based on Posix definition of the TZ environment variable
std_designation: []const u8,
std_offset: i32,
dst_designation: ?[]const u8 = null,
/// This field is ignored when dst is null
dst_offset: i32 = 0,
dst_range: ?struct {
    start: Rule,
    end: Rule,
} = null,

pub const Rule = union(enum) {
    JulianDay: struct {
        /// 1 <= day <= 365. Leap days are not counted and are impossible to refer to
        day: u16,
        /// The default DST transition time is 02:00:00 local time
        time: chrono.duration.HoursMinutesSeconds = chrono.duration.HoursMinutesSeconds.new(2, 0, 0),
    },
    JulianDayZero: struct {
        /// 0 <= day <= 365. Leap days are counted, and can be referred to.
        day: u16,
        /// The default DST transition time is 02:00:00 local time
        time: chrono.duration.HoursMinutesSeconds = chrono.duration.HoursMinutesSeconds.new(2, 0, 0),
    },
    /// In the format of "Mm.n.d", where m = month, n = n, and d = day.
    MonthNthWeekday: struct {
        /// Month of the year. 1 <= month <= 12
        month: chrono.date.Month,
        /// Specifies which of the weekdays should be used. Does NOT specify the week of the month! 1 <= week <= 5.
        ///
        /// Let's use M3.2.0 as an example. The month is 3, which translates to March.
        /// The day is 0, which means Sunday. `n` is 2, which means the second Sunday
        /// in the month, NOT Sunday of the second week!
        ///
        /// In 2021, this is difference between 2023-03-07 (Sunday of the second week of March)
        /// and 2023-03-14 (the Second Sunday of March).
        ///
        /// * When n is 1, it means the first week in which the day `day` occurs.
        /// * 5 is a special case. When n is 5, it means "the last day `day` in the month", which may occur in either the fourth or the fifth week.
        n: u8,
        weekday: chrono.date.Weekday,
        /// The default DST transition time is 02:00:00 local time
        time: chrono.duration.HoursMinutesSeconds = chrono.duration.HoursMinutesSeconds.new(2, 0, 0),
    },

    pub fn isAtStartOfYear(this: @This()) bool {
        switch (this) {
            .JulianDay => |j| return j.day == 1 and j.time.toSeconds() == 0,
            .JulianDayZero => |j| return j.day == 0 and j.time.toSeconds() == 0,
            .MonthNthWeekday => |mwd| return mwd.month == .jan and mwd.n == 1 and mwd.weekday == .sun and mwd.time.toSeconds() == 0,
        }
    }

    pub fn isAtEndOfYear(this: @This()) bool {
        switch (this) {
            .JulianDay => |j| return j.day == 365 and j.time.toSeconds() >= 24,
            // Since JulianDayZero dates account for leap year, it would vary depending on the year.
            .JulianDayZero => return false,
            // There is also no way to specify "end of the year" with MonthNthWeekday rules
            .MonthNthWeekday => return false,
        }
    }

    /// Returned value is the local timestamp when the timezone will transition in the given year.
    pub fn toTimestamp(this: @This(), year: i32) i64 {
        const is_leap: bool = chrono.date.isLeapYear(year);
        const start_of_year = chrono.date.YearMonthDay.fromNumbers(@intCast(year), 1, 1).toDaysSinceUnixEpoch();

        // how many days into the year does the rule say the transition is?
        const day_of_year = switch (this) {
            .JulianDay => |j| if (j.day < 60 or !is_leap) j.day - 1 else j.day,
            .JulianDayZero => |j| j.day,
            .MonthNthWeekday => |mwd| calculate_days_since_start_of_year: {
                const first_day_of_year_in_month = if (@intFromEnum(mwd.month) <= @intFromEnum(chrono.date.Month.feb) or !is_leap)
                    chrono.date.Month.FIRST_DAY_OF_COMMON_YEAR[@intFromEnum(mwd.month) - 1]
                else
                    chrono.date.Month.FIRST_DAY_OF_LEAP_YEAR[@intFromEnum(mwd.month) - 1];

                const days_since_epoch = start_of_year + first_day_of_year_in_month;
                const first_weekday_of_month = chrono.date.Weekday.fromDaysSinceUnixEpoch(days_since_epoch);

                const weekday_offset_for_month = mwd.weekday.difference(first_weekday_of_month);

                const DAYS_PER_WEEK: u9 = chrono.date.WEEKDAYS.len;
                const days_since_start_of_month = switch (mwd.n) {
                    1...4 => |n| (n - 1) * DAYS_PER_WEEK + weekday_offset_for_month,
                    5 => if (weekday_offset_for_month + (4 * DAYS_PER_WEEK) >= mwd.month.lastDay(year))
                        // the last matching weekday is during the 4th week of the month
                        (4 - 1) * DAYS_PER_WEEK + weekday_offset_for_month
                    else
                        // the last matching weekday is during the 5th week of the month
                        (5 - 1) * DAYS_PER_WEEK + weekday_offset_for_month,
                    else => unreachable,
                };
                break :calculate_days_since_start_of_year first_day_of_year_in_month + days_since_start_of_month;
            },
        };

        const time = switch (this) {
            inline else => |r| r.time,
        };

        return (@as(i64, start_of_year) + day_of_year) * std.time.s_per_day + time.toSeconds();
    }

    test "M3.2.0/01:30 toTimestamp" {
        // Transition times with minutes and seconds
        const rule = @This(){
            .MonthNthWeekday = .{
                .month = .mar,
                .n = 2,
                .weekday = .sun,
                .time = chrono.duration.HoursMinutesSeconds.new(1, 30, 0),
            },
        };
        try testing.expectEqual(@as(i64, 1331429400), rule.toTimestamp(2012)); // 2012-03-11T01:00:00-03:00
    }

    pub fn format(
        this: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        switch (this) {
            .JulianDay => |julian_day| {
                try std.fmt.format(writer, "J{}", .{julian_day.day});
            },
            .JulianDayZero => |julian_day_zero| {
                try std.fmt.format(writer, "{}", .{julian_day_zero.day});
            },
            .MonthNthWeekday => |month_week_day| {
                try std.fmt.format(writer, "M{}.{}.{}", .{
                    @intFromEnum(month_week_day.month),
                    month_week_day.n,
                    month_week_day.weekday.toIntSun0(),
                });
            },
        }

        const time = switch (this) {
            inline else => |rule| rule.time.toSeconds(),
        };

        // Only write out the time if it is not the default time of 02:00
        if (time != 2 * std.time.s_per_hour) {
            const seconds = @mod(time, std.time.s_per_min);
            const minutes = @mod(@divTrunc(time, std.time.s_per_min), 60);
            const hours = @divTrunc(@divTrunc(time, std.time.s_per_min), 60);

            try std.fmt.format(writer, "/{}", .{hours});
            if (minutes != 0 or seconds != 0) {
                try std.fmt.format(writer, ":{}", .{minutes});
            }
            if (seconds != 0) {
                try std.fmt.format(writer, ":{}", .{seconds});
            }
        }
    }
};

pub const TIMEZONE_VTABLE = chrono.tz.TimeZone.VTable.eraseTypes(@This(), .{
    .offsetAtTimestamp = offsetAtTimestamp,
});

pub fn timeZone(this: *const @This()) chrono.tz.TimeZone {
    return chrono.tz.TimeZone{
        .ptr = this,
        .vtable = &TIMEZONE_VTABLE,
    };
}

/// Get the offset from UTC for this TZ, factoring in Daylight Saving Time.
pub fn offsetAtTimestamp(this: *const @This(), timestamp: i64) ?chrono.tz.TimeZone.Offset {
    const dst_designation = this.dst_designation orelse {
        std.debug.assert(this.dst_range == null);
        return .{ .offset = this.std_offset, .designation = this.std_designation, .is_daylight_saving_time = false };
    };
    if (this.dst_range) |range| {
        const ymd = chrono.date.YearMonthDay.fromDaysSinceUnixEpoch(@intCast(@divFloor(timestamp, std.time.s_per_day)));
        const start_dst = range.start.toTimestamp(ymd.year) - this.std_offset;
        const end_dst = range.end.toTimestamp(ymd.year) - this.dst_offset;

        const is_dst_all_year = range.start.isAtStartOfYear() and range.end.isAtEndOfYear();
        if (is_dst_all_year) {
            return .{ .offset = this.dst_offset, .designation = dst_designation, .is_daylight_saving_time = true };
        }

        if (start_dst < end_dst) {
            if (timestamp >= start_dst and timestamp < end_dst) {
                return .{ .offset = this.dst_offset, .designation = dst_designation, .is_daylight_saving_time = true };
            } else {
                return .{ .offset = this.std_offset, .designation = this.std_designation, .is_daylight_saving_time = false };
            }
        } else {
            if (timestamp >= end_dst and timestamp < start_dst) {
                return .{ .offset = this.std_offset, .designation = this.std_designation, .is_daylight_saving_time = false };
            } else {
                return .{ .offset = this.dst_offset, .designation = dst_designation, .is_daylight_saving_time = true };
            }
        }
    } else {
        return .{ .offset = this.std_offset, .designation = this.std_designation, .is_daylight_saving_time = false };
    }
}

pub fn format(
    this: @This(),
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = fmt;
    _ = options;

    const should_quote_std_designation = for (this.std_designation) |character| {
        if (!std.ascii.isAlphabetic(character)) {
            break true;
        }
    } else false;

    if (should_quote_std_designation) {
        try writer.writeAll("<");
        try writer.writeAll(this.std_designation);
        try writer.writeAll(">");
    } else {
        try writer.writeAll(this.std_designation);
    }

    const std_offset_west = -this.std_offset;
    const std_seconds = @rem(std_offset_west, std.time.s_per_min);
    const std_minutes = @rem(@divTrunc(std_offset_west, std.time.s_per_min), 60);
    const std_hours = @divTrunc(@divTrunc(std_offset_west, std.time.s_per_min), 60);

    try std.fmt.format(writer, "{}", .{std_hours});
    if (std_minutes != 0 or std_seconds != 0) {
        try std.fmt.format(writer, ":{}", .{if (std_minutes < 0) -std_minutes else std_minutes});
    }
    if (std_seconds != 0) {
        try std.fmt.format(writer, ":{}", .{if (std_seconds < 0) -std_seconds else std_seconds});
    }

    if (this.dst_designation) |dst_designation| {
        const should_quote_dst_designation = for (dst_designation) |character| {
            if (!std.ascii.isAlphabetic(character)) {
                break true;
            }
        } else false;

        if (should_quote_dst_designation) {
            try writer.writeAll("<");
            try writer.writeAll(dst_designation);
            try writer.writeAll(">");
        } else {
            try writer.writeAll(dst_designation);
        }

        // Only write out the DST offset if it is not just the standard offset plus an hour
        if (this.dst_offset != this.std_offset + std.time.s_per_hour) {
            const dst_offset_west = -this.dst_offset;
            const dst_seconds = @rem(dst_offset_west, std.time.s_per_min);
            const dst_minutes = @rem(@divTrunc(dst_offset_west, std.time.s_per_min), 60);
            const dst_hours = @divTrunc(@divTrunc(dst_offset_west, std.time.s_per_min), 60);

            try std.fmt.format(writer, "{}", .{dst_hours});
            if (dst_minutes != 0 or dst_seconds != 0) {
                try std.fmt.format(writer, ":{}", .{if (dst_minutes < 0) -dst_minutes else dst_minutes});
            }
            if (dst_seconds != 0) {
                try std.fmt.format(writer, ":{}", .{if (dst_seconds < 0) -dst_seconds else dst_seconds});
            }
        }
    }

    if (this.dst_range) |dst_range| {
        try std.fmt.format(writer, ",{},{}", .{ dst_range.start, dst_range.end });
    }
}

const TZ = @This();

test format {
    const america_denver = TZ{
        .std_designation = "MST",
        .std_offset = -25200,
        .dst_designation = "MDT",
        .dst_offset = -21600,
        .dst_range = .{
            .start = .{
                .MonthNthWeekday = .{
                    .month = .mar,
                    .n = 2,
                    .weekday = .sun,
                    .time = chrono.duration.HoursMinutesSeconds.new(2, 0, 0),
                },
            },
            .end = .{
                .MonthNthWeekday = .{
                    .month = .nov,
                    .n = 1,
                    .weekday = .sun,
                    .time = chrono.duration.HoursMinutesSeconds.new(2, 0, 0),
                },
            },
        },
    };

    try std.testing.expectFmt("MST7MDT,M3.2.0,M11.1.0", "{}", .{america_denver});

    const europe_berlin = TZ{
        .std_designation = "CET",
        .std_offset = 3600,
        .dst_designation = "CEST",
        .dst_offset = 7200,
        .dst_range = .{
            .start = .{
                .MonthNthWeekday = .{
                    .month = .mar,
                    .n = 5,
                    .weekday = .sun,
                    .time = chrono.duration.HoursMinutesSeconds.new(2, 0, 0),
                },
            },
            .end = .{
                .MonthNthWeekday = .{
                    .month = .oct,
                    .n = 5,
                    .weekday = .sun,
                    .time = chrono.duration.HoursMinutesSeconds.new(3, 0, 0),
                },
            },
        },
    };
    try std.testing.expectFmt("CET-1CEST,M3.5.0,M10.5.0/3", "{}", .{europe_berlin});

    const antarctica_syowa = TZ{
        .std_designation = "+03",
        .std_offset = 3 * std.time.s_per_hour,
        .dst_designation = null,
        .dst_offset = undefined,
        .dst_range = null,
    };
    try std.testing.expectFmt("<+03>-3", "{}", .{antarctica_syowa});

    const pacific_chatham = TZ{
        .std_designation = "+1245",
        .std_offset = 12 * std.time.s_per_hour + 45 * std.time.s_per_min,
        .dst_designation = "+1345",
        .dst_offset = 13 * std.time.s_per_hour + 45 * std.time.s_per_min,
        .dst_range = .{
            .start = .{
                .MonthNthWeekday = .{
                    .month = .sep,
                    .n = 5,
                    .weekday = .sun,
                    .time = chrono.duration.HoursMinutesSeconds.new(2, 45, 0),
                },
            },
            .end = .{
                .MonthNthWeekday = .{
                    .month = .apr,
                    .n = 1,
                    .weekday = .sun,
                    .time = chrono.duration.HoursMinutesSeconds.new(3, 45, 0),
                },
            },
        },
    };
    try std.testing.expectFmt("<+1245>-12:45<+1345>,M9.5.0/2:45,M4.1.0/3:45", "{}", .{pacific_chatham});
}

fn parseRule(_string: []const u8) !Rule {
    var string = _string;
    if (string.len < 2) return error.InvalidFormat;

    const time: chrono.duration.HoursMinutesSeconds = if (std.mem.indexOf(u8, string, "/")) |start_of_time| parse_time: {
        const time_string = string[start_of_time + 1 ..];

        // The time at the end of the rule should be the last thing in the string. Fixes the parsing to return
        // an error in cases like "/2/3", where they have some extra characters.
        for (time_string) |c| {
            if (!(std.ascii.isDigit(c) or c == ':' or c == '-' or c == '+')) {
                return error.InvalidFormat;
            }
        }

        const time = try chrono.duration.HoursMinutesSeconds.parse(time_string, null);

        // Posix only allows +/- 24 hours, but GNU allows +/- 167 hours
        if (time.hours > 167) {
            return error.InvalidFormat;
        }

        string = string[0..start_of_time];

        break :parse_time time;
    } else chrono.duration.HoursMinutesSeconds.new(2, 0, 0);

    if (string[0] == 'J') {
        const julian_day1 = std.fmt.parseInt(u16, string[1..], 10) catch |err| switch (err) {
            error.InvalidCharacter => return error.InvalidFormat,
            error.Overflow => return error.InvalidFormat,
        };

        if (julian_day1 < 1 or julian_day1 > 365) return error.InvalidFormat;
        return TZ.Rule{ .JulianDay = .{ .day = julian_day1, .time = time } };
    } else if (std.ascii.isDigit(string[0])) {
        const julian_day0 = std.fmt.parseInt(u16, string[0..], 10) catch |err| switch (err) {
            error.InvalidCharacter => return error.InvalidFormat,
            error.Overflow => return error.InvalidFormat,
        };

        if (julian_day0 > 365) return error.InvalidFormat;
        return TZ.Rule{ .JulianDayZero = .{ .day = julian_day0, .time = time } };
    } else if (string[0] == 'M') {
        var split_iter = std.mem.split(u8, string[1..], ".");
        const m_str = split_iter.next() orelse return error.InvalidFormat;
        const n_str = split_iter.next() orelse return error.InvalidFormat;
        const d_str = split_iter.next() orelse return error.InvalidFormat;

        const m = std.fmt.parseInt(u8, m_str, 10) catch |err| switch (err) {
            error.InvalidCharacter => return error.InvalidFormat,
            error.Overflow => return error.InvalidFormat,
        };
        const n = std.fmt.parseInt(u8, n_str, 10) catch |err| switch (err) {
            error.InvalidCharacter => return error.InvalidFormat,
            error.Overflow => return error.InvalidFormat,
        };
        const d = std.fmt.parseInt(u3, d_str, 10) catch |err| switch (err) {
            error.InvalidCharacter => return error.InvalidFormat,
            error.Overflow => return error.InvalidFormat,
        };

        if (m < 1 or m > 12) return error.InvalidFormat;
        if (n < 1 or n > 5) return error.InvalidFormat;
        if (d > 6) return error.InvalidFormat;

        return TZ.Rule{ .MonthNthWeekday = .{
            .month = @enumFromInt(m),
            .n = n,
            .weekday = chrono.date.Weekday.fromIntSun0(d),
            .time = time,
        } };
    } else {
        return error.InvalidFormat;
    }
}

fn parseDesignation(string: []const u8, idx: *usize) ![]const u8 {
    const quoted = string[idx.*] == '<';
    if (quoted) idx.* += 1;
    const start = idx.*;
    while (idx.* < string.len) : (idx.* += 1) {
        if ((quoted and string[idx.*] == '>') or
            (!quoted and !std.ascii.isAlphabetic(string[idx.*])))
        {
            const designation = string[start..idx.*];

            // The designation must be at least one character long!
            if (designation.len == 0) return error.InvalidFormat;

            if (quoted) idx.* += 1;
            return designation;
        }
    }
    return error.InvalidFormat;
}

pub fn parse(string: []const u8) !TZ {
    var result = TZ{ .std_designation = undefined, .std_offset = undefined };
    var idx: usize = 0;

    result.std_designation = try parseDesignation(string, &idx);

    const end_of_std_offset = for (string[idx..], idx..) |c, i| {
        if (!(std.ascii.isDigit(c) or c == ':' or c == '-' or c == '+')) {
            break i;
        }
    } else string.len;

    // multiply by -1 to get offset as seconds East of Greenwich as TZif specifies it:
    const std_offset_hms = try chrono.duration.HoursMinutesSeconds.parse(string[idx..end_of_std_offset], null);
    if (std_offset_hms.hours > 167) {
        return error.InvalidFormat;
    }
    result.std_offset = @intCast(std_offset_hms.toSeconds() * -1);
    idx = end_of_std_offset;
    if (idx >= string.len) {
        return result;
    }

    if (string[idx] != ',') {
        result.dst_designation = try parseDesignation(string, &idx);

        const end_of_dst_offset = for (string[idx..], idx..) |c, i| {
            if (!(std.ascii.isDigit(c) or c == ':' or c == '-' or c == '+')) {
                break i;
            }
        } else string.len;

        if (idx < string.len and string[idx] != ',') {
            // multiply by -1 to get offset as seconds East of Greenwich as TZif specifies it:
            const dst_offset_hms = try chrono.duration.HoursMinutesSeconds.parse(string[idx..end_of_dst_offset], null);
            if (dst_offset_hms.hours > 167) {
                return error.InvalidFormat;
            }
            result.dst_offset = @intCast(dst_offset_hms.toSeconds() * -1);
            idx = end_of_dst_offset;
        } else {
            result.dst_offset = result.std_offset + std.time.s_per_hour;
        }

        if (idx >= string.len) {
            return result;
        }
    }

    std.debug.assert(string[idx] == ',');
    idx += 1;

    if (std.mem.indexOfScalarPos(u8, string, idx, ',')) |end_of_start_rule| {
        result.dst_range = .{
            .start = try parseRule(string[idx..end_of_start_rule]),
            .end = try parseRule(string[end_of_start_rule + 1 ..]),
        };
    } else {
        return error.InvalidFormat;
    }

    return result;
}

test "posix TZ string, regular year" {
    // IANA identifier America/Denver; default DST transition time at 2 am
    var result = try parse("MST7MDT,M3.2.0,M11.1.0");
    var stdoff: i32 = -25200;
    var dstoff: i32 = -21600;
    try testing.expectEqualSlices(u8, "MST", result.std_designation);
    try testing.expectEqual(stdoff, result.std_offset);
    try testing.expectEqualSlices(u8, "MDT", result.dst_designation.?);
    try testing.expectEqual(dstoff, result.dst_offset);
    try testing.expectEqual(TZ.Rule{ .MonthNthWeekday = .{ .month = .mar, .n = 2, .weekday = .sun, .time = chrono.duration.HoursMinutesSeconds.new(2, 0, 0) } }, result.dst_range.?.start);
    try testing.expectEqual(TZ.Rule{ .MonthNthWeekday = .{ .month = .nov, .n = 1, .weekday = .sun, .time = chrono.duration.HoursMinutesSeconds.new(2, 0, 0) } }, result.dst_range.?.end);
    try testing.expectEqual(stdoff, result.offsetAtTimestamp(1612734960).?.offset);
    // 2021-03-14T01:59:59-07:00 (2nd Sunday of the 3rd month, MST)
    try testing.expectEqual(stdoff, result.offsetAtTimestamp(1615712399).?.offset);
    // 2021-03-14T02:00:00-07:00 (2nd Sunday of the 3rd month, MST)
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1615712400).?.offset);
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1620453601).?.offset);
    // 2021-11-07T01:59:59-06:00 (1st Sunday of the 11th month, MDT)
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1636271999).?.offset);
    // 2021-11-07T02:00:00-06:00 (1st Sunday of the 11th month, MDT)
    try testing.expectEqual(stdoff, result.offsetAtTimestamp(1636272000).?.offset);

    // IANA identifier: Europe/Berlin
    result = try parse("CET-1CEST,M3.5.0,M10.5.0/3");
    stdoff = 3600;
    dstoff = 7200;
    try testing.expectEqualSlices(u8, "CET", result.std_designation);
    try testing.expectEqual(stdoff, result.std_offset);
    try testing.expectEqualSlices(u8, "CEST", result.dst_designation.?);
    try testing.expectEqual(dstoff, result.dst_offset);
    try testing.expectEqual(TZ.Rule{ .MonthNthWeekday = .{ .month = .mar, .n = 5, .weekday = .sun, .time = chrono.duration.HoursMinutesSeconds.new(2, 0, 0) } }, result.dst_range.?.start);
    try testing.expectEqual(TZ.Rule{ .MonthNthWeekday = .{ .month = .oct, .n = 5, .weekday = .sun, .time = chrono.duration.HoursMinutesSeconds.new(3, 0, 0) } }, result.dst_range.?.end);
    // 2023-10-29T00:59:59Z, or 2023-10-29 01:59:59 CEST. Offset should still be CEST.
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1698541199).?.offset);
    // 2023-10-29T01:00:00Z, or 2023-10-29 03:00:00 CEST. Offset should now be CET.
    try testing.expectEqual(stdoff, result.offsetAtTimestamp(1698541200).?.offset);

    // IANA identifier: America/New_York
    result = try parse("EST5EDT,M3.2.0/02:00:00,M11.1.0");
    stdoff = -18000;
    dstoff = -14400;
    try testing.expectEqualSlices(u8, "EST", result.std_designation);
    try testing.expectEqual(stdoff, result.std_offset);
    try testing.expectEqualSlices(u8, "EDT", result.dst_designation.?);
    try testing.expectEqual(dstoff, result.dst_offset);
    // transition std 2023-03-12T01:59:59-05:00 --> dst 2023-03-12T03:00:00-04:00
    try testing.expectEqual(stdoff, result.offsetAtTimestamp(1678604399).?.offset);
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1678604400).?.offset);
    // transition dst 2023-11-05T01:59:59-04:00 --> std 2023-11-05T01:00:00-05:00
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1699163999).?.offset);
    try testing.expectEqual(stdoff, result.offsetAtTimestamp(1699164000).?.offset);

    // IANA identifier: America/New_York
    result = try parse("EST5EDT,M3.2.0/02:00:00,M11.1.0/02:00:00");
    stdoff = -18000;
    dstoff = -14400;
    try testing.expectEqualSlices(u8, "EST", result.std_designation);
    try testing.expectEqual(stdoff, result.std_offset);
    try testing.expectEqualSlices(u8, "EDT", result.dst_designation.?);
    try testing.expectEqual(dstoff, result.dst_offset);
    // transition std 2023-03-12T01:59:59-05:00 --> dst 2023-03-12T03:00:00-04:00
    try testing.expectEqual(stdoff, result.offsetAtTimestamp(1678604399).?.offset);
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1678604400).?.offset);
    // transition dst 2023-11-05T01:59:59-04:00 --> std 2023-11-05T01:00:00-05:00
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1699163999).?.offset);
    try testing.expectEqual(stdoff, result.offsetAtTimestamp(1699164000).?.offset);

    // IANA identifier: America/New_York
    result = try parse("EST5EDT,M3.2.0,M11.1.0/02:00:00");
    stdoff = -18000;
    dstoff = -14400;
    try testing.expectEqualSlices(u8, "EST", result.std_designation);
    try testing.expectEqual(stdoff, result.std_offset);
    try testing.expectEqualSlices(u8, "EDT", result.dst_designation.?);
    try testing.expectEqual(dstoff, result.dst_offset);
    // transition std 2023-03-12T01:59:59-05:00 --> dst 2023-03-12T03:00:00-04:00
    try testing.expectEqual(stdoff, result.offsetAtTimestamp(1678604399).?.offset);
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1678604400).?.offset);
    // transition dst 2023-11-05T01:59:59-04:00 --> std 2023-11-05T01:00:00-05:00
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1699163999).?.offset);
    try testing.expectEqual(stdoff, result.offsetAtTimestamp(1699164000).?.offset);

    // IANA identifier: America/Chicago
    result = try parse("CST6CDT,M3.2.0/2:00:00,M11.1.0/2:00:00");
    stdoff = -21600;
    dstoff = -18000;
    try testing.expectEqualSlices(u8, "CST", result.std_designation);
    try testing.expectEqual(stdoff, result.std_offset);
    try testing.expectEqualSlices(u8, "CDT", result.dst_designation.?);
    try testing.expectEqual(dstoff, result.dst_offset);
    // transition std 2023-03-12T01:59:59-06:00 --> dst 2023-03-12T03:00:00-05:00
    try testing.expectEqual(stdoff, result.offsetAtTimestamp(1678607999).?.offset);
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1678608000).?.offset);
    // transition dst 2023-11-05T01:59:59-05:00 --> std 2023-11-05T01:00:00-06:00
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1699167599).?.offset);
    try testing.expectEqual(stdoff, result.offsetAtTimestamp(1699167600).?.offset);

    // IANA identifier: America/Denver
    result = try parse("MST7MDT,M3.2.0/2:00:00,M11.1.0/2:00:00");
    stdoff = -25200;
    dstoff = -21600;
    try testing.expectEqualSlices(u8, "MST", result.std_designation);
    try testing.expectEqual(stdoff, result.std_offset);
    try testing.expectEqualSlices(u8, "MDT", result.dst_designation.?);
    try testing.expectEqual(dstoff, result.dst_offset);
    // transition std 2023-03-12T01:59:59-07:00 --> dst 2023-03-12T03:00:00-06:00
    try testing.expectEqual(stdoff, result.offsetAtTimestamp(1678611599).?.offset);
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1678611600).?.offset);
    // transition dst 2023-11-05T01:59:59-06:00 --> std 2023-11-05T01:00:00-07:00
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1699171199).?.offset);
    try testing.expectEqual(stdoff, result.offsetAtTimestamp(1699171200).?.offset);

    // IANA identifier: America/Los_Angeles
    result = try parse("PST8PDT,M3.2.0/2:00:00,M11.1.0/2:00:00");
    stdoff = -28800;
    dstoff = -25200;
    try testing.expectEqualSlices(u8, "PST", result.std_designation);
    try testing.expectEqual(stdoff, result.std_offset);
    try testing.expectEqualSlices(u8, "PDT", result.dst_designation.?);
    try testing.expectEqual(dstoff, result.dst_offset);
    // transition std 2023-03-12T01:59:59-08:00 --> dst 2023-03-12T03:00:00-07:00
    try testing.expectEqual(stdoff, result.offsetAtTimestamp(1678615199).?.offset);
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1678615200).?.offset);
    // transition dst 2023-11-05T01:59:59-07:00 --> std 2023-11-05T01:00:00-08:00
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1699174799).?.offset);
    try testing.expectEqual(stdoff, result.offsetAtTimestamp(1699174800).?.offset);

    // IANA identifier: America/Sitka
    result = try parse("AKST9AKDT,M3.2.0,M11.1.0");
    stdoff = -32400;
    dstoff = -28800;
    try testing.expectEqualSlices(u8, "AKST", result.std_designation);
    try testing.expectEqual(stdoff, result.std_offset);
    try testing.expectEqualSlices(u8, "AKDT", result.dst_designation.?);
    try testing.expectEqual(dstoff, result.dst_offset);
    // transition std 2023-03-12T01:59:59-09:00 --> dst 2023-03-12T03:00:00-08:00
    try testing.expectEqual(stdoff, result.offsetAtTimestamp(1678618799).?.offset);
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1678618800).?.offset);
    // transition dst 2023-11-05T01:59:59-08:00 --> std 2023-11-05T01:00:00-09:00
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1699178399).?.offset);
    try testing.expectEqual(stdoff, result.offsetAtTimestamp(1699178400).?.offset);

    // IANA identifier: Asia/Jerusalem
    result = try parse("IST-2IDT,M3.4.4/26,M10.5.0");
    stdoff = 7200;
    dstoff = 10800;
    try testing.expectEqualSlices(u8, "IST", result.std_designation);
    try testing.expectEqual(stdoff, result.std_offset);
    try testing.expectEqualSlices(u8, "IDT", result.dst_designation.?);
    try testing.expectEqual(dstoff, result.dst_offset);
    // transition std 2023-03-24T01:59:59+02:00 --> dst 2023-03-24T03:00:00+03:00
    try testing.expectEqual(stdoff, result.offsetAtTimestamp(1679615999).?.offset);
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1679616000).?.offset);
    // transition dst 2023-10-29T01:59:59+03:00 --> std 2023-10-29T01:00:00+02:00
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1698533999).?.offset);
    try testing.expectEqual(stdoff, result.offsetAtTimestamp(1698534000).?.offset);

    // IANA identifier: America/Argentina/Buenos_Aires
    result = try parse("WART4WARST,J1/0,J365/25"); // TODO : separate tests for jday ?
    stdoff = -10800;
    dstoff = -10800;
    try testing.expectEqualSlices(u8, "WART", result.std_designation);
    try testing.expectEqualSlices(u8, "WARST", result.dst_designation.?);
    // transition std 2023-03-24T01:59:59-03:00 --> dst 2023-03-24T03:00:00-03:00
    try testing.expectEqual(stdoff, result.offsetAtTimestamp(1679633999).?.offset);
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1679637600).?.offset);
    // transition dst 2023-10-29T01:59:59-03:00 --> std 2023-10-29T01:00:00-03:00
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1698555599).?.offset);
    try testing.expectEqual(stdoff, result.offsetAtTimestamp(1698552000).?.offset);

    // IANA identifier: America/Nuuk
    result = try parse("WGT3WGST,M3.5.0/-2,M10.5.0/-1");
    stdoff = -10800;
    dstoff = -7200;
    try testing.expectEqualSlices(u8, "WGT", result.std_designation);
    try testing.expectEqual(stdoff, result.std_offset);
    try testing.expectEqualSlices(u8, "WGST", result.dst_designation.?);
    try testing.expectEqual(dstoff, result.dst_offset);
    // transition std 2021-03-27T21:59:59-03:00 --> dst 2021-03-27T23:00:00-02:00
    try testing.expectEqual(stdoff, result.offsetAtTimestamp(1616893199).?.offset);
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1616893200).?.offset);
    // transition dst 2021-10-30T22:59:59-02:00 --> std 2021-10-30T22:00:00-03:00
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1635641999).?.offset);
    try testing.expectEqual(stdoff, result.offsetAtTimestamp(1635642000).?.offset);
}

test "posix TZ string, leap year, America/New_York, start transition time specified" {
    // IANA identifier: America/New_York
    const result = try parse("EST5EDT,M3.2.0/02:00:00,M11.1.0");
    const stdoff: i32 = -18000;
    const dstoff: i32 = -14400;
    try testing.expectEqualSlices(u8, "EST", result.std_designation);
    try testing.expectEqual(stdoff, result.std_offset);
    try testing.expectEqualSlices(u8, "EDT", result.dst_designation.?);
    try testing.expectEqual(dstoff, result.dst_offset);
    // transition std 2020-03-08T01:59:59-05:00 --> dst 2020-03-08T03:00:00-04:00
    try testing.expectEqual(stdoff, result.offsetAtTimestamp(1583650799).?.offset);
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1583650800).?.offset);
    // transition dst 2020-11-01T01:59:59-04:00 --> std 2020-11-01T01:00:00-05:00
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1604210399).?.offset);
    try testing.expectEqual(stdoff, result.offsetAtTimestamp(1604210400).?.offset);
}

test "posix TZ string, leap year, America/New_York, both transition times specified" {
    // IANA identifier: America/New_York
    const result = try parse("EST5EDT,M3.2.0/02:00:00,M11.1.0/02:00:00");
    const stdoff: i32 = -18000;
    const dstoff: i32 = -14400;
    try testing.expectEqualSlices(u8, "EST", result.std_designation);
    try testing.expectEqual(stdoff, result.std_offset);
    try testing.expectEqualSlices(u8, "EDT", result.dst_designation.?);
    try testing.expectEqual(dstoff, result.dst_offset);
    // transition std 2020-03-08T01:59:59-05:00 --> dst 2020-03-08T03:00:00-04:00
    try testing.expectEqual(stdoff, result.offsetAtTimestamp(1583650799).?.offset);
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1583650800).?.offset);
    // transtion dst 2020-11-01T01:59:59-04:00 --> std 2020-11-01T01:00:00-05:00
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1604210399).?.offset);
    try testing.expectEqual(stdoff, result.offsetAtTimestamp(1604210400).?.offset);
}

test "posix TZ string, leap year, America/New_York, end transition time specified" {
    // IANA identifier: America/New_York
    const result = try parse("EST5EDT,M3.2.0,M11.1.0/02:00:00");
    const stdoff: i32 = -18000;
    const dstoff: i32 = -14400;
    try testing.expectEqualSlices(u8, "EST", result.std_designation);
    try testing.expectEqual(stdoff, result.std_offset);
    try testing.expectEqualSlices(u8, "EDT", result.dst_designation.?);
    try testing.expectEqual(dstoff, result.dst_offset);
    // transition std 2020-03-08T01:59:59-05:00 --> dst 2020-03-08T03:00:00-04:00
    try testing.expectEqual(stdoff, result.offsetAtTimestamp(1583650799).?.offset);
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1583650800).?.offset);
    // transtion dst 2020-11-01T01:59:59-04:00 --> std 2020-11-01T01:00:00-05:00
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1604210399).?.offset);
    try testing.expectEqual(stdoff, result.offsetAtTimestamp(1604210400).?.offset);
}

test "posix TZ string, leap year, America/Chicago, both transition times specified" {
    // IANA identifier: America/Chicago
    const result = try parse("CST6CDT,M3.2.0/2:00:00,M11.1.0/2:00:00");
    const stdoff: i32 = -21600;
    const dstoff: i32 = -18000;
    try testing.expectEqualSlices(u8, "CST", result.std_designation);
    try testing.expectEqual(stdoff, result.std_offset);
    try testing.expectEqualSlices(u8, "CDT", result.dst_designation.?);
    try testing.expectEqual(dstoff, result.dst_offset);
    // transition std 2020-03-08T01:59:59-06:00 --> dst 2020-03-08T03:00:00-05:00
    try testing.expectEqual(stdoff, result.offsetAtTimestamp(1583654399).?.offset);
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1583654400).?.offset);
    // transtion dst 2020-11-01T01:59:59-05:00 --> std 2020-11-01T01:00:00-06:00
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1604213999).?.offset);
    try testing.expectEqual(stdoff, result.offsetAtTimestamp(1604214000).?.offset);
}

test "posix TZ string, leap year, America/Denver, both transition times specified" {
    // IANA identifier: America/Denver
    const result = try parse("MST7MDT,M3.2.0/2:00:00,M11.1.0/2:00:00");
    const stdoff: i32 = -25200;
    const dstoff: i32 = -21600;
    try testing.expectEqualSlices(u8, "MST", result.std_designation);
    try testing.expectEqual(stdoff, result.std_offset);
    try testing.expectEqualSlices(u8, "MDT", result.dst_designation.?);
    try testing.expectEqual(dstoff, result.dst_offset);
    // transition std 2020-03-08T01:59:59-07:00 --> dst 2020-03-08T03:00:00-06:00
    try testing.expectEqual(stdoff, result.offsetAtTimestamp(1583657999).?.offset);
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1583658000).?.offset);
    // transtion dst 2020-11-01T01:59:59-06:00 --> std 2020-11-01T01:00:00-07:00
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1604217599).?.offset);
    try testing.expectEqual(stdoff, result.offsetAtTimestamp(1604217600).?.offset);
}

test "posix TZ string, leap year, America/Los_Angeles, both transition times specified" {
    // IANA identifier: America/Los_Angeles
    const result = try parse("PST8PDT,M3.2.0/2:00:00,M11.1.0/2:00:00");
    const stdoff: i32 = -28800;
    const dstoff: i32 = -25200;
    try testing.expectEqualSlices(u8, "PST", result.std_designation);
    try testing.expectEqual(stdoff, result.std_offset);
    try testing.expectEqualSlices(u8, "PDT", result.dst_designation.?);
    try testing.expectEqual(dstoff, result.dst_offset);
    // transition std 2020-03-08T01:59:59-08:00 --> dst 2020-03-08T03:00:00-07:00
    try testing.expectEqual(stdoff, result.offsetAtTimestamp(1583661599).?.offset);
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1583661600).?.offset);
    // transtion dst 2020-11-01T01:59:59-07:00 --> std 2020-11-01T01:00:00-08:00
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1604221199).?.offset);
    try testing.expectEqual(stdoff, result.offsetAtTimestamp(1604221200).?.offset);
}

test "posix TZ string, leap year, America/Sitka" {
    // IANA identifier: America/Sitka
    const result = try parse("AKST9AKDT,M3.2.0,M11.1.0");
    const stdoff: i32 = -32400;
    const dstoff: i32 = -28800;
    try testing.expectEqualSlices(u8, "AKST", result.std_designation);
    try testing.expectEqual(stdoff, result.std_offset);
    try testing.expectEqualSlices(u8, "AKDT", result.dst_designation.?);
    try testing.expectEqual(dstoff, result.dst_offset);
    // transition std 2020-03-08T01:59:59-09:00 --> dst 2020-03-08T03:00:00-08:00
    try testing.expectEqual(stdoff, result.offsetAtTimestamp(1583665199).?.offset);
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1583665200).?.offset);
    // transtion dst 2020-11-01T01:59:59-08:00 --> std 2020-11-01T01:00:00-09:00
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1604224799).?.offset);
    try testing.expectEqual(stdoff, result.offsetAtTimestamp(1604224800).?.offset);
}

test "posix TZ string, leap year, Asia/Jerusalem" {
    // IANA identifier: Asia/Jerusalem
    const result = try parse("IST-2IDT,M3.4.4/26,M10.5.0");
    const stdoff: i32 = 7200;
    const dstoff: i32 = 10800;
    try testing.expectEqualSlices(u8, "IST", result.std_designation);
    try testing.expectEqual(stdoff, result.std_offset);
    try testing.expectEqualSlices(u8, "IDT", result.dst_designation.?);
    try testing.expectEqual(dstoff, result.dst_offset);
    // transition std 2020-03-27T01:59:59+02:00 --> dst 2020-03-27T03:00:00+03:00
    try testing.expectEqual(stdoff, result.offsetAtTimestamp(1585267199).?.offset);
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1585267200).?.offset);
    // transtion dst 2020-10-25T01:59:59+03:00 --> std 2020-10-25T01:00:00+02:00
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1603580399).?.offset);
    try testing.expectEqual(stdoff, result.offsetAtTimestamp(1603580400).?.offset);
}

// Buenos Aires has DST all year long, make sure that it never returns the STD offset
test "posix TZ string, leap year, America/Argentina/Buenos_Aires" {
    // IANA identifier: America/Argentina/Buenos_Aires
    const result = try parse("WART4WARST,J1/0,J365/25");
    const stdoff: i32 = -4 * std.time.s_per_hour;
    const dstoff: i32 = -3 * std.time.s_per_hour;
    try testing.expectEqualSlices(u8, "WART", result.std_designation);
    try testing.expectEqualSlices(u8, "WARST", result.dst_designation.?);
    _ = stdoff;

    // transition std 2020-03-27T01:59:59-03:00 --> dst 2020-03-27T03:00:00-03:00
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1585285199).?.offset);
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1585288800).?.offset);
    // transtion dst 2020-10-25T01:59:59-03:00 --> std 2020-10-25T01:00:00-03:00
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1603601999).?.offset);
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1603598400).?.offset);

    // Make sure it returns dstoff at the start of the year
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1577836800).?.offset); // 2020
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1609459200).?.offset); // 2021

    // Make sure it returns dstoff at the end of the year
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1609459199).?.offset);
}

test "posix TZ string, leap year, America/Nuuk" {
    // IANA identifier: America/Nuuk
    const result = try parse("WGT3WGST,M3.5.0/-2,M10.5.0/-1");
    const stdoff: i32 = -10800;
    const dstoff: i32 = -7200;
    try testing.expectEqualSlices(u8, "WGT", result.std_designation);
    try testing.expectEqual(stdoff, result.std_offset);
    try testing.expectEqualSlices(u8, "WGST", result.dst_designation.?);
    try testing.expectEqual(dstoff, result.dst_offset);
    // transition std 2020-03-28T21:59:59-03:00 --> dst 2020-03-28T23:00:00-02:00
    try testing.expectEqual(stdoff, result.offsetAtTimestamp(1585443599).?.offset);
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1585443600).?.offset);
    // transtion dst 2020-10-24T22:59:59-02:00 --> std 2020-10-24T22:00:00-03:00
    try testing.expectEqual(dstoff, result.offsetAtTimestamp(1603587599).?.offset);
    try testing.expectEqual(stdoff, result.offsetAtTimestamp(1603587600).?.offset);
}

test "posix TZ, valid strings, Extreme offset hour" {
    _ = try parse("AAA24");
    _ = try parse("AAA+24");
    _ = try parse("AAA-24");
    _ = try parse("AAA24BBB,J60/2,J300/2");
    _ = try parse("AAA+24BBB,J60/2,J300/2");
    _ = try parse("AAA-24BBB,J60/2,J300/2");
    _ = try parse("AAA4BBB24,J60/2,J300/2");
    _ = try parse("AAA4BBB+24,J60/2,J300/2");
    _ = try parse("AAA4BBB-24,J60/2,J300/2");
}

test "posix TZ, valid strings, Extreme offset minutes" {
    _ = try parse("AAA4:00BBB,J60/2,J300/2");
    _ = try parse("AAA4:59BBB,J60/2,J300/2");
    _ = try parse("AAA4BBB5:00,J60/2,J300/2");
    _ = try parse("AAA4BBB5:59,J60/2,J300/2");
}

test "posix TZ, valid strings, Extreme offset seconds" {
    _ = try parse("AAA4:00:00BBB,J60/2,J300/2");
    _ = try parse("AAA4:00:59BBB,J60/2,J300/2");
    _ = try parse("AAA4BBB5:00:00,J60/2,J300/2");
    _ = try parse("AAA4BBB5:00:59,J60/2,J300/2");
}

test "posix TZ, valid strings, Extreme total offset" {
    _ = try parse("AAA24:59:59BBB5,J60/2,J300/2");
    _ = try parse("AAA-24:59:59BBB5,J60/2,J300/2");
    _ = try parse("AAA4BBB24:59:59,J60/2,J300/2");
    _ = try parse("AAA4BBB-24:59:59,J60/2,J300/2");
}

test "posix TZ, valid strings, Extreme months" {
    _ = try parse("AAA4BBB,M12.1.1/2,M1.1.1/2");
    _ = try parse("AAA4BBB,M1.1.1/2,M12.1.1/2");
}

test "posix TZ, valid strings, Extreme weeks" {
    _ = try parse("AAA4BBB,M1.5.1/2,M1.1.1/2");
    _ = try parse("AAA4BBB,M1.1.1/2,M1.5.1/2");
}

test "posix TZ, valid strings, Extreme weekday" {
    _ = try parse("AAA4BBB,M1.1.6/2,M2.1.1/2");
    _ = try parse("AAA4BBB,M1.1.1/2,M2.1.6/2");
}

test "posix TZ, valid strings, Extreme numeric offset" {
    _ = try parse("AAA4BBB,0/2,20/2");
    _ = try parse("AAA4BBB,0/2,0/14");
    _ = try parse("AAA4BBB,20/2,365/2");
    _ = try parse("AAA4BBB,365/2,365/14");
}

test "posix TZ, valid strings, Extreme julian offset" {
    _ = try parse("AAA4BBB,J1/2,J20/2");
    _ = try parse("AAA4BBB,J1/2,J1/14");
    _ = try parse("AAA4BBB,J20/2,J365/2");
    _ = try parse("AAA4BBB,J365/2,J365/14");
}

test "posix TZ, valid strings, Extreme transition hour" {
    _ = try parse("AAA4BBB,J60/167,J300/2");
    _ = try parse("AAA4BBB,J60/+167,J300/2");
    _ = try parse("AAA4BBB,J60/-167,J300/2");
    _ = try parse("AAA4BBB,J60/2,J300/167");
    _ = try parse("AAA4BBB,J60/2,J300/+167");
    _ = try parse("AAA4BBB,J60/2,J300/-167");
}

test "posix TZ, valid strings, Extreme transition minutes" {
    _ = try parse("AAA4BBB,J60/2:00,J300/2");
    _ = try parse("AAA4BBB,J60/2:59,J300/2");
    _ = try parse("AAA4BBB,J60/2,J300/2:00");
    _ = try parse("AAA4BBB,J60/2,J300/2:59");
}

test "posix TZ, valid strings, Extreme transition seconds" {
    _ = try parse("AAA4BBB,J60/2:00:00,J300/2");
    _ = try parse("AAA4BBB,J60/2:00:59,J300/2");
    _ = try parse("AAA4BBB,J60/2,J300/2:00:00");
    _ = try parse("AAA4BBB,J60/2,J300/2:00:59");
}

test "posix TZ, valid strings, Extreme total transition time" {
    _ = try parse("AAA4BBB,J60/167:59:59,J300/2");
    _ = try parse("AAA4BBB,J60/-167:59:59,J300/2");
    _ = try parse("AAA4BBB,J60/2,J300/167:59:59");
    _ = try parse("AAA4BBB,J60/2,J300/-167:59:59");
}

// The following tests are from CPython's zoneinfo tests;
// https://github.com/python/cpython/blob/main/Lib/test/test_zoneinfo/test_zoneinfo.py
test "posix TZ invalid string, unquoted alphanumeric" {
    try std.testing.expectError(error.InvalidFormat, parse("+11"));
}

test "posix TZ invalid string, unquoted alphanumeric in DST" {
    try std.testing.expectError(error.InvalidFormat, parse("GMT0+11,M3.2.0/2,M11.1.0/3"));
}

test "posix TZ invalid string, DST but no transition specified" {
    try std.testing.expectError(error.InvalidFormat, parse("PST8PDT"));
}

test "posix TZ invalid string, only one transition rule" {
    try std.testing.expectError(error.InvalidFormat, parse("PST8PDT,M3.2.0/2"));
}

test "posix TZ invalid string, transition rule but no DST" {
    try std.testing.expectError(error.InvalidFormat, parse("GMT,M3.2.0/2,M11.1.0/3"));
}

test "posix TZ invalid offset hours" {
    try std.testing.expectError(error.InvalidFormat, parse("AAA168"));
    try std.testing.expectError(error.InvalidFormat, parse("AAA+168"));
    try std.testing.expectError(error.InvalidFormat, parse("AAA-168"));
    try std.testing.expectError(error.InvalidFormat, parse("AAA168BBB,J60/2,J300/2"));
    try std.testing.expectError(error.InvalidFormat, parse("AAA+168BBB,J60/2,J300/2"));
    try std.testing.expectError(error.InvalidFormat, parse("AAA-168BBB,J60/2,J300/2"));
    try std.testing.expectError(error.InvalidFormat, parse("AAA4BBB168,J60/2,J300/2"));
    try std.testing.expectError(error.InvalidFormat, parse("AAA4BBB+168,J60/2,J300/2"));
    try std.testing.expectError(error.InvalidFormat, parse("AAA4BBB-168,J60/2,J300/2"));
}

test "posix TZ invalid offset minutes" {
    try std.testing.expectError(error.InvalidFormat, parse("AAA4:0BBB,J60/2,J300/2"));
    try std.testing.expectError(error.InvalidFormat, parse("AAA4:100BBB,J60/2,J300/2"));
    try std.testing.expectError(error.InvalidFormat, parse("AAA4BBB5:0,J60/2,J300/2"));
    try std.testing.expectError(error.InvalidFormat, parse("AAA4BBB5:100,J60/2,J300/2"));
}

test "posix TZ invalid offset seconds" {
    try std.testing.expectError(error.InvalidFormat, parse("AAA4:00:0BBB,J60/2,J300/2"));
    try std.testing.expectError(error.InvalidFormat, parse("AAA4:00:100BBB,J60/2,J300/2"));
    try std.testing.expectError(error.InvalidFormat, parse("AAA4BBB5:00:0,J60/2,J300/2"));
    try std.testing.expectError(error.InvalidFormat, parse("AAA4BBB5:00:100,J60/2,J300/2"));
}

test "posix TZ completely invalid dates" {
    try std.testing.expectError(error.InvalidFormat, parse("AAA4BBB,M1443339,M11.1.0/3"));
    try std.testing.expectError(error.InvalidFormat, parse("AAA4BBB,M3.2.0/2,0349309483959c"));
    try std.testing.expectError(error.InvalidFormat, parse("AAA4BBB,,J300/2"));
    try std.testing.expectError(error.InvalidFormat, parse("AAA4BBB,z,J300/2"));
    try std.testing.expectError(error.InvalidFormat, parse("AAA4BBB,J60/2,"));
    try std.testing.expectError(error.InvalidFormat, parse("AAA4BBB,J60/2,z"));
}

test "posix TZ invalid months" {
    try std.testing.expectError(error.InvalidFormat, parse("AAA4BBB,M13.1.1/2,M1.1.1/2"));
    try std.testing.expectError(error.InvalidFormat, parse("AAA4BBB,M1.1.1/2,M13.1.1/2"));
    try std.testing.expectError(error.InvalidFormat, parse("AAA4BBB,M0.1.1/2,M1.1.1/2"));
    try std.testing.expectError(error.InvalidFormat, parse("AAA4BBB,M1.1.1/2,M0.1.1/2"));
}

test "posix TZ invalid weeks" {
    try std.testing.expectError(error.InvalidFormat, parse("AAA4BBB,M1.6.1/2,M1.1.1/2"));
    try std.testing.expectError(error.InvalidFormat, parse("AAA4BBB,M1.1.1/2,M1.6.1/2"));
}

test "posix TZ invalid weekday" {
    try std.testing.expectError(error.InvalidFormat, parse("AAA4BBB,M1.1.7/2,M2.1.1/2"));
    try std.testing.expectError(error.InvalidFormat, parse("AAA4BBB,M1.1.1/2,M2.1.7/2"));
}

test "posix TZ invalid numeric offset" {
    try std.testing.expectError(error.InvalidFormat, parse("AAA4BBB,-1/2,20/2"));
    try std.testing.expectError(error.InvalidFormat, parse("AAA4BBB,1/2,-1/2"));
    try std.testing.expectError(error.InvalidFormat, parse("AAA4BBB,367,20/2"));
    try std.testing.expectError(error.InvalidFormat, parse("AAA4BBB,1/2,367/2"));
}

test "posix TZ invalid julian offset" {
    try std.testing.expectError(error.InvalidFormat, parse("AAA4BBB,J0/2,J20/2"));
    try std.testing.expectError(error.InvalidFormat, parse("AAA4BBB,J20/2,J366/2"));
}

test "posix TZ invalid transition time" {
    try std.testing.expectError(error.InvalidFormat, parse("AAA4BBB,J60/2/3,J300/2"));
    try std.testing.expectError(error.InvalidFormat, parse("AAA4BBB,J60/2,J300/2/3"));
}

test "posix TZ invalid transition hour" {
    try std.testing.expectError(error.InvalidFormat, parse("AAA4BBB,J60/168,J300/2"));
    try std.testing.expectError(error.InvalidFormat, parse("AAA4BBB,J60/+168,J300/2"));
    try std.testing.expectError(error.InvalidFormat, parse("AAA4BBB,J60/-168,J300/2"));
    try std.testing.expectError(error.InvalidFormat, parse("AAA4BBB,J60/2,J300/168"));
    try std.testing.expectError(error.InvalidFormat, parse("AAA4BBB,J60/2,J300/+168"));
    try std.testing.expectError(error.InvalidFormat, parse("AAA4BBB,J60/2,J300/-168"));
}

test "posix TZ invalid transition minutes" {
    try std.testing.expectError(error.InvalidFormat, parse("AAA4BBB,J60/2:0,J300/2"));
    try std.testing.expectError(error.InvalidFormat, parse("AAA4BBB,J60/2:100,J300/2"));
    try std.testing.expectError(error.InvalidFormat, parse("AAA4BBB,J60/2,J300/2:0"));
    try std.testing.expectError(error.InvalidFormat, parse("AAA4BBB,J60/2,J300/2:100"));
}

test "posix TZ invalid transition seconds" {
    try std.testing.expectError(error.InvalidFormat, parse("AAA4BBB,J60/2:00:0,J300/2"));
    try std.testing.expectError(error.InvalidFormat, parse("AAA4BBB,J60/2:00:100,J300/2"));
    try std.testing.expectError(error.InvalidFormat, parse("AAA4BBB,J60/2,J300/2:00:0"));
    try std.testing.expectError(error.InvalidFormat, parse("AAA4BBB,J60/2,J300/2:00:100"));
}

test "posix TZ EST5EDT,M3.2.0/4:00,M11.1.0/3:00 from zoneinfo_test.py" {
    // Transition to EDT on the 2nd Sunday in March at 4 AM, and
    // transition back on the first Sunday in November at 3AM
    const result = try parse("EST5EDT,M3.2.0/4:00,M11.1.0/3:00");
    try testing.expectEqual(@as(i32, -18000), result.offsetAtTimestamp(1552107600).?.offset); // 2019-03-09T00:00:00-05:00
    try testing.expectEqual(@as(i32, -18000), result.offsetAtTimestamp(1552208340).?.offset); // 2019-03-10T03:59:00-05:00
    try testing.expectEqual(@as(i32, -14400), result.offsetAtTimestamp(1572667200).?.offset); // 2019-11-02T00:00:00-04:00
    try testing.expectEqual(@as(i32, -14400), result.offsetAtTimestamp(1572760740).?.offset); // 2019-11-03T01:59:00-04:00
    try testing.expectEqual(@as(i32, -14400), result.offsetAtTimestamp(1572760800).?.offset); // 2019-11-03T02:00:00-04:00
    try testing.expectEqual(@as(i32, -18000), result.offsetAtTimestamp(1572764400).?.offset); // 2019-11-03T02:00:00-05:00
    try testing.expectEqual(@as(i32, -18000), result.offsetAtTimestamp(1583657940).?.offset); // 2020-03-08T03:59:00-05:00
    try testing.expectEqual(@as(i32, -14400), result.offsetAtTimestamp(1604210340).?.offset); // 2020-11-01T01:59:00-04:00
    try testing.expectEqual(@as(i32, -14400), result.offsetAtTimestamp(1604210400).?.offset); // 2020-11-01T02:00:00-04:00
    try testing.expectEqual(@as(i32, -18000), result.offsetAtTimestamp(1604214000).?.offset); // 2020-11-01T02:00:00-05:00
}

test "posix TZ GMT0BST-1,M3.5.0/1:00,M10.5.0/2:00 from zoneinfo_test.py" {
    // Transition to BST happens on the last Sunday in March at 1 AM GMT
    // and the transition back happens the last Sunday in October at 2AM BST
    const result = try parse("GMT0BST-1,M3.5.0/1:00,M10.5.0/2:00");
    try testing.expectEqual(@as(i32, 0), result.offsetAtTimestamp(1553904000).?.offset); // 2019-03-30T00:00:00+00:00
    try testing.expectEqual(@as(i32, 0), result.offsetAtTimestamp(1553993940).?.offset); // 2019-03-31T00:59:00+00:00
    try testing.expectEqual(@as(i32, 3600), result.offsetAtTimestamp(1553994000).?.offset); // 2019-03-31T02:00:00+01:00
    try testing.expectEqual(@as(i32, 3600), result.offsetAtTimestamp(1572044400).?.offset); // 2019-10-26T00:00:00+01:00
    try testing.expectEqual(@as(i32, 3600), result.offsetAtTimestamp(1572134340).?.offset); // 2019-10-27T00:59:00+01:00
    try testing.expectEqual(@as(i32, 0), result.offsetAtTimestamp(1585443540).?.offset); // 2020-03-29T00:59:00+00:00
    try testing.expectEqual(@as(i32, 3600), result.offsetAtTimestamp(1585443600).?.offset); // 2020-03-29T02:00:00+01:00
    try testing.expectEqual(@as(i32, 3600), result.offsetAtTimestamp(1603583940).?.offset); // 2020-10-25T00:59:00+01:00
    try testing.expectEqual(@as(i32, 3600), result.offsetAtTimestamp(1603584000).?.offset); // 2020-10-25T01:00:00+01:00
    try testing.expectEqual(@as(i32, 0), result.offsetAtTimestamp(1603591200).?.offset); // 2020-10-25T02:00:00+00:00
}

test "posix TZ AEST-10AEDT,M10.1.0/2,M4.1.0/3 from zoneinfo_test.py" {
    // Austrialian time zone - DST start is chronologically first
    const result = try parse("AEST-10AEDT,M10.1.0/2,M4.1.0/3");
    try testing.expectEqual(@as(i32, 39600), result.offsetAtTimestamp(1554469200).?.offset); // 2019-04-06T00:00:00+11:00
    try testing.expectEqual(@as(i32, 39600), result.offsetAtTimestamp(1554562740).?.offset); // 2019-04-07T01:59:00+11:00
    try testing.expectEqual(@as(i32, 39600), result.offsetAtTimestamp(1554562740).?.offset); // 2019-04-07T01:59:00+11:00
    try testing.expectEqual(@as(i32, 39600), result.offsetAtTimestamp(1554562800).?.offset); // 2019-04-07T02:00:00+11:00
    try testing.expectEqual(@as(i32, 39600), result.offsetAtTimestamp(1554562860).?.offset); // 2019-04-07T02:01:00+11:00
    try testing.expectEqual(@as(i32, 36000), result.offsetAtTimestamp(1554566400).?.offset); // 2019-04-07T02:00:00+10:00
    try testing.expectEqual(@as(i32, 36000), result.offsetAtTimestamp(1554566460).?.offset); // 2019-04-07T02:01:00+10:00
    try testing.expectEqual(@as(i32, 36000), result.offsetAtTimestamp(1554570000).?.offset); // 2019-04-07T03:00:00+10:00
    try testing.expectEqual(@as(i32, 36000), result.offsetAtTimestamp(1554570000).?.offset); // 2019-04-07T03:00:00+10:00
    try testing.expectEqual(@as(i32, 36000), result.offsetAtTimestamp(1570197600).?.offset); // 2019-10-05T00:00:00+10:00
    try testing.expectEqual(@as(i32, 36000), result.offsetAtTimestamp(1570291140).?.offset); // 2019-10-06T01:59:00+10:00
    try testing.expectEqual(@as(i32, 39600), result.offsetAtTimestamp(1570291200).?.offset); // 2019-10-06T03:00:00+11:00
}

test "posix TZ IST-1GMT0,M10.5.0,M3.5.0/1 from zoneinfo_test.py" {
    // Irish time zone - negative DST
    const result = try parse("IST-1GMT0,M10.5.0,M3.5.0/1");
    try testing.expectEqual(@as(i32, 0), result.offsetAtTimestamp(1553904000).?.offset); // 2019-03-30T00:00:00+00:00
    try testing.expectEqual(@as(i32, 0), result.offsetAtTimestamp(1553993940).?.offset); // 2019-03-31T00:59:00+00:00
    try testing.expectEqual(true, result.offsetAtTimestamp(1553993940).?.is_daylight_saving_time); // 2019-03-31T00:59:00+00:00
    try testing.expectEqual(@as(i32, 3600), result.offsetAtTimestamp(1553994000).?.offset); // 2019-03-31T02:00:00+01:00
    try testing.expectEqual(false, result.offsetAtTimestamp(1553994000).?.is_daylight_saving_time); // 2019-03-31T02:00:00+01:00
    try testing.expectEqual(@as(i32, 3600), result.offsetAtTimestamp(1572044400).?.offset); // 2019-10-26T00:00:00+01:00
    try testing.expectEqual(@as(i32, 3600), result.offsetAtTimestamp(1572134340).?.offset); // 2019-10-27T00:59:00+01:00
    try testing.expectEqual(@as(i32, 3600), result.offsetAtTimestamp(1572134400).?.offset); // 2019-10-27T01:00:00+01:00
    try testing.expectEqual(@as(i32, 0), result.offsetAtTimestamp(1572138000).?.offset); // 2019-10-27T01:00:00+00:00
    try testing.expectEqual(@as(i32, 0), result.offsetAtTimestamp(1572141600).?.offset); // 2019-10-27T02:00:00+00:00
    try testing.expectEqual(@as(i32, 0), result.offsetAtTimestamp(1585443540).?.offset); // 2020-03-29T00:59:00+00:00
    try testing.expectEqual(@as(i32, 3600), result.offsetAtTimestamp(1585443600).?.offset); // 2020-03-29T02:00:00+01:00
    try testing.expectEqual(@as(i32, 3600), result.offsetAtTimestamp(1603583940).?.offset); // 2020-10-25T00:59:00+01:00
    try testing.expectEqual(@as(i32, 3600), result.offsetAtTimestamp(1603584000).?.offset); // 2020-10-25T01:00:00+01:00
    try testing.expectEqual(@as(i32, 0), result.offsetAtTimestamp(1603591200).?.offset); // 2020-10-25T02:00:00+00:00
}

test "posix TZ <+11>-11 from zoneinfo_test.py" {
    // Pacific/Kosrae: Fixed offset zone with a quoted numerical tzname
    const result = try parse("<+11>-11");
    try testing.expectEqual(@as(i32, 39600), result.offsetAtTimestamp(1577797200).?.offset); // 2020-01-01T00:00:00+11:00
}

test "posix TZ <-04>4<-03>,M9.1.6/24,M4.1.6/24 from zoneinfo_test.py" {
    // Quoted STD and DST, transitions at 24:00
    const result = try parse("<-04>4<-03>,M9.1.6/24,M4.1.6/24");
    try testing.expectEqual(@as(i32, -14400), result.offsetAtTimestamp(1588305600).?.offset); // 2020-05-01T00:00:00-04:00
    try testing.expectEqual(@as(i32, -10800), result.offsetAtTimestamp(1604199600).?.offset); // 2020-11-01T00:00:00-03:00
}

test "posix TZ EST5EDT,0/0,J365/25 from zoneinfo_test.py" {
    // Permanent daylight saving time is modeled with transitions at 0/0
    // and J365/25, as mentioned in RFC 8536 Section 3.3.1
    const result = try parse("EST5EDT,0/0,J365/25");
    try testing.expectEqual(@as(i32, -14400), result.offsetAtTimestamp(1546315200).?.offset); // 2019-01-01T00:00:00-04:00
    try testing.expectEqual(@as(i32, -14400), result.offsetAtTimestamp(1559361600).?.offset); // 2019-06-01T00:00:00-04:00
    try testing.expectEqual(@as(i32, -14400), result.offsetAtTimestamp(1577851199).?.offset); // 2019-12-31T23:59:59.999999-04:00
    try testing.expectEqual(@as(i32, -14400), result.offsetAtTimestamp(1577851200).?.offset); // 2020-01-01T00:00:00-04:00
    try testing.expectEqual(@as(i32, -14400), result.offsetAtTimestamp(1583035200).?.offset); // 2020-03-01T00:00:00-04:00
    try testing.expectEqual(@as(i32, -14400), result.offsetAtTimestamp(1590984000).?.offset); // 2020-06-01T00:00:00-04:00
    try testing.expectEqual(@as(i32, -14400), result.offsetAtTimestamp(1609473599).?.offset); // 2020-12-31T23:59:59.999999-04:00
    try testing.expectEqual(@as(i32, -14400), result.offsetAtTimestamp(13569480000).?.offset); // 2400-01-01T00:00:00-04:00
    try testing.expectEqual(@as(i32, -14400), result.offsetAtTimestamp(13574664000).?.offset); // 2400-03-01T00:00:00-04:00
    try testing.expectEqual(@as(i32, -14400), result.offsetAtTimestamp(13601102399).?.offset); // 2400-12-31T23:59:59.999999-04:00
}

test "posix TZ AAA3BBB,J60/12,J305/12 from zoneinfo_test.py" {
    // Transitions on March 1st and November 1st of each year
    const result = try parse("AAA3BBB,J60/12,J305/12");
    try testing.expectEqual(@as(i32, -10800), result.offsetAtTimestamp(1546311600).?.offset); // 2019-01-01T00:00:00-03:00
    try testing.expectEqual(@as(i32, -10800), result.offsetAtTimestamp(1551322800).?.offset); // 2019-02-28T00:00:00-03:00
    try testing.expectEqual(@as(i32, -10800), result.offsetAtTimestamp(1551452340).?.offset); // 2019-03-01T11:59:00-03:00
    try testing.expectEqual(@as(i32, -7200), result.offsetAtTimestamp(1551452400).?.offset); // 2019-03-01T13:00:00-02:00
    try testing.expectEqual(@as(i32, -7200), result.offsetAtTimestamp(1572613140).?.offset); // 2019-11-01T10:59:00-02:00
    try testing.expectEqual(@as(i32, -7200), result.offsetAtTimestamp(1572613200).?.offset); // 2019-11-01T11:00:00-02:00
    try testing.expectEqual(@as(i32, -10800), result.offsetAtTimestamp(1572616800).?.offset); // 2019-11-01T11:00:00-03:00
    try testing.expectEqual(@as(i32, -10800), result.offsetAtTimestamp(1572620400).?.offset); // 2019-11-01T12:00:00-03:00
    try testing.expectEqual(@as(i32, -10800), result.offsetAtTimestamp(1577847599).?.offset); // 2019-12-31T23:59:59.999999-03:00
    try testing.expectEqual(@as(i32, -10800), result.offsetAtTimestamp(1577847600).?.offset); // 2020-01-01T00:00:00-03:00
    try testing.expectEqual(@as(i32, -10800), result.offsetAtTimestamp(1582945200).?.offset); // 2020-02-29T00:00:00-03:00
    try testing.expectEqual(@as(i32, -10800), result.offsetAtTimestamp(1583074740).?.offset); // 2020-03-01T11:59:00-03:00
    try testing.expectEqual(@as(i32, -7200), result.offsetAtTimestamp(1583074800).?.offset); // 2020-03-01T13:00:00-02:00
    try testing.expectEqual(@as(i32, -7200), result.offsetAtTimestamp(1604235540).?.offset); // 2020-11-01T10:59:00-02:00
    try testing.expectEqual(@as(i32, -7200), result.offsetAtTimestamp(1604235600).?.offset); // 2020-11-01T11:00:00-02:00
    try testing.expectEqual(@as(i32, -10800), result.offsetAtTimestamp(1604239200).?.offset); // 2020-11-01T11:00:00-03:00
    try testing.expectEqual(@as(i32, -10800), result.offsetAtTimestamp(1604242800).?.offset); // 2020-11-01T12:00:00-03:00
    try testing.expectEqual(@as(i32, -10800), result.offsetAtTimestamp(1609469999).?.offset); // 2020-12-31T23:59:59.999999-03:00
}

test "posix TZ <-03>3<-02>,M3.5.0/-2,M10.5.0/-1 from zoneinfo_test.py" {
    // Taken from America/Godthab, this rule has a transition on the
    // Saturday before the last Sunday of March and October, at 22:00 and 23:00,
    // respectively. This is encoded with negative start and end transition times.
    const result = try parse("<-03>3<-02>,M3.5.0/-2,M10.5.0/-1");
    try testing.expectEqual(@as(i32, -10800), result.offsetAtTimestamp(1585278000).?.offset); // 2020-03-27T00:00:00-03:00
    try testing.expectEqual(@as(i32, -10800), result.offsetAtTimestamp(1585443599).?.offset); // 2020-03-28T21:59:59-03:00
    try testing.expectEqual(@as(i32, -7200), result.offsetAtTimestamp(1585443600).?.offset); // 2020-03-28T23:00:00-02:00
    try testing.expectEqual(@as(i32, -7200), result.offsetAtTimestamp(1603580400).?.offset); // 2020-10-24T21:00:00-02:00
    try testing.expectEqual(@as(i32, -7200), result.offsetAtTimestamp(1603584000).?.offset); // 2020-10-24T22:00:00-02:00
    try testing.expectEqual(@as(i32, -10800), result.offsetAtTimestamp(1603587600).?.offset); // 2020-10-24T22:00:00-03:00
    try testing.expectEqual(@as(i32, -10800), result.offsetAtTimestamp(1603591200).?.offset); // 2020-10-24T23:00:00-03:00
}

test "posix TZ AAA3BBB,M3.2.0/01:30,M11.1.0/02:15:45 from zoneinfo_test.py" {
    // Transition times with minutes and seconds
    const result = try parse("AAA3BBB,M3.2.0/01:30,M11.1.0/02:15:45");
    try testing.expectEqual(@as(i32, -10800), result.offsetAtTimestamp(1331438400).?.offset); // 2012-03-11T01:00:00-03:00
    try testing.expectEqual(@as(i32, -7200), result.offsetAtTimestamp(1331440200).?.offset); // 2012-03-11T02:30:00-02:00
    try testing.expectEqual(@as(i32, -7200), result.offsetAtTimestamp(1351998944).?.offset); // 2012-11-04T01:15:44.999999-02:00
    try testing.expectEqual(@as(i32, -7200), result.offsetAtTimestamp(1351998945).?.offset); // 2012-11-04T01:15:45-02:00
    try testing.expectEqual(@as(i32, -10800), result.offsetAtTimestamp(1352002545).?.offset); // 2012-11-04T01:15:45-03:00
    try testing.expectEqual(@as(i32, -10800), result.offsetAtTimestamp(1352006145).?.offset); // 2012-11-04T02:15:45-03:00
}

const chrono = @import("../lib.zig");
const testing = @import("std").testing;
const std = @import("std");
