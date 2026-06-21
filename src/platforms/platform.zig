const builtin = @import("builtin");

const native_os = builtin.os.tag;

const impl = switch (native_os) {
    .linux => @import("linux.zig"),
    .windows => @import("windows.zig"),
    .macos, .ios, .tvos, .watchos, .visionos, .driverkit, .maccatalyst => @import("macos.zig"),
    else => @compileError("unsupported OS"),
};

pub fn get_max_child_procs() u32 {
    return impl.get_max_child_procs();
}
