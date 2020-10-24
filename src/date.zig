const std = @import("std");
const internals = @import("./internals.zig");
const YearInt = internals.YearInt;
const MonthInt = internals.MonthInt;
const DayInt = internals.DayInt;
const OrdinalInt = internals.OrdinalInt;
const YearFlags = internals.YearFlags;
const MIN_YEAR = internals.MIN_YEAR;
const MAX_YEAR = internals.MAX_YEAR;

// TODO: Make packed once packed structs aren't bugged
pub const NaiveDate = struct {
    year: YearInt,
    of: internals.Of,

    pub fn ymd_opt(year: YearInt, month: MonthInt, day: DayInt) ?@This() {
        const flags = internals.YearFlags.from_year(year);
        const mdf = internals.Mdf.new(month, day, flags);
        const of = mdf.to_of();
        if (of.valid()) {
            return @This(){
                .year = year,
                .of = mdf.to_of(),
            };
        } else {
            return null;
        }
    }

    pub fn ymd(year: YearInt, month: MonthInt, day: DayInt) @This() {
        return ymd_opt(year, month, day).?;
    }

    pub fn yo_opt(year: YearInt, ordinal: OrdinalInt) ?@This() {
        const flags = internals.YearFlags.from_year(year);
        const of = internals.Of.new(ordinal, flags);
        if (of.valid()) {
            return @This(){
                .year = year,
                .of = of,
            };
        } else {
            return null;
        }
    }

    pub fn yo(year: YearInt, ordinal: OrdinalInt) @This() {
        return yo_opt(year, ordinal).?;
    }
};

pub const MIN_DATE = NaiveDate{ .ymdf = (MIN_YEAR << 13) | (1 << 4) | internals.YearFlags.from_year(MIN_YEAR) };

test "date from ymd" {
    const ymd_opt = NaiveDate.ymd_opt;

    std.testing.expectEqual(@as(?NaiveDate, null), ymd_opt(2012, 0, 1));
    std.testing.expect(!std.meta.eql(@as(?NaiveDate, null), ymd_opt(2012, 1, 1)));
    std.testing.expect(!std.meta.eql(@as(?NaiveDate, null), ymd_opt(2012, 2, 29)));
    std.testing.expectEqual(@as(?NaiveDate, null), ymd_opt(2014, 2, 29));
    std.testing.expectEqual(@as(?NaiveDate, null), ymd_opt(2014, 3, 0));
    std.testing.expect(!std.meta.eql(@as(?NaiveDate, null), ymd_opt(2014, 3, 1)));
    std.testing.expect(!std.meta.eql(@as(?NaiveDate, null), ymd_opt(2014, 3, 31)));
    std.testing.expect(!std.meta.eql(@as(?NaiveDate, null), ymd_opt(2014, 12, 31)));
    std.testing.expectEqual(@as(?NaiveDate, null), ymd_opt(2014, 13, 1));
}

test "date from year-ordinal" {
    const yo_opt = NaiveDate.yo_opt;
    const yo = NaiveDate.yo;
    const ymd = NaiveDate.ymd;
    const null_date = @as(?NaiveDate, null);

    std.testing.expectEqual(null_date, yo_opt(2012, 0));
    std.testing.expectEqual(ymd(2012, 1, 1), yo(2012, 1));
    std.testing.expectEqual(ymd(2012, 1, 2), yo(2012, 2));
    std.testing.expectEqual(ymd(2012, 2, 1), yo(2012, 32));
    std.testing.expectEqual(ymd(2012, 2, 29), yo(2012, 60));
    std.testing.expectEqual(ymd(2012, 3, 1), yo(2012, 61));
    std.testing.expectEqual(ymd(2012, 4, 9), yo(2012, 100));
    std.testing.expectEqual(ymd(2012, 7, 18), yo(2012, 200));
    std.testing.expectEqual(ymd(2012, 10, 26), yo(2012, 300));
    std.testing.expectEqual(ymd(2012, 12, 31), yo(2012, 366));
    std.testing.expectEqual(null_date, yo_opt(2012, 367));

    std.testing.expectEqual(null_date, yo_opt(2014, 0));
    std.testing.expectEqual(ymd(2014, 1, 1), yo(2014, 1));
    std.testing.expectEqual(ymd(2014, 1, 2), yo(2014, 2));
    std.testing.expectEqual(ymd(2014, 2, 1), yo(2014, 32));
    std.testing.expectEqual(ymd(2014, 2, 28), yo(2014, 59));
    std.testing.expectEqual(ymd(2014, 3, 1), yo(2014, 60));
    std.testing.expectEqual(ymd(2014, 4, 10), yo(2014, 100));
    std.testing.expectEqual(ymd(2014, 7, 19), yo(2014, 200));
    std.testing.expectEqual(ymd(2014, 10, 27), yo(2014, 300));
    std.testing.expectEqual(ymd(2014, 12, 31), yo(2014, 365));
    std.testing.expectEqual(null_date, yo_opt(2014, 366));
}
