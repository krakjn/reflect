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
    const user_args = if (cmd_args.len > 0) cmd_args[1..] else cmd_args[0..0];
    const parsed = switch (cli.parse(arena, user_args)) {
        .ok => |parsed| parsed,
        .err => |parse_failure| {
            std.log.err("{f}", .{parse_failure});
            return error.ParseError;
        },
    };
    var session = reflect.Session.fromParsed(arena, init.io, parsed);
    if (session.validate()) |failure| {
        std.log.err("{f}", .{failure});
        return;
    }

    var filters = session.initFilters() catch |err| {
        std.log.err("filter setup failed: {s}", .{@errorName(err)});
        return;
    };
    defer filters.deinit();

    var catalog = session.buildCatalog(&filters) catch |err| {
        std.log.err("catalog walk failed: {s}", .{@errorName(err)});
        return;
    };
    defer catalog.deinit();

    var out_buf: [8192]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(init.io, &out_buf);
    const writer = &stdout_writer.interface;

    session.emitCatalog(&catalog, writer) catch |err| {
        std.log.err("output failed: {s}", .{@errorName(err)});
        return;
    };
    try stdout_writer.end();
}
