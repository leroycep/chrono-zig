const std = @import("std");
pub const posix = @import("./timezone/posix.zig");
pub const tzif = @import("./timezone/tzif.zig");

const FixedUTC = Fixed.init(0);
pub const UTC = &FixedUTC.timezone;

pub const TimeZone = struct {
    utcToLocalFn: fn (*const @This(), timestamp: i64) i64,

    pub fn utcToLocal(this: *const @This(), timestamp: i64) i64 {
        return this.utcToLocalFn(this, timestamp);
    }
};

pub const Fixed = struct {
    timezone: TimeZone = .{
        .utcToLocalFn = utcToLocal,
    },
    offset: i64,

    pub fn init(offset: i64) @This() {
        return .{ .offset = offset };
    }

    fn utcToLocal(timezone: *const TimeZone, timestamp: i64) i64 {
        const this = @fieldParentPtr(@This(), "timezone", timezone);
        return timestamp + this.offset;
    }
};

pub const TZif = struct {
    timezone: TimeZone = .{
        .utcToLocalFn = utcToLocal,
    },
    tzif: tzif.TimeZone,

    pub fn load(allocator: *std.mem.Allocator, path: []const u8) !@This() {
        return @This(){
            .tzif = try tzif.parseFile(allocator, path),
        };
    }

    pub fn deinit(this: @This()) void {
        this.tzif.deinit();
    }

    fn utcToLocal(timezone: *const TimeZone, timestamp: i64) i64 {
        const this = @fieldParentPtr(@This(), "timezone", timezone);
        const conversion = this.tzif.localTimeFromUTC(timestamp) orelse {
            std.debug.panic("TZif file does not specify TimeZone", .{});
        };
        return conversion.timestamp;
    }
};

pub const Posix = struct {
    timezone: TimeZone = .{
        .utcToLocalFn = utcToLocal,
    },
    tz: posix.TZ,

    fn utcToLocal(timezone: *const TimeZone, timestamp: i64) i64 {
        const this = @fieldParentPtr(@This(), "timezone", timezone);
        const offset_res = tz.offset(timestamp);
        return timestamp + offset_res.offset;
    }
};

test "" {
    @import("std").testing.refAllDecls(@This());
}

test "Load TZif file" {
    const utc = try TZif.load(std.testing.allocator, "src/timezone/zoneinfo/UTC");
    defer utc.deinit();
    const honolulu = try TZif.load(std.testing.allocator, "src/timezone/zoneinfo/Pacific/Honolulu");
    defer honolulu.deinit();
}
