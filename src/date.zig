const std = @import("std");
const internals = @import("./internals.zig");
const YearInt = internals.YearInt;
const MonthInt = internals.MonthInt;
const DayInt = internals.DayInt;
const OrdinalInt = internals.OrdinalInt;
const YearFlags = internals.YearFlags;
const Of = internals.Of;
const MIN_YEAR = internals.MIN_YEAR;
const MAX_YEAR = internals.MAX_YEAR;
const NaiveTime = @import("./time.zig").NaiveTime;
const NaiveDateTime = @import("./datetime.zig").NaiveDateTime;
const Weekday = @import("./lib.zig").Weekday;
const IsoWeek = @import("./IsoWeek.zig");
const Month = @import("./lib.zig").Month;

const DateError = error{
    InvalidDate,
};

// TODO: Make packed once packed structs aren't bugged
pub const NaiveDate = struct {
    _year: YearInt,
    _of: internals.Of,

    pub fn from_of(year_param: i32, of: Of) DateError!@This() {
        if (MIN_YEAR <= year_param and year_param <= MAX_YEAR and of.valid()) {
            return @This(){
                ._year = @intCast(YearInt, year_param),
                ._of = of,
            };
        } else {
            return error.InvalidDate;
        }
    }

    pub fn ymd(year_param: i32, month_param: MonthInt, day_param: DayInt) DateError!@This() {
        const flags = internals.YearFlags.from_year(year_param);
        const mdf = internals.Mdf.new(month_param, day_param, flags);
        const of = mdf.to_of();
        return from_of(year_param, of);
    }

    pub fn yo(year_param: i32, ordinal: OrdinalInt) DateError!@This() {
        const flags = internals.YearFlags.from_year(year_param);
        const of = internals.Of.new(ordinal, flags);
        return from_of(year_param, of);
    }

    pub fn isoywd(yearNum: YearInt, week: u32, weekdayParam: Weekday) DateError!@This() {
        const flags = YearFlags.from_year(yearNum);
        const nweeks = flags.nisoweeks();
        if (1 <= week and week <= nweeks) {
            const weekord = week * 7 + @enumToInt(weekdayParam);
            const delta = flags.isoweek_delta();
            if (weekord <= delta) {
                const prevflags = YearFlags.from_year(yearNum - 1);
                return @This(){
                    ._year = yearNum - 1,
                    ._of = internals.Of.new(weekord + prevflags.ndays() - delta, prevflags),
                };
            } else {
                const ordinal = weekord - delta;
                const ndays = flags.ndays();
                if (ordinal <= ndays) {
                    return @This(){
                        ._year = yearNum,
                        ._of = internals.Of.new(ordinal, flags),
                    };
                } else {
                    const nextflags = YearFlags.from_year(yearNum + 1);
                    return @This(){
                        ._year = yearNum + 1,
                        ._of = internals.Of.new(ordinal - ndays, nextflags),
                    };
                }
            }
        } else {
            return error.InvalidDate;
        }
    }

    pub fn succ(this: @This()) !@This() {
        const of = this._of.succ();
        if (!of.valid()) {
            var new_year: YearInt = undefined;
            if (@addWithOverflow(YearInt, this._year, 1, &new_year)) return error.Overflow;
            return yo(new_year, 1);
        } else {
            return @This(){
                ._year = this._year,
                ._of = of,
            };
        }
    }

    pub fn pred(this: @This()) !@This() {
        const of = this._of.pred();
        if (!of.valid()) {
            var new_year: YearInt = undefined;
            if (@subWithOverflow(YearInt, this._year, 1, &new_year)) return error.Overflow;
            return ymd(new_year, 12, 31);
        } else {
            return @This(){
                ._year = this._year,
                ._of = of,
            };
        }
    }

    pub fn hms(this: @This(), hour: u32, minute: u32, second: u32) !NaiveDateTime {
        const time = try NaiveTime.hms(hour, minute, second);
        return NaiveDateTime.new(this, time);
    }

    const DAYS_IN_400_YEARS = 146_097;

    pub fn from_num_days_from_ce(days: i32) !@This() {
        const days_1bce = days + 365;

        const year_div_400 = @divFloor(days_1bce, DAYS_IN_400_YEARS);
        const cycle = @mod(days_1bce, DAYS_IN_400_YEARS);

        const res = internals.cycle_to_yo(@intCast(u32, cycle));
        const flags = YearFlags.from_year_mod_400(res.year_mod_400);

        return NaiveDate.from_of(year_div_400 * 400 + @intCast(i32, res.year_mod_400), Of.new(res.ordinal, flags));
    }

    pub fn year(this: @This()) YearInt {
        return this._year;
    }

    pub fn month(this: @This()) Month {
        return @intToEnum(Month, this._of.to_mdf().month);
    }

    pub fn day(this: @This()) internals.DayInt {
        return this._of.to_mdf().day;
    }

    pub fn isoweek(this: @This()) IsoWeek {
        return IsoWeek.from_yof(this._year, this._of);
    }

    pub fn weekday(this: @This()) Weekday {
        const weekord = this._of.ordinal +% this._of.year_flags.isoweek_delta();
        return @intToEnum(Weekday, @intCast(u3, weekord % 7));
    }

    pub fn signed_duration_since(this: @This(), other: @This()) i64 {
        const year1 = this.year();
        const year1_div_400 = @intCast(i64, @divFloor(year1, 400));
        const year1_mod_400 = @mod(year1, 400);
        const cycle1 = @intCast(i64, internals.yo_to_cycle(@intCast(u32, year1_mod_400), this._of.ordinal));

        const year2 = other.year();
        const year2_div_400 = @intCast(i64, @divFloor(year2, 400));
        const year2_mod_400 = @mod(year2, 400);
        const cycle2 = @intCast(i64, internals.yo_to_cycle(@intCast(u32, year2_mod_400), other._of.ordinal));

        return ((year1_div_400 - year2_div_400) * DAYS_IN_400_YEARS + (cycle1 - cycle2)) * std.time.s_per_day;
    }
};

pub const MIN_DATE = NaiveDate{ .ymdf = (MIN_YEAR << 13) | (1 << 4) | internals.YearFlags.from_year(MIN_YEAR) };

test "date from ymd" {
    const ymd = NaiveDate.ymd;

    try std.testing.expectError(error.InvalidDate, ymd(2012, 0, 1));
    _ = try ymd(2012, 1, 1);
    _ = try ymd(2012, 2, 29);
    try std.testing.expectError(error.InvalidDate, ymd(2014, 2, 29));
    try std.testing.expectError(error.InvalidDate, ymd(2014, 3, 0));
    _ = try ymd(2014, 3, 1);
    _ = try ymd(2014, 3, 31);
    _ = try ymd(2014, 12, 31);
    try std.testing.expectError(error.InvalidDate, ymd(2014, 13, 1));
}

test "date from year-ordinal" {
    const yo = NaiveDate.yo;
    const ymd = NaiveDate.ymd;

    try std.testing.expectError(error.InvalidDate, yo(2012, 0));
    try std.testing.expectEqual(try ymd(2012, 1, 1), try yo(2012, 1));
    try std.testing.expectEqual(try ymd(2012, 1, 2), try yo(2012, 2));
    try std.testing.expectEqual(try ymd(2012, 2, 1), try yo(2012, 32));
    try std.testing.expectEqual(try ymd(2012, 2, 29), try yo(2012, 60));
    try std.testing.expectEqual(try ymd(2012, 3, 1), try yo(2012, 61));
    try std.testing.expectEqual(try ymd(2012, 4, 9), try yo(2012, 100));
    try std.testing.expectEqual(try ymd(2012, 7, 18), try yo(2012, 200));
    try std.testing.expectEqual(try ymd(2012, 10, 26), try yo(2012, 300));
    try std.testing.expectEqual(try ymd(2012, 12, 31), try yo(2012, 366));
    try std.testing.expectError(error.InvalidDate, yo(2012, 367));

    try std.testing.expectError(error.InvalidDate, yo(2014, 0));
    try std.testing.expectEqual(try ymd(2014, 1, 1), try yo(2014, 1));
    try std.testing.expectEqual(try ymd(2014, 1, 2), try yo(2014, 2));
    try std.testing.expectEqual(try ymd(2014, 2, 1), try yo(2014, 32));
    try std.testing.expectEqual(try ymd(2014, 2, 28), try yo(2014, 59));
    try std.testing.expectEqual(try ymd(2014, 3, 1), try yo(2014, 60));
    try std.testing.expectEqual(try ymd(2014, 4, 10), try yo(2014, 100));
    try std.testing.expectEqual(try ymd(2014, 7, 19), try yo(2014, 200));
    try std.testing.expectEqual(try ymd(2014, 10, 27), try yo(2014, 300));
    try std.testing.expectEqual(try ymd(2014, 12, 31), try yo(2014, 365));
    try std.testing.expectError(error.InvalidDate, yo(2014, 366));
}

test "date from isoywd" {
    const isoywd = NaiveDate.isoywd;
    const ymd = NaiveDate.ymd;

    try std.testing.expectError(error.InvalidDate, isoywd(2004, 0, .sun));
    try std.testing.expectEqual(try ymd(2003, 12, 29), try isoywd(2004, 1, .mon));
    try std.testing.expectEqual(try ymd(2004, 1, 4), try isoywd(2004, 1, .sun));
    try std.testing.expectEqual(try ymd(2004, 1, 5), try isoywd(2004, 2, .mon));
    try std.testing.expectEqual(try ymd(2004, 1, 11), try isoywd(2004, 2, .sun));
    try std.testing.expectEqual(try ymd(2004, 12, 20), try isoywd(2004, 52, .mon));
    try std.testing.expectEqual(try ymd(2004, 12, 26), try isoywd(2004, 52, .sun));
    try std.testing.expectEqual(try ymd(2004, 12, 27), try isoywd(2004, 53, .mon));
    try std.testing.expectEqual(try ymd(2005, 1, 2), try isoywd(2004, 53, .sun));
    try std.testing.expectError(error.InvalidDate, isoywd(2004, 54, .mon));

    try std.testing.expectError(error.InvalidDate, isoywd(2011, 0, .sun));
    try std.testing.expectEqual(try ymd(2011, 1, 3), try isoywd(2011, 1, .mon));
    try std.testing.expectEqual(try ymd(2011, 1, 9), try isoywd(2011, 1, .sun));
    try std.testing.expectEqual(try ymd(2011, 1, 10), try isoywd(2011, 2, .mon));
    try std.testing.expectEqual(try ymd(2011, 1, 16), try isoywd(2011, 2, .sun));

    try std.testing.expectEqual(try ymd(2018, 12, 17), try isoywd(2018, 51, .mon));
    try std.testing.expectEqual(try ymd(2018, 12, 23), try isoywd(2018, 51, .sun));
    try std.testing.expectEqual(try ymd(2018, 12, 24), try isoywd(2018, 52, .mon));
    try std.testing.expectEqual(try ymd(2018, 12, 30), try isoywd(2018, 52, .sun));
    try std.testing.expectError(error.InvalidDate, isoywd(2018, 53, .mon));
}

test "date successor" {
    const ymd = NaiveDate.ymd;
    try std.testing.expectEqual((try ymd(2014, 5, 7)), try (try ymd(2014, 5, 6)).succ());
    try std.testing.expectEqual((try ymd(2014, 6, 1)), try (try ymd(2014, 5, 31)).succ());
    try std.testing.expectEqual((try ymd(2015, 1, 1)), try (try ymd(2014, 12, 31)).succ());
    try std.testing.expectEqual((try ymd(2016, 2, 29)), try (try ymd(2016, 2, 28)).succ());
    try std.testing.expectError(error.Overflow, (try ymd(MAX_YEAR, 12, 31)).succ());
}

test "date predecessor" {
    const ymd = NaiveDate.ymd;
    try std.testing.expectEqual((try ymd(2016, 2, 29)), try (try ymd(2016, 3, 1)).pred());
    try std.testing.expectEqual((try ymd(2014, 12, 31)), try (try ymd(2015, 1, 1)).pred());
    try std.testing.expectEqual((try ymd(2014, 5, 31)), try (try ymd(2014, 6, 1)).pred());
    try std.testing.expectEqual((try ymd(2014, 5, 6)), try (try ymd(2014, 5, 7)).pred());
    try std.testing.expectError(error.Overflow, (try ymd(MIN_YEAR, 1, 1)).pred());
}

test "date signed duration since" {
    const ymd = NaiveDate.ymd;
    try std.testing.expectEqual(@as(i64, 86400), (try ymd(2016, 3, 1)).signed_duration_since((try ymd(2016, 2, 29))));
    try std.testing.expectEqual(@as(i64, 1613952000), (try ymd(2021, 2, 22)).signed_duration_since((try ymd(1970, 1, 1))));
}
