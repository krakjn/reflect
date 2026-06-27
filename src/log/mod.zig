//! Client output formatting (rsync log.c subset).

pub const itemize = @import("itemize.zig");
pub const format = @import("format.zig");

pub const ItemFlags = itemize.ItemFlags;
pub const formatItemize = itemize.formatItemize;
pub const logItem = format.logItem;
pub const resolvedStdoutFormat = format.resolvedStdoutFormat;
pub const formatNamePath = format.formatNamePath;

test {
    _ = @import("itemize.zig");
    _ = @import("format.zig");
}
