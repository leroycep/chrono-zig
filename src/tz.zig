pub const Fixed = @import("./tz/Fixed.zig");
pub const Posix = @import("./tz/Posix.zig");
pub const TZif = @import("./tz/TZif.zig");
pub const Win32 = @import("./tz/Win32.zig");

pub const UTC = (Fixed{
    .offset = 0,
    .designation = "+00:00",
    .iana_identifier = Identifier.parse("UTC") catch unreachable,
}).timeZone();

// Make sure that the UTC timezone works
test UTC {
    try std.testing.expectEqual(@as(?i32, 0), UTC.offsetAtTimestamp(0));
    try std.testing.expectEqual(@as(?i32, 0), UTC.offsetAtTimestamp(1331438400));

    try std.testing.expectEqualStrings("+00:00", UTC.designationAtTimestamp(0) orelse return error.TestExpectedEqual);
    try std.testing.expectEqualStrings("+00:00", UTC.designationAtTimestamp(1331438400) orelse return error.TestExpectedEqual);

    try std.testing.expectEqualStrings("UTC", UTC.identifier().?.string);
}

pub const DataBase = struct {
    gpa: std.mem.Allocator,
    tz_env_var: ?[]const u8 = null,
    localtime_identifier: ?[]const u8 = null,

    tzif_dir: ?std.fs.Dir,
    tzif_cache: std.StringHashMapUnmanaged(*TZif) = .{},

    /// A hashmap mapping Windows' timezone keys to IANA timezone keys
    win32_timezone_mapping: if (platform_supports_win32) *Win32.mapping.WindowsToIANAHashmap else void,
    win32_timezones: if (platform_supports_win32) std.AutoHashMapUnmanaged(*Win32, void) else void = if (platform_supports_win32) .{},

    const platform_supports_win32 = builtin.target.os.tag == .windows;

    pub fn init(gpa: std.mem.Allocator) !@This() {
        const cwd = std.fs.cwd();

        const tzdir_err_opt = if (std.process.getEnvVarOwned(gpa, "TZDIR")) |tzdir| open_tzdir: {
            defer gpa.free(tzdir);
            break :open_tzdir cwd.openDir(tzdir, .{});
        } else |err| switch (err) {
            // Continue on to other methods if the environement variable is not found
            error.EnvironmentVariableNotFound => cwd.openDir("/usr/share/zoneinfo", .{}),
            else => return err,
        };

        const tzif_dir: ?std.fs.Dir = tzdir_err_opt catch null;

        const win32_timezone_key_mapping = if (platform_supports_win32) try gpa.create(Win32.mapping.WindowsToIANAHashmap);
        if (platform_supports_win32) {
            win32_timezone_key_mapping.* = try Win32.mapping.constructWindowsToIANAHashmap(gpa);
        }

        return @This(){
            .gpa = gpa,
            .tzif_dir = tzif_dir,
            .win32_timezone_mapping = win32_timezone_key_mapping,
        };
    }

    pub fn deinit(this: *@This()) void {
        if (this.tz_env_var) |tz_env_var| {
            this.gpa.free(tz_env_var);
        }
        if (this.localtime_identifier) |localtime_identifier| {
            this.gpa.free(localtime_identifier);
        }

        var tzif_iter = this.tzif_cache.iterator();
        while (tzif_iter.next()) |tzif| {
            tzif.value_ptr.*.deinit();
            this.gpa.destroy(tzif.value_ptr.*);
            this.gpa.free(tzif.key_ptr.*);
        }
        this.tzif_cache.deinit(this.gpa);

        if (platform_supports_win32) {
            var win32_iter = this.win32_timezones.iterator();
            while (win32_iter.next()) |win32| {
                win32.key_ptr.*.deinit();
                this.gpa.destroy(win32.key_ptr.*);
            }
            this.win32_timezones.deinit(this.gpa);

            Win32.mapping.freeWindowsToIANAHashmap(this.gpa, this.win32_timezone_mapping);
            this.gpa.destroy(this.win32_timezone_mapping);
        }

        if (this.tzif_dir) |*tzif_dir| {
            tzif_dir.close();
        }
    }

    /// Gets a TimeZone by it's IANA identifier
    pub fn getTimeZone(this: *@This(), identifier: Identifier) !TimeZone {
        if (this.tzif_cache.get(identifier.string)) |tzif| {
            return tzif.timeZone();
        }

        if (this.tzif_dir) |tzif_dir| parse_tzif_file: {
            const tzif_file = tzif_dir.openFile(identifier.string, .{}) catch |err| switch (err) {
                error.FileNotFound => {
                    log.debug("IANA identifier not found in zoneinfo dir: \"{}\"", .{std.zig.fmtEscapes(identifier.string)});
                    break :parse_tzif_file;
                },
                else => return err,
            };
            defer tzif_file.close();

            const tzif = try this.gpa.create(TZif);
            tzif.* = try TZif.parse(this.gpa, tzif_file.reader(), tzif_file.seekableStream());

            const identifier_owned = try this.gpa.dupe(u8, identifier.string);
            try this.tzif_cache.putNoClobber(this.gpa, identifier_owned, tzif);

            return tzif.timeZone();
        }

        return error.NotFound;
    }

    /// Returns the local timezone if it can find it, or null otherwise. Returns an error on OutOfMemory.
    pub fn getLocalTimeZone(this: *@This()) !TimeZone {
        // TODO: Check if we are on a platform that uses TZ or `/etc/localtime` to specify the timezone
        const platform_supports_tz_env = true;
        const platform_supports_etc_localtime = true;

        if (platform_supports_tz_env) {
            if (try this.getLocalTimeZoneFromTZEnvVar()) |new_timezone| {
                return new_timezone;
            }
        }

        if (platform_supports_win32) {
            if (try Win32.localTimeZone(this.gpa, this.win32_timezone_mapping)) |win32_timezone| {
                const win32_timezone_ptr = try this.gpa.create(Win32);
                win32_timezone_ptr.* = win32_timezone;
                try this.win32_timezones.put(this.gpa, win32_timezone_ptr, {});

                return win32_timezone_ptr.timeZone();
            }
        }

        if (platform_supports_etc_localtime) {
            if (try this.getLocalTimeZoneFromEtcLocaltime()) |etc_localtime_timezone| {
                return etc_localtime_timezone;
            }
        }

        return error.NotFound;
    }

    fn getLocalTimeZoneFromTZEnvVar(this: *@This()) !?TimeZone {
        const tz_env_var = this.tz_env_var orelse if (std.process.getEnvVarOwned(this.gpa, "TZ")) |tz_env| store_tz_env_var: {
            this.tz_env_var = tz_env;
            break :store_tz_env_var tz_env;
        } else |err| switch (err) {
            // Continue on to other methods if the environement variable is not found
            error.EnvironmentVariableNotFound => return null,
            else => return err,
        };

        // TODO: Check for TZ strings starting with `:`
        const posix = try this.gpa.create(Posix);
        posix.* = try Posix.parse(tz_env_var);
        return posix.timeZone();
    }

    fn getLocalTimeZoneFromEtcLocaltime(this: *@This()) !?TimeZone {
        const cwd = std.fs.cwd();

        var path_to_localtime_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
        const path_to_localtime = cwd.readLink("/etc/localtime", &path_to_localtime_buf) catch |err| switch (err) {
            error.FileNotFound => return null,
            else => return err,
        };

        // TODO: Make it not rely on the path containing "/zoneinfo/"?
        var component_iter = try std.fs.path.componentIterator(path_to_localtime);
        while (component_iter.next()) |component| {
            if (std.mem.eql(u8, component.name, "zoneinfo")) {
                break;
            }
        } else {
            return error.InvalidEtcLocalTimeSymlink;
        }

        var identifier_string = std.ArrayList(u8).init(this.gpa);
        defer identifier_string.deinit();

        while (component_iter.next()) |component| {
            if (identifier_string.items.len > 0) try identifier_string.append('/');
            try identifier_string.appendSlice(component.name);
        }

        const identifier = try Identifier.parse(identifier_string.items);
        const timezone = try this.getTimeZone(identifier);

        this.localtime_identifier = try identifier_string.toOwnedSlice();

        return timezone;
    }
};

/// IANA timezone strings must be parsed into an Identifier first, to ensure that user input won't read from a different
/// directory zoneinfo.
pub const Identifier = struct {
    string: []const u8,

    /// This function will validate that the IANA identifier only contains valid characters and doesn't, for example,
    /// contain stuff like "../".
    pub fn parse(string: []const u8) !@This() {
        for (string) |character| {
            switch (character) {
                'A'...'Z',
                'a'...'z',
                '0'...'9',
                '+',
                '-',
                '_',
                '/',
                => {},
                else => return error.InvalidFormat,
            }
        }
        return @This(){
            .string = string,
        };
    }
};

pub const TimeZone = struct {
    ptr: *const anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        offsetAtTimestamp: *const fn (ptr: *const anyopaque, timestamp_utc: i64) ?i32,
        isDaylightSavingTimeAtTimestamp: *const fn (ptr: *const anyopaque, timestamp_utc: i64) ?bool,
        designationAtTimestamp: *const fn (ptr: *const anyopaque, timestamp_utc: i64) ?[]const u8,

        /// Should return and IANA (Olson database) identifer
        identifier: *const fn (ptr: *const anyopaque) ?Identifier,

        /// Takes a list of typed functions and makes functions that take *anyopaque.
        /// Used when implementing a type that exposes a TimeZone interface.
        pub fn eraseTypes(comptime T: type, typed_vtable_functions: struct {
            offsetAtTimestamp: *const fn (ptr: *const T, utc: i64) ?i32,
            isDaylightSavingTimeAtTimestamp: *const fn (ptr: *const T, timestamp_utc: i64) ?bool,
            designationAtTimestamp: *const fn (ptr: *const T, timestamp_utc: i64) ?[]const u8,
            identifier: *const fn (ptr: *const T) ?Identifier,
        }) TimeZone.VTable {
            const generic_vtable_functions = struct {
                fn offsetAtTimestamp(generic_ptr: *const anyopaque, utc: i64) ?i32 {
                    const typed_ptr: *const T = @ptrCast(@alignCast(generic_ptr));
                    return typed_vtable_functions.offsetAtTimestamp(typed_ptr, utc);
                }

                fn isDaylightSavingTimeAtTimestamp(generic_ptr: *const anyopaque, utc: i64) ?bool {
                    const typed_ptr: *const T = @ptrCast(@alignCast(generic_ptr));
                    return typed_vtable_functions.isDaylightSavingTimeAtTimestamp(typed_ptr, utc);
                }

                fn designationAtTimestamp(generic_ptr: *const anyopaque, utc: i64) ?[]const u8 {
                    const typed_ptr: *const T = @ptrCast(@alignCast(generic_ptr));
                    return typed_vtable_functions.designationAtTimestamp(typed_ptr, utc);
                }

                fn identifier(generic_ptr: *const anyopaque) ?Identifier {
                    const typed_ptr: *const T = @ptrCast(@alignCast(generic_ptr));
                    return typed_vtable_functions.identifier(typed_ptr);
                }
            };

            return TimeZone.VTable{
                .offsetAtTimestamp = generic_vtable_functions.offsetAtTimestamp,
                .isDaylightSavingTimeAtTimestamp = generic_vtable_functions.isDaylightSavingTimeAtTimestamp,
                .designationAtTimestamp = generic_vtable_functions.designationAtTimestamp,
                .identifier = generic_vtable_functions.identifier,
            };
        }
    };

    pub fn offsetAtTimestamp(this: *const @This(), timestamp_utc: i64) ?i32 {
        return this.vtable.offsetAtTimestamp(this.ptr, timestamp_utc);
    }

    pub fn isDaylightSavingTimeAtTimestamp(this: *const @This(), timestamp_utc: i64) ?bool {
        return this.vtable.isDaylightSavingTimeAtTimestamp(this.ptr, timestamp_utc);
    }

    pub fn designationAtTimestamp(this: *const @This(), timestamp_utc: i64) ?[]const u8 {
        return this.vtable.designationAtTimestamp(this.ptr, timestamp_utc);
    }

    pub fn identifier(this: *const @This()) ?Identifier {
        return this.vtable.identifier(this.ptr);
    }
};

test {
    _ = Fixed;
    _ = Posix;
    _ = TZif;
}

const builtin = @import("builtin");
const log = std.log.scoped(.chrono);
const std = @import("std");
