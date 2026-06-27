//! Transfer planning: dest comparison and dry-run output.

pub const compare = @import("compare.zig");
pub const emit = @import("emit.zig");
pub const list_format = @import("list_format.zig");

pub const compareEntry = compare.compareEntry;
pub const shouldTransfer = compare.shouldTransfer;
pub const emitCatalog = emit.emitCatalog;

test {
    _ = @import("compare.zig");
    _ = @import("emit.zig");
    _ = @import("list_format.zig");
}
