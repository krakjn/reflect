//! Filter rule types and flags (rsync.h filter_struct / filter_list_struct).

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const NameFlags = struct {
    bits: u32 = NAME_IS_FILE,

    pub const NAME_IS_FILE: u32 = 0;
    pub const NAME_IS_DIR: u32 = 1 << 0;
    pub const NAME_IS_XATTR: u32 = 1 << 2;

    pub fn isFile(nf: NameFlags) bool {
        return nf.bits & (NAME_IS_DIR | NAME_IS_XATTR) == NAME_IS_FILE;
    }

    pub fn isDir(nf: NameFlags) bool {
        return nf.bits & NAME_IS_DIR != 0;
    }

    pub fn isXattr(nf: NameFlags) bool {
        return nf.bits & NAME_IS_XATTR != 0;
    }

    pub fn file() NameFlags {
        return .{};
    }

    pub fn dir() NameFlags {
        return .{ .bits = NAME_IS_DIR };
    }

    pub fn xattr() NameFlags {
        return .{ .bits = NAME_IS_XATTR };
    }
};

pub const FILTRULE_WILD: u32 = 1 << 0;
pub const FILTRULE_WILD2: u32 = 1 << 1;
pub const FILTRULE_WILD2_PREFIX: u32 = 1 << 2;
pub const FILTRULE_WILD3_SUFFIX: u32 = 1 << 3;
pub const FILTRULE_ABS_PATH: u32 = 1 << 4;
pub const FILTRULE_INCLUDE: u32 = 1 << 5;
pub const FILTRULE_DIRECTORY: u32 = 1 << 6;
pub const FILTRULE_WORD_SPLIT: u32 = 1 << 7;
pub const FILTRULE_NO_INHERIT: u32 = 1 << 8;
pub const FILTRULE_NO_PREFIXES: u32 = 1 << 9;
pub const FILTRULE_MERGE_FILE: u32 = 1 << 10;
pub const FILTRULE_PERDIR_MERGE: u32 = 1 << 11;
pub const FILTRULE_EXCLUDE_SELF: u32 = 1 << 12;
pub const FILTRULE_FINISH_SETUP: u32 = 1 << 13;
pub const FILTRULE_NEGATE: u32 = 1 << 14;
pub const FILTRULE_CVS_IGNORE: u32 = 1 << 15;
pub const FILTRULE_SENDER_SIDE: u32 = 1 << 16;
pub const FILTRULE_RECEIVER_SIDE: u32 = 1 << 17;
pub const FILTRULE_CLEAR_LIST: u32 = 1 << 18;
pub const FILTRULE_PERISHABLE: u32 = 1 << 19;
pub const FILTRULE_XATTR: u32 = 1 << 20;

pub const FILTRULES_SIDES: u32 = FILTRULE_SENDER_SIDE | FILTRULE_RECEIVER_SIDE;

pub const FILTRULES_FROM_CONTAINER: u32 = FILTRULE_ABS_PATH | FILTRULE_INCLUDE | FILTRULE_DIRECTORY |
    FILTRULE_NEGATE | FILTRULE_PERISHABLE;

pub const NO_FILTERS: u32 = 0;
pub const SERVER_FILTERS: u32 = 1;
pub const ALL_FILTERS: u32 = 2;

pub const LOCAL_RULE: u8 = 1;
pub const REMOTE_RULE: u8 = 2;

pub const XFLG_FATAL_ERRORS: u32 = 1 << 0;
pub const XFLG_OLD_PREFIXES: u32 = 1 << 1;
pub const XFLG_ANCHORED2ABS: u32 = 1 << 2;
pub const XFLG_ABS_IF_SLASH: u32 = 1 << 3;
pub const XFLG_DIR2WILD3: u32 = 1 << 4;

pub const FilterResult = enum(i8) {
    not_matched = 0,
    included = 1,
    excluded = -1,
};

pub const RuleData = union {
    slash_cnt: u32,
    mergelist: *FilterList,
};

pub const FilterRule = struct {
    next: ?*FilterRule = null,
    pattern: []u8,
    rflags: u32 = 0,
    data: RuleData,
    elide: u8 = 0,

    pub fn slashCount(self: *const FilterRule) u32 {
        if (self.rflags & FILTRULE_PERDIR_MERGE != 0) return 0;
        return self.data.slash_cnt;
    }

    pub fn mergelist(self: *const FilterRule) *FilterList {
        return self.data.mergelist;
    }
};

pub const FilterList = struct {
    head: ?*FilterRule = null,
    tail: ?*FilterRule = null,
    debug_type: []const u8 = "",
    allocator: Allocator,

    pub fn init(allocator: Allocator, debug_type: []const u8) FilterList {
        return .{
            .allocator = allocator,
            .debug_type = debug_type,
        };
    }

    pub fn deinit(self: *FilterList) void {
        freeFilters(self, self.head);
        self.head = null;
        self.tail = null;
    }

    pub fn ruleTemplate(self: *const FilterList, rflags: u32) FilterRule {
        _ = self;
        return .{
            .pattern = &.{},
            .rflags = rflags,
            .data = .{ .slash_cnt = 0 },
        };
    }

    fn freeFilter(self: *FilterList, rule: *FilterRule) void {
        if (rule.rflags & FILTRULE_PERDIR_MERGE != 0) {
            const lp = rule.data.mergelist;
            if (lp.debug_type.len != 0)
                self.allocator.free(@constCast(lp.debug_type));
            lp.deinit();
            self.allocator.destroy(lp);
        }
        self.allocator.free(rule.pattern);
        self.allocator.destroy(rule);
    }

    fn freeFilters(self: *FilterList, ent: ?*FilterRule) void {
        var node = ent;
        while (node) |rule| {
            const next = rule.next;
            self.freeFilter(rule);
            node = next;
        }
    }

    pub fn popLocal(self: *FilterList) void {
        const tail = self.tail orelse return;
        const inherited = tail.next;
        tail.next = null;
        freeFilters(self, self.head);
        self.head = inherited;
        self.tail = null;
    }

    pub fn clear(self: *FilterList) void {
        popLocal(self);
        self.head = null;
    }
};

pub fn bitsSetAndUnset(val: u32, onbits: u32, offbits: u32) bool {
    return (val & (onbits | offbits)) == onbits;
}
