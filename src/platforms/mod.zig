const builtin = @import("builtin");
const native_os = builtin.os.tag;

pub const platform = switch (native_os) {
    .linux => @import("linux.zig"),
    .windows => @import("windows.zig"),
    .macos, .ios => @import("macos.zig"),
    else => @compileError("unsupported OS"),
};
