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

    pub fn ymd(year: YearInt, month: MonthInt, day: DayInt) ?@This() {
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

    pub fn yo(year: i32, ordinal: OrdinalInt) ?@This() {
        const flags = internals.YearFlags.from_year(year);
        const of = internals.Of.new(ordinal, flags);
        if (MIN_YEAR <= year and year <= MAX_YEAR and of.valid()) {
            return @This(){
                .year = @intCast(YearInt, year),
                .of = of,
            };
        } else {
            return null;
        }
    }

    pub fn succ(this: @This()) ?@This() {
        const of = this.of.succ();
        if (!of.valid()) {
            var new_year: YearInt = undefined;
            if (@addWithOverflow(YearInt, this.year, 1, &new_year)) return null;
            return yo(new_year, 1);
        } else {
            return @This(){
                .year = this.year,
                .of = of,
            };
        }
    }

    pub fn pred(this: @This()) ?@This() {
        const of = this.of.pred();
        if (!of.valid()) {
            var new_year: YearInt = undefined;
            if (@subWithOverflow(YearInt, this.year, 1, &new_year)) return null;
            return ymd(new_year, 12, 31);
        } else {
            return @This(){
                .year = this.year,
                .of = of,
            };
        }
    }
};

pub const MIN_DATE = NaiveDate{ .ymdf = (MIN_YEAR << 13) | (1 << 4) | internals.YearFlags.from_year(MIN_YEAR) };

test "date from ymd" {
    const ymd = NaiveDate.ymd;

    std.testing.expectEqual(@as(?NaiveDate, null), ymd(2012, 0, 1));
    std.testing.expect(!std.meta.eql(@as(?NaiveDate, null), ymd(2012, 1, 1)));
    std.testing.expect(!std.meta.eql(@as(?NaiveDate, null), ymd(2012, 2, 29)));
    std.testing.expectEqual(@as(?NaiveDate, null), ymd(2014, 2, 29));
    std.testing.expectEqual(@as(?NaiveDate, null), ymd(2014, 3, 0));
    std.testing.expect(!std.meta.eql(@as(?NaiveDate, null), ymd(2014, 3, 1)));
    std.testing.expect(!std.meta.eql(@as(?NaiveDate, null), ymd(2014, 3, 31)));
    std.testing.expect(!std.meta.eql(@as(?NaiveDate, null), ymd(2014, 12, 31)));
    std.testing.expectEqual(@as(?NaiveDate, null), ymd(2014, 13, 1));
}

test "date from year-ordinal" {
    const yo = NaiveDate.yo;
    const ymd = NaiveDate.ymd;
    const null_date = @as(?NaiveDate, null);

    std.testing.expectEqual(null_date, yo(2012, 0));
    std.testing.expectEqual(ymd(2012, 1, 1).?, yo(2012, 1).?);
    std.testing.expectEqual(ymd(2012, 1, 2).?, yo(2012, 2).?);
    std.testing.expectEqual(ymd(2012, 2, 1).?, yo(2012, 32).?);
    std.testing.expectEqual(ymd(2012, 2, 29).?, yo(2012, 60).?);
    std.testing.expectEqual(ymd(2012, 3, 1).?, yo(2012, 61).?);
    std.testing.expectEqual(ymd(2012, 4, 9).?, yo(2012, 100).?);
    std.testing.expectEqual(ymd(2012, 7, 18).?, yo(2012, 200).?);
    std.testing.expectEqual(ymd(2012, 10, 26).?, yo(2012, 300).?);
    std.testing.expectEqual(ymd(2012, 12, 31).?, yo(2012, 366).?);
    std.testing.expectEqual(null_date, yo(2012, 367));

    std.testing.expectEqual(null_date, yo(2014, 0));
    std.testing.expectEqual(ymd(2014, 1, 1).?, yo(2014, 1).?);
    std.testing.expectEqual(ymd(2014, 1, 2).?, yo(2014, 2).?);
    std.testing.expectEqual(ymd(2014, 2, 1).?, yo(2014, 32).?);
    std.testing.expectEqual(ymd(2014, 2, 28).?, yo(2014, 59).?);
    std.testing.expectEqual(ymd(2014, 3, 1).?, yo(2014, 60).?);
    std.testing.expectEqual(ymd(2014, 4, 10).?, yo(2014, 100).?);
    std.testing.expectEqual(ymd(2014, 7, 19).?, yo(2014, 200).?);
    std.testing.expectEqual(ymd(2014, 10, 27).?, yo(2014, 300).?);
    std.testing.expectEqual(ymd(2014, 12, 31).?, yo(2014, 365).?);
    std.testing.expectEqual(null_date, yo(2014, 366));
}

test "date successor" {
    const ymd = NaiveDate.ymd;
    std.testing.expectEqual(ymd(2014, 5, 7).?, ymd(2014, 5, 6).?.succ().?);
    std.testing.expectEqual(ymd(2014, 6, 1).?, ymd(2014, 5, 31).?.succ().?);
    std.testing.expectEqual(ymd(2015, 1, 1).?, ymd(2014, 12, 31).?.succ().?);
    std.testing.expectEqual(ymd(2016, 2, 29).?, ymd(2016, 2, 28).?.succ().?);
    std.testing.expectEqual(@as(?NaiveDate, null), ymd(MAX_YEAR, 12, 31).?.succ());
}

test "date predecessor" {
    const ymd = NaiveDate.ymd;
    std.testing.expectEqual(ymd(2016, 2, 29).?, ymd(2016, 3, 1).?.pred().?);
    std.testing.expectEqual(ymd(2014, 12, 31).?, ymd(2015, 1, 1).?.pred().?);
    std.testing.expectEqual(ymd(2014, 5, 31).?, ymd(2014, 6, 1).?.pred().?);
    std.testing.expectEqual(ymd(2014, 5, 6).?, ymd(2014, 5, 7).?.pred().?);
    std.testing.expectEqual(@as(?NaiveDate, null), ymd(MIN_YEAR, 1, 1).?.pred());
}
