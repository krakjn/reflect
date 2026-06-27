//! Local file catalog: walk source trees and apply filters (Slice 1b).

pub const entry = @import("entry.zig");
pub const list = @import("list.zig");
pub const walk = @import("walk.zig");

pub const FileEntry = entry.FileEntry;
pub const FileList = list.FileList;
pub const Kind = entry.Kind;
pub const WalkOptions = walk.WalkOptions;

test {
    _ = @import("walk_test.zig");
}
