//! This is an implementation of [Howard Hinnant's `chrono` (the C++ version) compatible date algorithms][date_algorithms].
//! Some of the algorithms have been renamed, in an effort to make the them more descriptive.
//!
//! [date_algorithms]: https://howardhinnant.github.io/date_algorithms.html

pub const UNIX_EPOCH = YearMonthDay{
    .year = 1970,
    .month = .jan,
    .day = 1,
};

pub const YearMonthDay = packed struct(i32) {
    year: YearInt,
    month: Month,
    /// The day of the month. Must be a number from 1 to `month.lastDay(year)`
    day: Month.DayInt,

    pub const YearInt = i23;

    pub fn fromComponents(year: YearInt, month: Month, day: Month.DayInt) YearMonthDay {
        return YearMonthDay{
            .year = year,
            .month = month,
            .day = day,
        };
    }

    pub fn fromNumbers(year: YearInt, month: Month.Int, day: Month.DayInt) YearMonthDay {
        return YearMonthDay{
            .year = year,
            .month = @enumFromInt(month),
            .day = day,
        };
    }

    /// Given and year, month, and a day, returns the number of days since the Unix Epoch. Negative values indicate
    /// years prior to the Unix Epoch.
    pub fn toDaysSinceUnixEpoch(ymd: YearMonthDay) i32 {
        return ymd.toDays() - UNIX_EPOCH.toDays();
    }

    /// Given and year, month, and a day, returns the number of days since `0000-01-01`. Negative values indicate
    /// years prior to year 0000.
    pub fn toDays(ymd: YearMonthDay) i32 {
        // The year number, if we consider March 1st to be the start of the year. This is convenient because it puts the leap day,
        // Feb. 29 as the last day of the year, or actually the preceding year. That is, Feb. 15, 2000, is considered by this algorithm
        // to be the 15th day of the last month of the year 1999.
        const march_year = if (@intFromEnum(ymd.month) <= 2) ymd.year - 1 else ymd.year;
        const era: i32 = @divFloor(march_year, YEARS_PER_ERA);
        const year_of_era: YearInt = @intCast(@mod(march_year, YEARS_PER_ERA));

        // An unsigned number in the range of [0, 364] for a non-leap year, and for leap years has a range of [0, 365]. A value of 0
        // corresponds to Mar 1, and a value of 364 corresponds to Feb. 28 of the following (civil) year.
        const march_month = MarchYear.fromCivilMonth(@intFromEnum(ymd.month));
        const day_of_year = (ymd.day - 1) + MarchYear.dayOfYearFromMonth(march_month);

        const number_of_four_year_periods = @divFloor(year_of_era, 4);
        const centuries = @divFloor(year_of_era, 100);
        const leap_days_in_era = number_of_four_year_periods - centuries;

        const day_of_era = @as(i32, year_of_era) * DAYS_PER_COMMON_YEAR +
            leap_days_in_era +
            day_of_year;

        return era * DAYS_PER_ERA + day_of_era + (DAYS_BEFORE_MARCH_1ST_0000);
    }

    /// Returns the year, month, and day when given number of days since the Unix Epoch.
    pub fn fromDaysSinceUnixEpoch(days_since_epoch: i32) YearMonthDay {
        return fromDays(days_since_epoch + UNIX_EPOCH.toDays());
    }

    /// Returns the year, month, and day when given number of days since year 0000.
    pub fn fromDays(days_raw: i32) YearMonthDay {
        const days = days_raw - (DAYS_BEFORE_MARCH_1ST_0000);
        const era: i32 = @divFloor(days, DAYS_PER_ERA);
        const day_of_era: u24 = @intCast(@mod(days, DAYS_PER_ERA));

        const leap_days = leapDaysSinceEraBegan(day_of_era);
        const year_of_era = @divFloor(day_of_era - leap_days, DAYS_PER_COMMON_YEAR);

        const year = era * YEARS_PER_ERA + @as(i32, @intCast(year_of_era));

        const day_of_year: u24 = day_of_era - (DAYS_PER_COMMON_YEAR * year_of_era + @divFloor(year_of_era, 4) - @divFloor(year_of_era, 100));

        const march_month_of_year = MarchYear.monthFromDayOfYear(day_of_year);
        const day_of_month = day_of_year - MarchYear.dayOfYearFromMonth(march_month_of_year) + 1;

        const month = MarchYear.toCivilMonth(march_month_of_year);

        return YearMonthDay{
            .year = @intCast(year + @intFromBool(month <= 2)),
            .month = @enumFromInt(month),
            .day = @intCast(day_of_month),
        };
    }

    pub fn format(
        this: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        const sign_str = if (this.year < 0) "-" else "";

        try std.fmt.format(writer, "{s}{:0>4}-{:0>2}-{:0>2}", .{ sign_str, std.math.absCast(this.year), @intFromEnum(this.month), this.day });
    }
};

fn leapDaysSinceEraBegan(day_of_era: u24) u24 {
    const leap_days = day_of_era / (COMMON_DAYS_PER_4_YEAR_PERIOD - 1);
    const leap_days_skipped_by_centuries = day_of_era / (COMMON_DAYS_PER_CENTURY - 1);
    const leap_days_unskipped_by_eras = day_of_era / (DAYS_PER_ERA - 1);
    return leap_days - leap_days_skipped_by_centuries + leap_days_unskipped_by_eras;
}

test leapDaysSinceEraBegan {
    try std.testing.expectEqual(@as(u24, 0), leapDaysSinceEraBegan(365));
    try std.testing.expectEqual(@as(u24, 0), leapDaysSinceEraBegan(1459));
    try std.testing.expectEqual(@as(u24, 1), leapDaysSinceEraBegan(1460));
    try std.testing.expectEqual(@as(u24, 1), leapDaysSinceEraBegan(1461));
    try std.testing.expectEqual(@as(u24, 24), leapDaysSinceEraBegan(36523));
    try std.testing.expectEqual(@as(u24, 24), leapDaysSinceEraBegan(36524));
    try std.testing.expectEqual(@as(u24, 24), leapDaysSinceEraBegan(36525));
    try std.testing.expectEqual(@as(u24, 96), leapDaysSinceEraBegan(146095));
    try std.testing.expectEqual(@as(u24, 97), leapDaysSinceEraBegan(146096));
}

const MarchYear = struct {
    pub fn fromCivilMonth(civil_month: Month.Int) Month.Int {
        return @intCast((@as(u6, civil_month) + 9) % 12);
    }

    test fromCivilMonth {
        try std.testing.expectEqual(@as(Month.Int, 10), fromCivilMonth(1));
        try std.testing.expectEqual(@as(Month.Int, 11), fromCivilMonth(2));
        try std.testing.expectEqual(@as(Month.Int, 0), fromCivilMonth(3));
        try std.testing.expectEqual(@as(Month.Int, 1), fromCivilMonth(4));
        try std.testing.expectEqual(@as(Month.Int, 2), fromCivilMonth(5));
        try std.testing.expectEqual(@as(Month.Int, 3), fromCivilMonth(6));
        try std.testing.expectEqual(@as(Month.Int, 4), fromCivilMonth(7));
        try std.testing.expectEqual(@as(Month.Int, 5), fromCivilMonth(8));
        try std.testing.expectEqual(@as(Month.Int, 6), fromCivilMonth(9));
        try std.testing.expectEqual(@as(Month.Int, 7), fromCivilMonth(10));
        try std.testing.expectEqual(@as(Month.Int, 8), fromCivilMonth(11));
        try std.testing.expectEqual(@as(Month.Int, 9), fromCivilMonth(12));
    }

    pub fn toCivilMonth(march_month: Month.Int) Month.Int {
        return @intCast((@as(u6, march_month) + 12 - 10) % 12 + 1);
    }

    test toCivilMonth {
        try std.testing.expectEqual(@as(Month.Int, 1), toCivilMonth(10));
        try std.testing.expectEqual(@as(Month.Int, 2), toCivilMonth(11));
        try std.testing.expectEqual(@as(Month.Int, 3), toCivilMonth(0));
        try std.testing.expectEqual(@as(Month.Int, 4), toCivilMonth(1));
        try std.testing.expectEqual(@as(Month.Int, 5), toCivilMonth(2));
        try std.testing.expectEqual(@as(Month.Int, 6), toCivilMonth(3));
        try std.testing.expectEqual(@as(Month.Int, 7), toCivilMonth(4));
        try std.testing.expectEqual(@as(Month.Int, 8), toCivilMonth(5));
        try std.testing.expectEqual(@as(Month.Int, 9), toCivilMonth(6));
        try std.testing.expectEqual(@as(Month.Int, 10), toCivilMonth(7));
        try std.testing.expectEqual(@as(Month.Int, 11), toCivilMonth(8));
        try std.testing.expectEqual(@as(Month.Int, 12), toCivilMonth(9));
    }

    pub fn dayOfYearFromMonth(march_month: Month.Int) u24 {
        return @divFloor((153 * @as(u24, march_month) + 2), 5);
    }

    test dayOfYearFromMonth {
        try std.testing.expectEqual(@as(i32, 0), dayOfYearFromMonth(0));
        try std.testing.expectEqual(@as(i32, 31), dayOfYearFromMonth(1));
        try std.testing.expectEqual(@as(i32, 61), dayOfYearFromMonth(2));
        try std.testing.expectEqual(@as(i32, 92), dayOfYearFromMonth(3));
        try std.testing.expectEqual(@as(i32, 122), dayOfYearFromMonth(4));
        try std.testing.expectEqual(@as(i32, 153), dayOfYearFromMonth(5));
        try std.testing.expectEqual(@as(i32, 184), dayOfYearFromMonth(6));
        try std.testing.expectEqual(@as(i32, 214), dayOfYearFromMonth(7));
        try std.testing.expectEqual(@as(i32, 245), dayOfYearFromMonth(8));
        try std.testing.expectEqual(@as(i32, 275), dayOfYearFromMonth(9));
        try std.testing.expectEqual(@as(i32, 306), dayOfYearFromMonth(10));
        try std.testing.expectEqual(@as(i32, 337), dayOfYearFromMonth(11));
    }

    pub fn monthFromDayOfYear(march_day_of_year: u24) Month.Int {
        return @intCast((5 * march_day_of_year + 2) / 153);
    }

    test monthFromDayOfYear {
        try std.testing.expectEqual(@as(i32, 0), monthFromDayOfYear(0));
        try std.testing.expectEqual(@as(i32, 1), monthFromDayOfYear(31));
        try std.testing.expectEqual(@as(i32, 2), monthFromDayOfYear(61));
        try std.testing.expectEqual(@as(i32, 3), monthFromDayOfYear(92));
        try std.testing.expectEqual(@as(i32, 4), monthFromDayOfYear(122));
        try std.testing.expectEqual(@as(i32, 5), monthFromDayOfYear(153));
        try std.testing.expectEqual(@as(i32, 6), monthFromDayOfYear(184));
        try std.testing.expectEqual(@as(i32, 7), monthFromDayOfYear(214));
        try std.testing.expectEqual(@as(i32, 8), monthFromDayOfYear(245));
        try std.testing.expectEqual(@as(i32, 9), monthFromDayOfYear(275));
        try std.testing.expectEqual(@as(i32, 10), monthFromDayOfYear(306));
        try std.testing.expectEqual(@as(i32, 11), monthFromDayOfYear(337));
    }
};

const UNIX_EPOCH_WEEKDAY = Weekday.thu;

const DAYS_BEFORE_MARCH_1ST_0000 = 31 + 29;
test "0000 is a leap year" {
    try std.testing.expect(isLeapYear(0));
}

const DAYS_PER_COMMON_YEAR = 365;
const DAYS_PER_LEAP_YEAR = DAYS_PER_COMMON_YEAR + 1;

const YEARS_PER_ERA = 400;
const DAYS_PER_ERA = YEARS_PER_ERA * DAYS_PER_COMMON_YEAR + LEAP_YEARS_PER_ERA;
const LEAP_YEARS_PER_ERA = FOUR_YEAR_PERIODS_PER_ERA - CENTURIES_PER_ERA + 1;
const FOUR_YEAR_PERIODS_PER_ERA = YEARS_PER_ERA / 4;
const CENTURIES_PER_ERA = YEARS_PER_ERA / YEARS_PER_CENTURY;

const YEARS_PER_CENTURY = 100;
/// Days per century, not including the effect of eras
const COMMON_DAYS_PER_CENTURY = COMMON_DAYS_PER_4_YEAR_PERIOD * FOUR_YEAR_PERIODS_PER_CENTURY - 1;

/// Days per 4 year period, not including the effect centuries
const COMMON_DAYS_PER_4_YEAR_PERIOD = 4 * DAYS_PER_COMMON_YEAR + 1;
const LEAP_YEARS_PER_CENTURY = FOUR_YEAR_PERIODS_PER_CENTURY - 1;
const FOUR_YEAR_PERIODS_PER_CENTURY = YEARS_PER_CENTURY / 4;

test "constant math" {
    try std.testing.expectEqual(25, FOUR_YEAR_PERIODS_PER_CENTURY);
    try std.testing.expectEqual(24, LEAP_YEARS_PER_CENTURY);

    try std.testing.expectEqual(1461, COMMON_DAYS_PER_4_YEAR_PERIOD);
    try std.testing.expectEqual(36524, COMMON_DAYS_PER_CENTURY);
    try std.testing.expectEqual(146097, DAYS_PER_ERA);
}

pub const WEEKDAYS = [_]Weekday{
    .mon,
    .tue,
    .wed,
    .thu,
    .fri,
    .sat,
    .sun,
};

pub const Weekday = enum(u3) {
    mon = 0,
    tue = 1,
    wed = 2,
    thu = 3,
    fri = 4,
    sat = 5,
    sun = 6,

    pub const COUNT = @as(comptime_int, WEEKDAYS.len);

    pub fn fullName(this: @This()) []const u8 {
        return switch (this) {
            .mon => "Monday",
            .tue => "Tuesday",
            .wed => "Wednesday",
            .thu => "Thursday",
            .fri => "Friday",
            .sat => "Saturday",
            .sun => "Sunday",
        };
    }

    pub fn shortName(this: @This()) [3:0]u8 {
        return (switch (this) {
            .mon => "Mon",
            .tue => "Tue",
            .wed => "Wed",
            .thu => "Thu",
            .fri => "Fri",
            .sat => "Sat",
            .sun => "Sun",
        }).*;
    }

    pub fn fromDaysSinceUnixEpoch(days_since_epoch: i64) @This() {
        return @enumFromInt(@mod((days_since_epoch +% @intFromEnum(UNIX_EPOCH_WEEKDAY)), @as(u3, WEEKDAYS.len)));
    }

    /// Returns number of days from the weekday `b` to the weekday `a`
    pub fn difference(a: @This(), b: @This()) u3 {
        const num_weekdays: u3 = WEEKDAYS.len;
        return @intCast((@as(u4, @intFromEnum(a)) + num_weekdays - @intFromEnum(b)) % num_weekdays);
    }

    test difference {
        try std.testing.expectEqual(@as(u3, 0), difference(.sun, .sun));
        try std.testing.expectEqual(@as(u3, 6), difference(.sun, .mon));
        try std.testing.expectEqual(@as(u3, 5), difference(.sun, .tue));
        try std.testing.expectEqual(@as(u3, 4), difference(.sun, .wed));
        try std.testing.expectEqual(@as(u3, 3), difference(.sun, .thu));
        try std.testing.expectEqual(@as(u3, 2), difference(.sun, .fri));
        try std.testing.expectEqual(@as(u3, 1), difference(.sun, .sat));

        try std.testing.expectEqual(@as(u3, 1), difference(.mon, .sun));
        try std.testing.expectEqual(@as(u3, 0), difference(.mon, .mon));
        try std.testing.expectEqual(@as(u3, 6), difference(.mon, .tue));
        try std.testing.expectEqual(@as(u3, 5), difference(.mon, .wed));
        try std.testing.expectEqual(@as(u3, 4), difference(.mon, .thu));
        try std.testing.expectEqual(@as(u3, 3), difference(.mon, .fri));
        try std.testing.expectEqual(@as(u3, 2), difference(.mon, .sat));

        try std.testing.expectEqual(@as(u3, 2), difference(.tue, .sun));
        try std.testing.expectEqual(@as(u3, 1), difference(.tue, .mon));
        try std.testing.expectEqual(@as(u3, 0), difference(.tue, .tue));
        try std.testing.expectEqual(@as(u3, 6), difference(.tue, .wed));
        try std.testing.expectEqual(@as(u3, 5), difference(.tue, .thu));
        try std.testing.expectEqual(@as(u3, 4), difference(.tue, .fri));
        try std.testing.expectEqual(@as(u3, 3), difference(.tue, .sat));

        try std.testing.expectEqual(@as(u3, 3), difference(.wed, .sun));
        try std.testing.expectEqual(@as(u3, 2), difference(.wed, .mon));
        try std.testing.expectEqual(@as(u3, 1), difference(.wed, .tue));
        try std.testing.expectEqual(@as(u3, 0), difference(.wed, .wed));
        try std.testing.expectEqual(@as(u3, 6), difference(.wed, .thu));
        try std.testing.expectEqual(@as(u3, 5), difference(.wed, .fri));
        try std.testing.expectEqual(@as(u3, 4), difference(.wed, .sat));

        try std.testing.expectEqual(@as(u3, 4), difference(.thu, .sun));
        try std.testing.expectEqual(@as(u3, 3), difference(.thu, .mon));
        try std.testing.expectEqual(@as(u3, 2), difference(.thu, .tue));
        try std.testing.expectEqual(@as(u3, 1), difference(.thu, .wed));
        try std.testing.expectEqual(@as(u3, 0), difference(.thu, .thu));
        try std.testing.expectEqual(@as(u3, 6), difference(.thu, .fri));
        try std.testing.expectEqual(@as(u3, 5), difference(.thu, .sat));

        try std.testing.expectEqual(@as(u3, 5), difference(.fri, .sun));
        try std.testing.expectEqual(@as(u3, 4), difference(.fri, .mon));
        try std.testing.expectEqual(@as(u3, 3), difference(.fri, .tue));
        try std.testing.expectEqual(@as(u3, 2), difference(.fri, .wed));
        try std.testing.expectEqual(@as(u3, 1), difference(.fri, .thu));
        try std.testing.expectEqual(@as(u3, 0), difference(.fri, .fri));
        try std.testing.expectEqual(@as(u3, 6), difference(.fri, .sat));

        try std.testing.expectEqual(@as(u3, 6), difference(.sat, .sun));
        try std.testing.expectEqual(@as(u3, 5), difference(.sat, .mon));
        try std.testing.expectEqual(@as(u3, 4), difference(.sat, .tue));
        try std.testing.expectEqual(@as(u3, 3), difference(.sat, .wed));
        try std.testing.expectEqual(@as(u3, 2), difference(.sat, .thu));
        try std.testing.expectEqual(@as(u3, 1), difference(.sat, .fri));
        try std.testing.expectEqual(@as(u3, 0), difference(.sat, .sat));
    }

    pub fn next(this: @This()) @This() {
        return @enumFromInt((@intFromEnum(this) +% 1) % @as(u3, WEEKDAYS.len));
    }

    test next {
        try std.testing.expectEqual(@as(Weekday, .mon), next(.sun));
        try std.testing.expectEqual(@as(Weekday, .tue), next(.mon));
        try std.testing.expectEqual(@as(Weekday, .wed), next(.tue));
        try std.testing.expectEqual(@as(Weekday, .thu), next(.wed));
        try std.testing.expectEqual(@as(Weekday, .fri), next(.thu));
        try std.testing.expectEqual(@as(Weekday, .sat), next(.fri));
        try std.testing.expectEqual(@as(Weekday, .sun), next(.sat));
    }

    pub fn prev(this: @This()) @This() {
        const num_weekdays: u3 = WEEKDAYS.len;
        return @enumFromInt((@as(u4, @intFromEnum(this)) + num_weekdays -% 1) % num_weekdays);
    }

    test prev {
        try std.testing.expectEqual(@as(Weekday, .sat), prev(.sun));
        try std.testing.expectEqual(@as(Weekday, .sun), prev(.mon));
        try std.testing.expectEqual(@as(Weekday, .mon), prev(.tue));
        try std.testing.expectEqual(@as(Weekday, .tue), prev(.wed));
        try std.testing.expectEqual(@as(Weekday, .wed), prev(.thu));
        try std.testing.expectEqual(@as(Weekday, .thu), prev(.fri));
        try std.testing.expectEqual(@as(Weekday, .fri), prev(.sat));
    }

    /// Convert the weekday to an integer, with Monday as day 0
    pub fn toIntMon0(this: @This()) u3 {
        return @intFromEnum(this);
    }

    /// Convert the weekday to an integer, with Sunday as 0
    pub fn toIntSun0(this: @This()) u3 {
        return @intCast((@as(u4, @intFromEnum(this)) + COUNT + 1) % COUNT);
    }

    test toIntSun0 {
        try std.testing.expectEqual(@as(u3, 0), toIntSun0(.sun));
        try std.testing.expectEqual(@as(u3, 1), toIntSun0(.mon));
        try std.testing.expectEqual(@as(u3, 2), toIntSun0(.tue));
        try std.testing.expectEqual(@as(u3, 3), toIntSun0(.wed));
        try std.testing.expectEqual(@as(u3, 4), toIntSun0(.thu));
        try std.testing.expectEqual(@as(u3, 5), toIntSun0(.fri));
        try std.testing.expectEqual(@as(u3, 6), toIntSun0(.sat));
    }

    /// Convert the weekday to an integer, with Sunday as 0
    pub fn fromIntSun0(int: u3) @This() {
        return @enumFromInt((@as(u4, int) + COUNT - 1) % COUNT);
    }

    test fromIntSun0 {
        try std.testing.expectEqual(@This().sun, fromIntSun0(0));
        try std.testing.expectEqual(@This().mon, fromIntSun0(1));
        try std.testing.expectEqual(@This().tue, fromIntSun0(2));
        try std.testing.expectEqual(@This().wed, fromIntSun0(3));
        try std.testing.expectEqual(@This().thu, fromIntSun0(4));
        try std.testing.expectEqual(@This().fri, fromIntSun0(5));
        try std.testing.expectEqual(@This().sat, fromIntSun0(6));
    }
};

pub const MONTHS = [_]Month{
    .jan,
    .feb,
    .mar,
    .apr,
    .may,
    .jun,
    .jul,
    .aug,
    .sep,
    .oct,
    .nov,
    .dec,
};

pub const Month = enum(u4) {
    jan = 1,
    feb,
    mar,
    apr,
    may,
    jun,
    jul,
    aug,
    sep,
    oct,
    nov,
    dec,

    pub const Int = u4;
    pub const DayInt = u5;

    pub fn fullName(this: @This()) []const u8 {
        return switch (this) {
            .jan => "January",
            .feb => "Febuary",
            .mar => "March",
            .apr => "April",
            .may => "May",
            .jun => "June",
            .jul => "July",
            .aug => "August",
            .sep => "September",
            .oct => "October",
            .nov => "November",
            .dec => "December",
        };
    }

    pub fn shortName(this: @This()) [3:0]u8 {
        return (switch (this) {
            .jan => "Jan",
            .feb => "Feb",
            .mar => "Mar",
            .apr => "Apr",
            .may => "May",
            .jun => "Jun",
            .jul => "Jul",
            .aug => "Aug",
            .sep => "Sep",
            .oct => "Oct",
            .nov => "Nov",
            .dec => "Dec",
        }).*;
    }

    pub fn number(this: @This()) u4 {
        return @intFromEnum(this);
    }

    pub fn lastDay(month: Month, year: i32) DayInt {
        if (month != .feb or !isLeapYear(year)) {
            return LAST_DAY_OF_MONTH_COMMON_YEAR[@intFromEnum(month) - 1];
        } else {
            return LAST_DAY_OF_MONTH_LEAP_YEAR[@intFromEnum(month) - 1];
        }
    }

    pub const LAST_DAY_OF_MONTH_COMMON_YEAR = [12]DayInt{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    pub const LAST_DAY_OF_MONTH_LEAP_YEAR = [12]DayInt{ 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };

    /// Returns the day of the year that this months starts at. Return value is in the range [0, 334]
    pub fn firstDayOfYear(month: Month, year: i32) u9 {
        if (@intFromEnum(month) <= @intFromEnum(Month.feb) or !isLeapYear(year)) {
            return FIRST_DAY_OF_COMMON_YEAR[@intFromEnum(month) - 1];
        } else {
            return FIRST_DAY_OF_LEAP_YEAR[@intFromEnum(month) - 1];
        }
    }

    pub const FIRST_DAY_OF_COMMON_YEAR = calc_days_into_year: {
        var months_days_into_year: [LAST_DAY_OF_MONTH_COMMON_YEAR.len]u9 = undefined;
        months_days_into_year[0] = 0;
        for (months_days_into_year[0..11], LAST_DAY_OF_MONTH_COMMON_YEAR[0..11], months_days_into_year[1..12]) |days_into_year_prev_month, last_day_of_prev_month, *days_into_year| {
            days_into_year.* = days_into_year_prev_month + last_day_of_prev_month;
        }

        break :calc_days_into_year months_days_into_year;
    };
    pub const FIRST_DAY_OF_LEAP_YEAR = calc_days_into_year: {
        var months_days_into_year: [LAST_DAY_OF_MONTH_LEAP_YEAR.len]u9 = undefined;
        months_days_into_year[0] = 0;
        for (months_days_into_year[0..11], LAST_DAY_OF_MONTH_LEAP_YEAR[0..11], months_days_into_year[1..12]) |days_into_year_prev_month, last_day_of_prev_month, *days_into_year| {
            days_into_year.* = days_into_year_prev_month + last_day_of_prev_month;
        }

        break :calc_days_into_year months_days_into_year;
    };
};

pub fn isLeapYear(year: i32) bool {
    return @mod(year, 4) == 0 and (@mod(year, 100) != 0 or @mod(year, 400) == 0);
}

test isLeapYear {
    const leap_years_1800_to_2400 = [_]i19{
        1804, 1808, 1812, 1816, 1820, 1824, 1828,
        1832, 1836, 1840, 1844, 1848, 1852, 1856,
        1860, 1864, 1868, 1872, 1876, 1880, 1884,
        1888, 1892, 1896, 1904, 1908, 1912, 1916,
        1920, 1924, 1928, 1932, 1936, 1940, 1944,
        1948, 1952, 1956, 1960, 1964, 1968, 1972,
        1976, 1980, 1984, 1988, 1992, 1996, 2000,
        2004, 2008, 2012, 2016, 2020, 2024, 2028,
        2032, 2036, 2040, 2044, 2048, 2052, 2056,
        2060, 2064, 2068, 2072, 2076, 2080, 2084,
        2088, 2092, 2096, 2104, 2108, 2112, 2116,
        2120, 2124, 2128, 2132, 2136, 2140, 2144,
        2148, 2152, 2156, 2160, 2164, 2168, 2172,
        2176, 2180, 2184, 2188, 2192, 2196, 2204,
        2208, 2212, 2216, 2220, 2224, 2228, 2232,
        2236, 2240, 2244, 2248, 2252, 2256, 2260,
        2264, 2268, 2272, 2276, 2280, 2284, 2288,
        2292, 2296, 2304, 2308, 2312, 2316, 2320,
        2324, 2328, 2332, 2336, 2340, 2344, 2348,
        2352, 2356, 2360, 2364, 2368, 2372, 2376,
        2380, 2384, 2388, 2392, 2396, 2400,
    };

    for (leap_years_1800_to_2400) |leap_year| {
        errdefer std.debug.print("year = {}\n", .{leap_year});
        try std.testing.expect(isLeapYear(leap_year));
    }
    try std.testing.expect(!isLeapYear(2021));
    try std.testing.expect(!isLeapYear(2023));
}

test "Yes, but how do you know this all really works?" {
    try std.testing.expectEqual(146097, DAYS_PER_ERA);
    try std.testing.expectEqual(@as(i64, 719528), YearMonthDay.fromNumbers(1970, 1, 1).toDays());
    {
        const day719527 = YearMonthDay.fromDays(719528);
        errdefer std.debug.print("day719528 = {}\n", .{day719527});
        try std.testing.expectEqual(YearMonthDay.fromNumbers(1970, 1, 1), day719527);
    }

    try std.testing.expectEqual(@as(i64, 0), YearMonthDay.fromNumbers(1970, 1, 1).toDaysSinceUnixEpoch());
    {
        const day0 = YearMonthDay.fromDaysSinceUnixEpoch(0);
        errdefer std.debug.print("day0 = {}\n", .{day0});
        try std.testing.expectEqualDeep(YearMonthDay.fromNumbers(1970, 1, 1), day0);
    }
    try std.testing.expectEqual(Weekday.thu, Weekday.fromDaysSinceUnixEpoch(0));

    const START_YEAR = if (builtin.mode == .Debug) -1_000 else 1_000_000;
    const END_YEAR = if (builtin.mode == .Debug) 1_000 else 1_000_000;

    var year: YearMonthDay.YearInt = START_YEAR;
    var prev_days_since_epoch = YearMonthDay.fromNumbers(START_YEAR, 1, 1).toDaysSinceUnixEpoch() - 1;
    var prev_weekday = Weekday.fromDaysSinceUnixEpoch(prev_days_since_epoch);
    while (year <= END_YEAR) : (year += 1) {
        for (MONTHS) |month| {
            const last_day_of_month = month.lastDay(year);
            for (0..last_day_of_month) |day_0index| {
                const day: Month.DayInt = @intCast(day_0index + 1);
                const year_month_day = YearMonthDay.fromComponents(year, month, day);
                const days_since_epoch = year_month_day.toDaysSinceUnixEpoch();

                errdefer std.debug.print("days since unix epoch = {}, prev = {}\n", .{ days_since_epoch, prev_days_since_epoch });
                try std.testing.expectEqual(days_since_epoch, prev_days_since_epoch + 1);

                {
                    const ymd = YearMonthDay.fromDaysSinceUnixEpoch(days_since_epoch);
                    errdefer std.debug.print("{:0>4}-{:0>2}-{:0>2}; from days since unix epoch = {}\n", .{ year, @intFromEnum(month), day, ymd });
                    try std.testing.expectEqualDeep(year_month_day, ymd);
                }

                const weekday = Weekday.fromDaysSinceUnixEpoch(days_since_epoch);
                try std.testing.expectEqual(weekday, prev_weekday.next());
                try std.testing.expectEqual(prev_weekday, weekday.prev());

                prev_days_since_epoch = days_since_epoch;
                prev_weekday = weekday;
            }
        }
    }
}

const std = @import("std");
const builtin = @import("builtin");
