//! rsync-style `list_file_entry` output (`--list-only`).

const std = @import("std");
const cli = @import("cli");
const entry = @import("../catalog/entry.zig");
const log = @import("../log/mod.zig");

const Io = std.Io;
const File = Io.File;
const FileEntry = entry.FileEntry;

fn permString(kind: entry.Kind, perms: File.Permissions, buf: *[10]u8) []const u8 {
    const mode = perms.toMode() & 0o777;
    buf[0] = switch (kind) {
        .dir => 'd',
        .symlink => 'l',
        else => '-',
    };
    const masks = [_]std.posix.mode_t{ 0o400, 0o200, 0o100, 0o040, 0o020, 0o010, 0o004, 0o002, 0o001 };
    const chars = "rwxrwxrwx";
    for (masks, 0..) |mask, idx| {
        buf[idx + 1] = if (mode & mask != 0) chars[idx] else '-';
    }
    return buf[0..10];
}

fn formatTime(mtime_ns: i128, buf: *[32]u8) []const u8 {
    const secs_u: u64 = @intCast(@max(@divTrunc(mtime_ns, std.time.ns_per_s), 0));
    const epoch_sec = std.time.epoch.EpochSeconds{ .secs = secs_u };
    const ymd = epoch_sec.getEpochDay().calculateYearDay();
    const md = ymd.calculateMonthDay();
    const day_sec = epoch_sec.getDaySeconds();
    return std.fmt.bufPrint(buf, "{d:0>4}/{d:0>2}/{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}", .{
        ymd.year,
        md.month.numeric(),
        md.day_index + 1,
        day_sec.getHoursIntoDay(),
        day_sec.getMinutesIntoHour(),
        day_sec.getSecondsIntoMinute(),
    }) catch "1970/01/01 00:00:00";
}

pub fn listEntry(writer: *Io.Writer, e: *const FileEntry, opts: *const cli.ReflectOptions) Io.Writer.Error!void {
    var perm_buf: [10]u8 = undefined;
    var time_buf: [32]u8 = undefined;
    var name_buf: [std.fs.max_path_bytes]u8 = undefined;

    const perms = permString(e.kind, e.permissions, &perm_buf);
    const mtime = formatTime(e.mtime, &time_buf);
    const name = log.formatNamePath(e, &name_buf);

    const size_val: u64 = e.size;

    if (e.kind == .symlink and opts.preserve_links) {
        if (e.symlink_target) |target| {
            try writer.print("{s} {d:>11} {s} {s} -> {s}\n", .{ perms, size_val, mtime, name, target });
            return;
        }
    }
    try writer.print("{s} {d:>11} {s} {s}\n", .{ perms, size_val, mtime, name });
}

test "permString file mode" {
    var buf: [10]u8 = undefined;
    const s = permString(.file, File.Permissions.fromMode(0o100644), &buf);
    try std.testing.expectEqualStrings("-rw-r--r--", s);
}
