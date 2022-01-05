const std = @import("std");
const NaiveDateTime = @import("../datetime.zig").NaiveDateTime;

pub fn utcToLocal(timestamp: i64) i64 {
    const timestamp_ms = timestamp * 1000;
    var offsetSeconds: i64 = 0;

    getOffset(&timestamp_ms, &offsetSeconds);

    return timestamp + offsetSeconds;
}

pub fn localToUtc(timestamp: i64) i64 {
    var str_buf: [100]u8 = undefined;

    const datetime = NaiveDateTime.from_timestamp(timestamp, 0).?;
    const str = std.fmt.bufPrint(&str_buf, "{}", .{datetime.formatted("%Y-%m-%dT%H:%M:%S")}) catch unreachable;

    return datetimeStrToUTCTimestamp(str.ptr, str.len);
}

extern "chrono" fn getOffset(timestampMsIn: *const i64, offsetOut: *i64) void;
extern "chrono" fn datetimeStrToUTCTimestamp(datetimeStrPtr: [*]const u8, datetimeStrLen: usize) i64;
