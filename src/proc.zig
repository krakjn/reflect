const std = @import("std");
const builtin = @import("builtin");
const native_os = builtin.os.tag;
const posix = std.posix;
const platform = @import("platforms/platform.zig");

// There's probably never more than at most 2 outstanding child processes,
// but set it higher, just in case.
pub var max_child_procs: u8 = 7;

var pid_stat_table: [max_child_procs]struct {
    pid: i32,
    status: i32,
} = .{ .pid = 0, .status = 0 } ** max_child_procs;

/// Non-blocking wait flag. Matches `WNOHANG` on POSIX; bit 0 on Windows.
pub const w_nohang: i32 = switch (native_os) {
    .windows => 1,
    else => if (@hasDecl(posix.W, "NOHANG"))
        @intCast(posix.W.NOHANG)
    else
        @compileError("wait flags unsupported on this OS"),
};

fn lookupHarvestedStatus(pid: i32, status_ptr: *i32) ?i32 {
    for (pid_stat_table) |*entry| {
        if (pid == entry.pid) {
            status_ptr.* = entry.status;
            entry.pid = 0;
            return pid;
        }
    }
    return null;
}

/// Works like waitpid(), but if we already harvested the child pid in
/// remember_children(), we succeed instead of returning an error.
pub fn wait_process(pid: i32, status_ptr: *i32, flags: i32) !i32 {
    return switch (native_os) {
        .windows => waitProcessWindows(pid, status_ptr, flags),
        .wasi => @compileError("wait_process is unsupported on WASI"),
        else => if (@hasDecl(posix.system, "waitpid"))
            waitProcessPosix(pid, status_ptr, flags)
        else
            @compileError("wait_process is unsupported on this OS"),
    };
}

fn waitProcessPosix(pid: i32, status_ptr: *i32, flags: i32) !i32 {
    var waited_pid: i32 = -1;
    var last_err: posix.E = .SUCCESS;
    var status: if (builtin.link_libc) c_int else u32 = undefined;

    while (true) {
        const rc = posix.system.waitpid(pid, &status, flags);
        switch (posix.errno(rc)) {
            .SUCCESS => {
                waited_pid = @intCast(rc);
                break;
            },
            .INTR => continue,
            else => |err| {
                waited_pid = -1;
                last_err = err;
                break;
            },
        }
    }

    if (waited_pid != -1) {
        status_ptr.* = @intCast(status);
        return waited_pid;
    }

    if (last_err == .CHILD) {
        if (lookupHarvestedStatus(pid, status_ptr)) |found_pid| return found_pid;
    }

    return -1;
}

fn waitProcessWindows(pid: i32, status_ptr: *i32, flags: i32) !i32 {
    const windows = std.os.windows;

    const handle = kernel32.OpenProcess(
        windows.ACCESS_MASK.fromSpecific(.{
            .PROCESS = .{
                .SYNCHRONIZE = true,
                .QUERY_LIMITED_INFORMATION = true,
            },
        }),
        windows.FALSE,
        @intCast(pid),
    ) orelse {
        if (lookupHarvestedStatus(pid, status_ptr)) |found_pid| return found_pid;
        return -1;
    };
    defer windows.CloseHandle(handle);

    const nohang = flags & w_nohang != 0;
    const timeout_ms: windows.DWORD = if (nohang) 0 else windows.INFINITE;
    switch (kernel32.WaitForSingleObject(handle, timeout_ms)) {
        windows.WAIT_OBJECT_0 => {},
        windows.WAIT_TIMEOUT => return 0,
        else => return -1,
    }

    var exit_code: windows.DWORD = undefined;
    if (kernel32.GetExitCodeProcess(handle, &exit_code) == windows.FALSE) return -1;

    // Encode like a normal Unix exit status so WEXITSTATUS() works.
    status_ptr.* = @as(i32, @intCast(exit_code << 8));
    return pid;
}

const kernel32 = struct {
    pub extern "kernel32" fn OpenProcess(
        dwDesiredAccess: std.os.windows.ACCESS_MASK,
        bInheritHandle: std.os.windows.BOOL,
        dwProcessId: std.os.windows.DWORD,
    ) callconv(.winapi) ?std.os.windows.HANDLE;

    pub extern "kernel32" fn WaitForSingleObject(
        hHandle: std.os.windows.HANDLE,
        dwMilliseconds: std.os.windows.DWORD,
    ) callconv(.winapi) std.os.windows.DWORD;

    pub extern "kernel32" fn GetExitCodeProcess(
        hProcess: std.os.windows.HANDLE,
        lpExitCode: *std.os.windows.DWORD,
    ) callconv(.winapi) std.os.windows.BOOL;
};
