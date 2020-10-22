const std = @import("std");
const expectEqual = std.testing.expectEqual;

pub const YearFlags = packed struct {
    flags: u8,

    pub const A = YearFlags{ .flags = 0o15 };
    pub const AG = YearFlags{ .flags = 0o05 };
    pub const B = YearFlags{ .flags = 0o14 };
    pub const BA = YearFlags{ .flags = 0o04 };
    pub const C = YearFlags{ .flags = 0o13 };
    pub const CB = YearFlags{ .flags = 0o03 };
    pub const D = YearFlags{ .flags = 0o12 };
    pub const DC = YearFlags{ .flags = 0o02 };
    pub const E = YearFlags{ .flags = 0o11 };
    pub const ED = YearFlags{ .flags = 0o01 };
    pub const F = YearFlags{ .flags = 0o17 };
    pub const FE = YearFlags{ .flags = 0o07 };
    pub const G = YearFlags{ .flags = 0o16 };
    pub const GF = YearFlags{ .flags = 0o06 };

    pub const MOD_400_TO_FLAGS = [400]YearFlags{
        BA, G,  F,  E,  DC, B,  A,  G,  FE, D,  C,  B,  AG, F,  E,
        D,  CB, A,  G,  F,  ED, C,  B,  A,  GF, E,  D,  C,  BA, G,
        F,  E,  DC, B,  A,  G,  FE, D,  C,  B,  AG, F,  E,  D,  CB,
        A,  G,  F,  ED, C,  B,  A,  GF, E,  D,  C,  BA, G,  F,  E,
        DC, B,  A,  G,  FE, D,  C,  B,  AG, F,  E,  D,  CB, A,  G,
        F,  ED, C,  B,  A,  GF, E,  D,  C,  BA, G,  F,
        E,  DC, B,  A,  G,  FE, D,  C,  B,  AG, F,  E,  D, // 100
        C,  B,  A,  G,  FE, D,  C,  B,  AG, F,  E,  D,  CB,
        A,  G,  F,  ED, C,  B,  A,  GF, E,  D,  C,  BA, G,
        F,  E,  DC, B,  A,  G,  FE, D,  C,  B,  AG, F,  E,
        D,  CB, A,  G,  F,  ED, C,  B,  A,  GF, E,  D,  C,
        BA, G,  F,  E,  DC, B,  A,  G,  FE, D,  C,  B,  AG,
        F,  E,  D,  CB, A,  G,  F,  ED, C,  B,  A,  GF, E,
        D,  C,  BA, G,  F,  E,  DC, B,  A,
        G,  FE, D,  C,  B,  AG, F,  E,  D,  CB, A,  G,  F, // 200
        E,  D,  C,  B,  AG, F,  E,  D,  CB, A,  G,  F,  ED,
        C,  B,  A,  GF, E,  D,  C,  BA, G,  F,  E,  DC, B,
        A,  G,  FE, D,  C,  B,  AG, F,  E,  D,  CB, A,  G,
        F,  ED, C,  B,  A,  GF, E,  D,  C,  BA, G,  F,  E,
        DC, B,  A,  G,  FE, D,  C,  B,  AG, F,  E,  D,  CB,
        A,  G,  F,  ED, C,  B,  A,  GF, E,  D,  C,  BA, G,
        F,  E,  DC, B,  A,  G,  FE, D,  C,
        B,  AG, F,  E,  D,  CB, A,  G,  F,  ED, C,  B,  A, // 300
        G,  F,  E,  D,  CB, A,  G,  F,  ED, C,  B,  A,  GF,
        E,  D,  C,  BA, G,  F,  E,  DC, B,  A,  G,  FE, D,
        C,  B,  AG, F,  E,  D,  CB, A,  G,  F,  ED, C,  B,
        A,  GF, E,  D,  C,  BA, G,  F,  E,  DC, B,  A,  G,
        FE, D,  C,  B,  AG, F,  E,  D,  CB, A,  G,  F,  ED,
        C,  B,  A,  GF, E,  D,  C,  BA, G,  F,  E,  DC, B,
        A,  G,  FE, D,  C,  B,  AG, F,  E,
        D, CB, A, G, F, ED, C, B, A, GF, E, D, C, // 400
    };

    pub fn from_year(year: i32) YearFlags {
        return from_year_mod_400(@intCast(usize, @mod(year, 400)));
    }

    pub fn from_year_mod_400(year: usize) YearFlags {
        return MOD_400_TO_FLAGS[year];
    }

    pub fn ndays(this: @This()) u32 {
        return @as(u32, 366) - (this.flags >> 3);
    }
};

test "year flags number of days from year" {
    expectEqual(@as(u32, 365), YearFlags.from_year(2014).ndays());
    expectEqual(@as(u32, 366), YearFlags.from_year(2012).ndays());
    expectEqual(@as(u32, 366), YearFlags.from_year(2000).ndays());
    expectEqual(@as(u32, 365), YearFlags.from_year(1900).ndays());
    expectEqual(@as(u32, 366), YearFlags.from_year(1600).ndays());
    expectEqual(@as(u32, 365), YearFlags.from_year(1).ndays());
    expectEqual(@as(u32, 366), YearFlags.from_year(0).ndays()); // 1 BCE (proleptic Gregorian)
    expectEqual(@as(u32, 365), YearFlags.from_year(-1).ndays()); // 2 BCE
    expectEqual(@as(u32, 366), YearFlags.from_year(-4).ndays()); // 5 BCE
    expectEqual(@as(u32, 365), YearFlags.from_year(-99).ndays()); // 100 BCE
    expectEqual(@as(u32, 365), YearFlags.from_year(-100).ndays()); // 101 BCE
    expectEqual(@as(u32, 365), YearFlags.from_year(-399).ndays()); // 400 BCE
    expectEqual(@as(u32, 366), YearFlags.from_year(-400).ndays()); // 401 BCE
}
