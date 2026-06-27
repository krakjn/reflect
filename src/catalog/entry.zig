//! One path in the transfer catalog (subset of rsync file_struct for Slice 1).

const std = @import("std");

pub const Kind = enum {
    file,
    dir,
    symlink,

    pub fn fromMode(_: u32) Kind {
        @compileError("use fromFileKind");
    }

    pub fn fromFileKind(k: @import("std").Io.File.Kind) Kind {
        return switch (k) {
            .directory => .dir,
            .sym_link => .symlink,
            else => .file,
        };
    }

    pub fn nameFlags(self: Kind) @import("../filter/rule.zig").NameFlags {
        const nf = @import("../filter/rule.zig").NameFlags;
        return switch (self) {
            .dir => nf.dir(),
            else => nf.file(),
        };
    }
};

pub const FileEntry = struct {
    /// Path relative to the source root (no leading slash).
    rel_path: []const u8,
    /// Same as `rel_path`; used by logging / itemize (Slice 1c).
    path: []const u8,
    /// Filter-check path (leading `/`, rsync-style).
    filter_path: []const u8,
    /// Absolute source path (for local copy, Slice 2).
    src_abs: []const u8,
    kind: Kind,
    size: u64,
    mtime: i128,
    permissions: @import("std").Io.File.Permissions,
    /// Symlink target when `kind == .symlink` and links are read.
    symlink_target: ?[]const u8 = null,

    pub fn deinit(self: *FileEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.rel_path);
        allocator.free(self.filter_path);
        allocator.free(self.src_abs);
        if (self.symlink_target) |t| allocator.free(t);
        self.* = undefined;
    }
};

pub fn filterPathFromRel(allocator: std.mem.Allocator, rel: []const u8) ![]const u8 {
    if (rel.len == 0) return try allocator.dupe(u8, "/");
    const need = 1 + rel.len;
    const out = try allocator.alloc(u8, need);
    out[0] = '/';
    @memcpy(out[1..], rel);
    return out;
}
