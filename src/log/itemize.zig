//! rsync itemize-changes flag bits and 11-character summary (log.c `%i`).

const std = @import("std");
const cli = @import("cli");
const entry = @import("../catalog/entry.zig");

pub const ItemFlags = struct {
    report_atime: bool = false,
    report_change: bool = false,
    report_size: bool = false,
    report_time: bool = false,
    report_perms: bool = false,
    report_owner: bool = false,
    report_group: bool = false,
    report_acl: bool = false,
    report_xattr: bool = false,
    report_crtime: bool = false,
    basis_type_follows: bool = false,
    xname_follows: bool = false,
    is_new: bool = false,
    local_change: bool = false,
    transfer: bool = false,

    pub fn isSignificant(self: ItemFlags) bool {
        return self.is_new or self.report_atime or self.report_change or
            self.report_size or self.report_time or self.report_perms or self.report_owner or
            self.report_group or self.report_acl or self.report_xattr or self.report_crtime or
            self.local_change;
    }

    pub fn forNewEntry(kind: entry.Kind) ItemFlags {
        return if (kind == .dir)
            .{ .local_change = true, .is_new = true }
        else
            .{ .transfer = true, .is_new = true };
    }

    pub fn forNewTransfer() ItemFlags {
        return .{ .transfer = true, .is_new = true };
    }
};

/// Build the rsync itemize prefix (e.g. `>f+++++++++`, `>f..t......`).
pub fn formatItemize(
    iflags: ItemFlags,
    kind: entry.Kind,
    opts: *const cli.ReflectOptions,
    buf: *[12]u8,
) []const u8 {
    const preserve_time = opts.preserve_mtimes;

    buf[0] = if (iflags.local_change)
        if (iflags.xname_follows) 'h' else 'c'
    else if (!iflags.transfer)
        '.'
    else
        '>';
    buf[1] = switch (kind) {
        .dir => 'd',
        .symlink => 'L',
        else => 'f',
    };

    if (kind == .symlink) {
        buf[3] = '.';
        buf[4] = if (!iflags.report_time) '.' else if (!preserve_time) 'T' else 't';
    } else {
        buf[3] = if (!iflags.report_size) '.' else 's';
        buf[4] = if (!iflags.report_time) '.' else if (!preserve_time) 'T' else 't';
    }
    buf[2] = if (!iflags.report_change) '.' else 'c';
    buf[5] = if (!iflags.report_perms) '.' else 'p';
    buf[6] = if (!iflags.report_owner) '.' else 'o';
    buf[7] = if (!iflags.report_group) '.' else 'g';
    buf[8] = if (!iflags.report_atime and !iflags.report_crtime) '.'
        else if (iflags.report_atime and iflags.report_crtime) 'b'
        else if (iflags.report_atime) 'u'
        else 'n';
    buf[9] = if (!iflags.report_acl) '.' else 'a';
    buf[10] = if (!iflags.report_xattr) '.' else 'x';
    buf[11] = 0;

    if (iflags.is_new) {
        var i: usize = 2;
        while (i < 11) : (i += 1) buf[i] = '+';
    } else if (buf[0] == '.' or buf[0] == 'h' or buf[0] == 'c') {
        var i: usize = 2;
        var all_dot = true;
        while (i < 11) : (i += 1) {
            if (buf[i] != '.') {
                all_dot = false;
                break;
            }
        }
        if (all_dot) {
            i = 2;
            while (i < 11) : (i += 1) buf[i] = ' ';
        }
    }

    return buf[0..11];
}

test "formatItemize new directory" {
    var opts = cli.ReflectOptions.defaults();
    opts.applyArchive();

    var buf: [12]u8 = undefined;
    const s = formatItemize(.forNewEntry(.dir), .dir, &opts, &buf);
    try std.testing.expectEqualStrings("cd+++++++++", s);
}

test "formatItemize new file with -a" {
    var opts = cli.ReflectOptions.defaults();
    opts.applyArchive();

    var buf: [12]u8 = undefined;
    const s = formatItemize(.forNewTransfer(), .file, &opts, &buf);
    try std.testing.expectEqualStrings(">f+++++++++", s);
}

test "formatItemize mtime-only update" {
    var opts = cli.ReflectOptions.defaults();
    opts.applyArchive();

    var buf: [12]u8 = undefined;
    const s = formatItemize(.{ .transfer = true, .report_time = true }, .file, &opts, &buf);
    try std.testing.expectEqualStrings(">f..t......", s);
}
