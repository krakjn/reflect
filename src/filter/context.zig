//! Filter context replacing exclude.c globals (dirbuf, mergelist, push/pop).

const std = @import("std");
const rule = @import("rule.zig");
const path = @import("path.zig");
const parse = @import("parse.zig");
const cvs = @import("cvs.zig");

const Allocator = std.mem.Allocator;
const FilterRule = rule.FilterRule;
const FilterList = rule.FilterList;
const NameFlags = rule.NameFlags;

pub const FilterError = error{
    OutOfMemory,
    Overflow,
    Refused,
    FileNotFound,
    UnknownFilterRule,
    InvalidModifier,
    ClearRuleTrailingChars,
    UnexpectedEndOfRule,
    SideConflict,
} || parse.ParseError;

pub const Options = struct {
    curr_dir: []const u8 = "",
    module_dirlen: usize = 0,
    am_sender: bool = true,
    ignore_perishable: bool = false,
    delete_excluded: bool = false,
    sanitize_paths: bool = false,
    protocol_version: u32 = 32,
    home_dir: ?[]const u8 = null,
    cvsignore_env: ?[]const u8 = null,
    eol_nulls: bool = false,
};

const Io = std.Io;

pub const LocalFilterState = struct {
    mergelist_cnt: usize,
    mergelists: []FilterList,
};

pub const FilterContext = struct {
    allocator: Allocator,
    options: Options,

    filter_list: FilterList,
    cvs_filter_list: FilterList,
    daemon_filter_list: FilterList,

    dirbuf: []u8,
    dirbuf_len: usize,
    dirbuf_depth: i32,
    parent_dirscan: bool,
    mergelist_parents: std.ArrayList(*FilterRule),
    mergelist_cnt: usize = 0,
    add_rule_env: parse.AddRuleEnv = undefined,
    cur_elide_value: u8 = rule.REMOTE_RULE,
    cvs_initialized: bool = false,

    change_depth: i32 = -1,
    filt_stack: [path.max_path_len / 2 + 1]?*LocalFilterState = .{null} ** (path.max_path_len / 2 + 1),
    threaded: Io.Threaded,

    pub fn ioInterface(self: *FilterContext) Io {
        return self.threaded.io();
    }

    pub fn init(allocator: Allocator, options: Options) !FilterContext {
        const dirbuf = try allocator.alloc(u8, path.max_path_len + 1);
        @memset(dirbuf, 0);

        var ctx: FilterContext = .{
            .allocator = allocator,
            .options = options,
            .filter_list = FilterList.init(allocator, ""),
            .cvs_filter_list = FilterList.init(allocator, " [global CVS]"),
            .daemon_filter_list = FilterList.init(allocator, " [daemon]"),
            .dirbuf = dirbuf,
            .dirbuf_len = 0,
            .dirbuf_depth = 0,
            .parent_dirscan = false,
            .mergelist_parents = std.ArrayList(*FilterRule).empty,
            .mergelist_cnt = 0,
            .add_rule_env = undefined,
            .threaded = Io.Threaded.init(allocator, .{}),
        };
        ctx.add_rule_env = .{
            .allocator = allocator,
            .dirbuf = ctx.dirbuf,
            .dirbuf_len = 0,
            .module_dirlen = options.module_dirlen,
            .am_sender = options.am_sender,
            .mergelist_parents = undefined,
            .mergelist_cnt = undefined,
        };
        ctx.add_rule_env.mergelist_parents = &ctx.mergelist_parents;
        ctx.add_rule_env.mergelist_cnt = &ctx.mergelist_cnt;
        return ctx;
    }

    pub fn deinit(self: *FilterContext) void {
        self.changeLocalFilterDir(null, 0) catch {};
        self.mergelist_cnt = 0;
        self.filter_list.deinit();
        self.cvs_filter_list.deinit();
        self.daemon_filter_list.deinit();
        self.mergelist_parents.deinit(self.allocator);
        self.threaded.deinit();
        self.allocator.free(self.dirbuf);
    }

    pub fn addRuleEnv(self: *FilterContext) *parse.AddRuleEnv {
        self.add_rule_env.dirbuf = self.dirbuf;
        self.add_rule_env.dirbuf_len = self.dirbuf_len;
        self.add_rule_env.mergelist_parents = &self.mergelist_parents;
        self.add_rule_env.mergelist_cnt = &self.mergelist_cnt;
        return &self.add_rule_env;
    }

    pub fn setFilterDir(self: *FilterContext, dir: []const u8) !void {
        var len: usize = 0;
        if (dir.len == 0 or dir[0] != '/') {
            const curr = self.options.curr_dir;
            if (curr.len + 1 > self.dirbuf.len) return error.Overflow;
            @memcpy(self.dirbuf[0..curr.len], curr);
            self.dirbuf[curr.len] = '/';
            len = curr.len + 1;
            const copy_len = @min(dir.len, self.dirbuf.len - len);
            @memcpy(self.dirbuf[len .. len + copy_len], dir[0..copy_len]);
            len += copy_len;
        } else {
            const copy_len = @min(dir.len, self.dirbuf.len);
            @memcpy(self.dirbuf[0..copy_len], dir[0..copy_len]);
            len = copy_len;
        }
        self.dirbuf[len] = 0;
        const cleaned = try path.cleanFname(self.dirbuf[0..len], path.CFN_COLLAPSE_DOT_DOT_DIRS);
        self.dirbuf_len = cleaned;
        if (self.dirbuf_len > 1 and self.dirbuf[self.dirbuf_len - 1] == '.' and
            self.dirbuf[self.dirbuf_len - 2] == '/')
        {
            self.dirbuf_len -= 2;
        }
        if (self.dirbuf_len != 1) {
            self.dirbuf[self.dirbuf_len] = '/';
            self.dirbuf_len += 1;
        }
        self.dirbuf[self.dirbuf_len] = 0;
        if (self.options.sanitize_paths)
            self.dirbuf_depth = @intCast(path.countDirElements(self.dirbuf[self.options.module_dirlen..]));
    }

    fn parseMergeName(self: *FilterContext, merge_file: []const u8, prefix_skip: usize) !?[]const u8 {
        if (!self.parent_dirscan and merge_file.len != 0 and merge_file[0] != '/') {
            if (std.mem.indexOfScalar(u8, merge_file, '/') == null)
                return merge_file;
        }

        var tmp: [path.max_path_len]u8 = undefined;
        const fn_buf = if (merge_file.len != 0 and merge_file[0] == '/') self.dirbuf else &tmp;
        @memcpy(fn_buf[0..merge_file.len], merge_file);
        fn_buf[merge_file.len] = 0;
        var fn_len = try path.cleanFname(fn_buf[0..merge_file.len], path.CFN_COLLAPSE_DOT_DOT_DIRS);

        if (fn_buf.ptr != self.dirbuf.ptr) {
            const d_len = self.dirbuf_len - prefix_skip;
            if (d_len + fn_len >= path.max_path_len) return error.Overflow;
            @memcpy(self.dirbuf[prefix_skip .. prefix_skip + fn_len], fn_buf[0..fn_len]);
            fn_len = try path.cleanFname(self.dirbuf[prefix_skip .. prefix_skip + fn_len], path.CFN_COLLAPSE_DOT_DOT_DIRS);
            self.dirbuf_len = prefix_skip + fn_len;
        } else {
            self.dirbuf_len = fn_len;
        }
        self.dirbuf[self.dirbuf_len] = 0;
        return self.dirbuf[0..self.dirbuf_len];
    }

    fn setupMergeFile(self: *FilterContext, mergelist_num: usize, ex: *FilterRule, lp: *FilterList) !bool {
        const x = try self.parseMergeName(ex.pattern, 0) orelse return false;
        if (x.len == 0 or x[0] != '/') return false;

        const slash = std.mem.lastIndexOfScalar(u8, x, '/') orelse return false;
        const basename = x[slash + 1 ..];
        const old_pat = ex.pattern;
        ex.pattern = try self.allocator.dupe(u8, basename);

        var buf: [path.max_path_len]u8 = undefined;
        const path_part = x[0..slash];
        if (path_part.len == 0) {
            buf[0] = '/';
            buf[1] = 0;
        } else if (path_part[0] == '/') {
            @memcpy(buf[0..path_part.len], path_part);
            buf[path_part.len] = 0;
        } else {
            _ = try path.pathJoin(&buf, self.dirbuf[0..self.dirbuf_len], path_part);
        }
        var len = try path.cleanFname(buf[0..], path.CFN_COLLAPSE_DOT_DOT_DIRS);
        if (len != 1 and len < path.max_path_len - 1) {
            buf[len] = '/';
            len += 1;
            buf[len] = 0;
        }

        var y_offset: usize = 0;
        var x_i: usize = 0;
        while (x_i < len and y_offset < self.dirbuf_len and buf[x_i] == self.dirbuf[y_offset]) : ({
            x_i += 1;
            y_offset += 1;
        }) {}
        if (x_i < len) y_offset = self.dirbuf_len;

        self.parent_dirscan = true;
        while (y_offset < self.dirbuf_len) {
            var save_len: usize = 0;
            while (y_offset + save_len < self.dirbuf_len and self.dirbuf[y_offset + save_len] != '/') : (save_len += 1) {}
            const save = self.dirbuf[y_offset .. y_offset + save_len + 1];
            self.dirbuf[y_offset] = 0;
            self.dirbuf_len = y_offset;

            @memcpy(buf[len - ex.pattern.len .. len], ex.pattern);
            try self.parseFilterFile(lp, buf[0..len], ex, rule.XFLG_ANCHORED2ABS);
            if (ex.rflags & rule.FILTRULE_NO_INHERIT != 0) {
                lp.clear();
            }
            lp.tail = null;

            @memcpy(self.dirbuf[y_offset .. y_offset + save.len], save);
            self.dirbuf_len = y_offset + save.len;
            y_offset += save_len;
            while (y_offset < self.dirbuf_len and self.dirbuf[y_offset] != '/') y_offset += 1;
            if (y_offset < self.dirbuf_len) y_offset += 1;
        }
        self.parent_dirscan = false;
        self.allocator.free(old_pat);
        _ = mergelist_num;
        return true;
    }

    pub fn parseFilterStr(
        self: *FilterContext,
        list: *FilterList,
        rulestr_in: []const u8,
        template: *const FilterRule,
        xflags: u32,
    ) FilterError!void {
        var rulestr = rulestr_in;
        while (rulestr.len != 0) {
            var pat: []const u8 = undefined;
            var pat_len: usize = undefined;
            const r_opt = parse.parseRuleTok(
                self.allocator,
                &rulestr,
                template,
                xflags,
                self.options.delete_excluded,
                &pat,
                &pat_len,
            ) catch |err| return err;
            const r = r_opt orelse break;
            errdefer parse.teardownMergelist(self.allocator, &self.mergelist_parents, &self.mergelist_cnt, r);

            if (pat_len >= path.max_path_len) {
                parse.teardownMergelist(self.allocator, &self.mergelist_parents, &self.mergelist_cnt, r);
                self.allocator.destroy(r);
                continue;
            }

            const new_rflags = r.rflags;
            if (new_rflags & rule.FILTRULE_CLEAR_LIST != 0) {
                list.clear();
                parse.teardownMergelist(self.allocator, &self.mergelist_parents, &self.mergelist_cnt, r);
                self.allocator.destroy(r);
                continue;
            }

            if (new_rflags & rule.FILTRULE_MERGE_FILE != 0) {
                var effective_pat = pat;
                var effective_len = pat_len;
                if (effective_len == 0) {
                    effective_pat = ".cvsignore";
                    effective_len = 10;
                }
                if (new_rflags & rule.FILTRULE_EXCLUDE_SELF != 0) {
                    var name = effective_pat;
                    var i = effective_len;
                    while (i > 0) : (i -= 1) {
                        if (effective_pat[i - 1] == '/') {
                            name = effective_pat[i .. effective_len];
                            break;
                        }
                    }
                    const excl = try self.allocator.create(FilterRule);
                    excl.* = .{ .pattern = &.{}, .rflags = 0, .data = .{ .slash_cnt = 0 } };
                    try parse.addRule(list, self.addRuleEnv(), name, excl, 0);
                    r.rflags &= ~rule.FILTRULE_EXCLUDE_SELF;
                }
                if (new_rflags & rule.FILTRULE_PERDIR_MERGE != 0) {
                    if (self.parent_dirscan) {
                        if (try self.parseMergeName(effective_pat[0..effective_len], self.options.module_dirlen)) |p| {
                            try parse.addRule(list, self.addRuleEnv(), p, r, 0);
                        } else {
                            parse.teardownMergelist(self.allocator, &self.mergelist_parents, &self.mergelist_cnt, r);
                            self.allocator.destroy(r);
                        }
                        continue;
                    }
                } else {
                    if (try self.parseMergeName(effective_pat[0..effective_len], 0)) |p| {
                        try self.parseFilterFile(list, p, r, rule.XFLG_FATAL_ERRORS);
                    }
                    parse.teardownMergelist(self.allocator, &self.mergelist_parents, &self.mergelist_cnt, r);
                    self.allocator.destroy(r);
                    continue;
                }
            }

            try parse.addRule(list, self.addRuleEnv(), pat[0..pat_len], r, xflags);

            if (new_rflags & rule.FILTRULE_CVS_IGNORE != 0 and new_rflags & rule.FILTRULE_MERGE_FILE == 0) {
                try self.getCvsExcludes(new_rflags);
            }
        }
    }

    pub fn getCvsExcludes(self: *FilterContext, rflags: u32) !void {
        if (self.cvs_initialized) return;
        self.cvs_initialized = true;

        var template_flags = rflags;
        if (self.options.protocol_version >= 30) template_flags |= rule.FILTRULE_PERISHABLE;
        const template = self.cvs_filter_list.ruleTemplate(template_flags);

        try self.parseFilterStr(&self.cvs_filter_list, cvs.default_cvsignore, &template, 0);

        if (self.options.home_dir) |home| {
            var fname: [path.max_path_len]u8 = undefined;
            const joined = try path.pathJoin(&fname, home, ".cvsignore");
            try self.parseFilterFile(&self.cvs_filter_list, joined, &template, 0);
        }

        if (self.options.cvsignore_env) |env| {
            try self.parseFilterStr(&self.cvs_filter_list, env, &template, 0);
        }
    }

    pub fn parseFilterFile(
        self: *FilterContext,
        list: *FilterList,
        fname: []const u8,
        template: *const FilterRule,
        xflags: u32,
    ) FilterError!void {
        if (fname.len == 0) return;

        const io = self.ioInterface();
        const data = readFileContents(self.allocator, io, fname) catch |err| switch (err) {
            error.FileNotFound => {
                if (xflags & rule.XFLG_FATAL_ERRORS != 0) return error.FileNotFound;
                return;
            },
            else => return err,
        };
        defer self.allocator.free(data);

        self.dirbuf[self.dirbuf_len] = 0;

        const word_split = template.rflags & rule.FILTRULE_WORD_SPLIT != 0;
        var line_start: usize = 0;
        var i: usize = 0;
        while (i <= data.len) : (i += 1) {
            const at_eol = i == data.len or data[i] == '\n' or data[i] == '\r';
            if (!at_eol) continue;
            const line = data[line_start..i];
            line_start = i + 1;
            if (i < data.len and data[i] == '\r' and i + 1 < data.len and data[i + 1] == '\n')
                line_start += 1;

            var end = line.len;
            while (end > 0 and (line[end - 1] == '\r' or line[end - 1] == '\n')) end -= 1;
            const trimmed = std.mem.trim(u8, line[0..end], &std.ascii.whitespace);
            if (trimmed.len == 0) continue;
            if (!word_split and (trimmed[0] == ';' or trimmed[0] == '#')) continue;
            try self.parseFilterStr(list, trimmed, template, xflags);
        }
    }

    pub fn pushLocalFilters(self: *FilterContext, dir: []const u8) !?*LocalFilterState {
        try self.setFilterDir(dir);
        if (self.mergelist_cnt == 0) return null;

        const state = try self.allocator.create(LocalFilterState);
        errdefer self.allocator.destroy(state);
        const lists = try self.allocator.alloc(FilterList, self.mergelist_parents.items.len);
        errdefer self.allocator.free(lists);

        state.mergelist_cnt = self.mergelist_parents.items.len;
        for (self.mergelist_parents.items, lists) |ex, *saved| {
            saved.* = ex.data.mergelist.*;
        }
        state.mergelists = lists;

        for (self.mergelist_parents.items, 0..) |ex, i| {
            const lp = ex.data.mergelist;
            lp.tail = null;
            if (ex.rflags & rule.FILTRULE_NO_INHERIT != 0) lp.head = null;
            if (ex.rflags & rule.FILTRULE_FINISH_SETUP != 0) {
                ex.rflags &= ~rule.FILTRULE_FINISH_SETUP;
                if (try self.setupMergeFile(i, ex, lp)) {
                    try self.setFilterDir(dir);
                }
            }
            const merge_path_len = ex.pattern.len;
            if (self.dirbuf_len + merge_path_len < path.max_path_len) {
                @memcpy(self.dirbuf[self.dirbuf_len .. self.dirbuf_len + merge_path_len], ex.pattern);
                self.dirbuf[self.dirbuf_len + merge_path_len] = 0;
                try self.parseFilterFile(lp, self.dirbuf[0 .. self.dirbuf_len + merge_path_len], ex, rule.XFLG_ANCHORED2ABS);
            }
            self.dirbuf[self.dirbuf_len] = 0;
        }

        return state;
    }

    pub fn popLocalFilters(self: *FilterContext, mem: ?*LocalFilterState) void {
        var i = self.mergelist_parents.items.len;
        while (i > 0) {
            i -= 1;
            const ex = self.mergelist_parents.items[i];
            const lp = ex.data.mergelist;
            lp.popLocal();
            if (mem == null or i >= mem.?.mergelist_cnt) {
                if (lp.head != null) lp.popLocal();
            }
        }

        const pop = mem orelse return;
        for (self.mergelist_parents.items[0..pop.mergelist_cnt], pop.mergelists) |ex, saved| {
            ex.data.mergelist.* = saved;
        }
        self.allocator.free(pop.mergelists);
        self.allocator.destroy(pop);
    }

    pub fn changeLocalFilterDir(self: *FilterContext, dname: ?[]const u8, dir_depth: i32) !void {
        if (dname == null) {
            while (self.change_depth >= 0) : (self.change_depth -= 1) {
                if (self.filt_stack[@intCast(self.change_depth)]) |state| {
                    self.popLocalFilters(state);
                    self.filt_stack[@intCast(self.change_depth)] = null;
                }
            }
            return;
        }

        std.debug.assert(dir_depth < path.max_path_len / 2 + 1);

        while (self.change_depth >= dir_depth) : (self.change_depth -= 1) {
            if (self.filt_stack[@intCast(self.change_depth)]) |state| {
                self.popLocalFilters(state);
                self.filt_stack[@intCast(self.change_depth)] = null;
            }
        }

        self.change_depth = dir_depth;
        self.filt_stack[@intCast(dir_depth)] = try self.pushLocalFilters(dname.?);
    }
};

fn readFileContents(allocator: Allocator, io: Io, fname: []const u8) ![]u8 {
    const file = if (fname.len != 0 and fname[0] == '/')
        Io.Dir.openFileAbsolute(io, fname, .{}) catch return error.FileNotFound
    else
        Io.Dir.cwd().openFile(io, fname, .{}) catch return error.FileNotFound;
    defer file.close(io);

    var read_buf: [8192]u8 = undefined;
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    var reader = file.reader(io, &read_buf);
    while (true) {
        const n = reader.interface.readSliceShort(&read_buf) catch break;
        if (n == 0) break;
        try out.appendSlice(allocator, read_buf[0..n]);
    }
    return try out.toOwnedSlice(allocator);
}
