const std = @import("std");
const Io = std.Io;

const cli = @import("cli");
const reflect = @import("reflect");
const proc = @import("proc.zig");

pub const std_options: std.Options = .{
    .log_level = .info,
};

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();

    const cmd_args = try init.minimal.args.toSlice(arena);
    const parsed = switch (cli.parse(arena, cmd_args)) {
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

    std.log.info("Validation successful ({d} filter rules)", .{countFilterRules(&filters)});
}

fn countFilterRules(engine: *const reflect.FilterEngine) usize {
    var count: usize = 0;
    var node = engine.ctx.filter_list.head;
    while (node) |rule| {
        count += 1;
        node = rule.next;
    }
    return count;
}
