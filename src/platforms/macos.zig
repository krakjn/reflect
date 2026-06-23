const std = @import("std");

const ProcessIdentity = @import("types.zig").ProcessIdentity;

pub fn get_page_size() u32 {
    const task_port = std.c.mach_task_self();
    if (task_port == std.c.TASK.NULL) return 0;
    var info_count = std.c.TASK.VM.INFO_COUNT;
    var vm_info: std.c.task_vm_info_data_t = undefined;
    vm_info.page_size = 0;
    _ = std.c.task_info(
        task_port,
        std.c.TASK.VM.INFO,
        @as(std.c.task_info_t, @ptrCast(&vm_info)),
        &info_count,
    );
    return @intCast(vm_info.page_size);
}

pub fn capture_process_identity() ProcessIdentity {
    return .{
        .uid = @intCast(std.c.getuid()),
        .gid = @intCast(std.c.getgid()),
        .umask = @truncate(std.c.umask(0)),
    };
}

pub fn get_timestamp() i64 {
    var tv: std.c.timeval = undefined;
    if (std.c.gettimeofday(&tv, null) != 0) return 0;
    return tv.sec;
}
