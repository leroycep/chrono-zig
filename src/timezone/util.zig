const std = @import("std");

pub fn hhmmss_offset_to_s(_string: []const u8, idx: *usize) !i32 {
    var string = _string;
    var sign: i2 = 1;
    if (string[0] == '+') {
        sign = 1;
        string = string[1..];
        idx.* += 1;
    } else if (string[0] == '-') {
        sign = -1;
        string = string[1..];
        idx.* += 1;
    }

    for (string, 0..) |c, i| {
        if (!(std.ascii.isDigit(c) or c == ':')) {
            string = string[0..i];
            break;
        }
        idx.* += 1;
    }

    var result: i32 = 0;

    var segment_iter = std.mem.split(u8, string, ":");
    const hour_string = segment_iter.next() orelse return error.EmptyString;
    const hours = try std.fmt.parseInt(u32, hour_string, 10);
    if (hours > 167) {
        return error.InvalidFormat;
    }
    result += std.time.s_per_hour * @as(i32, @intCast(hours));

    if (segment_iter.next()) |minute_string| {
        const minutes = try std.fmt.parseInt(u32, minute_string, 10);
        if (minutes > 59) return error.InvalidFormat;
        result += std.time.s_per_min * @as(i32, @intCast(minutes));
    }

    if (segment_iter.next()) |second_string| {
        const seconds = try std.fmt.parseInt(u8, second_string, 10);
        if (seconds > 59) return error.InvalidFormat;
        result += seconds;
    }

    return result * sign;
}

pub fn days_in_month(m: u8, is_leap: bool) i32 {
    if (m == 2) {
        return 28 + @as(i32, @intFromBool(is_leap));
    } else {
        return 30 + ((@as(i32, 0xad5) >> @as(u5, @intCast(m - 1))) & 1);
    }
}

pub fn month_to_secs(m: u8, is_leap: bool) i32 {
    const d = std.time.s_per_day;
    const secs_though_month = [12]i32{
        0 * d,   31 * d,  59 * d,  90 * d,
        120 * d, 151 * d, 181 * d, 212 * d,
        243 * d, 273 * d, 304 * d, 334 * d,
    };
    var t = secs_though_month[m];
    if (is_leap and m >= 2) t += d;
    return t;
}

pub fn isLeapYear(year: i32) bool {
    return @mod(year, 4) == 0 and (@mod(year, 100) != 0 or @mod(year, 400) == 0);
}

test isLeapYear {
    const leap_years_1800_to_2400 = [_]i32{
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

const UNIX_EPOCH_YEAR = 1970;
const UNIX_EPOCH_NUMBER_OF_4_YEAR_PERIODS = UNIX_EPOCH_YEAR / 4;
const UNIX_EPOCH_CENTURIES = UNIX_EPOCH_YEAR / 100;
/// Number of 400 year periods before the unix epoch
const UNIX_EPOCH_CYCLES = UNIX_EPOCH_YEAR / 400;

/// Takes in year number, returns the unix timestamp for the start of the year.
pub fn year_to_secs(year: i32) i64 {
    const number_of_four_year_periods = @divFloor(year - 1, 4);
    const centuries = @divFloor(year - 1, 100);
    const cycles = @divFloor(year - 1, 400);

    const years_since_epoch = year - UNIX_EPOCH_YEAR;
    const number_of_four_year_periods_since_epoch = number_of_four_year_periods - UNIX_EPOCH_NUMBER_OF_4_YEAR_PERIODS;
    const centuries_since_epoch = centuries - UNIX_EPOCH_CENTURIES;
    const cycles_since_epoch = cycles - UNIX_EPOCH_CYCLES;

    const number_of_leap_days_since_epoch =
        number_of_four_year_periods_since_epoch -
        centuries_since_epoch +
        cycles_since_epoch;

    const SECONDS_PER_REGULAR_YEAR = 365 * std.time.s_per_day;
    return @as(i64, years_since_epoch) * SECONDS_PER_REGULAR_YEAR + number_of_leap_days_since_epoch * std.time.s_per_day;
}

test year_to_secs {
    try std.testing.expectEqual(@as(i64, 0), year_to_secs(1970));
    try std.testing.expectEqual(@as(i64, 1577836800), year_to_secs(2020));
    try std.testing.expectEqual(@as(i64, 1609459200), year_to_secs(2021));
    try std.testing.expectEqual(@as(i64, 1640995200), year_to_secs(2022));
    try std.testing.expectEqual(@as(i64, 1672531200), year_to_secs(2023));
}

pub fn secs_to_year(secs: i64) i32 {
    // Copied from MUSL
    // TODO: make more efficient?
    var y = @as(i32, @intCast(@divFloor(secs, std.time.s_per_day * 365) + 1970));
    while (year_to_secs(y) > secs) y -= 1;
    while (year_to_secs(y + 1) < secs) y += 1;
    return y;
}

test secs_to_year {
    try std.testing.expectEqual(@as(i32, 1970), secs_to_year(0));
    try std.testing.expectEqual(@as(i32, 2023), secs_to_year(1672531200));
}
