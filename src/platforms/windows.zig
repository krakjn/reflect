const std = @import("std");
const windows = std.os.windows;

const ProcessIdentity = @import("types.zig").ProcessIdentity;

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

pub fn capture_process_identity() ProcessIdentity {
    return .{ .uid = 0, .gid = 0, .umask = 0 };
}

pub fn get_timestamp() i64 {
    var ft: windows.FILETIME = undefined;
    _ = windows.GetSystemTimeAsFileTime(&ft);
    return @as(i64, @intCast(ft.dwHighDateTime)) << 32 | @as(i64, @intCast(ft.dwLowDateTime));
}
