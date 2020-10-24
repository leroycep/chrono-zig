const std = @import("std");
const internals = @import("./internals.zig");
const YearInt = internals.YearInt;
const MonthInt = internals.YearInt;
const DayInt = internals.YearInt;
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
    std.testing.expectEqual(@as(?NaiveDate, null), ymd_opt(2014, 3, 32));
    std.testing.expect(!std.meta.eql(@as(?NaiveDate, null), ymd_opt(2014, 12, 31)));
    std.testing.expectEqual(@as(?NaiveDate, null), ymd_opt(2014, 13, 1));
}
