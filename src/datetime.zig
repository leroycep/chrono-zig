const std = @import("std");
const NaiveDate = @import("./date.zig").NaiveDate;
const NaiveTime = @import("./time.zig").NaiveTime;

const DAYS_AFTER_ZERO_EPOCH = 719163;

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
};

test "datetime from timestamp" {
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
