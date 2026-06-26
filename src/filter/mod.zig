//! Public filter engine API.

const std = @import("std");
const rule = @import("rule.zig");
const context = @import("context.zig");
const match = @import("match.zig");
const cvs = @import("cvs.zig");

pub const rule_mod = rule;
pub const wildmatch = @import("wildmatch.zig");
pub const path = @import("path.zig");

pub const NameFlags = rule.NameFlags;
pub const FilterRule = rule.FilterRule;
pub const FilterList = rule.FilterList;
pub const FilterResult = rule.FilterResult;
pub const FilterContext = context.FilterContext;
pub const Options = context.Options;
pub const ParseError = @import("parse.zig").ParseError;
pub const default_cvsignore = cvs.default_cvsignore;

pub const FilterLevel = enum(u32) {
    none = rule.NO_FILTERS,
    server = rule.SERVER_FILTERS,
    all = rule.ALL_FILTERS,
};

pub const FilterEngine = struct {
    ctx: FilterContext,

    pub fn init(allocator: std.mem.Allocator, options: Options) !FilterEngine {
        return .{ .ctx = try FilterContext.init(allocator, options) };
    }

    pub fn deinit(self: *FilterEngine) void {
        self.ctx.deinit();
    }

    pub fn parseFilterStr(self: *FilterEngine, rulestr: []const u8, template_rflags: u32) !void {
        try self.parseFilterStrFlags(rulestr, template_rflags, 0);
    }

    pub fn parseFilterStrFlags(self: *FilterEngine, rulestr: []const u8, template_rflags: u32, xflags: u32) !void {
        const template = self.ctx.filter_list.ruleTemplate(template_rflags);
        try self.ctx.parseFilterStr(&self.ctx.filter_list, rulestr, &template, xflags);
    }

    pub fn parseFilterFile(self: *FilterEngine, fname: []const u8, template_rflags: u32, xflags: u32) !void {
        try self.parseFilterFileFlags(fname, template_rflags, xflags);
    }

    pub fn parseFilterFileFlags(self: *FilterEngine, fname: []const u8, template_rflags: u32, xflags: u32) !void {
        const template = self.ctx.filter_list.ruleTemplate(template_rflags);
        try self.ctx.parseFilterFile(&self.ctx.filter_list, fname, &template, xflags);
    }

    pub fn parseFilterStrToList(self: *FilterEngine, list: *FilterList, rulestr: []const u8, template: *const FilterRule, xflags: u32) !void {
        try self.ctx.parseFilterStr(list, rulestr, template, xflags);
    }

    pub fn checkFilter(self: *FilterEngine, name: []const u8, name_flags: NameFlags) FilterResult {
        return match.checkFilterWithCvs(
            &self.ctx.filter_list,
            &self.ctx.cvs_filter_list,
            name,
            name_flags,
            self.ctx.cur_elide_value,
            self.ctx.options.ignore_perishable,
            self.ctx.options.curr_dir,
            self.ctx.options.module_dirlen,
        );
    }

    pub fn isExcluded(self: *FilterEngine, name: []const u8, name_flags: NameFlags, level: FilterLevel) bool {
        return match.nameIsExcluded(
            &self.ctx.filter_list,
            &self.ctx.cvs_filter_list,
            &self.ctx.daemon_filter_list,
            name,
            name_flags,
            @intFromEnum(level),
            self.ctx.cur_elide_value,
            self.ctx.options.ignore_perishable,
            self.ctx.options.curr_dir,
            self.ctx.options.module_dirlen,
        );
    }

    pub fn setFilterDir(self: *FilterEngine, dir: []const u8) !void {
        try self.ctx.setFilterDir(dir);
    }

    pub fn changeLocalFilterDir(self: *FilterEngine, dname: ?[]const u8, dir_depth: i32) !void {
        try self.ctx.changeLocalFilterDir(dname, dir_depth);
    }

    pub fn pushLocalFilters(self: *FilterEngine, dir: []const u8) !?*context.LocalFilterState {
        return try self.ctx.pushLocalFilters(dir);
    }

    pub fn popLocalFilters(self: *FilterEngine, state: ?*context.LocalFilterState) void {
        self.ctx.popLocalFilters(state);
    }

    pub fn getCvsExcludes(self: *FilterEngine, rflags: u32) !void {
        try self.ctx.getCvsExcludes(rflags);
    }

    pub fn fromReflectOptions(
        allocator: std.mem.Allocator,
        opts: *const @import("cli").ReflectOptions,
        source_root: ?[]const u8,
    ) !FilterEngine {
        return @import("from_options.zig").fromReflectOptions(allocator, opts, source_root);
    }
};

// --- unit tests mirroring rsync/testsuite/exclude.test scenarios ---

test {
    _ = @import("wildtest.zig");
    _ = @import("exclude_scenarios.zig");
    _ = @import("from_options.zig");
}

test "clear rule resets list" {
    const a = std.testing.allocator;
    var engine = try FilterEngine.init(a, .{});
    defer engine.deinit();

    try engine.parseFilterStr("- *.bak", 0);
    try engine.parseFilterStr("- *.old", 0);
    try std.testing.expect(engine.isExcluded("/foo/file.bak", .file(), .all));
    try engine.parseFilterStr("!", 0);
    try std.testing.expect(!engine.isExcluded("/foo/file.bak", .file(), .all));
}

test "include/exclude + and - rules" {
    const a = std.testing.allocator;
    var engine = try FilterEngine.init(a, .{});
    defer engine.deinit();

    try engine.parseFilterStr("+ file4", 0);
    try engine.parseFilterStr("- file[2-9]", 0);
    try std.testing.expect(engine.isExcluded("/path/file2", .file(), .all));
    try std.testing.expect(!engine.isExcluded("/path/file4", .file(), .all));
}

test "absolute +/ - rules" {
    const a = std.testing.allocator;
    var engine = try FilterEngine.init(a, .{ .curr_dir = "/transfer", .module_dirlen = 0 });
    defer engine.deinit();

    try engine.parseFilterStr("+ **/bar", 0);
    try engine.parseFilterStr("- /bar", 0);
    try std.testing.expect(!engine.isExcluded("/foo/down/to/bar/baz", .file(), .all));
    try engine.parseFilterStr("!", 0);
    try engine.parseFilterStr("- /bar", 0);
    try std.testing.expect(engine.isExcluded("/bar", .file(), .all));
}

test "** vs *** suffix" {
    const a = std.testing.allocator;
    var engine = try FilterEngine.init(a, .{});
    defer engine.deinit();

    try engine.parseFilterStr("- new/keep/**", 0);
    try engine.parseFilterStr("- new/lose/***", 0);
    try std.testing.expect(!engine.isExcluded("/new/keep", .dir(), .all));
    try std.testing.expect(engine.isExcluded("/new/keep/this", .file(), .all));
    try std.testing.expect(engine.isExcluded("/new/lose", .dir(), .all));
    try std.testing.expect(engine.isExcluded("/new/lose/this", .file(), .all));
}

test "CVS -C default excludes" {
    const a = std.testing.allocator;
    var engine = try FilterEngine.init(a, .{
        .cvsignore_env = "*.junk",
    });
    defer engine.deinit();

    try engine.parseFilterStr("-C", 0);
    try std.testing.expect(engine.isExcluded("/foo/file.old", .file(), .all));
    try std.testing.expect(engine.isExcluded("/foo/file.junk", .file(), .all));
    try std.testing.expect(!engine.isExcluded("/foo/file.txt", .file(), .all));
}

test "dir-merge per-directory filters" {
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

    try std.testing.expect(engine.isExcluded("/foo/file1", .file(), .all));
    try std.testing.expect(!engine.isExcluded("/foo/file.junk", .file(), .all));
    try std.testing.expect(engine.isExcluded("/foo/file.bak", .file(), .all));
    try std.testing.expect(!engine.isExcluded("/bar/file1", .file(), .all));
}

test "double-star path match" {
    const a = std.testing.allocator;
    var engine = try FilterEngine.init(a, .{});
    defer engine.deinit();

    try engine.parseFilterStr("+ **/bar", 0);
    try engine.parseFilterStr("- /bar", rule.FILTRULE_ABS_PATH);
    try std.testing.expect(!engine.isExcluded("/foo/down/to/bar/baz", .file(), .all));
}
