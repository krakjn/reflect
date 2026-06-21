const std = @import("std");
const windows = std.os.windows;

pub fn get_page_size() u32 {
    var sbi: windows.SYSTEM.BASIC_INFORMATION = undefined;
    switch (windows.ntdll.NtQuerySystemInformation(
        .Basic,
        &sbi,
        @sizeOf(windows.SYSTEM.BASIC_INFORMATION),
        null,
    )) {
        .SUCCESS => return sbi.PageSize,
        else => return 0,
    }
}
