const std = @import("std");
pub const posix = @import("./timezone/posix.zig");
pub const tzif = @import("./timezone/tzif.zig");

pub const UTC = TimeZone{ .Fixed = 0 };

// CrossPlatform timezone abstraction
pub const TimeZone = union(enum) {
    Fixed: i32,
    /// Specifies a timezone that has daylight savings during part of the year
    Posix: posix.TZ,
    /// IANA timezone specification RFC 8536
    TZif: tzif.TimeZone,

    pub fn loadTZif(allocator: *std.mem.Allocator, path: []const u8) !@This() {
        return TimeZone{
            .TZif = try tzif.parseFile(allocator, path),
        };
    }

    pub fn deinit(this: @This()) void {
        switch (this) {
            .Fixed, .Posix => {},
            .TZif => |tz|  tz.deinit() ,
        }
    }

    pub fn utcToLocal(this: @This(), timestamp: i64) i64 {
        switch (this) {
            .Fixed => |offset| return timestamp + offset,
            .Posix => |tz| {
                const offset_res = tz.offset(timestamp);
                return timestamp + offset_res.offset;
            },
            .TZif => |tz| {
                const conversion = tz.localTimeFromUTC(timestamp) orelse {
                    std.debug.panic("TZif file does not specify TimeZone", .{});
                };
                return conversion.timestamp;
            },
        }
    }
};

test "" {
    @import("std").testing.refAllDecls(@This());
}

test "Load TZif file" {
    const utc = try TimeZone.loadTZif(std.testing.allocator, "src/timezone/zoneinfo/UTC");
    defer utc.deinit();
    const honolulu = try TimeZone.loadTZif(std.testing.allocator, "src/timezone/zoneinfo/Pacific/Honolulu");
    defer honolulu.deinit();
}
