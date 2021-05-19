const internals = @import("internals.zig");
const YearInt = internals.YearInt;
const WeekInt = internals.WeekInt;
const Weekday = @import("./lib.zig").Weekday;
const YearFlags = internals.YearFlags;

year: YearInt,
week: WeekInt,

pub fn from_yof(year: YearInt, of: internals.Of) @This() {
    const weekord = of.ordinal +% of.year_flags.isoweek_delta();
    const raw_week = weekord / 7;
    const weekday = @intToEnum(Weekday, @intCast(u3, weekord % 7));

    if (raw_week < 1) {
        const prevlastweek = YearFlags.from_year(year - 1).nisoweeks();
        return @This(){
            .year = year - 1,
            .week = prevlastweek,
        };
    } else {
        const lastweek = of.year_flags.nisoweeks();
        if (raw_week > lastweek) {
            return @This(){
                .year = year + 1,
                .week = 1,
            };
        } else {
            return @This(){
                .year = year,
                .week = @intCast(WeekInt, raw_week),
            };
        }
    }
}
