//! Build a FilterEngine from parsed CLI options (rsync options.c / exclude.c).

const std = @import("std");
const cli = @import("cli");
const rule = @import("rule.zig");
const context = @import("context.zig");
const mod = @import("mod.zig");

const FilterEngine = mod.FilterEngine;
const Options = context.Options;

fn envVar(name: [*:0]const u8) ?[]const u8 {
    const ptr = std.c.getenv(name) orelse return null;
    return std.mem.span(ptr);
}

pub fn optionsFromReflect(opts: *const cli.ReflectOptions, source_root: ?[]const u8) Options {
    const root = source_root orelse "";
    return .{
        .curr_dir = root,
        .module_dirlen = 0,
        .am_sender = opts.am_sender,
        .delete_excluded = opts.delete_excluded,
        .protocol_version = @intCast(@max(0, opts.protocol_version)),
        .home_dir = envVar("HOME"),
        .cvsignore_env = envVar("CVSIGNORE"),
    };
}

/// Load filter rules in argv order, matching rsync `parse_filter_str` / `parse_filter_file` calls.
pub fn fromReflectOptions(
    allocator: std.mem.Allocator,
    opts: *const cli.ReflectOptions,
    source_root: ?[]const u8,
) !FilterEngine {
    var engine = try FilterEngine.init(allocator, optionsFromReflect(opts, source_root));
    errdefer engine.deinit();

    const old_prefixes = rule.XFLG_OLD_PREFIXES;
    const fatal_old = rule.XFLG_FATAL_ERRORS | old_prefixes;

    if (opts.filter_commands.len != 0) {
        for (opts.filter_commands) |cmd| {
            switch (cmd.kind) {
                .filter => try engine.parseFilterStr(cmd.value, 0),
                .exclude => try engine.parseFilterStrFlags(cmd.value, 0, old_prefixes),
                .include => try engine.parseFilterStrFlags(cmd.value, rule.FILTRULE_INCLUDE, old_prefixes),
                .exclude_from => try engine.parseFilterFileFlags(cmd.value, 0, fatal_old),
                .include_from => try engine.parseFilterFileFlags(cmd.value, rule.FILTRULE_INCLUDE, fatal_old),
            }
        }
    } else {
        // Legacy fallback if filter_commands was not populated.
        for (opts.filters) |rulestr| try engine.parseFilterStr(rulestr, 0);
        for (opts.includes) |pat| try engine.parseFilterStrFlags(pat, rule.FILTRULE_INCLUDE, old_prefixes);
        for (opts.excludes) |pat| try engine.parseFilterStrFlags(pat, 0, old_prefixes);
        for (opts.include_from) |fname| try engine.parseFilterFileFlags(fname, rule.FILTRULE_INCLUDE, fatal_old);
        for (opts.exclude_from) |fname| try engine.parseFilterFileFlags(fname, 0, fatal_old);
    }

    // rsync recv_filter_list / send_filter_list append -C after user rules.
    if (opts.cvs_exclude) try engine.parseFilterStr("-C", 0);

    return engine;
}

test "fromReflectOptions preserves argv order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const result = cli.parse(a, &.{
        "--include=keep.o",
        "--exclude=*.o",
        "--filter=+ Makefile",
        "src/",
        "dest/",
    });
    const parsed = switch (result) {
        .ok => |p| p,
        .err => return error.TestUnexpectedResult,
    };

    var engine = try fromReflectOptions(std.testing.allocator, &parsed.options, parsed.sources[0]);
    defer engine.deinit();

    try std.testing.expectEqual(@as(usize, 3), parsed.options.filter_commands.len);
    try std.testing.expect(!engine.isExcluded("/path/keep.o", .file(), .all));
    try std.testing.expect(engine.isExcluded("/path/foo.o", .file(), .all));
    try std.testing.expect(!engine.isExcluded("/path/Makefile", .file(), .all));
}

test "fromReflectOptions -C adds cvs ignores" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const result = cli.parse(a, &.{ "-C", "src/", "dest/" });
    const parsed = switch (result) {
        .ok => |p| p,
        .err => return error.TestUnexpectedResult,
    };

    var engine = try fromReflectOptions(std.testing.allocator, &parsed.options, parsed.sources[0]);
    defer engine.deinit();

    try std.testing.expect(engine.isExcluded("/src/file.old", .file(), .all));
    try std.testing.expect(!engine.isExcluded("/src/file.txt", .file(), .all));
}
