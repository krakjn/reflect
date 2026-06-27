//! Local whole-file copy (Slice 2): single-process src/ → dest/ on disk.

const std = @import("std");
const cli = @import("cli");
const catalog = @import("../catalog/mod.zig");
const plan = @import("../plan/mod.zig");

const Io = std.Io;
const Dir = Io.Dir;
const File = Io.File;
const Allocator = std.mem.Allocator;
const FileEntry = catalog.FileEntry;
const FileList = catalog.FileList;

pub const CopyStats = struct {
    xferred_files: i32 = 0,
    created_dirs: i32 = 0,
    created_symlinks: i32 = 0,
    total_transferred_size: i64 = 0,
    num_files: i32 = 0,
    total_size: i64 = 0,
};

pub const LocalError = error{
    OutOfMemory,
    DestinationNotDirectory,
} || Dir.OpenError || Dir.StatFileError || Dir.RealPathFileAllocError ||
    Dir.CopyFileError || Dir.CreateDirError || Dir.CreateDirPathError ||
    Dir.SymLinkError || Dir.SetFilePermissionsError || Dir.SetTimestampsError ||
    Dir.RenameError;

fn trimTrailingSep(path: []const u8) []const u8 {
    var end = path.len;
    while (end > 0 and path[end - 1] == std.fs.path.sep) end -= 1;
    return path[0..end];
}

fn pathHasTrailingSlash(path: []const u8) bool {
    return path.len > 0 and path[path.len - 1] == std.fs.path.sep;
}

fn anySourceTrailingSlash(sources: []const []const u8) bool {
    for (sources) |source| {
        if (pathHasTrailingSlash(source)) return true;
    }
    return false;
}

/// Resolve destination to an absolute path without requiring it to exist.
fn resolveDestPath(io: Io, allocator: Allocator, path: []const u8) LocalError![]const u8 {
    const trimmed = trimTrailingSep(path);
    if (trimmed.len == 0) return error.DestinationNotDirectory;

    if (std.fs.path.isAbsolute(trimmed)) return try allocator.dupe(u8, trimmed);

    const cwd = try Dir.cwd().realPathFileAlloc(io, ".", allocator);
    defer allocator.free(cwd);
    return try std.fs.path.join(allocator, &.{ cwd, trimmed });
}

fn joinDestPath(allocator: Allocator, dest_root: []const u8, rel: []const u8) ![]const u8 {
    if (rel.len == 0) return try allocator.dupe(u8, dest_root);
    return std.fs.path.join(allocator, &.{ dest_root, rel });
}

fn backupPath(allocator: Allocator, dest_path: []const u8, suffix: []const u8) ![]const u8 {
    return try std.fmt.allocPrint(allocator, "{s}{s}", .{ dest_path, suffix });
}

fn applyMetadata(
    io: Io,
    dest_path: []const u8,
    src: *const FileEntry,
    opts: *const cli.ReflectOptions,
) LocalError!void {
    if (opts.preserve_perms or opts.preserve_executability) {
        try Dir.cwd().setFilePermissions(io, dest_path, src.permissions, .{});
    }
    if (opts.preserve_mtimes) {
        const ts = Io.Timestamp{ .nanoseconds = @intCast(src.mtime) };
        try Dir.cwd().setTimestamps(io, dest_path, .{
            .access_timestamp = .unchanged,
            .modify_timestamp = File.SetTimestamp.init(ts),
        });
    }
}

fn copyRegularFile(
    io: Io,
    allocator: Allocator,
    src: *const FileEntry,
    dest_path: []const u8,
    dest_stat: ?File.Stat,
    opts: *const cli.ReflectOptions,
) LocalError!void {
    if (opts.make_backups and dest_stat != null) {
        const backup = try backupPath(allocator, dest_path, opts.effectiveBackupSuffix());
        defer allocator.free(backup);
        Dir.renameAbsolute(dest_path, backup, io) catch {};
    }

    const perms: ?File.Permissions = if (opts.preserve_perms or opts.preserve_executability)
        src.permissions
    else
        null;

    try Dir.copyFileAbsolute(src.src_abs, dest_path, io, .{
        .permissions = perms,
        .make_path = true,
        .replace = true,
    });

    try applyMetadata(io, dest_path, src, opts);
}

fn copySymlink(
    io: Io,
    src: *const FileEntry,
    dest_path: []const u8,
    opts: *const cli.ReflectOptions,
) LocalError!void {
    const target = src.symlink_target orelse return;
    const flags: Dir.SymLinkFlags = .{};
    try Dir.cwd().symLinkAtomic(io, target, dest_path, flags);
    if (opts.preserve_mtimes) {
        try applyMetadata(io, dest_path, src, opts);
    }
}

fn ensureDirectory(
    io: Io,
    dest_path: []const u8,
    src: *const FileEntry,
    dest_stat: ?File.Stat,
    opts: *const cli.ReflectOptions,
) LocalError!void {
    if (dest_stat != null and dest_stat.?.kind == .directory) {
        try applyMetadata(io, dest_path, src, opts);
        return;
    }
    try Dir.cwd().createDirPath(io, dest_path);
    try applyMetadata(io, dest_path, src, opts);
}

fn copyEntry(
    io: Io,
    allocator: Allocator,
    src: *const FileEntry,
    dest_root: []const u8,
    opts: *const cli.ReflectOptions,
    stats: *CopyStats,
) LocalError!void {
    const dest_path = try joinDestPath(allocator, dest_root, src.rel_path);
    defer allocator.free(dest_path);

    const dest_stat = Dir.cwd().statFile(io, dest_path, .{}) catch null;

    if (!plan.shouldTransfer(src, dest_stat, opts)) return;

    switch (src.kind) {
        .file => {
            try copyRegularFile(io, allocator, src, dest_path, dest_stat, opts);
            stats.xferred_files += 1;
            stats.total_transferred_size += @intCast(src.size);
        },
        .dir => {
            try ensureDirectory(io, dest_path, src, dest_stat, opts);
            if (dest_stat == null) stats.created_dirs += 1;
        },
        .symlink => {
            if (!opts.preserve_links) return;
            try copySymlink(io, src, dest_path, opts);
            stats.created_symlinks += 1;
        },
    }
}

fn ensureDestRoot(
    io: Io,
    dest_abs: []const u8,
    multi_source: bool,
    dest_trailing_slash: bool,
    source_trailing_slash: bool,
) LocalError!void {
    const st = Dir.cwd().statFile(io, dest_abs, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            if (!multi_source and !dest_trailing_slash and !source_trailing_slash)
                return error.DestinationNotDirectory;
            try Dir.cwd().createDirPath(io, dest_abs);
            return;
        },
        else => return err,
    };

    if (st.kind != .directory) return error.DestinationNotDirectory;
}

/// Copy all catalog entries to `dest_arg` using whole-file semantics.
pub fn runWholeFile(
    io: Io,
    allocator: Allocator,
    opts: *const cli.ReflectOptions,
    sources: []const []const u8,
    dest_arg: []const u8,
    catalog_list: *const FileList,
    stats: *CopyStats,
) LocalError!void {
    const dest_abs = try resolveDestPath(io, allocator, dest_arg);
    defer allocator.free(dest_abs);

    try ensureDestRoot(
        io,
        dest_abs,
        sources.len > 1,
        pathHasTrailingSlash(dest_arg),
        anySourceTrailingSlash(sources),
    );

    for (catalog_list.entries.items) |*entry| {
        try copyEntry(io, allocator, entry, dest_abs, opts, stats);
    }

    stats.num_files = @intCast(catalog_list.len());
    stats.total_size = @intCast(catalog_list.totalSize());
}

test {
    _ = @import("local_test.zig");
}
