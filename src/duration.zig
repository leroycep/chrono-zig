const std = @import("std");

/// The number of seconds in the Duration, total
pub fn totalSeconds(secs: i64) i64 {
    return secs;
}

/// The number of seconds in the Duration that are not in a minute
pub fn seconds(secs: i64) i64 {
    return @mod(secs, 60);
}

/// The number of minutes in the Duration, total
pub fn totalMinutes(secs: i64) i64 {
    return @divFloor(secs, 60);
}

/// The number of minutes in the Duration that are not in a hour
pub fn minutes(secs: i64) i64 {
    return @mod(totalMinutes(secs), 60);
}

/// The number of hours in the Duration, total
pub fn totalHours(secs: i64) i64 {
    return @divFloor(secs, 60 * 60);
}

/// The number of hours in the Duration that are not in a day
pub fn hours(secs: i64) i64 {
    return @mod(totalHours(secs), 24);
}

pub const DurationFormatComponent = enum(u8) {
    percent = '%',
    total_hours = 'H',
    total_minutes = 'M',
    total_seconds = 'S',
    hours = 'h',
    minutes = 'm',
    seconds = 's',
    _,
};

pub fn DurationFormat(comptime durationFormatStr: []const u8) type {
    return struct {
        secs: i64,

        pub fn format(
            this: @This(),
            comptime _: []const u8,
            _: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            var last_was_percent = false;
            for (durationFormatStr) |c| {
                if (last_was_percent) {
                    switch (@as(DurationFormatComponent, @enumFromInt(c))) {
                        .percent => try writer.writeByte('%'),
                        .total_hours => try writer.print("{}", .{totalHours(this.secs)}),
                        .total_minutes => try writer.print("{}", .{totalMinutes(this.secs)}),
                        .total_seconds => try writer.print("{}", .{totalSeconds(this.secs)}),
                        .hours => try writer.print("{}", .{hours(this.secs)}),
                        .minutes => try writer.print("{}", .{minutes(this.secs)}),
                        .seconds => try writer.print("{}", .{seconds(this.secs)}),
                        else => @panic("unknown duration format specifier"),
                    }
                    last_was_percent = false;
                } else {
                    switch (c) {
                        '%' => last_was_percent = true,
                        else => |b| try writer.writeByte(b),
                    }
                }
            }
        }
    };
}

pub fn fmtDuration(comptime durationFmt: []const u8, secs: i64) DurationFormat(durationFmt) {
    return DurationFormat(durationFmt){
        .secs = secs,
    };
}
