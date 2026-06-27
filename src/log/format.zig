//! Subset of rsync log.c `log_formatted` for client stdout (`%i`, `%n`, `%L`).

const std = @import("std");
const cli = @import("cli");
const entry = @import("../catalog/entry.zig");
const itemize = @import("itemize.zig");

const Io = std.Io;
const FileEntry = entry.FileEntry;
const ItemFlags = itemize.ItemFlags;

pub fn resolvedStdoutFormat(opts: *const cli.ReflectOptions) []const u8 {
    if (opts.stdout_format) |fmt| return fmt;
    if (opts.itemize_changes) return "%i %n%L";
    if (opts.dry_run or opts.list_only != .off or opts.verbose > 0) return "%n%L";
    return "%n%L";
}

pub fn formatNamePath(e: *const FileEntry, buf: []u8) []const u8 {
    if (e.rel_path.len == 0) {
        @memcpy(buf[0..2], "./");
        return buf[0..2];
    }
    if (e.kind == .dir) {
        const need = e.rel_path.len + 1;
        if (need > buf.len) return e.rel_path;
        @memcpy(buf[0..e.rel_path.len], e.rel_path);
        buf[e.rel_path.len] = '/';
        return buf[0 .. e.rel_path.len + 1];
    }
    if (e.rel_path.len > buf.len) return e.rel_path;
    @memcpy(buf[0..e.rel_path.len], e.rel_path);
    return e.rel_path;
}

fn writeLinkSuffix(
    writer: *Io.Writer,
    e: *const FileEntry,
    hlink: ?[]const u8,
) Io.Writer.Error!void {
    if (hlink) |h| {
        if (h.len != 0) try writer.print(" => {s}", .{h});
        return;
    }
    if (e.kind == .symlink) {
        if (e.symlink_target) |target| try writer.print(" -> {s}", .{target});
    }
}

pub fn logItem(
    writer: *Io.Writer,
    format: []const u8,
    e: *const FileEntry,
    iflags: ItemFlags,
    hlink: ?[]const u8,
    opts: *const cli.ReflectOptions,
) Io.Writer.Error!void {
    var name_buf: [std.fs.max_path_bytes]u8 = undefined;
    var item_buf: [12]u8 = undefined;

    var i: usize = 0;
    while (i < format.len) {
        if (format[i] != '%') {
            const start = i;
            while (i < format.len and format[i] != '%') : (i += 1) {}
            try writer.writeAll(format[start..i]);
            continue;
        }
        i += 1;
        if (i >= format.len) break;
        switch (format[i]) {
            'i' => {
                const s = itemize.formatItemize(iflags, e.kind, opts, &item_buf);
                try writer.writeAll(s);
            },
            'n' => {
                const name = formatNamePath(e, &name_buf);
                try writer.writeAll(name);
            },
            'L' => try writeLinkSuffix(writer, e, hlink),
            '%' => try writer.writeAll("%"),
            else => {},
        }
        i += 1;
    }
    try writer.writeAll("\n");
}
