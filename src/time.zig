const std = @import("std");

const min_per_hour = std.time.s_per_hour / std.time.s_per_min;
const s_per_hour = std.time.s_per_hour;
const s_per_min = std.time.s_per_min;

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

/// Frac can be up to two milliseconds to represent leap seconds
pub const MAX_FRAC = 2 * std.time.ns_per_ms;
pub const FracInt = @Type(.{
    .Int = .{
        .bits = std.math.log2_int_ceil(u64, MAX_FRAC),
        .signedness = .unsigned,
    },
});

pub const NaiveTime = struct {
    secs: SecsInt,
    frac: FracInt,

    pub fn hms(hr: u32, min: u32, sec: u32) ?@This() {
        return hms_nano(hr, min, sec, 0);
    }

    pub fn hms_nano(hr: u32, min: u32, sec: u32, nano: u32) ?@This() {
        if (hr >= MAX_HOURS or min >= min_per_hour or sec >= std.time.s_per_min or nano >= MAX_FRAC) {
            return null;
        }
        return NaiveTime{
            .secs = @intCast(SecsInt, hr * std.time.s_per_hour + min * std.time.s_per_min + sec),
            .frac = @intCast(FracInt, nano),
        };
    }

    pub fn hour(this: @This()) HoursInt {
        const mins = this.secs / std.time.s_per_min;
        const hr = mins / min_per_hour;
        return @intCast(HoursInt, hr);
    }

    pub fn with_hour(this: @This(), hr: HoursInt) ?@This() {
        if (hr >= MAX_HOURS) {
            return null;
        }
        const secs = @intCast(u32, hr) * s_per_hour + @intCast(u32, this.secs) % s_per_hour;
        return @This(){
            .secs = @intCast(SecsInt, secs),
            .frac = this.frac,
        };
    }

    pub fn minute(this: @This()) MinutesInt {
        const mins = this.secs / std.time.s_per_min;
        const min = mins % min_per_hour;
        return @intCast(MinutesInt, min);
    }

    pub fn with_minute(this: @This(), min: MinutesInt) ?@This() {
        if (min >= min_per_hour) {
            return null;
        }
        const secs = (@intCast(u32, this.secs) / s_per_hour * s_per_hour) + (@intCast(u32, min) * s_per_min) + (this.secs % s_per_min);
        return @This(){
            .secs = @intCast(SecsInt, secs),
            .frac = this.frac,
        };
    }

    pub fn second(this: @This()) SecondsInt {
        return @intCast(SecondsInt, this.secs % (s_per_min));
    }

    pub fn with_second(this: @This(), sec: SecondsInt) ?@This() {
        if (sec >= s_per_min) {
            return null;
        }
        const secs = @intCast(u32, this.secs) / s_per_min * s_per_min + sec;
        return @This(){
            .secs = @intCast(SecsInt, secs),
            .frac = this.frac,
        };
    }

    pub fn from_num_seconds_from_midnight(secs: u32, nano: u32) ?@This() {
        if (secs >= std.time.s_per_day or nano >= MAX_FRAC) {
            return null;
        }
        return @This(){ .secs = @intCast(SecsInt, secs), .frac = @intCast(FracInt, nano) };
    }
};

test "time hour, minute, second" {
    std.testing.expectEqual(@as(HoursInt, 3), NaiveTime.hms(3, 5, 7).?.hour());
    std.testing.expectEqual(NaiveTime.hms(0, 5, 7), NaiveTime.hms(3, 5, 7).?.with_hour(0));
    std.testing.expectEqual(NaiveTime.hms(23, 5, 7), NaiveTime.hms(3, 5, 7).?.with_hour(23));
    std.testing.expectEqual(@as(?NaiveTime, null), NaiveTime.hms(3, 5, 7).?.with_hour(24));
    std.testing.expectEqual(@as(?NaiveTime, null), NaiveTime.hms(3, 5, 7).?.with_hour(std.math.maxInt(HoursInt)));

    std.testing.expectEqual(@as(MinutesInt, 5), NaiveTime.hms(3, 5, 7).?.minute());
    std.testing.expectEqual(NaiveTime.hms(3, 0, 7), NaiveTime.hms(3, 5, 7).?.with_minute(0));
    std.testing.expectEqual(NaiveTime.hms(3, 59, 7), NaiveTime.hms(3, 5, 7).?.with_minute(59));
    std.testing.expectEqual(@as(?NaiveTime, null), NaiveTime.hms(3, 5, 7).?.with_minute(60));
    std.testing.expectEqual(@as(?NaiveTime, null), NaiveTime.hms(3, 5, 7).?.with_minute(std.math.maxInt(MinutesInt)));

    std.testing.expectEqual(@as(MinutesInt, 7), NaiveTime.hms(3, 5, 7).?.second());
    std.testing.expectEqual(NaiveTime.hms(3, 5, 0), NaiveTime.hms(3, 5, 7).?.with_second(0));
    std.testing.expectEqual(NaiveTime.hms(3, 5, 59), NaiveTime.hms(3, 5, 7).?.with_second(59));
    std.testing.expectEqual(@as(?NaiveTime, null), NaiveTime.hms(3, 5, 7).?.with_second(60));
    std.testing.expectEqual(@as(?NaiveTime, null), NaiveTime.hms(3, 5, 7).?.with_second(std.math.maxInt(MinutesInt)));
}
