const std = @import("std");
const chrono = @import("./lib.zig");

const NaiveDate = @import("./date.zig").NaiveDate;
const time_module = @import("./time.zig");
const NaiveTime = time_module.NaiveTime;
const timezone = @import("./timezone.zig");
const TimeZone = timezone.TimeZone;
const internals = @import("./internals.zig");
const format_module = @import("./format.zig");
const IsoWeek = @import("./IsoWeek.zig");
const Weekday = @import("./lib.zig").Weekday;
const Month = @import("./lib.zig").Month;
const YearInt = internals.YearInt;
const MonthInt = internals.MonthInt;
const DayInt = internals.DayInt;

const DAYS_AFTER_ZERO_EPOCH = 719163;

const EPOCH = chrono.EPOCH;

pub const DateTime = struct {
    /// UTC based date
    datetime: NaiveDateTime,
    /// TimeZone is used to get localtime values
    timezone: *const TimeZone,

    pub fn utc(datetime: NaiveDateTime, tz: *const TimeZone) @This() {
        return .{ .datetime = datetime, .timezone = tz };
    }

    pub fn local(localDatetime: NaiveDateTime, tz: *const TimeZone) !@This() {
        const timezone_timestamp = localDatetime.signed_duration_since(EPOCH);
        const timestamp = tz.timezoneToUtc(timezone_timestamp);
        return @This(){
            .datetime = try NaiveDateTime.from_timestamp(timestamp, 0),
            .timezone = tz,
        };
    }

    pub fn toTimestamp(this: @This()) i64 {
        return this.datetime.signed_duration_since(EPOCH);
    }

    pub fn toNaiveDateTime(this: @This()) !NaiveDateTime {
        const utc_timestamp = this.datetime.signed_duration_since(EPOCH);
        const local_timestamp = this.timezone.utcToLocal(utc_timestamp);
        return NaiveDateTime.from_timestamp(local_timestamp, 0);
    }
};

pub const NaiveDateTime = struct {
    date: NaiveDate,
    time: NaiveTime,

    pub fn new(date: NaiveDate, time: NaiveTime) @This() {
        return .{ .date = date, .time = time };
    }

    pub fn from_timestamp(seconds: i64, nsecs: u32) !@This() {
        const days = @divFloor(seconds, std.time.s_per_day);
        const secs = @mod(seconds, std.time.s_per_day);

        if (std.math.minInt(i32) > days or days > std.math.maxInt(i32)) {
            return error.InvalidDate;
        }
        var days_abs = @as(i32, @intCast(days));
        const addition = @addWithOverflow(days_abs, DAYS_AFTER_ZERO_EPOCH);
        if (addition[1] > 0) {
            return error.InvalidDate;
        }
        days_abs = addition[0];

        const date = try NaiveDate.from_num_days_from_ce(days_abs);

        const time = try NaiveTime.from_num_seconds_from_midnight(@as(u32, @intCast(secs)), nsecs);

        return @This(){
            .date = date,
            .time = time,
        };
    }

    /// Create a NaiveDateTime from YMD and HMS components
    pub fn ymd_hms(year_param: i32, month_param: MonthInt, day_param: DayInt, hour_param: u32, minute_param: u32, second_param: u32) !@This() {
        return @This(){
            .date = try NaiveDate.ymd(year_param, month_param, day_param),
            .time = try NaiveTime.hms(hour_param, minute_param, second_param),
        };
    }

    pub fn with_timezone(this: @This(), tz: *const TimeZone) DateTime {
        return DateTime{ .datetime = this, .timezone = tz };
    }

    pub fn signed_duration_since(this: @This(), other: @This()) i64 {
        return this.date.signed_duration_since(other.date) + this.time.signed_duration_since(other.time);
    }

    pub fn year(this: @This()) internals.YearInt {
        return this.date.year();
    }

    pub fn month(this: @This()) Month {
        return this.date.month();
    }

    pub fn day(this: @This()) internals.DayInt {
        return this.date.day();
    }

    pub fn hour(this: @This()) time_module.HoursInt {
        return this.time.hour();
    }

    pub fn minute(this: @This()) time_module.MinutesInt {
        return this.time.minute();
    }

    pub fn second(this: @This()) time_module.SecondsInt {
        return this.time.second();
    }

    pub fn isoweek(this: @This()) IsoWeek {
        return this.date.isoweek();
    }

    pub fn weekday(this: @This()) Weekday {
        return this.date.weekday();
    }

    pub fn Formatted(comptime format_str: []const u8) type {
        var parts_buf: [format_str.len]format_module.Part = undefined;
        const parts = format_module.parseFormatBuf(&parts_buf, format_str) catch unreachable;
        return struct {
            dt: NaiveDateTime,

            pub fn format(
                this: @This(),
                comptime fmt: []const u8,
                _: std.fmt.FormatOptions,
                writer: anytype,
            ) !void {
                if (fmt.len == 0) {
                    try format_module.formatNaiveDateTimeParts(writer, parts, this.dt);
                } else {
                    @compileError("Unknown format character: '" ++ fmt ++ "'");
                }
            }
        };
    }

    pub fn formatted(this: @This(), comptime format_str: []const u8) Formatted(format_str) {
        return Formatted(format_str){ .dt = this };
    }

    pub fn format(
        this: @This(),
        comptime fmt: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        var buf: [fmt.len]format_module.Part = undefined;
        const parts = format_module.parseFormatBuf(&buf, fmt) catch unreachable;
        try format_module.formatNaiveDateTimeParts(writer, parts, this);
    }
};

test "naive datetime from timestamp" {
    try std.testing.expectEqual(try NaiveDateTime.ymd_hms(1969, 12, 31, 23, 59, 59), try NaiveDateTime.from_timestamp(-1, 0));
    try std.testing.expectEqual(try NaiveDateTime.ymd_hms(1970, 1, 1, 0, 0, 0), try NaiveDateTime.from_timestamp(0, 0));
    try std.testing.expectEqual(try NaiveDateTime.ymd_hms(1970, 1, 1, 0, 0, 1), try NaiveDateTime.from_timestamp(1, 0));
    try std.testing.expectEqual(try NaiveDateTime.ymd_hms(2001, 9, 9, 1, 46, 40), try NaiveDateTime.from_timestamp(1000000000, 0));
    try std.testing.expectEqual(try NaiveDateTime.ymd_hms(2038, 1, 19, 3, 14, 7), try NaiveDateTime.from_timestamp(0x7fffffff, 0));

    try std.testing.expectError(error.InvalidDate, NaiveDateTime.from_timestamp(std.math.minInt(i64), 0));
    try std.testing.expectError(error.InvalidDate, NaiveDateTime.from_timestamp(std.math.minInt(i64) + 1, 0));
    try std.testing.expectError(error.InvalidDate, NaiveDateTime.from_timestamp(std.math.maxInt(i64), 0));
    try std.testing.expectError(error.InvalidDate, NaiveDateTime.from_timestamp(std.math.maxInt(i64) - 1, 0));
}

test "Pacific/Honolulu datetime from timestamp" {
    var fbs = std.io.fixedBufferStream(@embedFile("timezone/zoneinfo/Pacific/Honolulu"));
    const honolulu_tzif = timezone.TZif{ .tzif = try timezone.tzif.parse(std.testing.allocator, fbs.reader(), fbs.seekableStream()) };
    defer honolulu_tzif.deinit();
    const honolulu = &honolulu_tzif.timezone;

    const Case = struct {
        timestamp: i64,
        local_time: NaiveDateTime,
    };

    const cases = [_]Case{
        .{ .timestamp = 1613703600, .local_time = try NaiveDateTime.ymd_hms(2021, 2, 18, 17, 0, 0) },
    };

    for (cases) |case| {
        const dt = (try NaiveDateTime.from_timestamp(case.timestamp, 0)).with_timezone(honolulu);
        try std.testing.expectEqual(case.local_time, try dt.toNaiveDateTime());
    }
}

test "naive datetime .formatted()" {
    var a = std.testing.allocator;
    {
        const str = try std.fmt.allocPrint(a, "{}", .{(try NaiveDateTime.ymd_hms(2021, 2, 18, 17, 0, 0)).formatted("%Y-%m-%d %H:%M:%S")});
        defer a.free(str);
        try std.testing.expectEqualSlices(u8, "2021-2-18 17:0:0", str);
    }
    {
        const str = try std.fmt.allocPrint(a, "{%F %T}", .{(try NaiveDateTime.ymd_hms(2021, 2, 18, 17, 0, 0))});
        defer a.free(str);
        try std.testing.expectEqualStrings("2021-2-18 17:0:0", str);
    }
}
