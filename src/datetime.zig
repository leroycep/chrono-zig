const std = @import("std");
const NaiveDate = @import("./date.zig").NaiveDate;
const NaiveTime = @import("./time.zig").NaiveTime;
const timezone = @import("./timezone.zig");
const TimeZone = timezone.TimeZone;

const DAYS_AFTER_ZERO_EPOCH = 719163;
const EPOCH = NaiveDate.ymd(1970, 01, 01).?.hms(0, 0, 0).?;

pub const DateTime = struct {
    /// UTC based date
    datetime: NaiveDateTime,
    /// TimeZone is used to get localtime values
    timezone: *const TimeZone,

    pub fn utc(datetime: NaiveDateTime, tz: *const TimeZone) @This() {
        return .{ .datetime = datetime, .timezone = tz };
    }

    pub fn local(date: NaiveDate, time: NaiveTime, tz: *const TimeZone) @This() {
        @compileError("Creating DateTime using localtime is not yet implemented");
    }

    pub fn toNaiveDateTime(this: @This()) NaiveDateTime {
        const utc_timestamp = this.datetime.signed_duration_since(EPOCH);
        const local_timestamp = this.timezone.utcToLocal(utc_timestamp);
        return NaiveDateTime.from_timestamp(local_timestamp, 0).?;
    }
};

pub const NaiveDateTime = struct {
    date: NaiveDate,
    time: NaiveTime,

    pub fn new(date: NaiveDate, time: NaiveTime) @This() {
        return .{ .date = date, .time = time };
    }

    pub fn from_timestamp(seconds: i64, nsecs: u32) ?@This() {
        const days = @divFloor(seconds, std.time.s_per_day);
        const secs = @mod(seconds, std.time.s_per_day);

        if (std.math.minInt(i32) > days or days > std.math.maxInt(i32)) {
            return null;
        }
        var days_abs = @intCast(i32, days);
        if (@addWithOverflow(i32, days_abs, DAYS_AFTER_ZERO_EPOCH, &days_abs)) {
            return null;
        }
        const date = NaiveDate.from_num_days_from_ce(days_abs) orelse return null;

        const time = NaiveTime.from_num_seconds_from_midnight(@intCast(u32, secs), nsecs) orelse return null;

        return @This(){
            .date = date,
            .time = time,
        };
    }

    pub fn with_timezone(this: @This(), tz: *const TimeZone) DateTime {
        return DateTime{ .datetime = this, .timezone = tz };
    }

    pub fn signed_duration_since(this: @This(), other: @This()) i64 {
        return this.date.signed_duration_since(other.date) + this.time.signed_duration_since(other.time);
    }
};

test "naive datetime from timestamp" {
    std.testing.expectEqual(NaiveDate.ymd(1969, 12, 31).?.hms(23, 59, 59), NaiveDateTime.from_timestamp(-1, 0));
    std.testing.expectEqual(NaiveDate.ymd(1970, 1, 1).?.hms(0, 0, 0), NaiveDateTime.from_timestamp(0, 0));
    std.testing.expectEqual(NaiveDate.ymd(1970, 1, 1).?.hms(0, 0, 1), NaiveDateTime.from_timestamp(1, 0));
    std.testing.expectEqual(NaiveDate.ymd(2001, 9, 9).?.hms(1, 46, 40), NaiveDateTime.from_timestamp(1000000000, 0));
    std.testing.expectEqual(NaiveDate.ymd(2038, 1, 19).?.hms(3, 14, 7), NaiveDateTime.from_timestamp(0x7fffffff, 0));
    std.testing.expectEqual(@as(?NaiveDateTime, null), NaiveDateTime.from_timestamp(std.math.minInt(i64), 0));
    std.testing.expectEqual(@as(?NaiveDateTime, null), NaiveDateTime.from_timestamp(std.math.minInt(i64) + 1, 0));
    std.testing.expectEqual(@as(?NaiveDateTime, null), NaiveDateTime.from_timestamp(std.math.maxInt(i64), 0));
    std.testing.expectEqual(@as(?NaiveDateTime, null), NaiveDateTime.from_timestamp(std.math.maxInt(i64) - 1, 0));
}

test "Pacific/Honolulu datetime from timestamp" {
    var fbs = std.io.fixedBufferStream(@embedFile("timezone/zoneinfo/Pacific/Honolulu"));
    const honolulu = timezone.TimeZone{ .TZif = try timezone.tzif.parse(std.testing.allocator, fbs.reader(), fbs.seekableStream()) };
    defer honolulu.deinit();

    const Case = struct {
        timestamp: i64,
        local_time: NaiveDateTime,
    };

    const cases = [_]Case{
        .{ .timestamp = 1613703600, .local_time = NaiveDate.ymd(2021, 02, 18).?.hms(17, 00, 00).? },
    };

    for (cases) |case| {
        const dt = NaiveDateTime.from_timestamp(case.timestamp, 0).?.with_timezone(&honolulu);
        std.testing.expectEqual(case.local_time, dt.toNaiveDateTime());
    }
}
