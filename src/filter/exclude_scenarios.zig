//! Filter scenario tests mirroring rsync/testsuite/exclude.test (unit level).

const std = @import("std");
const mod = @import("mod.zig");
const rule = @import("rule.zig");

const FilterEngine = mod.FilterEngine;
const NameFlags = rule.NameFlags;

fn expectExcluded(engine: *FilterEngine, path: []const u8, nf: NameFlags) !void {
    try std.testing.expect(engine.isExcluded(path, nf, .all));
}

fn expectIncluded(engine: *FilterEngine, path: []const u8, nf: NameFlags) !void {
    try std.testing.expect(!engine.isExcluded(path, nf, .all));
}

fn loadRules(engine: *FilterEngine, rules: []const u8) !void {
    var it = std.mem.splitScalar(u8, rules, '\n');
    while (it.next()) |line| {
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
        if (trimmed.len == 0 or trimmed[0] == '#') continue;
        try engine.parseFilterStr(trimmed, 0);
    }
}

test "foo star slash directory exclude" {
    const a = std.testing.allocator;
    var engine = try FilterEngine.init(a, .{});
    defer engine.deinit();

    try engine.parseFilterStr("- foo/*/", 0);
    try expectExcluded(&engine, "/foo/down", NameFlags.dir());
    try expectExcluded(&engine, "/foo/sub", NameFlags.dir());
}

test "exclude.test exclude-from ruleset" {
    const a = std.testing.allocator;
    var engine = try FilterEngine.init(a, .{});
    defer engine.deinit();

    const rules =
        \\!
        \\+ **/bar
        \\- /bar
        \\+ foo**too
        \\+ foo/s?b/
        \\- foo/*/
        \\- new/keep/**
        \\- new/lose/***
        \\+ t[o]/
        \\- to
        \\+ file4
        \\- file[2-9]
        \\- /mid/for/foo/extra
    ;
    try loadRules(&engine, rules);

    // + **/bar then - /bar: nested bar paths stay included.
    try expectIncluded(&engine, "/foo/down/to/bar/baz", NameFlags.file());
    try expectIncluded(&engine, "/bar/down/to/foo/too", NameFlags.file());

    // foo**too matches path segment, not just basename.
    try expectIncluded(&engine, "/bar/down/to/foo/too", NameFlags.file());

    // foo/s?b/ includes foo/sub/ style dirs; foo/*/ excludes other direct foo child dirs.
    try expectIncluded(&engine, "/foo/sub/file", NameFlags.file());
    try expectExcluded(&engine, "/foo/down", NameFlags.dir());
    // Nested files under an excluded directory are pruned during traversal, not by check_filter.
    try expectIncluded(&engine, "/foo/down/to/you", NameFlags.file());

    // /** vs /*** on directories.
    try expectIncluded(&engine, "/new/keep", NameFlags.dir());
    try expectExcluded(&engine, "/new/keep/this", NameFlags.file());
    try expectExcluded(&engine, "/new/lose", NameFlags.dir());
    try expectExcluded(&engine, "/new/lose/this", NameFlags.file());

    // competing + t[o]/ vs - to (first matching rule wins; - to excludes basename to)
    try expectExcluded(&engine, "/bar/down/to/foo/to", NameFlags.file());

    // file4 included, file2-9 excluded (basename rules).
    try expectIncluded(&engine, "/anywhere/file4", NameFlags.file());
    try expectExcluded(&engine, "/anywhere/file2", NameFlags.file());
    try expectExcluded(&engine, "/anywhere/file9", NameFlags.file());

    // absolute path exclude
    try expectExcluded(&engine, "/mid/for/foo/extra", NameFlags.file());
    try expectIncluded(&engine, "/mid/for/foo/keep", NameFlags.file());
}

test "exclude --exclude and --include old-prefix form" {
    const a = std.testing.allocator;
    var engine = try FilterEngine.init(a, .{});
    defer engine.deinit();

    try engine.parseFilterStr("- *.o", 0);
    try engine.parseFilterStr("+ Makefile", rule.FILTRULE_INCLUDE);
    try expectExcluded(&engine, "/src/foo.o", NameFlags.file());
    try expectIncluded(&engine, "/src/Makefile", NameFlags.file());
}

test "directory-only trailing slash" {
    const a = std.testing.allocator;
    var engine = try FilterEngine.init(a, .{});
    defer engine.deinit();

    try engine.parseFilterStr("- build/", 0);
    try expectExcluded(&engine, "/build", NameFlags.dir());
    try expectIncluded(&engine, "/build/output.o", NameFlags.file());
}

test "negated rule" {
    const a = std.testing.allocator;
    var engine = try FilterEngine.init(a, .{});
    defer engine.deinit();

    try engine.parseFilterStr("-! *.txt", 0);
    try expectIncluded(&engine, "/notes.txt", NameFlags.file());
    try expectExcluded(&engine, "/notes.log", NameFlags.file());
}

test "word-split merge rules" {
    const a = std.testing.allocator;
    var engine = try FilterEngine.init(a, .{});
    defer engine.deinit();

    const template = engine.ctx.filter_list.ruleTemplate(rule.FILTRULE_WORD_SPLIT);
    try engine.ctx.parseFilterStr(&engine.ctx.filter_list, "- *.bak", &template, 0);
    try engine.ctx.parseFilterStr(&engine.ctx.filter_list, "+ keep.me", &template, 0);

    try expectExcluded(&engine, "/foo/file.bak", NameFlags.file());
    try expectIncluded(&engine, "/foo/keep.me", NameFlags.file());
}

test "dir-merge with anchored per-dir rules" {
    const a = std.testing.allocator;
    var engine = try FilterEngine.init(a, .{});
    defer engine.deinit();

    try engine.parseFilterStr("dir-merge .filt", 0);
    try engine.setFilterDir("foo/");
    const head = engine.ctx.filter_list.head orelse return error.TestUnexpectedResult;
    const lp = head.data.mergelist;
    const tmpl = lp.ruleTemplate(head.rflags);
    try engine.ctx.parseFilterStr(lp, "- /file1", &tmpl, rule.XFLG_ANCHORED2ABS);

    try engine.changeLocalFilterDir("foo/", 0);
    try engine.ctx.parseFilterStr(lp, "+ *.junk", &tmpl, rule.XFLG_ANCHORED2ABS);
    try engine.ctx.parseFilterStr(lp, "- *.bak", &tmpl, rule.XFLG_ANCHORED2ABS);

    try expectExcluded(&engine, "/foo/file1", NameFlags.file());
    try expectIncluded(&engine, "/foo/file.junk", NameFlags.file());
    try expectExcluded(&engine, "/foo/file.bak", NameFlags.file());
    try expectIncluded(&engine, "/bar/file1", NameFlags.file());
}

test "first matching rule wins order" {
    const a = std.testing.allocator;
    var engine = try FilterEngine.init(a, .{});
    defer engine.deinit();

    try engine.parseFilterStr("+ important.txt", rule.FILTRULE_INCLUDE);
    try engine.parseFilterStr("- *", 0);
    try expectIncluded(&engine, "/important.txt", NameFlags.file());
    try expectExcluded(&engine, "/other.txt", NameFlags.file());
}

test "sender-side hide rule stored" {
    const a = std.testing.allocator;
    var engine = try FilterEngine.init(a, .{ .am_sender = false });
    defer engine.deinit();

    try engine.parseFilterStr("H secret", 0);
    const head = engine.ctx.filter_list.head orelse return error.TestUnexpectedResult;
    try std.testing.expect(head.rflags & rule.FILTRULE_SENDER_SIDE != 0);
}

test "CVS ignore with env override" {
    const a = std.testing.allocator;
    var engine = try FilterEngine.init(a, .{
        .cvsignore_env = "home-cvs-exclude",
    });
    defer engine.deinit();

    try engine.parseFilterStr("-C", 0);
    try expectExcluded(&engine, "/mid/home-cvs-exclude", NameFlags.file());
    try expectExcluded(&engine, "/foo/file.old", NameFlags.file());
    try expectIncluded(&engine, "/foo/file.txt", NameFlags.file());
}
