const std = @import("std");
const Io = std.Io;

const cli = @import("cli");
const reflect = @import("reflect");

pub const std_options: std.Options = .{
    .log_level = .warn,
};

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();

    const cmd_args = try init.minimal.args.toSlice(arena);
    const parsed = switch (cli.parse(arena, cmd_args)) {
        .ok => |parsed| parsed,
        .err => |parse_failure| {
            std.log.err("{f}", .{parse_failure});
            return std.process.exit(1);
        },
    };
    var session = reflect.Session.fromParsed(arena, init.io, parsed);
    if (session.validate()) |failure| {
        std.log.err("{f}", .{failure});
        return std.process.exit(3);
    }

    var filters = session.initFilters() catch |err| {
        std.log.err("filter setup failed: {s}", .{@errorName(err)});
        return std.process.exit(3);
    };
    defer filters.deinit();

    var catalog = session.buildCatalog(&filters) catch |err| {
        std.log.err("catalog walk failed: {s}", .{@errorName(err)});
        return std.process.exit(3);
    };
    defer catalog.deinit();

    if (session.wantsTransfer()) {
        session.runLocalTransfer(&catalog) catch |err| {
            std.log.err("transfer failed: {s}", .{@errorName(err)});
            return std.process.exit(3);
        };
        return;
    }

    var out_buf: [8192]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(init.io, &out_buf);
    const writer = &stdout_writer.interface;

    session.emitCatalog(&catalog, writer) catch |err| {
        std.log.err("output failed: {s}", .{@errorName(err)});
        return std.process.exit(13);
    };
    try stdout_writer.end();

    return std.process.exit(0);
}
