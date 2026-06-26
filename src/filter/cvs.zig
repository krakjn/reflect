//! Default CVS exclude patterns (usage.c / default-cvsignore.h).

/// Auto-generated list from rsync.1.md (rsync 3.4.x default -C excludes).
pub const default_cvsignore =
    "RCS SCCS CVS CVS.adm RCSLOG cvslog.* tags TAGS .make.state .nse_depinfo " ++
    "*~ #* .#* ,* _$* *$ *.old *.bak *.BAK *.orig *.rej .del-* *.a *.olb " ++
    "*.o *.obj *.so *.exe *.Z *.elc *.ln core .svn/ .git/ .hg/ .bzr/";

pub fn getCvsExcludes(
    cvs_list: *@import("rule.zig").FilterList,
    parse_filter_str: *const fn (
        list: *@import("rule.zig").FilterList,
        rulestr: []const u8,
        template: *const @import("rule.zig").FilterRule,
        xflags: u32,
    ) anyerror!void,
    parse_filter_file: *const fn (
        list: *@import("rule.zig").FilterList,
        fname: []const u8,
        template: *const @import("rule.zig").FilterRule,
        xflags: u32,
    ) anyerror!void,
    home_dir: ?[]const u8,
    cvsignore_env: ?[]const u8,
    rflags: u32,
    protocol_version: u32,
    initialized: *bool,
) !void {
    if (initialized.*) return;
    initialized.* = true;

    const rule = @import("rule.zig");
    var template_flags = rflags;
    if (protocol_version >= 30) template_flags |= rule.FILTRULE_PERISHABLE;
    const template = cvs_list.ruleTemplate(template_flags);

    try parse_filter_str(cvs_list, default_cvsignore, &template, 0);

    if (home_dir) |home| {
        var fname: [@import("path.zig").max_path_len]u8 = undefined;
        const joined = try @import("path.zig").pathJoin(&fname, home, ".cvsignore");
        try parse_filter_file(cvs_list, joined, &template, 0);
    }

    if (cvsignore_env) |env| {
        try parse_filter_str(cvs_list, env, &template, 0);
    }
}
