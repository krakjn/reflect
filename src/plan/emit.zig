//! Dry-run / list-only output driver (rsync generator.c + main.c).

const std = @import("std");
const cli = @import("cli");
const catalog = @import("../catalog/mod.zig");
const log = @import("../log/mod.zig");
const compare = @import("compare.zig");
const list_format = @import("list_format.zig");

const Io = std.Io;
const Dir = Io.Dir;
const File = Io.File;
const FileEntry = catalog.FileEntry;
const FileList = catalog.FileList;
const ItemFlags = log.ItemFlags;

pub const EmitError = error{
    OutOfMemory,
} || Dir.StatFileError || Dir.RealPathFileAllocError || Io.Writer.Error;

fn trimTrailingSep(path: []const u8) []const u8 {
    var end = path.len;
    while (end > 0 and path[end - 1] == std.fs.path.sep) end -= 1;
    return path[0..end];
}

fn resolveAbsPath(io: Io, allocator: std.mem.Allocator, path: []const u8) EmitError![]const u8 {
    const resolved: []const u8 = if (std.fs.path.isAbsolute(path))
        try allocator.dupe(u8, path)
    else
        try Dir.cwd().realPathFileAlloc(io, path, allocator);
    return try allocator.dupe(u8, trimTrailingSep(resolved));
}

fn destHasTrailingSlash(dest: []const u8) bool {
    return dest.len > 0 and dest[dest.len - 1] == std.fs.path.sep;
}

fn joinDestPath(allocator: std.mem.Allocator, dest_root: []const u8, rel: []const u8) ![]const u8 {
    if (rel.len == 0) return allocator.dupe(u8, dest_root);
    return std.fs.path.join(allocator, &.{ dest_root, rel });
}

fn shouldShowFlistBanner(opts: *const cli.ReflectOptions) bool {
    return !opts.quiet and opts.list_only == .off and opts.recurse != .off;
}

fn shouldEmitStats(opts: *const cli.ReflectOptions) bool {
    return !opts.quiet;
}

fn pathLessThan(_: void, a: catalog.FileEntry, b: catalog.FileEntry) bool {
    return std.mem.order(u8, a.rel_path, b.rel_path) == .lt;
}

pub fn emitCatalog(
    io: Io,
    allocator: std.mem.Allocator,
    opts: *const cli.ReflectOptions,
    dest_arg: ?[]const u8,
    catalog_list: *const FileList,
    writer: *Io.Writer,
) EmitError!void {
    const list_only = opts.list_only != .off;

    if (list_only) {
        if (shouldShowFlistBanner(opts)) try writer.writeAll("sending incremental file list\n");
        var indices: std.ArrayListUnmanaged(usize) = .empty;
        defer indices.deinit(allocator);
        for (catalog_list.entries.items, 0..) |_, i| try indices.append(allocator, i);
        std.mem.sortUnstable(usize, indices.items, catalog_list.entries.items, struct {
            fn less(ctx: []catalog.FileEntry, a_idx: usize, b_idx: usize) bool {
                return pathLessThan({}, ctx[a_idx], ctx[b_idx]);
            }
        }.less);
        for (indices.items) |idx| {
            try list_format.listEntry(writer, &catalog_list.entries.items[idx], opts);
        }
        if (shouldEmitStats(opts)) try writeStats(writer, catalog_list, opts);
        return;
    }

    if (dest_arg == null) return;

    const dest_abs = try resolveAbsPath(io, allocator, dest_arg.?);
    defer allocator.free(dest_abs);

    const dest_existed = blk: {
        _ = Dir.cwd().statFile(io, dest_abs, .{}) catch break :blk false;
        break :blk true;
    };

    const need_create_msg = !dest_existed and
        (catalog_list.entries.items.len > 1 or destHasTrailingSlash(dest_arg.?));

    if (shouldShowFlistBanner(opts)) try writer.writeAll("sending incremental file list\n");
    if (need_create_msg and !opts.quiet) {
        try writer.print("created directory {s}\n", .{dest_abs});
    }

    const format = log.resolvedStdoutFormat(opts);
    const use_itemize = opts.itemize_changes or std.mem.indexOf(u8, format, "%i") != null;

    var indices: std.ArrayListUnmanaged(usize) = .empty;
    defer indices.deinit(allocator);
    for (catalog_list.entries.items, 0..) |_, i| try indices.append(allocator, i);
    std.mem.sortUnstable(usize, indices.items, catalog_list.entries.items, struct {
        fn less(ctx: []catalog.FileEntry, a_idx: usize, b_idx: usize) bool {
            return pathLessThan({}, ctx[a_idx], ctx[b_idx]);
        }
    }.less);

    for (indices.items) |idx| {
        const e = &catalog_list.entries.items[idx];
        const dest_rel = try joinDestPath(allocator, dest_abs, e.rel_path);
        defer allocator.free(dest_rel);

        const dest_stat: ?File.Stat = if (!dest_existed)
            null
        else
            Dir.cwd().statFile(io, dest_rel, .{}) catch null;

        const iflags = compare.compareEntry(e, dest_stat, opts);

        if (use_itemize) {
            if (!iflags.isSignificant()) continue;
            try log.logItem(writer, format, e, iflags, null, opts);
        } else if (opts.dry_run or opts.verbose > 0) {
            if (!iflags.isSignificant() and dest_stat != null) continue;
            var name_buf: [std.fs.max_path_bytes]u8 = undefined;
            const name = log.formatNamePath(e, &name_buf);
            try writer.print("{s}\n", .{name});
        }
    }

    if (shouldEmitStats(opts)) try writeStats(writer, catalog_list, opts);
}

fn writeStats(writer: *Io.Writer, catalog_list: *const FileList, opts: *const cli.ReflectOptions) Io.Writer.Error!void {
    const total = catalog_list.totalSize();
    const sent: u64 = @intCast(catalog_list.len() * 40 + total);
    const recv: u64 = @intCast(catalog_list.len() * 30);
    if (opts.dry_run) {
        try writer.print(
            "sent {d} bytes  received {d} bytes  total size is {d}  (DRY RUN)\n",
            .{ sent, recv, total },
        );
    } else if (opts.list_only != .off) {
        try writer.print("total size is {d}\n", .{total});
    }
}

test {
    _ = @import("compare.zig");
    _ = @import("list_format.zig");
}
