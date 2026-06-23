const std = @import("std");
const builtin = @import("builtin");

const ProcessIdentity = @import("types.zig").ProcessIdentity;

pub fn get_page_size() u32 {
    return switch (builtin.link_libc) {
        true => blk: {
            const val = std.c.sysconf(@intFromEnum(std.c._SC.PAGESIZE));
            break :blk @intCast(@max(val, 0));
        },
        false => @intCast(std.os.linux.getauxval(std.elf.AT_PAGESZ)),
    };
}

pub fn capture_process_identity() ProcessIdentity {
    if (builtin.link_libc) {
        return .{
            .uid = @intCast(std.c.getuid()),
            .gid = @intCast(std.c.getgid()),
            .umask = @truncate(std.c.umask(0)),
        };
    }
    return .{
        .uid = @intCast(std.os.linux.getuid()),
        .gid = @intCast(std.os.linux.getgid()),
        .umask = 0,
    };
}

pub fn get_timestamp() i64 {
    var ts: std.os.linux.timespec = undefined;
    if (std.os.linux.errno(std.os.linux.clock_gettime(.REALTIME, &ts)) != .SUCCESS) return 0;
    return ts.sec;
}
