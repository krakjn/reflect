//! Filter rule parsing (parse_rule_tok, add_rule from exclude.c).

const std = @import("std");
const rule = @import("rule.zig");
const path = @import("path.zig");

const Allocator = std.mem.Allocator;
const FilterRule = rule.FilterRule;
const FilterList = rule.FilterList;

pub const ParseError = error{
    UnknownFilterRule,
    InvalidModifier,
    ClearRuleTrailingChars,
    UnexpectedEndOfRule,
    SideConflict,
    Overflow,
    OutOfMemory,
};

pub const AddRuleEnv = struct {
    allocator: Allocator,
    dirbuf: []const u8,
    dirbuf_len: usize,
    module_dirlen: usize,
    am_sender: bool,
    mergelist_parents: *std.ArrayList(*FilterRule),
    mergelist_cnt: *usize,
};

const slash_wild3_suffix = "/***";

pub fn addRule(
    list: *FilterList,
    env: *AddRuleEnv,
    pat: []const u8,
    rule_in: *FilterRule,
    xflags: u32,
) ParseError!void {
    var pat_len = pat.len;
    var slash_cnt: u32 = 0;
    var pre_len: usize = 0;
    var suf_len: usize = 0;

    if (xflags & (rule.XFLG_ANCHORED2ABS | rule.XFLG_ABS_IF_SLASH) != 0 and
        (rule_in.rflags & rule.FILTRULES_SIDES) ==
            if (env.am_sender) rule.FILTRULE_RECEIVER_SIDE else rule.FILTRULE_SENDER_SIDE)
    {
        freeRule(list, rule_in);
        return;
    }

    if (pat_len > 1 and pat[pat_len - 1] == '/') {
        pat_len -= 1;
        rule_in.rflags |= rule.FILTRULE_DIRECTORY;
    }

    for (pat[0..pat_len]) |c| {
        if (c == '/') slash_cnt += 1;
    }

    if (rule_in.rflags & (rule.FILTRULE_ABS_PATH | rule.FILTRULE_MERGE_FILE) == 0 and
        ((xflags & (rule.XFLG_ANCHORED2ABS | rule.XFLG_ABS_IF_SLASH) != 0 and pat.len != 0 and pat[0] == '/') or
            (xflags & rule.XFLG_ABS_IF_SLASH != 0 and slash_cnt != 0)))
    {
        rule_in.rflags |= rule.FILTRULE_ABS_PATH;
        pre_len = if (pat.len != 0 and pat[0] == '/')
            env.dirbuf_len - env.module_dirlen - 1
        else
            0;
    }

    if (xflags & rule.XFLG_DIR2WILD3 != 0 and
        rule.bitsSetAndUnset(rule_in.rflags, rule.FILTRULE_DIRECTORY, rule.FILTRULE_INCLUDE))
    {
        rule_in.rflags &= ~rule.FILTRULE_DIRECTORY;
        suf_len = slash_wild3_suffix.len;
    }

    const total_len = pre_len + pat_len + suf_len;
    var pattern_buf = env.allocator.alloc(u8, total_len + 1) catch return error.OutOfMemory;
    errdefer env.allocator.free(pattern_buf);

    if (pre_len != 0) {
        @memcpy(pattern_buf[0..pre_len], env.dirbuf[env.module_dirlen .. env.module_dirlen + pre_len]);
        for (pattern_buf[0..pre_len]) |c| {
            if (c == '/') slash_cnt += 1;
        }
    }
    rule_in.elide = 0;
    @memcpy(pattern_buf[pre_len .. pre_len + pat_len], pat[0..pat_len]);
    var final_len = pre_len + pat_len;
    if (suf_len != 0) {
        @memcpy(pattern_buf[final_len .. final_len + suf_len], slash_wild3_suffix);
        final_len += suf_len;
        slash_cnt += 1;
    }
    pattern_buf[final_len] = 0;
    rule_in.pattern = try env.allocator.dupe(u8, pattern_buf[0..final_len]);
    env.allocator.free(pattern_buf);
    pat_len = final_len;

    if (std.mem.indexOfAny(u8, rule_in.pattern, "*[?")) |_| {
        rule_in.rflags |= rule.FILTRULE_WILD;
        if (std.mem.indexOf(u8, rule_in.pattern, "**")) |cp| {
            rule_in.rflags |= rule.FILTRULE_WILD2;
            if (cp == 0) rule_in.rflags |= rule.FILTRULE_WILD2_PREFIX;
            if (pat_len >= 3 and
                rule_in.pattern[pat_len - 3] == '*' and
                rule_in.pattern[pat_len - 2] == '*' and
                rule_in.pattern[pat_len - 1] == '*')
            {
                rule_in.rflags |= rule.FILTRULE_WILD3_SUFFIX;
            }
        }
    }

    if (rule_in.rflags & rule.FILTRULE_PERDIR_MERGE != 0) {
        const basename = blk: {
            if (std.mem.lastIndexOfScalar(u8, rule_in.pattern, '/')) |idx|
                break :blk rule_in.pattern[idx + 1 ..]
            else
                break :blk rule_in.pattern;
        };

        for (env.mergelist_parents.items[0..env.mergelist_cnt.*]) |ex| {
            const s = blk: {
                if (std.mem.lastIndexOfScalar(u8, ex.pattern, '/')) |idx|
                    break :blk ex.pattern[idx + 1 ..]
                else
                    break :blk ex.pattern;
            };
            if (s.len == basename.len and std.mem.eql(u8, s, basename)) {
                freeRule(list, rule_in);
                return;
            }
        }

        const lp = env.allocator.create(FilterList) catch return error.OutOfMemory;
        lp.* = FilterList.init(env.allocator, "");
        const debug = std.fmt.allocPrint(env.allocator, " [per-dir {s}]", .{basename}) catch {
            env.allocator.destroy(lp);
            return error.OutOfMemory;
        };
        lp.debug_type = debug;
        rule_in.data = .{ .mergelist = lp };

        try env.mergelist_parents.append(env.allocator, rule_in);
        env.mergelist_cnt.* += 1;
    } else {
        rule_in.data = .{ .slash_cnt = slash_cnt };
    }

    if (list.tail == null) {
        rule_in.next = list.head;
        list.head = rule_in;
        list.tail = rule_in;
    } else {
        rule_in.next = list.tail.?.next;
        list.tail.?.next = rule_in;
        list.tail = rule_in;
    }
}

fn freeRule(list: *FilterList, ex: *FilterRule) void {
    if (ex.rflags & rule.FILTRULE_PERDIR_MERGE != 0) {
        ex.data.mergelist.deinit();
        list.allocator.free(@constCast(ex.data.mergelist).debug_type);
        list.allocator.destroy(ex.data.mergelist);
    }
    list.allocator.free(ex.pattern);
    list.allocator.destroy(ex);
}

fn ruleStrcmp(str: []const u8, tok: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, str, tok)) return null;
    const after: u8 = if (tok.len < str.len) str[tok.len] else 0;
    if (after == 0 or std.ascii.isWhitespace(after) or after == '_' or after == ',')
        return str[tok.len - 1 ..];
    return null;
}

pub fn parseRuleTok(
    allocator: Allocator,
    rulestr_ptr: *[]const u8,
    template: *const FilterRule,
    xflags: u32,
    delete_excluded: bool,
    pat_ptr: *[]const u8,
    pat_len_ptr: *usize,
) ParseError!?*FilterRule {
    var s = rulestr_ptr.*;
    const rule_ptr = allocator.create(FilterRule) catch return error.OutOfMemory;
    errdefer allocator.destroy(rule_ptr);
    rule_ptr.* = .{
        .pattern = &.{},
        .rflags = template.rflags & rule.FILTRULES_FROM_CONTAINER,
        .data = .{ .slash_cnt = 0 },
    };

    if (template.rflags & rule.FILTRULE_WORD_SPLIT != 0) {
        s = std.mem.trimStart(u8, s, &std.ascii.whitespace);
        rulestr_ptr.* = s;
    }
    if (s.len == 0) return null;

    if (template.rflags & rule.FILTRULE_NO_PREFIXES != 0) {
        if (s[0] == '!' and template.rflags & rule.FILTRULE_CVS_IGNORE != 0)
            rule_ptr.rflags |= rule.FILTRULE_CLEAR_LIST;
    } else if (xflags & rule.XFLG_OLD_PREFIXES != 0) {
        if (s.len >= 2 and s[0] == '-' and s[1] == ' ') {
            rule_ptr.rflags &= ~rule.FILTRULE_INCLUDE;
            s = s[2..];
        } else if (s.len >= 2 and s[0] == '+' and s[1] == ' ') {
            rule_ptr.rflags |= rule.FILTRULE_INCLUDE;
            s = s[2..];
        } else if (s[0] == '!') {
            rule_ptr.rflags |= rule.FILTRULE_CLEAR_LIST;
        }
    } else {
        var ch: u8 = 0;
        var prefix_specifies_side = false;
        const rest = switch (s[0]) {
            'c' => if (ruleStrcmp(s, "clear")) |r| blk: {
                ch = '!';
                break :blk r;
            } else s,
            'd' => if (ruleStrcmp(s, "dir-merge")) |r| blk: {
                ch = ':';
                break :blk r;
            } else s,
            'e' => if (ruleStrcmp(s, "exclude")) |r| blk: {
                ch = '-';
                break :blk r;
            } else s,
            'h' => if (ruleStrcmp(s, "hide")) |r| blk: {
                ch = 'H';
                break :blk r;
            } else s,
            'i' => if (ruleStrcmp(s, "include")) |r| blk: {
                ch = '+';
                break :blk r;
            } else s,
            'm' => if (ruleStrcmp(s, "merge")) |r| blk: {
                ch = '.';
                break :blk r;
            } else s,
            'p' => if (ruleStrcmp(s, "protect")) |r| blk: {
                ch = 'P';
                break :blk r;
            } else s,
            'r' => if (ruleStrcmp(s, "risk")) |r| blk: {
                ch = 'R';
                break :blk r;
            } else s,
            's' => if (ruleStrcmp(s, "show")) |r| blk: {
                ch = 'S';
                break :blk r;
            } else s,
            else => blk: {
                ch = s[0];
                if (s.len >= 2 and s[1] == ',') break :blk s[1..];
                break :blk s;
            },
        };
        s = rest;

        switch (ch) {
            ':' => {
                rule_ptr.rflags |= rule.FILTRULE_PERDIR_MERGE | rule.FILTRULE_FINISH_SETUP;
                rule_ptr.rflags |= rule.FILTRULE_MERGE_FILE;
            },
            '.' => rule_ptr.rflags |= rule.FILTRULE_MERGE_FILE,
            '+' => rule_ptr.rflags |= rule.FILTRULE_INCLUDE,
            '-' => {},
            'S' => {
                rule_ptr.rflags |= rule.FILTRULE_INCLUDE;
                rule_ptr.rflags |= rule.FILTRULE_SENDER_SIDE;
                prefix_specifies_side = true;
            },
            'H' => {
                rule_ptr.rflags |= rule.FILTRULE_SENDER_SIDE;
                prefix_specifies_side = true;
            },
            'R' => {
                rule_ptr.rflags |= rule.FILTRULE_INCLUDE;
                rule_ptr.rflags |= rule.FILTRULE_RECEIVER_SIDE;
                prefix_specifies_side = true;
            },
            'P' => {
                rule_ptr.rflags |= rule.FILTRULE_RECEIVER_SIDE;
                prefix_specifies_side = true;
            },
            '!' => rule_ptr.rflags |= rule.FILTRULE_CLEAR_LIST,
            else => return error.UnknownFilterRule,
        }

        while (ch != '!') {
            if (s.len == 0) break;
            s = s[1..];
            if (s.len == 0 or s[0] == ' ' or s[0] == '_') break;
            if (template.rflags & rule.FILTRULE_WORD_SPLIT != 0 and std.ascii.isWhitespace(s[0])) break;
            const mod = s[0];
            switch (mod) {
                '-' => {
                    if (!rule.bitsSetAndUnset(rule_ptr.rflags, rule.FILTRULE_MERGE_FILE, rule.FILTRULE_NO_PREFIXES))
                        return error.InvalidModifier;
                    rule_ptr.rflags |= rule.FILTRULE_NO_PREFIXES;
                },
                '+' => {
                    if (!rule.bitsSetAndUnset(rule_ptr.rflags, rule.FILTRULE_MERGE_FILE, rule.FILTRULE_NO_PREFIXES))
                        return error.InvalidModifier;
                    rule_ptr.rflags |= rule.FILTRULE_NO_PREFIXES | rule.FILTRULE_INCLUDE;
                },
                '/' => rule_ptr.rflags |= rule.FILTRULE_ABS_PATH,
                '!' => {
                    if (rule_ptr.rflags & rule.FILTRULE_MERGE_FILE != 0) return error.InvalidModifier;
                    rule_ptr.rflags |= rule.FILTRULE_NEGATE;
                },
                'C' => {
                    if (rule_ptr.rflags & rule.FILTRULE_NO_PREFIXES != 0 or prefix_specifies_side)
                        return error.InvalidModifier;
                    rule_ptr.rflags |= rule.FILTRULE_NO_PREFIXES | rule.FILTRULE_WORD_SPLIT |
                        rule.FILTRULE_NO_INHERIT | rule.FILTRULE_CVS_IGNORE;
                },
                'e' => {
                    if (rule_ptr.rflags & rule.FILTRULE_MERGE_FILE == 0) return error.InvalidModifier;
                    rule_ptr.rflags |= rule.FILTRULE_EXCLUDE_SELF;
                },
                'n' => {
                    if (rule_ptr.rflags & rule.FILTRULE_MERGE_FILE == 0) return error.InvalidModifier;
                    rule_ptr.rflags |= rule.FILTRULE_NO_INHERIT;
                },
                'p' => rule_ptr.rflags |= rule.FILTRULE_PERISHABLE,
                'r' => {
                    if (prefix_specifies_side) return error.InvalidModifier;
                    rule_ptr.rflags |= rule.FILTRULE_RECEIVER_SIDE;
                },
                's' => {
                    if (prefix_specifies_side) return error.InvalidModifier;
                    rule_ptr.rflags |= rule.FILTRULE_SENDER_SIDE;
                },
                'w' => {
                    if (rule_ptr.rflags & rule.FILTRULE_MERGE_FILE == 0) return error.InvalidModifier;
                    rule_ptr.rflags |= rule.FILTRULE_WORD_SPLIT;
                },
                'x' => rule_ptr.rflags |= rule.FILTRULE_XATTR,
                else => return error.InvalidModifier,
            }
        }
        if (s.len != 0) s = s[1..];
    }

    if (template.rflags & rule.FILTRULES_SIDES != 0) {
        if (rule_ptr.rflags & rule.FILTRULES_SIDES != 0) return error.SideConflict;
        rule_ptr.rflags |= template.rflags & rule.FILTRULES_SIDES;
    }

    const len: usize = if (template.rflags & rule.FILTRULE_WORD_SPLIT != 0) blk: {
        var cp = s;
        while (cp.len != 0 and !std.ascii.isWhitespace(cp[0])) cp = cp[1..];
        break :blk s.len - cp.len;
    } else s.len;

    if (rule_ptr.rflags & rule.FILTRULE_CLEAR_LIST != 0) {
        if (template.rflags & rule.FILTRULE_NO_PREFIXES == 0 and
            xflags & rule.XFLG_OLD_PREFIXES == 0 and len != 0)
        {
            return error.ClearRuleTrailingChars;
        }
        if (len > 1) rule_ptr.rflags &= ~rule.FILTRULE_CLEAR_LIST;
    } else if (len == 0 and rule_ptr.rflags & rule.FILTRULE_CVS_IGNORE == 0) {
        return error.UnexpectedEndOfRule;
    }

    if (delete_excluded and
        rule_ptr.rflags & (rule.FILTRULES_SIDES | rule.FILTRULE_MERGE_FILE | rule.FILTRULE_PERDIR_MERGE) == 0)
    {
        rule_ptr.rflags |= rule.FILTRULE_SENDER_SIDE;
    }

    pat_ptr.* = s;
    pat_len_ptr.* = len;
    rulestr_ptr.* = s[len..];
    return rule_ptr;
}

pub fn teardownMergelist(
    allocator: Allocator,
    mergelist_parents: *std.ArrayList(*FilterRule),
    mergelist_cnt: *usize,
    ex: *FilterRule,
) void {
    if (ex.rflags & rule.FILTRULE_PERDIR_MERGE == 0) return;
    ex.data.mergelist.deinit();
    allocator.free(@constCast(ex.data.mergelist).debug_type);
    allocator.destroy(ex.data.mergelist);

    for (mergelist_parents.items[0..mergelist_cnt.*], 0..) |item, j| {
        if (item == ex) {
            _ = mergelist_parents.orderedRemove(j);
            mergelist_cnt.* -= 1;
            break;
        }
    }
}

test "parseRuleTok clear" {
    const a = std.testing.allocator;
    var s: []const u8 = "!";
    var pat: []const u8 = undefined;
    var pat_len: usize = undefined;
    const template = FilterList.init(a, "").ruleTemplate(0);
    const r = (try parseRuleTok(a, &s, &template, 0, false, &pat, &pat_len)).?;
    defer a.destroy(r);
    try std.testing.expect(r.rflags & rule.FILTRULE_CLEAR_LIST != 0);
}
