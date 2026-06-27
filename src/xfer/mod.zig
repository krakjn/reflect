pub const local = @import("local.zig");

pub const runWholeFile = local.runWholeFile;
pub const CopyStats = local.CopyStats;
pub const LocalError = local.LocalError;

test {
    _ = @import("local.zig");
}
