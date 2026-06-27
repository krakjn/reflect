//! In-memory file catalog (rsync file_list, local half only).

const std = @import("std");
const entry = @import("entry.zig");

const Allocator = std.mem.Allocator;
const FileEntry = entry.FileEntry;

pub const FileList = struct {
    allocator: Allocator,
    entries: std.ArrayList(FileEntry),

    pub fn init(allocator: Allocator) FileList {
        return .{
            .allocator = allocator,
            .entries = .empty,
        };
    }

    pub fn deinit(self: *FileList) void {
        for (self.entries.items) |*e| {
            e.deinit(self.allocator);
        }
        self.entries.deinit(self.allocator);
    }

    pub fn append(self: *FileList, e: FileEntry) !void {
        try self.entries.append(self.allocator, e);
    }

    pub fn len(self: *const FileList) usize {
        return self.entries.items.len;
    }

    pub fn totalSize(self: *const FileList) u64 {
        var sum: u64 = 0;
        for (self.entries.items) |e| {
            if (e.kind == .file) sum += e.size;
        }
        return sum;
    }
};
