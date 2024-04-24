const std = @import("std");
const date = @import("./date.zig");
const Time = @import("./Time.zig");

pub fn rfc3339UTCStringFromUnixTimestamp(str_buffer: []u8, timestamp: i64) ![]const u8 {
    const ymd = date.YearMonthDay.fromDaysSinceUnixEpoch(@intCast(@divFloor(timestamp, std.time.s_per_day)));
    const time = try Time.fromNumSecondsFromMidnight(@intCast(@mod(timestamp, std.time.s_per_day)), 0);
    return try std.fmt.bufPrint(str_buffer, "{}T{}Z", .{ ymd, time });
}

test rfc3339UTCStringFromUnixTimestamp {
    var buffer: [32]u8 = undefined;
    try std.testing.expectEqualStrings("1970-01-01T00:00:00Z", try rfc3339UTCStringFromUnixTimestamp(&buffer, 0));
    try std.testing.expectEqualStrings("2024-04-24T19:44:31Z", try rfc3339UTCStringFromUnixTimestamp(&buffer, 1713987871));
}
