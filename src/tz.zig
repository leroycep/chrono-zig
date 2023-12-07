pub const Fixed = @import("./tz/Fixed.zig");
pub const Posix = @import("./tz/Posix.zig");
pub const TZif = @import("./tz/TZif.zig");

pub const UTC = Fixed.init(0, "+00:00").timeZone();

pub const DataBase = struct {
    gpa: std.mem.Allocator,
    tz_env_var: ?[]const u8 = null,
    localtime_identifier: ?[]const u8 = null,

    tzif_dir: ?std.fs.Dir,
    tzif_cache: std.StringHashMapUnmanaged(*TZif) = .{},

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

        return @This(){
            .gpa = gpa,
            .tzif_dir = tzif_dir,
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

        if (this.tzif_dir) |*tzif_dir| {
            tzif_dir.close();
        }
    }

    /// Gets a TimeZone by it's IANA identifier
    pub fn getTimeZone(this: *@This(), identifier: []const u8) !TimeZone {
        if (this.tzif_cache.get(identifier)) |tzif| {
            return tzif.timeZone();
        }

        if (this.tzif_dir) |tzif_dir| parse_tzif_file: {
            const tzif_file = tzif_dir.openFile(identifier, .{}) catch |err| switch (err) {
                error.FileNotFound => {
                    log.debug("IANA identifier not found in zoneinfo dir: \"{}\"", .{std.zig.fmtEscapes(identifier)});
                    break :parse_tzif_file;
                },
                else => return err,
            };
            defer tzif_file.close();

            const tzif = try this.gpa.create(TZif);
            tzif.* = try TZif.parse(this.gpa, tzif_file.reader(), tzif_file.seekableStream());

            const identifier_owned = try this.gpa.dupe(u8, identifier);
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

        if (platform_supports_tz_env) parse_tz_env_var: {
            const tz_env_var = this.tz_env_var orelse if (std.process.getEnvVarOwned(this.gpa, "TZ")) |tz_env| store_tz_env_var: {
                this.tz_env_var = tz_env;
                break :store_tz_env_var tz_env;
            } else |err| switch (err) {
                // Continue on to other methods if the environement variable is not found
                error.EnvironmentVariableNotFound => break :parse_tz_env_var,
                else => return err,
            };

            // TODO: Check for TZ strings starting with `:`
            const posix = try this.gpa.create(Posix);
            posix.* = try Posix.parse(tz_env_var);
            return posix.timeZone();
        }

        if (platform_supports_etc_localtime) parse_etc_localtime: {
            const cwd = std.fs.cwd();

            var path_to_localtime_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
            const path_to_localtime = cwd.readLink("/etc/localtime", &path_to_localtime_buf) catch |err| switch (err) {
                error.FileNotFound => break :parse_etc_localtime,
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

            var identifier = std.ArrayList(u8).init(this.gpa);
            defer identifier.deinit();

            while (component_iter.next()) |component| {
                if (identifier.items.len > 0) try identifier.append('/');
                try identifier.appendSlice(component.name);
            }

            const timezone = try this.getTimeZone(identifier.items);

            this.localtime_identifier = try identifier.toOwnedSlice();

            return timezone;
        }

        return error.NotFound;
    }
};

pub const TimeZone = struct {
    ptr: *const anyopaque,
    vtable: *const VTable,

    pub const Offset = struct {
        offset: i32,
        is_daylight_saving_time: bool,
        designation: []const u8,
    };

    pub const VTable = struct {
        offsetAtTimestamp: *const fn (ptr: *const anyopaque, utc: i64) ?Offset,

        /// Takes a list of typed functions and makes functions that take *anyopaque.
        pub fn eraseTypes(comptime T: type, typed_vtable_functions: struct {
            offsetAtTimestamp: *const fn (ptr: *const T, utc: i64) ?TimeZone.Offset,
        }) TimeZone.VTable {
            const generic_vtable_functions = struct {
                fn offsetAtTimestamp(generic_ptr: *const anyopaque, utc: i64) ?TimeZone.Offset {
                    const typed_ptr: *const T = @ptrCast(@alignCast(generic_ptr));
                    return typed_vtable_functions.offsetAtTimestamp(typed_ptr, utc);
                }
            };

            return TimeZone.VTable{
                .offsetAtTimestamp = generic_vtable_functions.offsetAtTimestamp,
            };
        }
    };

    pub fn offsetAtTimestamp(this: *const @This(), utc: i64) ?Offset {
        return this.vtable.offsetAtTimestamp(this.ptr, utc);
    }
};

test {
    _ = Posix;
    _ = TZif;
}

const log = std.log.scoped(.chrono);
const std = @import("std");
