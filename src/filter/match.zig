//! Filter matching (rule_matches, check_filter, name_is_excluded from exclude.c).

const rule = @import("rule.zig");
const wildmatch = @import("wildmatch.zig");

const FilterRule = rule.FilterRule;
const FilterList = rule.FilterList;
const NameFlags = rule.NameFlags;
const FilterResult = rule.FilterResult;

pub fn ruleMatches(
    fname: []const u8,
    ex: *const FilterRule,
    name_flags: NameFlags,
    cur_elide_value: u8,
    curr_dir: []const u8,
    module_dirlen: usize,
) bool {
    var slash_handling: i32 = 0;
    var str_cnt: usize = 0;
    var anchored_match: bool = false;
    const ret_match = (ex.rflags & rule.FILTRULE_NEGATE) == 0;
    var pattern = ex.pattern;
    const name_start = if (fname.len != 0 and fname[0] == '/') fname[1..] else fname;

    if (name_start.len == 0 or ex.elide == cur_elide_value) return false;

    const is_xattr = name_flags.isXattr();
    const rule_xattr = (ex.rflags & rule.FILTRULE_XATTR) != 0;
    if (is_xattr != rule_xattr) return false;

    var name = name_start;
    if (ex.slashCount() == 0 and (ex.rflags & rule.FILTRULE_WILD2) == 0) {
        if (std.mem.lastIndexOfScalar(u8, name, '/')) |p|
            name = name[p + 1 ..];
    } else if (ex.rflags & rule.FILTRULE_ABS_PATH != 0 and fname.len != 0 and fname[0] != '/' and
        curr_dir.len > module_dirlen + 1)
    {
        // handled via strings array below
    } else if (ex.rflags & rule.FILTRULE_WILD2_PREFIX != 0 and (fname.len == 0 or fname[0] != '/')) {
        // handled via strings array below
    }

    var strings: [16][]const u8 = undefined;
    if (ex.rflags & rule.FILTRULE_ABS_PATH != 0 and fname.len != 0 and fname[0] != '/' and
        curr_dir.len > module_dirlen + 1)
    {
        strings[str_cnt] = curr_dir[module_dirlen + 1 ..];
        str_cnt += 1;
        strings[str_cnt] = "/";
        str_cnt += 1;
    } else if (ex.rflags & rule.FILTRULE_WILD2_PREFIX != 0 and (fname.len == 0 or fname[0] != '/')) {
        strings[str_cnt] = "/";
        str_cnt += 1;
    }
    strings[str_cnt] = name;
    str_cnt += 1;
    if (name_flags.isDir()) {
        if (ex.rflags & rule.FILTRULE_WILD3_SUFFIX != 0) {
            strings[str_cnt] = "/";
            str_cnt += 1;
        }
    } else if (ex.rflags & rule.FILTRULE_DIRECTORY != 0) {
        return !ret_match;
    }
    strings[str_cnt] = "";

    if (pattern.len != 0 and pattern[0] == '/') {
        anchored_match = true;
        pattern = pattern[1..];
    }

    if (!anchored_match and ex.slashCount() != 0 and (ex.rflags & rule.FILTRULE_WILD2) == 0) {
        slash_handling = @intCast(ex.slashCount() + 1);
    } else if (!anchored_match and (ex.rflags & rule.FILTRULE_WILD2_PREFIX) == 0 and
        (ex.rflags & rule.FILTRULE_WILD2) != 0)
    {
        slash_handling = -1;
    } else {
        slash_handling = 0;
    }

    if (ex.rflags & rule.FILTRULE_WILD != 0) {
        if (wildmatch.wildmatchArray(pattern, strings[0 .. str_cnt + 1], slash_handling))
            return ret_match;
    } else if (str_cnt > 1) {
        if (wildmatch.litmatchArray(pattern, strings[0 .. str_cnt + 1], slash_handling))
            return ret_match;
    } else if (anchored_match) {
        if (std.mem.eql(u8, name, pattern)) return ret_match;
    } else {
        const l1 = name.len;
        const l2 = pattern.len;
        if (l2 <= l1 and
            std.mem.eql(u8, name[l1 - l2 ..], pattern) and
            (l1 == l2 or name[l1 - (l2 + 1)] == '/'))
        {
            return ret_match;
        }
    }

    return !ret_match;
}

pub fn checkFilter(
    list: *FilterList,
    name: []const u8,
    name_flags: NameFlags,
    cur_elide_value: u8,
    ignore_perishable: bool,
    curr_dir: []const u8,
    module_dirlen: usize,
) FilterResult {
    var ent = list.head;
    while (ent) |rule_ptr| : (ent = rule_ptr.next) {
        if (ignore_perishable and rule_ptr.rflags & rule.FILTRULE_PERISHABLE != 0) continue;
        if (rule_ptr.rflags & rule.FILTRULE_PERDIR_MERGE != 0) {
            const rc = checkFilter(
                rule_ptr.data.mergelist,
                name,
                name_flags,
                cur_elide_value,
                ignore_perishable,
                curr_dir,
                module_dirlen,
            );
            if (rc != .not_matched) return rc;
            continue;
        }
        if (rule_ptr.rflags & rule.FILTRULE_CVS_IGNORE != 0) {
            // deferred to caller (cvs list)
            continue;
        }
        if (ruleMatches(name, rule_ptr, name_flags, cur_elide_value, curr_dir, module_dirlen)) {
            return if (rule_ptr.rflags & rule.FILTRULE_INCLUDE != 0) .included else .excluded;
        }
    }
    return .not_matched;
}

pub fn checkFilterWithCvs(
    list: *FilterList,
    cvs_list: *FilterList,
    name: []const u8,
    name_flags: NameFlags,
    cur_elide_value: u8,
    ignore_perishable: bool,
    curr_dir: []const u8,
    module_dirlen: usize,
) FilterResult {
    var ent = list.head;
    while (ent) |rule_ptr| : (ent = rule_ptr.next) {
        if (ignore_perishable and rule_ptr.rflags & rule.FILTRULE_PERISHABLE != 0) continue;
        if (rule_ptr.rflags & rule.FILTRULE_PERDIR_MERGE != 0) {
            const rc = checkFilterWithCvs(
                rule_ptr.data.mergelist,
                cvs_list,
                name,
                name_flags,
                cur_elide_value,
                ignore_perishable,
                curr_dir,
                module_dirlen,
            );
            if (rc != .not_matched) return rc;
            continue;
        }
        if (rule_ptr.rflags & rule.FILTRULE_CVS_IGNORE != 0) {
            const rc = checkFilter(
                cvs_list,
                name,
                name_flags,
                cur_elide_value,
                ignore_perishable,
                curr_dir,
                module_dirlen,
            );
            if (rc != .not_matched) return rc;
            continue;
        }
        if (ruleMatches(name, rule_ptr, name_flags, cur_elide_value, curr_dir, module_dirlen)) {
            return if (rule_ptr.rflags & rule.FILTRULE_INCLUDE != 0) .included else .excluded;
        }
    }
    return .not_matched;
}

pub fn nameIsExcluded(
    filter_list: *FilterList,
    cvs_list: *FilterList,
    daemon_list: *FilterList,
    name: []const u8,
    name_flags: NameFlags,
    filter_level: u32,
    cur_elide_value: u8,
    ignore_perishable: bool,
    curr_dir: []const u8,
    module_dirlen: usize,
) bool {
    if (daemon_list.head != null) {
        const rc = checkFilter(
            daemon_list,
            name,
            name_flags,
            cur_elide_value,
            ignore_perishable,
            curr_dir,
            module_dirlen,
        );
        if (rc == .excluded) return true;
    }

    if (filter_level != rule.ALL_FILTERS) return false;

    if (filter_list.head != null) {
        const rc = checkFilterWithCvs(
            filter_list,
            cvs_list,
            name,
            name_flags,
            cur_elide_value,
            ignore_perishable,
            curr_dir,
            module_dirlen,
        );
        if (rc == .excluded) return true;
    }

    return false;
}

const std = @import("std");

test "ruleMatches suffix" {
    var pat: [5]u8 = .{ 'f', 'i', 'l', 'e', '1' };
    var rule_mut: FilterRule = .{
        .pattern = &pat,
        .rflags = 0,
        .data = .{ .slash_cnt = 0 },
    };
    try std.testing.expect(ruleMatches("/foo/file1", &rule_mut, NameFlags.file(), rule.REMOTE_RULE, "", 0));
    try std.testing.expect(!ruleMatches("/foo/file2", &rule_mut, NameFlags.file(), rule.REMOTE_RULE, "", 0));
}
