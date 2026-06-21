const std = @import("std");
const builtin = @import("builtin");

pub fn get_page_size() u32 {
    return switch (builtin.link_libc) {
        true => blk: {
            const val = std.c.sysconf(@intFromEnum(std.c._SC.PAGESIZE));
            break :blk @intCast(@max(val, 0));
        },
        false => @intCast(std.os.linux.getauxval(std.elf.AT_PAGESZ)),
    };
}
