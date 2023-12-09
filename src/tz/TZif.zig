allocator: std.mem.Allocator,
version: Version,
transitionTimes: []i64,
transitionTypes: []u8,
localTimeTypes: []LocalTimeType,
designations: []u8,
leapSeconds: []LeapSecond,
transitionIsStd: []bool,
transitionIsUT: []bool,
string: []u8,
posixTZ: ?Posix,

const TZif = @This();

pub fn deinit(this: *@This()) void {
    this.allocator.free(this.transitionTimes);
    this.allocator.free(this.transitionTypes);
    this.allocator.free(this.localTimeTypes);
    this.allocator.free(this.designations);
    this.allocator.free(this.leapSeconds);
    this.allocator.free(this.transitionIsStd);
    this.allocator.free(this.transitionIsUT);
    this.allocator.free(this.string);
}

pub const TIMEZONE_VTABLE = chrono.tz.TimeZone.VTable.eraseTypes(@This(), .{
    .offsetAtTimestamp = offsetAtTimestamp,
    .isDaylightSavingTimeAtTimestamp = isDaylightSavingTimeAtTimestamp,
    .designationAtTimestamp = designationAtTimestamp,
});

pub fn timeZone(this: *@This()) chrono.tz.TimeZone {
    return chrono.tz.TimeZone{
        .ptr = this,
        .vtable = &TIMEZONE_VTABLE,
    };
}

pub fn offsetAtTimestamp(this: *const @This(), utc: i64) ?i32 {
    const transition_type_by_timestamp = getTransitionTypeByTimestamp(this.transitionTimes, utc);
    switch (transition_type_by_timestamp) {
        .first_local_time_type => return this.localTimeTypes[0].ut_offset,
        .transition_index => |transition_index| {
            const local_time_type_idx = this.transitionTypes[transition_index];
            const local_time_type = this.localTimeTypes[local_time_type_idx];
            return local_time_type.ut_offset;
        },
        .specified_by_posix_tz,
        .specified_by_posix_tz_or_index_0,
        => if (this.posixTZ) |posixTZ| {
            // Base offset on the TZ string
            return posixTZ.offsetAtTimestamp(utc);
        } else {
            switch (transition_type_by_timestamp) {
                .specified_by_posix_tz => return null,
                .specified_by_posix_tz_or_index_0 => return this.localTimeTypes[0].ut_offset,
                else => unreachable,
            }
        },
    }
}

pub fn isDaylightSavingTimeAtTimestamp(this: *const @This(), utc: i64) ?bool {
    const transition_type_by_timestamp = getTransitionTypeByTimestamp(this.transitionTimes, utc);
    switch (transition_type_by_timestamp) {
        .first_local_time_type => return this.localTimeTypes[0].is_daylight_saving_time,
        .transition_index => |transition_index| {
            const local_time_type_idx = this.transitionTypes[transition_index];
            const local_time_type = this.localTimeTypes[local_time_type_idx];
            return local_time_type.is_daylight_saving_time;
        },
        .specified_by_posix_tz,
        .specified_by_posix_tz_or_index_0,
        => if (this.posixTZ) |posixTZ| {
            // Base offset on the TZ string
            return posixTZ.isDaylightSavingTimeAtTimestamp(utc);
        } else {
            switch (transition_type_by_timestamp) {
                .specified_by_posix_tz => return null,
                .specified_by_posix_tz_or_index_0 => {
                    return this.localTimeTypes[0].is_daylight_saving_time;
                },
                else => unreachable,
            }
        },
    }
}

pub fn designationAtTimestamp(this: *const @This(), utc: i64) ?[]const u8 {
    const transition_type_by_timestamp = getTransitionTypeByTimestamp(this.transitionTimes, utc);
    switch (transition_type_by_timestamp) {
        .first_local_time_type => {
            const local_time_type = this.localTimeTypes[0];

            const designation_end = std.mem.indexOfScalarPos(u8, this.designations[0 .. this.designations.len - 1], local_time_type.designation_index, 0) orelse this.designations.len - 1;
            const designation = this.designations[local_time_type.designation_index..designation_end];

            return designation;
        },
        .transition_index => |transition_index| {
            const local_time_type_idx = this.transitionTypes[transition_index];
            const local_time_type = this.localTimeTypes[local_time_type_idx];

            const designation_end = std.mem.indexOfScalarPos(u8, this.designations[0 .. this.designations.len - 1], local_time_type.designation_index, 0) orelse this.designations.len - 1;
            const designation = this.designations[local_time_type.designation_index..designation_end];

            return designation;
        },
        .specified_by_posix_tz,
        .specified_by_posix_tz_or_index_0,
        => if (this.posixTZ) |posixTZ| {
            // Base offset on the TZ string
            return posixTZ.designationAtTimestamp(utc);
        } else {
            switch (transition_type_by_timestamp) {
                .specified_by_posix_tz => return null,
                .specified_by_posix_tz_or_index_0 => {
                    const local_time_type = this.localTimeTypes[0];

                    const designation_end = std.mem.indexOfScalarPos(u8, this.designations[0 .. this.designations.len - 1], local_time_type.designation_index, 0) orelse this.designations.len - 1;
                    const designation = this.designations[local_time_type.designation_index..designation_end];

                    return designation;
                },
                else => unreachable,
            }
        },
    }
}

pub const ConversionResult = struct {
    timestamp: i64,
    offset: i32,
    is_daylight_saving_time: bool,
    designation: []const u8,
};

fn localTimeFromUTC(this: @This(), utc: i64) ?ConversionResult {
    const offset = this.offsetAtTimestamp(utc) orelse return null;
    const is_daylight_saving_time = this.isDaylightSavingTimeAtTimestamp(utc) orelse return null;
    const designation = this.designationAtTimestamp(utc) orelse return null;
    return ConversionResult{
        .timestamp = utc + offset,
        .offset = offset,
        .is_daylight_saving_time = is_daylight_saving_time,
        .designation = designation,
    };
}

pub const Version = enum(u8) {
    V1 = 0,
    V2 = '2',
    V3 = '3',

    pub fn timeSize(this: @This()) u32 {
        return switch (this) {
            .V1 => 4,
            .V2, .V3 => 8,
        };
    }

    pub fn leapSize(this: @This()) u32 {
        return this.timeSize() + 4;
    }

    pub fn string(this: @This()) []const u8 {
        return switch (this) {
            .V1 => "1",
            .V2 => "2",
            .V3 => "3",
        };
    }
};

pub const LocalTimeType = struct {
    /// An i32 specifying the number of seconds to be added to UT in order to determine local time.
    /// The value MUST NOT be -2**31 and SHOULD be in the range
    /// [-89999, 93599] (i.e., its value SHOULD be more than -25 hours
    /// and less than 26 hours).  Avoiding -2**31 allows 32-bit clients
    /// to negate the value without overflow.  Restricting it to
    /// [-89999, 93599] allows easy support by implementations that
    /// already support the POSIX-required range [-24:59:59, 25:59:59].
    ut_offset: i32,

    /// A value indicating whether local time should be considered Daylight Saving Time (DST).
    ///
    /// A value of `true` indicates that this type of time is DST.
    /// A value of `false` indicates that this time type is standard time.
    is_daylight_saving_time: bool,

    /// A u8 specifying an index into the time zone designations, thereby
    /// selecting a particular designation string. Each index MUST be
    /// in the range [0, "charcnt" - 1]; it designates the
    /// NUL-terminated string of octets starting at position `designation_index` in
    /// the time zone designations.  (This string MAY be empty.)  A NUL
    /// octet MUST exist in the time zone designations at or after
    /// position `designation_index`.
    designation_index: u8,
};

pub const LeapSecond = struct {
    occur: i64,
    corr: i32,
};

const TIME_TYPE_SIZE = 6;

pub const Header = struct {
    version: Version,
    isutcnt: u32,
    isstdcnt: u32,
    leapcnt: u32,
    timecnt: u32,
    typecnt: u32,
    charcnt: u32,

    pub fn dataSize(this: @This(), dataBlockVersion: Version) u32 {
        return this.timecnt * dataBlockVersion.timeSize() +
            this.timecnt +
            this.typecnt * TIME_TYPE_SIZE +
            this.charcnt +
            this.leapcnt * dataBlockVersion.leapSize() +
            this.isstdcnt +
            this.isutcnt;
    }

    pub fn parse(reader: anytype, seekableStream: anytype) !Header {
        var magic_buf: [4]u8 = undefined;
        try reader.readNoEof(&magic_buf);
        if (!std.mem.eql(u8, "TZif", &magic_buf)) {
            log.warn("File is missing magic string 'TZif'", .{});
            return error.InvalidFormat;
        }

        // Check verison
        const version = reader.readEnum(Version, .Little) catch |err| switch (err) {
            error.InvalidValue => return error.UnsupportedVersion,
            else => |e| return e,
        };
        if (version == .V1) {
            return error.UnsupportedVersion;
        }

        // Seek past reserved bytes
        try seekableStream.seekBy(15);

        return Header{
            .version = version,
            .isutcnt = try reader.readInt(u32, .Big),
            .isstdcnt = try reader.readInt(u32, .Big),
            .leapcnt = try reader.readInt(u32, .Big),
            .timecnt = try reader.readInt(u32, .Big),
            .typecnt = try reader.readInt(u32, .Big),
            .charcnt = try reader.readInt(u32, .Big),
        };
    }
};

pub fn parse(allocator: std.mem.Allocator, reader: anytype, seekableStream: anytype) !TZif {
    const v1_header = try Header.parse(reader, seekableStream);
    try seekableStream.seekBy(v1_header.dataSize(.V1));

    const v2_header = try Header.parse(reader, seekableStream);

    // Parse transition times
    var transition_times = try allocator.alloc(i64, v2_header.timecnt);
    errdefer allocator.free(transition_times);
    {
        var prev: i64 = -(2 << 59); // Earliest time supported, this is earlier than the big bang
        var i: usize = 0;
        while (i < transition_times.len) : (i += 1) {
            transition_times[i] = try reader.readInt(i64, .Big);
            if (transition_times[i] <= prev) {
                return error.InvalidFormat;
            }
            prev = transition_times[i];
        }
    }

    // Parse transition types
    const transition_types = try allocator.alloc(u8, v2_header.timecnt);
    errdefer allocator.free(transition_types);
    try reader.readNoEof(transition_types);
    for (transition_types) |transition_type| {
        if (transition_type >= v2_header.typecnt) {
            return error.InvalidFormat; // a transition type index is out of bounds
        }
    }

    // Parse local time type records
    var local_time_types = try allocator.alloc(LocalTimeType, v2_header.typecnt);
    errdefer allocator.free(local_time_types);
    {
        var i: usize = 0;
        while (i < local_time_types.len) : (i += 1) {
            local_time_types[i].ut_offset = try reader.readInt(i32, .Big);
            local_time_types[i].is_daylight_saving_time = switch (try reader.readByte()) {
                0 => false,
                1 => true,
                else => return error.InvalidFormat,
            };

            local_time_types[i].designation_index = try reader.readByte();
            if (local_time_types[i].designation_index >= v2_header.charcnt) {
                return error.InvalidFormat;
            }
        }
    }

    // Read designations
    const time_zone_designations = try allocator.alloc(u8, v2_header.charcnt);
    errdefer allocator.free(time_zone_designations);
    try reader.readNoEof(time_zone_designations);

    // Parse leap seconds records
    var leap_seconds = try allocator.alloc(LeapSecond, v2_header.leapcnt);
    errdefer allocator.free(leap_seconds);
    {
        var i: usize = 0;
        while (i < leap_seconds.len) : (i += 1) {
            leap_seconds[i].occur = try reader.readInt(i64, .Big);
            if (i == 0 and leap_seconds[i].occur < 0) {
                return error.InvalidFormat;
            } else if (i != 0 and leap_seconds[i].occur - leap_seconds[i - 1].occur < 2419199) {
                return error.InvalidFormat; // There must be at least 28 days worth of seconds between leap seconds
            }

            leap_seconds[i].corr = try reader.readInt(i32, .Big);
            if (i == 0 and (leap_seconds[0].corr != 1 and leap_seconds[0].corr != -1)) {
                log.warn("First leap second correction is not 1 or -1: {}", .{leap_seconds[0]});
                return error.InvalidFormat;
            } else if (i != 0) {
                const diff = leap_seconds[i].corr - leap_seconds[i - 1].corr;
                if (diff != 1 and diff != -1) {
                    log.warn("Too large of a difference between leap seconds: {}", .{diff});
                    return error.InvalidFormat;
                }
            }
        }
    }

    // Parse standard/wall indicators
    var transition_is_std = try allocator.alloc(bool, v2_header.isstdcnt);
    errdefer allocator.free(transition_is_std);
    {
        var i: usize = 0;
        while (i < transition_is_std.len) : (i += 1) {
            transition_is_std[i] = switch (try reader.readByte()) {
                1 => true,
                0 => false,
                else => return error.InvalidFormat,
            };
        }
    }

    // Parse UT/local indicators
    var transition_is_ut = try allocator.alloc(bool, v2_header.isutcnt);
    errdefer allocator.free(transition_is_ut);
    {
        var i: usize = 0;
        while (i < transition_is_ut.len) : (i += 1) {
            transition_is_ut[i] = switch (try reader.readByte()) {
                1 => true,
                0 => false,
                else => return error.InvalidFormat,
            };
        }
    }

    // Parse TZ string from footer
    if ((try reader.readByte()) != '\n') return error.InvalidFormat;
    const tz_string = try reader.readUntilDelimiterAlloc(allocator, '\n', 60);
    errdefer allocator.free(tz_string);

    const posixTZ: ?Posix = if (tz_string.len > 0)
        try Posix.parse(tz_string)
    else
        null;

    return TZif{
        .allocator = allocator,
        .version = v2_header.version,
        .transitionTimes = transition_times,
        .transitionTypes = transition_types,
        .localTimeTypes = local_time_types,
        .designations = time_zone_designations,
        .leapSeconds = leap_seconds,
        .transitionIsStd = transition_is_std,
        .transitionIsUT = transition_is_ut,
        .string = tz_string,
        .posixTZ = posixTZ,
    };
}

pub fn parseFile(allocator: std.mem.Allocator, path: []const u8) !TZif {
    const cwd = std.fs.cwd();

    const file = try cwd.openFile(path, .{});
    defer file.close();

    return parse(allocator, file.reader(), file.seekableStream());
}

const TransitionType = union(enum) {
    first_local_time_type,
    transition_index: usize,
    specified_by_posix_tz,
    specified_by_posix_tz_or_index_0,
};

/// Get the transition type of the first element in the `transition_times` array which is less than or equal to `timestamp_utc`.
///
/// Returns `.transition_index` if the timestamp is contained inside the `transition_times` array.
///
/// Returns `.specified_by_posix_tz_or_index_0` if the `transition_times` list is empty.
///
/// Returns `.first_local_time_type` if `timestamp_utc` is before the first transition time.
///
/// Returns `.specified_by_posix_tz` if `timestamp_utc` is after or on the last transition time.
fn getTransitionTypeByTimestamp(transition_times: []const i64, timestamp_utc: i64) TransitionType {
    if (transition_times.len == 0) return .specified_by_posix_tz_or_index_0;
    if (timestamp_utc < transition_times[0]) return .first_local_time_type;
    if (timestamp_utc >= transition_times[transition_times.len - 1]) return .specified_by_posix_tz;

    var left: usize = 0;
    var right: usize = transition_times.len;

    while (left < right) {
        // Avoid overflowing in the midpoint calculation
        const mid = left + (right - left) / 2;
        // Compare the key with the midpoint element
        if (transition_times[mid] == timestamp_utc) {
            if (mid + 1 < transition_times.len) {
                return .{ .transition_index = mid };
            } else {
                return .{ .transition_index = mid };
            }
        } else if (transition_times[mid] > timestamp_utc) {
            right = mid;
        } else if (transition_times[mid] < timestamp_utc) {
            left = mid + 1;
        }
    }

    if (right >= transition_times.len) {
        return .specified_by_posix_tz;
    } else if (right > 0) {
        return .{ .transition_index = right - 1 };
    } else {
        return .first_local_time_type;
    }
}

test getTransitionTypeByTimestamp {
    const transition_times = [7]i64{ -2334101314, -1157283000, -1155436200, -880198200, -769395600, -765376200, -712150200 };

    try testing.expectEqual(TransitionType.first_local_time_type, getTransitionTypeByTimestamp(&transition_times, -2334101315));
    try testing.expectEqual(TransitionType{ .transition_index = 0 }, getTransitionTypeByTimestamp(&transition_times, -2334101314));
    try testing.expectEqual(TransitionType{ .transition_index = 0 }, getTransitionTypeByTimestamp(&transition_times, -2334101313));

    try testing.expectEqual(TransitionType{ .transition_index = 0 }, getTransitionTypeByTimestamp(&transition_times, -1157283001));
    try testing.expectEqual(TransitionType{ .transition_index = 1 }, getTransitionTypeByTimestamp(&transition_times, -1157283000));
    try testing.expectEqual(TransitionType{ .transition_index = 1 }, getTransitionTypeByTimestamp(&transition_times, -1157282999));

    try testing.expectEqual(TransitionType{ .transition_index = 1 }, getTransitionTypeByTimestamp(&transition_times, -1155436201));
    try testing.expectEqual(TransitionType{ .transition_index = 2 }, getTransitionTypeByTimestamp(&transition_times, -1155436200));
    try testing.expectEqual(TransitionType{ .transition_index = 2 }, getTransitionTypeByTimestamp(&transition_times, -1155436199));

    try testing.expectEqual(TransitionType{ .transition_index = 2 }, getTransitionTypeByTimestamp(&transition_times, -880198201));
    try testing.expectEqual(TransitionType{ .transition_index = 3 }, getTransitionTypeByTimestamp(&transition_times, -880198200));
    try testing.expectEqual(TransitionType{ .transition_index = 3 }, getTransitionTypeByTimestamp(&transition_times, -880198199));

    try testing.expectEqual(TransitionType{ .transition_index = 3 }, getTransitionTypeByTimestamp(&transition_times, -769395601));
    try testing.expectEqual(TransitionType{ .transition_index = 4 }, getTransitionTypeByTimestamp(&transition_times, -769395600));
    try testing.expectEqual(TransitionType{ .transition_index = 4 }, getTransitionTypeByTimestamp(&transition_times, -769395599));

    try testing.expectEqual(TransitionType{ .transition_index = 4 }, getTransitionTypeByTimestamp(&transition_times, -765376201));
    try testing.expectEqual(TransitionType{ .transition_index = 5 }, getTransitionTypeByTimestamp(&transition_times, -765376200));
    try testing.expectEqual(TransitionType{ .transition_index = 5 }, getTransitionTypeByTimestamp(&transition_times, -765376199));

    // Why is there 7 transition types if the last type is not used?
    try testing.expectEqual(TransitionType{ .transition_index = 5 }, getTransitionTypeByTimestamp(&transition_times, -712150201));
    try testing.expectEqual(TransitionType.specified_by_posix_tz, getTransitionTypeByTimestamp(&transition_times, -712150200));
    try testing.expectEqual(TransitionType.specified_by_posix_tz, getTransitionTypeByTimestamp(&transition_times, -712150199));
}

test "parse invalid bytes" {
    var fbs = std.io.fixedBufferStream("dflkasjreklnlkvnalkfek");
    try testing.expectError(error.InvalidFormat, parse(std.testing.allocator, fbs.reader(), fbs.seekableStream()));
}

test "parse UTC zoneinfo" {
    var fbs = std.io.fixedBufferStream(@embedFile("zoneinfo/UTC"));

    var res = try parse(std.testing.allocator, fbs.reader(), fbs.seekableStream());
    defer res.deinit();

    try testing.expectEqual(Version.V2, res.version);
    try testing.expectEqualSlices(i64, &[_]i64{}, res.transitionTimes);
    try testing.expectEqualSlices(u8, &[_]u8{}, res.transitionTypes);
    try testing.expectEqualSlices(LocalTimeType, &[_]LocalTimeType{.{ .ut_offset = 0, .is_daylight_saving_time = false, .designation_index = 0 }}, res.localTimeTypes);
    try testing.expectEqualSlices(u8, "UTC\x00", res.designations);
}

test "parse Pacific/Honolulu zoneinfo and calculate local times" {
    const transition_times = [7]i64{ -2334101314, -1157283000, -1155436200, -880198200, -769395600, -765376200, -712150200 };
    const transition_types = [7]u8{ 1, 2, 1, 3, 4, 1, 5 };
    const local_time_types = [6]LocalTimeType{
        .{ .ut_offset = -37886, .is_daylight_saving_time = false, .designation_index = 0 },
        .{ .ut_offset = -37800, .is_daylight_saving_time = false, .designation_index = 4 },
        .{ .ut_offset = -34200, .is_daylight_saving_time = true, .designation_index = 8 },
        .{ .ut_offset = -34200, .is_daylight_saving_time = true, .designation_index = 12 },
        .{ .ut_offset = -34200, .is_daylight_saving_time = true, .designation_index = 16 },
        .{ .ut_offset = -36000, .is_daylight_saving_time = false, .designation_index = 4 },
    };
    const designations = "LMT\x00HST\x00HDT\x00HWT\x00HPT\x00";
    const is_std = &[6]bool{ false, false, false, false, true, false };
    const is_ut = &[6]bool{ false, false, false, false, true, false };
    const string = "HST10";

    var fbs = std.io.fixedBufferStream(@embedFile("zoneinfo/Pacific/Honolulu"));

    var res = try parse(std.testing.allocator, fbs.reader(), fbs.seekableStream());
    defer res.deinit();

    try testing.expectEqual(Version.V2, res.version);
    try testing.expectEqualSlices(i64, &transition_times, res.transitionTimes);
    try testing.expectEqualSlices(u8, &transition_types, res.transitionTypes);
    try testing.expectEqualSlices(LocalTimeType, &local_time_types, res.localTimeTypes);
    try testing.expectEqualSlices(u8, designations, res.designations);
    try testing.expectEqualSlices(bool, is_std, res.transitionIsStd);
    try testing.expectEqualSlices(bool, is_ut, res.transitionIsUT);
    try testing.expectEqualSlices(u8, string, res.string);

    {
        const conversion = res.localTimeFromUTC(-1156939200).?;
        try testing.expectEqual(@as(i64, -1156973400), conversion.timestamp);
        try testing.expectEqual(true, conversion.is_daylight_saving_time);
        try testing.expectEqualSlices(u8, "HDT", conversion.designation);
    }
    {
        // A second before the first timezone transition
        const conversion = res.localTimeFromUTC(-2334101315).?;
        try testing.expectEqual(@as(i64, -2334101315 - 37886), conversion.timestamp);
        try testing.expectEqual(false, conversion.is_daylight_saving_time);
        try testing.expectEqualSlices(u8, "LMT", conversion.designation);
    }
    {
        // At the first timezone transition
        const conversion = res.localTimeFromUTC(-2334101314).?;
        try testing.expectEqual(@as(i64, -2334101314 - 37800), conversion.timestamp);
        try testing.expectEqual(false, conversion.is_daylight_saving_time);
        try testing.expectEqualSlices(u8, "HST", conversion.designation);
    }
    {
        // After the first timezone transition
        const conversion = res.localTimeFromUTC(-2334101313).?;
        try testing.expectEqual(@as(i64, -2334101313 - 37800), conversion.timestamp);
        try testing.expectEqual(false, conversion.is_daylight_saving_time);
        try testing.expectEqualSlices(u8, "HST", conversion.designation);
    }
    {
        // After the last timezone transition; conversion should be performed using the Posix TZ footer.
        // Taken from RFC8536 Appendix B.2
        const conversion = res.localTimeFromUTC(1546300800).?;
        try testing.expectEqual(@as(i64, 1546300800) - 10 * std.time.s_per_hour, conversion.timestamp);
        try testing.expectEqual(false, conversion.is_daylight_saving_time);
        try testing.expectEqualSlices(u8, "HST", conversion.designation);
    }
}

const log = std.log.scoped(.tzif);

const chrono = @import("../lib.zig");
const Posix = @import("./Posix.zig");
const testing = std.testing;
const std = @import("std");
