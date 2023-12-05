const std = @import("std");
const chrono = @import("chrono");

pub fn main() !void {
    var gpa_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_allocator.deinit();
    const gpa = gpa_allocator.allocator();

    // TODO: create cross platform API to get the local timezone
    const timezone = try chrono.tz.TZif.parseFile(gpa, "/etc/localtime");
    defer timezone.deinit();

    const timestamp_utc = std.time.timestamp();
    const conversion_to_local = timezone.localTimeFromUTC(timestamp_utc) orelse {
        std.debug.print("Could not convert the current time to local time.", .{});
        return error.ConversionFailed;
    };
    const timestamp_local = conversion_to_local.timestamp;

    const date = chrono.date.YearMonthDay.fromDaysSinceUnixEpoch(@intCast(@divFloor(timestamp_local, std.time.s_per_day)));
    const time = chrono.Time{ .secs = @intCast(@mod(timestamp_local, std.time.s_per_day)), .frac = 0 };

    std.debug.print("The current date is {}, and the time is {} in the {s} timezone", .{ date, time, conversion_to_local.designation });
}
