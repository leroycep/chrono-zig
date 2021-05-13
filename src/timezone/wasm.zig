pub fn utcToLocal(timestamp: i64) i64 {
    const timestamp_ms = timestamp * 1000;
    var offsetSeconds: i64 = 0;

    getOffset(&timestamp_ms, &offsetSeconds);

    return timestamp + offsetSeconds;
}

extern "chrono" fn getOffset(timestampMsIn: *const i64, offsetOut: *i64) void;
