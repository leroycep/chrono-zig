const std = @import("std");
pub const posix = @import("./timezone/posix.zig");
pub const tzif = @import("./timezone/tzif.zig");
const builtin = @import("builtin");

const FixedUTC = Fixed.init(0);
pub const UTC = &FixedUTC.timezone;

pub const TimeZone = struct {
    utcToLocalFn: *const fn (*const @This(), timestamp: i64) i64,
    timezoneToUtcFn: *const fn (*const @This(), timestamp: i64) i64,

    pub fn utcToLocal(this: *const @This(), timestamp: i64) i64 {
        return this.utcToLocalFn(this, timestamp);
    }

    pub fn timezoneToUtc(this: *const @This(), timestamp: i64) i64 {
        return this.timezoneToUtcFn(this, timestamp);
    }
};

var local_timezone: LocalTimeZone = undefined;
pub fn getLocalTimeZone(allocator: std.mem.Allocator) !*const TimeZone {
    switch (builtin.os.tag) {
        .linux => {
            local_timezone = try TZif.load(allocator, "/etc/localtime");
            return &local_timezone.timezone;
        },
        .freestanding => if (builtin.cpu.arch == .wasm32) {
            local_timezone = Wasm{};
            return &local_timezone.timezone;
        } else @compileError("Platform not supported"),
        else => @compileError("Platform not supported"),
    }
}
pub fn deinitLocalTimeZone() void {
    switch (builtin.os.tag) {
        .linux => {
            local_timezone.deinit();
        },
        .freestanding => if (builtin.cpu.arch == .wasm32) {} else @compileError("Platform not supported"),
        else => @compileError("Platform not supported"),
    }
}

pub const Fixed = struct {
    timezone: TimeZone = .{
        .utcToLocalFn = utcToLocal,
        .timezoneToUtcFn = timezoneToUtc,
    },
    offset: i64,

    pub fn init(offset: i64) @This() {
        return .{ .offset = offset };
    }

    fn utcToLocal(timezone: *const TimeZone, timestamp: i64) i64 {
        const this = @fieldParentPtr(@This(), "timezone", timezone);
        return timestamp + this.offset;
    }

    fn timezoneToUtc(timezone: *const TimeZone, timestamp: i64) i64 {
        const this = @fieldParentPtr(@This(), "timezone", timezone);
        return timestamp - this.offset;
    }
};

pub const TZif = struct {
    timezone: TimeZone = .{
        .utcToLocalFn = utcToLocal,
        .timezoneToUtcFn = timezoneToUtc,
    },
    tzif: tzif.TimeZone,

    pub fn load(allocator: std.mem.Allocator, path: []const u8) !@This() {
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

    fn timezoneToUtc(timezone: *const TimeZone, timestamp: i64) i64 {
        const this = @fieldParentPtr(@This(), "timezone", timezone);
        const conversion = this.tzif.localTimeToUTC(timestamp) orelse {
            std.debug.panic("TZif file does not specify TimeZone", .{});
        };
        return conversion.timestamp;
    }
};

pub const Posix = struct {
    timezone: TimeZone = .{
        .utcToLocalFn = utcToLocal,
        .timezoneToUtcFn = timezoneToUtc,
    },

    tz: posix.TZ,

    fn utcToLocal(timezone: *const TimeZone, timestamp: i64) i64 {
        const this = @fieldParentPtr(@This(), "timezone", timezone);
        const offset_res = this.tz.offset(timestamp);
        return timestamp + offset_res.offset;
    }

    fn timezoneToUtc(timezone: *const TimeZone, timestamp: i64) i64 {
        const this = @fieldParentPtr(@This(), "timezone", timezone);
        const offset_res = this.tz.offset(timestamp);
        return timestamp - offset_res.offset;
    }
};

// Only supports converting to local time
pub const Wasm = struct {
    timezone: TimeZone = .{
        .utcToLocalFn = utcToLocal,
        .timezoneToUtcFn = timezoneToUtc,
    },

    const wasm = @import("timezone/wasm.zig");

    fn utcToLocal(_: *const TimeZone, timestamp: i64) i64 {
        return wasm.utcToLocal(timestamp);
    }

    fn timezoneToUtc(_: *const TimeZone, timestamp: i64) i64 {
        return wasm.localToUtc(timestamp);
    }
};

// TODO: Give user more control over this?
const LocalTimeZone = switch (builtin.os.tag) {
    .linux => TZif,
    .freestanding => if (builtin.cpu.arch == .wasm32) Wasm else @compileError("Platform not supported"),
    else => @compileError("Platform not supported"),
};

comptime {
    @import("std").testing.refAllDecls(@This());
}

test "Load TZif file" {
    const utc = TZif.load(std.testing.allocator, "src/timezone/zoneinfo/UTC") catch |err| switch (err) {
        error.FileNotFound => return error.SkipZigTest,
        else => |e| return e,
    };
    defer utc.deinit();

    const honolulu = TZif.load(std.testing.allocator, "src/timezone/zoneinfo/Pacific/Honolulu") catch |err| switch (err) {
        error.FileNotFound => return error.SkipZigTest,
        else => |e| return e,
    };
    defer honolulu.deinit();
}
