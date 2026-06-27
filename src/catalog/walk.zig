//! Directory walk with filter integration (rsync flist.c send_directory / make_file).

const std = @import("std");
const cli = @import("cli");
const filter = @import("../filter/mod.zig");
const entry = @import("entry.zig");
const list = @import("list.zig");

const Io = std.Io;
const Dir = Io.Dir;
const File = Io.File;
const Allocator = std.mem.Allocator;
const FileList = list.FileList;
const FilterEngine = filter.FilterEngine;
const NameFlags = filter.NameFlags;

pub const WalkError = error{
    OutOfMemory,
    AccessDenied,
    NameTooLong,
    Unexpected,
} || Dir.OpenError || Dir.StatFileError || Dir.RealPathFileAllocError || filter.FilterError;

pub fn shouldRecurse(options: *const cli.ReflectOptions) bool {
    return options.recurse != .off;
}

pub fn shouldIncludeDirs(options: *const cli.ReflectOptions) bool {
    return shouldRecurse(options) or options.xfer_dirs != .off;
}

/// Walk policy derived from CLI options (Slice 1b).
pub const WalkOptions = struct {
    recurse: bool,
    include_dirs: bool,
    one_file_system: bool,

    pub fn fromReflect(options: *const cli.ReflectOptions) WalkOptions {
        return .{
            .recurse = shouldRecurse(options),
            .include_dirs = shouldIncludeDirs(options),
            .one_file_system = options.one_file_system,
        };
    }
};

fn kindFromFileKind(k: File.Kind) entry.Kind {
    return switch (k) {
        .directory => .dir,
        .sym_link => .symlink,
        else => .file,
    };
}

fn dirDev(_: Dir) ?std.posix.dev_t {
    // Io.File.Stat does not expose st_dev yet; -x is a no-op until then.
    return null;
}

fn isExcluded(engine: *FilterEngine, filter_path: []const u8, kind: entry.Kind) bool {
    const nf = kind.nameFlags();
    if (engine.isExcluded(filter_path, nf, .all)) return true;
    if (kind != .dir and engine.isExcluded(filter_path, NameFlags.dir(), .all)) return true;
    if (kind == .dir and engine.isExcluded(filter_path, NameFlags.file(), .all)) return true;
    return false;
}

fn pushFilterDir(engine: *FilterEngine, rel: []const u8) WalkError!?*filter.LocalFilterState {
    const dir = if (rel.len == 0) "." else rel;
    return engine.pushLocalFilters(dir) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => |e| return e,
    };
}

fn srcAbsPath(allocator: Allocator, source_root: []const u8, rel: []const u8) Allocator.Error![]const u8 {
    if (rel.len == 0) return try allocator.dupe(u8, source_root);
    return std.fs.path.join(allocator, &.{ source_root, rel });
}

fn appendEntry(
    allocator: Allocator,
    catalog: *FileList,
    source_root: []const u8,
    rel: []const u8,
    kind: entry.Kind,
    stat: File.Stat,
    symlink_target: ?[]const u8,
) WalkError!void {
    const rel_owned = try allocator.dupe(u8, rel);
    errdefer allocator.free(rel_owned);
    const filter_path = try entry.filterPathFromRel(allocator, rel);
    errdefer allocator.free(filter_path);
    const src_abs = try srcAbsPath(allocator, source_root, rel);
    errdefer allocator.free(src_abs);

    try catalog.append(.{
        .rel_path = rel_owned,
        .path = rel_owned,
        .filter_path = filter_path,
        .src_abs = src_abs,
        .kind = kind,
        .size = stat.size,
        .mtime = @intCast(stat.mtime.nanoseconds),
        .permissions = stat.permissions,
        .symlink_target = symlink_target,
    });
}

fn walkDir(
    io: Io,
    allocator: Allocator,
    engine: *FilterEngine,
    dir: Dir,
    source_root: []const u8,
    rel: []const u8,
    options: *const cli.ReflectOptions,
    catalog: *FileList,
    root_dev: ?std.posix.dev_t,
) WalkError!void {
    const recurse = shouldRecurse(options);
    const include_dirs = shouldIncludeDirs(options);

    const filter_state = try pushFilterDir(engine, rel);
    defer engine.popLocalFilters(filter_state);

    var it = dir.iterate();
    while (try it.next(io)) |dent| {
        if (std.mem.eql(u8, dent.name, ".") or std.mem.eql(u8, dent.name, "..")) continue;

        const child_rel = if (rel.len == 0)
            try allocator.dupe(u8, dent.name)
        else
            try std.fmt.allocPrint(allocator, "{s}/{s}", .{ rel, dent.name });
        defer allocator.free(child_rel);

        const child_filter = try entry.filterPathFromRel(allocator, child_rel);
        defer allocator.free(child_filter);

        const stat = dir.statFile(io, dent.name, .{}) catch |err| switch (err) {
            error.AccessDenied, error.PermissionDenied => continue,
            else => return err,
        };

        const kind = kindFromFileKind(stat.kind);

        if (options.one_file_system and kind == .dir) {
            if (root_dev) |dev| {
                const sub = dir.openDir(io, dent.name, .{}) catch continue;
                defer sub.close(io);
                if (dirDev(sub)) |sub_dev| {
                    if (sub_dev != dev) continue;
                }
            }
        }

        if (isExcluded(engine, child_filter, kind)) continue;

        if (kind == .dir and !include_dirs) continue;

        const symlink_target: ?[]const u8 = if (kind == .symlink) blk: {
            var link_buf: [std.fs.max_path_bytes]u8 = undefined;
            const n = dir.readLink(io, dent.name, &link_buf) catch break :blk null;
            break :blk try allocator.dupe(u8, link_buf[0..n]);
        } else null;
        errdefer if (symlink_target) |t| allocator.free(t);

        try appendEntry(allocator, catalog, source_root, child_rel, kind, stat, symlink_target);

        if (kind == .dir and recurse) {
            const sub = try dir.openDir(io, dent.name, .{ .iterate = true });
            defer sub.close(io);
            try walkDir(io, allocator, engine, sub, source_root, child_rel, options, catalog, root_dev);
        }
    }
}

/// Walk one source path and append included entries to `catalog`.
pub fn walkSource(
    io: Io,
    allocator: Allocator,
    engine: *FilterEngine,
    source: []const u8,
    options: *const cli.ReflectOptions,
    catalog: *FileList,
) WalkError!void {
    const source_path = blk: {
        const resolved: []const u8 = if (std.fs.path.isAbsolute(source))
            try allocator.dupe(u8, source)
        else
            try Dir.cwd().realPathFileAlloc(io, source, allocator);
        defer allocator.free(resolved);
        var end = resolved.len;
        while (end > 0 and resolved[end - 1] == std.fs.path.sep) end -= 1;
        break :blk try allocator.dupe(u8, resolved[0..end]);
    };
    defer allocator.free(source_path);

    try engine.setCurrDirPath(source_path);
    engine.ctx.options.module_dirlen = 0;
    try engine.setFilterDir(".");

    var root_dir = try Dir.cwd().openDir(io, source_path, .{ .iterate = true });
    defer root_dir.close(io);

    const root_stat = try root_dir.stat(io);
    const root_dev = if (options.one_file_system) dirDev(root_dir) else null;

    if (shouldIncludeDirs(options) and !isExcluded(engine, "/", .dir)) {
        try appendEntry(allocator, catalog, source_path, "", .dir, root_stat, null);
    }

    try walkDir(io, allocator, engine, root_dir, source_path, "", options, catalog, root_dev);
}
