pub const Posix = @import("./tz/Posix.zig");
pub const TZif = @import("./tz/TZif.zig");

test {
    _ = Posix;
    _ = TZif;
}
