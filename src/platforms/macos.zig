const std = @import("std");

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
