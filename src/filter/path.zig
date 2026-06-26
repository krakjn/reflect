//! Path helpers used by rsync's exclude logic (from util1.c clean_fname/pathjoin).

const std = @import("std");

pub const CFN_KEEP_DOT_DIRS: u32 = 1 << 0;
pub const CFN_KEEP_TRAILING_SLASH: u32 = 1 << 1;
pub const CFN_DROP_TRAILING_DOT_DIR: u32 = 1 << 2;
pub const CFN_COLLAPSE_DOT_DOT_DIRS: u32 = 1 << 3;
pub const CFN_REFUSE_DOT_DOT_DIRS: u32 = 1 << 4;

pub const max_path_len: usize = 1024;
pub const big_path_buf_len: usize = 4096 + 1024;

inline fn dotIsDotDotDir(bp: []const u8) bool {
    return bp.len >= 2 and bp[0] == '.' and bp[1] == '.' and (bp.len == 2 or bp[2] == '/');
}

/// Clean a path in-place. Returns new length, or error.Refused on invalid `..`.
pub fn cleanFname(name: []u8, flags: u32) !usize {
    var limit: usize = 0;
    var t: usize = 0;
    var f: usize = 0;
    const anchored = name.len > 0 and name[0] == '/';
    if (anchored) {
        name[t] = name[f];
        t += 1;
        f += 1;
    } else if (flags & CFN_KEEP_DOT_DIRS != 0 and name.len >= 2 and name[0] == '.' and name[1] == '/') {
        name[t] = '.';
        t += 1;
        name[f] = '/';
        t += 1;
        f += 1;
    } else if (flags & CFN_REFUSE_DOT_DOT_DIRS != 0 and dotIsDotDotDir(name[f..])) {
        return error.Refused;
    }

    while (f < name.len) : (f += 1) {
        if (name[f] == '/') continue;
        if (name[f] == '.') {
            if (f + 1 < name.len and name[f + 1] == '/' and flags & CFN_KEEP_DOT_DIRS == 0) {
                f += 1;
                continue;
            }
            if (f + 1 == name.len and flags & CFN_DROP_TRAILING_DOT_DIR != 0) break;
            if (flags & (CFN_COLLAPSE_DOT_DOT_DIRS | CFN_REFUSE_DOT_DOT_DIRS) != 0 and dotIsDotDotDir(name[f..])) {
                if (flags & CFN_REFUSE_DOT_DOT_DIRS != 0) return error.Refused;
                var s: usize = if (t > 0) t - 1 else 0;
                if (s == 0 and anchored) {
                    f += 1;
                    continue;
                }
                while (s > limit and name[s - 1] != '/') s -= 1;
                if (s != t -| 1 and (s <= 0 or name[s] == '/')) {
                    t = if (s == 0) 0 else s + 1;
                    f += 1;
                    continue;
                }
                limit = t + 2;
            }
        }
        while (f < name.len) : ({ f += 1; t += 1; }) {
            name[t] = name[f];
            if (name[f] == '/') break;
        }
    }

    if (t > @intFromBool(anchored) and name[t - 1] == '/' and flags & CFN_KEEP_TRAILING_SLASH == 0)
        t -= 1;
    if (t == 0) {
        name[0] = '.';
        t = 1;
    }
    return t;
}

pub fn pathJoin(dest: []u8, p1: []const u8, p2: []const u8) ![]const u8 {
    var len: usize = 0;
    if (p1.len != 0) {
        if (len + p1.len > dest.len) return error.Overflow;
        @memcpy(dest[len .. len + p1.len], p1);
        len += p1.len;
        if (p1[p1.len - 1] != '/' and p2.len != 0 and p2[0] != '/') {
            if (len + 1 > dest.len) return error.Overflow;
            dest[len] = '/';
            len += 1;
        }
    }
    if (p2.len != 0) {
        if (len + p2.len > dest.len) return error.Overflow;
        @memcpy(dest[len .. len + p2.len], p2);
        len += p2.len;
    }
    return dest[0..len];
}

pub fn countDirElements(path: []const u8) usize {
    var count: usize = 0;
    var i: usize = 0;
    while (i < path.len) {
        while (i < path.len and path[i] == '/') i += 1;
        if (i >= path.len) break;
        count += 1;
        while (i < path.len and path[i] != '/') i += 1;
    }
    return count;
}
