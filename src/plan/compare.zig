//! Compare source catalog entries to destination paths (generator.c / itemize()).

const std = @import("std");
const cli = @import("cli");
const entry = @import("../catalog/entry.zig");
const log = @import("../log/mod.zig");

const Io = std.Io;
const File = Io.File;
const ItemFlags = log.ItemFlags;

pub fn compareEntry(
    src: *const entry.FileEntry,
    dest: ?File.Stat,
    opts: *const cli.ReflectOptions,
) ItemFlags {
    if (dest == null) return .forNewEntry(src.kind);

    var flags = ItemFlags{};

    if (src.kind == .file and dest.?.size != src.size) {
        flags.report_size = true;
    }

    if (opts.preserve_mtimes and dest.?.mtime.nanoseconds != src.mtime) {
        flags.report_time = true;
    }

    if (opts.preserve_perms and src.permissions.toMode() & 0o7777 != dest.?.permissions.toMode() & 0o7777) {
        flags.report_perms = true;
    } else if (opts.preserve_executability and src.kind != .symlink) {
        const src_x = src.permissions.toMode() & 0o111;
        const dst_x = dest.?.permissions.toMode() & 0o111;
        if (src_x != dst_x) flags.report_perms = true;
    }

    if (!flags.isSignificant()) return .{};
    flags.transfer = true;
    return flags;
}

test "compareEntry new vs unchanged" {
    var opts = cli.ReflectOptions.defaults();
    opts.applyArchive();

    const src = entry.FileEntry{
        .rel_path = "f",
        .path = "f",
        .filter_path = "/f",
        .kind = .file,
        .size = 10,
        .mtime = 1000,
        .permissions = File.Permissions.fromMode(0o100644),
        .symlink_target = null,
    };

    const new_flags = compareEntry(&src, null, &opts);
    try std.testing.expect(new_flags.is_new);

    const dst_stat: File.Stat = .{
        .inode = 1,
        .nlink = 1,
        .size = 10,
        .permissions = File.Permissions.fromMode(0o100644),
        .kind = .file,
        .atime = .zero,
        .mtime = .{ .nanoseconds = 1000 },
        .ctime = .zero,
        .block_size = 4096,
    };
    const same = compareEntry(&src, dst_stat, &opts);
    try std.testing.expect(!same.isSignificant());
}
