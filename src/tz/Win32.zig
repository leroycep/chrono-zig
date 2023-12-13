//! Implements looking up timezone information based on the Win32 APIs for date and time.

gpa: std.mem.Allocator,
/// Holds onto timezone designations for the user
string_pool: *std.StringHashMapUnmanaged(void),

/// A hashmap mapping Windows' timezone keys to IANA timezone keys
timezone_mapping: *const mapping.WindowsToIANAHashmap,

dynamic_time_zone_information: TIME_DYNAMIC_ZONE_INFORMATION,

pub const mapping = @import("./Win32/mapping.zig");

pub fn deinit(this: *@This()) void {
    var string_iter = this.string_pool.iterator();
    while (string_iter.next()) |string| {
        this.gpa.free(string.key_ptr.*);
    }
    this.string_pool.deinit(this.gpa);
    this.gpa.destroy(this.string_pool);
}

pub fn localTimeZone(gpa: std.mem.Allocator, timezone_mapping: *const mapping.WindowsToIANAHashmap) !?@This() {
    const string_pool = try gpa.create(std.StringHashMapUnmanaged(void));
    string_pool.* = .{};

    var this: @This() = .{
        .gpa = gpa,
        .string_pool = string_pool,
        .dynamic_time_zone_information = undefined,
        .timezone_mapping = timezone_mapping,
    };
    switch (GetDynamicTimeZoneInformation(&this.dynamic_time_zone_information)) {
        .UNKNOWN,
        .STANDARD,
        .DAYLIGHT,
        => {},
        else => return null,
    }

    return this;
}

pub const TIMEZONE_VTABLE = chrono.tz.TimeZone.VTable.eraseTypes(@This(), .{
    .offsetAtTimestamp = offsetAtTimestamp,
    .isDaylightSavingTimeAtTimestamp = isDaylightSavingTimeAtTimestamp,
    .designationAtTimestamp = designationAtTimestamp,
    .identifier = identifier,
});

pub fn timeZone(this: *const @This()) chrono.tz.TimeZone {
    return chrono.tz.TimeZone{
        .ptr = this,
        .vtable = &TIMEZONE_VTABLE,
    };
}

pub fn offsetAtTimestamp(this: *const @This(), timestamp_utc: i64) ?i32 {
    const ymd = chrono.date.YearMonthDay.fromDaysSinceUnixEpoch(@intCast(@divFloor(timestamp_utc, std.time.s_per_day)));

    var dynamic_time_zone_info = this.dynamic_time_zone_information;

    var time_zone_info: TIME_ZONE_INFORMATION = undefined;
    if (GetTimeZoneInformationForYear(@intCast(ymd.year), &dynamic_time_zone_info, &time_zone_info) == 0) {
        return null;
    }

    if (time_zone_info.isDaylightSavingTimeAtTimestamp(timestamp_utc)) {
        return (time_zone_info.Bias + time_zone_info.DaylightBias) * -std.time.s_per_min;
    } else {
        return (time_zone_info.Bias + time_zone_info.StandardBias) * -std.time.s_per_min;
    }
}

pub fn isDaylightSavingTimeAtTimestamp(this: *const @This(), timestamp_utc: i64) ?bool {
    const ymd = chrono.date.YearMonthDay.fromDaysSinceUnixEpoch(@intCast(@divFloor(timestamp_utc, std.time.s_per_day)));

    var dynamic_time_zone_info = this.dynamic_time_zone_information;

    var time_zone_info: TIME_ZONE_INFORMATION = undefined;
    if (GetTimeZoneInformationForYear(@intCast(ymd.year), &dynamic_time_zone_info, &time_zone_info) == 0) {
        return null;
    }

    return time_zone_info.isDaylightSavingTimeAtTimestamp(timestamp_utc);
}

pub fn designationAtTimestamp(this: *const @This(), timestamp_utc: i64) ?[]const u8 {
    const ymd = chrono.date.YearMonthDay.fromDaysSinceUnixEpoch(@intCast(@divFloor(timestamp_utc, std.time.s_per_day)));

    var dynamic_time_zone_info = this.dynamic_time_zone_information;

    var time_zone_info: TIME_ZONE_INFORMATION = undefined;
    if (GetTimeZoneInformationForYear(@intCast(ymd.year), &dynamic_time_zone_info, &time_zone_info) == 0) {
        return null;
    }

    const designation_utf16 = if (time_zone_info.isDaylightSavingTimeAtTimestamp(timestamp_utc))
        time_zone_info.DaylightName[0..]
    else
        time_zone_info.StandardName[0..];

    const designation_utf16_len = std.mem.indexOfScalar(u16, designation_utf16, 0) orelse designation_utf16.len;
    var designation_buf: [64]u8 = undefined;
    const designation_len = std.unicode.utf16leToUtf8(designation_buf[0..], designation_utf16[0..designation_utf16_len]) catch return null;
    const designation = designation_buf[0..designation_len];

    const gop = this.string_pool.getOrPut(this.gpa, designation) catch return null;
    if (!gop.found_existing) {
        gop.key_ptr.* = this.gpa.dupe(u8, designation) catch return null;
    }

    return gop.key_ptr.*;
}

pub fn identifier(this: *const @This()) ?chrono.tz.Identifier {
    const key_name_len = std.mem.indexOfScalar(u16, this.dynamic_time_zone_information.TimeZoneKeyName[0..], 0) orelse this.dynamic_time_zone_information.TimeZoneKeyName.len;
    const key_name = this.dynamic_time_zone_information.TimeZoneKeyName[0..key_name_len];

    if (tryGetRegion()) |region| {
        if (this.timezone_mapping.get(.{ .name = key_name, .territory = region })) |iana_identifier| {
            return iana_identifier[0];
        }
    }

    if (this.timezone_mapping.get(.{ .name = key_name, .territory = null })) |iana_identifier| {
        return iana_identifier[0];
    }

    return null;
}

fn tryGetRegion() ?[2]u8 {
    // we need the buffer to be at least 3 bytes long to hold a null byte at the end
    var iso_2letter_region: [3]u8 = undefined;

    const geoid = GetUserGeoID(.NATION);

    if (GetGeoInfoA(geoid, .ISO2, &iso_2letter_region, iso_2letter_region.len, .NONE) == 0) {
        return null;
    }

    return iso_2letter_region[0..2].*;
}

const GEOCLASS = enum(c_int) {
    NATION = 16,
    _,
};

const GEOID = c_int;

const GEOTYPE = enum(c_int) {
    ISO2 = 0x004,
    _,
};

const LANGID = enum(c_int) {
    NONE = 0,
    _,
};

extern fn GetUserGeoID(GEOCLASS) GEOID;
extern fn GetGeoInfoA(GEOID, GEOTYPE, out_ptr: ?[*]u8, out_len: c_int, LANGID) c_int;

const TIME_ZONE_ID = enum(std.os.windows.DWORD) {
    UNKNOWN = 0,
    STANDARD = 1,
    DAYLIGHT = 2,
    // TODO: Find value of TIME_ZONE_ID_INVALID
    // INVALID = ???,
    _,
};

extern fn GetDynamicTimeZoneInformation(time_zone_information_out: *TIME_DYNAMIC_ZONE_INFORMATION) TIME_ZONE_ID;
extern fn GetDynamicTimeZoneInformationEffectiveYears(*const TIME_DYNAMIC_ZONE_INFORMATION, first_year: *std.os.windows.DWORD, last_year: *std.os.windows.DWORD) std.os.windows.Win32Error;
extern fn GetTimeZoneInformationForYear(year: std.os.windows.USHORT, time_zone_information_in: ?*TIME_DYNAMIC_ZONE_INFORMATION, timezone_info_out: *TIME_ZONE_INFORMATION) std.os.windows.BOOL;

const TIME_ZONE_INFORMATION = extern struct {
    /// The current offset for the local time zone
    Bias: std.os.windows.LONG,
    StandardName: [32]std.os.windows.WCHAR,
    StandardDate: SYSTEMTIME,
    StandardBias: std.os.windows.LONG,
    DaylightName: [32]std.os.windows.WCHAR,
    DaylightDate: SYSTEMTIME,
    DaylightBias: std.os.windows.LONG,

    pub fn isDaylightSavingTimeAtTimestamp(time_zone_info: @This(), timestamp_utc: i64) bool {
        const ymd = chrono.date.YearMonthDay.fromDaysSinceUnixEpoch(@intCast(@divFloor(timestamp_utc, std.time.s_per_day)));

        const end_dst = time_zone_info.StandardDate.toSecondsSinceUnixEpoch(ymd.year);
        const start_dst = time_zone_info.DaylightDate.toSecondsSinceUnixEpoch(ymd.year);

        if (start_dst < end_dst) {
            if (timestamp_utc >= start_dst and timestamp_utc < end_dst) {
                return true;
            } else {
                return false;
            }
        } else {
            if (timestamp_utc >= end_dst and timestamp_utc < start_dst) {
                return false;
            } else {
                return true;
            }
        }
    }

    pub fn format(
        this: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        const std_len = std.mem.indexOfScalar(u16, &this.StandardName, 0) orelse this.StandardName.len;
        const dst_len = std.mem.indexOfScalar(u16, &this.DaylightName, 0) orelse this.DaylightName.len;

        try std.fmt.format(writer, "TIME_ZONE_INFORMATION{{ .Bias = {}, .StandardName = {}, .StandardDate = {}, .StandardBias = {}, .DaylightName = {}, .DaylightDate = {}, .DaylightBias = {} }}", .{
            this.Bias,
            std.unicode.fmtUtf16le(this.StandardName[0..std_len]),
            this.StandardDate,
            this.StandardBias,
            std.unicode.fmtUtf16le(this.DaylightName[0..dst_len]),
            this.DaylightDate,
            this.DaylightBias,
        });
    }
};

const TIME_DYNAMIC_ZONE_INFORMATION = extern struct {
    /// The current offset for the local time zone
    Bias: std.os.windows.LONG,
    StandardName: [32]std.os.windows.WCHAR,
    StandardDate: SYSTEMTIME,
    StandardBias: std.os.windows.LONG,
    DaylightName: [32]std.os.windows.WCHAR,
    DaylightDate: SYSTEMTIME,
    DaylightBias: std.os.windows.LONG,
    TimeZoneKeyName: [128]std.os.windows.WCHAR,
    DynamicDaylightTimeDisabled: std.os.windows.BOOLEAN,
};

const SYSTEMTIME = extern struct {
    /// The year. The valid values for this field are 1601 through 30827.
    Year: std.os.windows.WORD,
    /// The month. The valid values for this field are 1 (January) through 12 (December).
    Month: std.os.windows.WORD,
    /// The day of the week. The valid values for this field are 0 (Sunday) through 6 (Saturday).
    DayOfWeek: std.os.windows.WORD,
    /// The day of the month. The valid values for this field are 1 through 31.
    Day: std.os.windows.WORD,
    /// The hour. The valid values for this field are 0 through 23.
    Hour: std.os.windows.WORD,
    /// The minute. The valid values for this field are 0 through 59.
    Minute: std.os.windows.WORD,
    /// The second. The valid values for this field are 0 through 59.
    Second: std.os.windows.WORD,
    /// The milliseconds. The valid values for this field are 0 through 999.
    Milliseconds: std.os.windows.WORD,

    pub fn toSecondsSinceUnixEpoch(this: @This(), current_year: i23) i64 {
        const ymd = chrono.date.YearMonthDay{
            .year = if (this.Year != 0) @intCast(this.Year) else current_year,
            .month = @enumFromInt(@as(chrono.date.Month.Int, @intCast(this.Month))),
            .day = @intCast(this.Day),
        };

        return @as(i64, ymd.toDaysSinceUnixEpoch()) * std.time.s_per_day +
            @as(i64, this.Hour) * std.time.s_per_hour +
            @as(i64, this.Minute) * std.time.s_per_min +
            @as(i64, this.Second);
    }
};

const chrono = @import("../lib.zig");
const Posix = @import("./Posix.zig");
const testing = std.testing;
const std = @import("std");
