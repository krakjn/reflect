const builtin = @import("builtin");

const native_os = builtin.os.tag;

const plat = switch (native_os) {
    .linux => @import("linux.zig"),
    .windows => @import("windows.zig"),
    .macos, .ios, .tvos, .watchos, .visionos, .driverkit, .maccatalyst => @import("macos.zig"),
    else => @compileError("unsupported OS"),
};

pub fn get_page_size() u32 {
    return plat.get_page_size();
}
