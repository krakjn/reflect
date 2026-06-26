//! Shell-style pattern matching for rsync filters (from lib/wildmatch.c).

const std = @import("std");

const FALSE: i32 = 0;
const TRUE: i32 = 1;
const ABORT_ALL: i32 = -1;
const ABORT_TO_STARSTAR: i32 = -2;

fn isGraph(c: u8) bool {
    return std.ascii.isPrint(c) and !std.ascii.isWhitespace(c);
}

fn ccEq(class: []const u8, lit: []const u8) bool {
    return class.len == lit.len and std.mem.eql(u8, class, lit);
}

fn trailingNElements(a: []const []const u8, a_start: usize, count: i32) struct { text: []const u8, next: usize } {
    var a_idx = a_start;
    while (a_idx < a.len and a[a_idx].len != 0) : (a_idx += 1) {}

    var idx = a_idx;
    var remaining = count;
    while (idx > a_start) {
        idx -= 1;
        var s: usize = a[idx].len;
        const base = a[idx];
        while (s > 0) {
            s -= 1;
            if (base[s] == '/') {
                remaining -= 1;
                if (remaining == 0) {
                    return .{ .text = base[s + 1 ..], .next = idx + 1 };
                }
            }
        }
    }

    if (remaining == 1 and a_start < a.len) {
        return .{ .text = a[a_start], .next = a_start + 1 };
    }
    return .{ .text = "", .next = a_start };
}

fn dowild(p: []const u8, text_in: []const u8, a: []const []const u8, a_idx_in: usize) i32 {
    var p_i: usize = 0;
    var text: []const u8 = text_in;
    var text_i: usize = 0;
    var a_idx = a_idx_in;

    while (p_i < p.len) {
        const p_ch = p[p_i];
        var t_ch: u8 = 0;
        while (true) {
            t_ch = if (text_i < text.len) text[text_i] else 0;
            if (t_ch != 0) break;
            if (a_idx >= a.len or a[a_idx].len == 0) {
                if (p_ch != '*') return ABORT_ALL;
                break;
            }
            text = a[a_idx];
            text_i = 0;
            a_idx += 1;
        }

        switch (p_ch) {
            '\\' => {
                p_i += 1;
                if (p_i >= p.len) return FALSE;
                if (t_ch != p[p_i]) return FALSE;
                p_i += 1;
                text_i += 1;
                continue;
            },
            '?' => {
                if (t_ch == '/') return FALSE;
                p_i += 1;
                text_i += 1;
                continue;
            },
            '*' => {
                var special = false;
                p_i += 1;
                if (p_i < p.len and p[p_i] == '*') {
                    while (p_i < p.len and p[p_i] == '*') p_i += 1;
                    special = true;
                }
                if (p_i >= p.len) {
                    if (!special) {
                        while (true) {
                            if (std.mem.indexOfScalar(u8, text[text_i..], '/')) |_| return FALSE;
                            if (a_idx >= a.len or a[a_idx].len == 0) break;
                            text = a[a_idx];
                            text_i = 0;
                            a_idx += 1;
                        }
                    }
                    return TRUE;
                }
                const p_rest = p[p_i..];
                while (true) {
                    if (t_ch == 0) {
                        if (a_idx >= a.len or a[a_idx].len == 0) break;
                        text = a[a_idx];
                        text_i = 0;
                        a_idx += 1;
                        t_ch = if (text.len != 0) text[0] else 0;
                        continue;
                    }
                    const matched = dowild(p_rest, text[text_i..], a, a_idx);
                    if (matched != FALSE) {
                        if (!special or matched != ABORT_TO_STARSTAR) return matched;
                    } else if (!special and t_ch == '/') {
                        return ABORT_TO_STARSTAR;
                    }
                    text_i += 1;
                    t_ch = if (text_i < text.len) text[text_i] else 0;
                }
                return ABORT_ALL;
            },
            '[' => {
                p_i += 1;
                if (p_i >= p.len) return ABORT_ALL;
                var p_ch2 = p[p_i];
                if (p_ch2 == '^') p_ch2 = '!';
                const inverted = p_ch2 == '!';
                if (inverted) {
                    p_i += 1;
                    if (p_i >= p.len) return ABORT_ALL;
                    p_ch2 = p[p_i];
                }
                var prev_ch: u8 = 0;
                var matched = false;
                while (true) {
                    if (p_i >= p.len) return ABORT_ALL;
                    if (p_ch2 == '\\') {
                        p_i += 1;
                        if (p_i >= p.len) return ABORT_ALL;
                        p_ch2 = p[p_i];
                        if (t_ch == p_ch2) matched = true;
                    } else if (p_ch2 == '-' and prev_ch != 0 and p_i + 1 < p.len and p[p_i + 1] != ']') {
                        p_i += 1;
                        p_ch2 = p[p_i];
                        if (p_ch2 == '\\') {
                            p_i += 1;
                            if (p_i >= p.len) return ABORT_ALL;
                            p_ch2 = p[p_i];
                        }
                        if (t_ch <= p_ch2 and t_ch >= prev_ch) matched = true;
                        p_ch2 = 0;
                    } else if (p_ch2 == '[' and p_i + 1 < p.len and p[p_i + 1] == ':') {
                        p_i += 2;
                        const s_start = p_i;
                        while (p_i < p.len and p[p_i] != ']') p_i += 1;
                        if (p_i >= p.len) return ABORT_ALL;
                        if (p_i < s_start + 1 or p[p_i - 1] != ':') {
                            p_i = if (s_start >= 2) s_start - 2 else 0;
                            p_ch2 = '[';
                            if (t_ch == p_ch2) matched = true;
                        } else {
                            const name_len = p_i - 1 - s_start;
                            const name = p[s_start .. s_start + name_len];
                            if (ccEq(name, "alnum")) {
                                if (std.ascii.isAlphanumeric(t_ch)) matched = true;
                            } else if (ccEq(name, "alpha")) {
                                if (std.ascii.isAlphabetic(t_ch)) matched = true;
                            } else if (ccEq(name, "blank")) {
                                if (t_ch == ' ' or t_ch == '\t') matched = true;
                            } else if (ccEq(name, "cntrl")) {
                                if (std.ascii.isControl(t_ch)) matched = true;
                            } else if (ccEq(name, "digit")) {
                                if (std.ascii.isDigit(t_ch)) matched = true;
                            } else if (ccEq(name, "graph")) {
                                if (isGraph(t_ch)) matched = true;
                            } else if (ccEq(name, "lower")) {
                                if (std.ascii.isLower(t_ch)) matched = true;
                            } else if (ccEq(name, "print")) {
                                if (std.ascii.isPrint(t_ch)) matched = true;
                            } else if (ccEq(name, "punct")) {
                                if (std.ascii.isPunctuation(t_ch)) matched = true;
                            } else if (ccEq(name, "space")) {
                                if (std.ascii.isWhitespace(t_ch)) matched = true;
                            } else if (ccEq(name, "upper")) {
                                if (std.ascii.isUpper(t_ch)) matched = true;
                            } else if (ccEq(name, "xdigit")) {
                                if (std.ascii.isHex(t_ch)) matched = true;
                            } else return ABORT_ALL;
                            p_ch2 = 0;
                        }
                    } else if (t_ch == p_ch2) {
                        matched = true;
                    }
                    prev_ch = p_ch2;
                    p_i += 1;
                    if (p_i >= p.len) return ABORT_ALL;
                    p_ch2 = p[p_i];
                    if (p_ch2 == ']') {
                        p_i += 1;
                        break;
                    }
                }
                if (matched == inverted or t_ch == '/') return FALSE;
                text_i += 1;
                continue;
            },
            else => {
                if (t_ch != p_ch) return FALSE;
                p_i += 1;
                text_i += 1;
                continue;
            },
        }
    }

    while (true) {
        if (text_i < text.len) return FALSE;
        if (a_idx >= a.len or a[a_idx].len == 0) break;
        text = a[a_idx];
        text_i = 0;
        a_idx += 1;
    }
    return TRUE;
}

fn doliteral(s: []const u8, text_in: []const u8, a: []const []const u8, a_idx_in: usize) i32 {
    var s_i: usize = 0;
    var text: []const u8 = text_in;
    var text_i: usize = 0;
    var a_idx = a_idx_in;

    while (s_i < s.len) : (s_i += 1) {
        while (text_i >= text.len) {
            if (a_idx >= a.len or a[a_idx].len == 0) return FALSE;
            text = a[a_idx];
            text_i = 0;
            a_idx += 1;
        }
        if (text[text_i] != s[s_i]) return FALSE;
        text_i += 1;
    }

    while (true) {
        if (text_i < text.len) return FALSE;
        if (a_idx >= a.len or a[a_idx].len == 0) break;
        text = a[a_idx];
        text_i = 0;
        a_idx += 1;
    }
    return TRUE;
}

pub fn wildmatch(pattern: []const u8, text: []const u8) bool {
    const nomore = [_][]const u8{""};
    return dowild(pattern, text, &nomore, 0) == TRUE;
}

pub fn wildmatchArray(pattern: []const u8, texts: []const []const u8, where: i32) bool {
    var a_start: usize = 0;
    const text: []const u8 = if (where > 0) blk: {
        const hit = trailingNElements(texts, 0, where);
        if (hit.text.len == 0 and where != 1) return false;
        a_start = hit.next;
        break :blk hit.text;
    } else texts[0];

    const a_idx: usize = if (where > 0) a_start else 1;
    var matched = dowild(pattern, text, texts, a_idx);
    if (matched != TRUE and where < 0 and matched != ABORT_ALL) {
        var cur = text;
        var cur_a = a_idx;
        var cur_i: usize = 0;
        while (true) {
            if (cur_i >= cur.len) {
                if (cur_a >= texts.len or texts[cur_a].len == 0) return false;
                cur = texts[cur_a];
                cur_a += 1;
                cur_i = 0;
                continue;
            }
            if (cur[cur_i] == '/') {
                cur_i += 1;
                matched = dowild(pattern, cur[cur_i..], texts, cur_a);
                if (matched != FALSE and matched != ABORT_TO_STARSTAR) break;
            } else {
                cur_i += 1;
            }
        }
    }
    return matched == TRUE;
}

pub fn litmatchArray(string: []const u8, texts: []const []const u8, where: i32) bool {
    var a_idx: usize = 1;
    const text: []const u8 = if (where > 0) blk: {
        const hit = trailingNElements(texts, 0, where);
        if (hit.text.len == 0 and where != 1) return false;
        a_idx = hit.next;
        break :blk hit.text;
    } else texts[0];
    return doliteral(string, text, texts, a_idx) == TRUE;
}

test "wildmatch combined posix classes" {
    try std.testing.expect(wildmatch("foo/*", "foo/down"));
    try std.testing.expect(wildmatch("[[:upper:]]", "A"));
    try std.testing.expect(wildmatch("[[:digit:][:upper:]]", "A"));
    try std.testing.expect(wildmatch("[[:digit:][:upper:][:space:]]", "A"));
    try std.testing.expect(wildmatch("[[:digit:][:upper:][:space:]]", "1"));
    try std.testing.expect(!wildmatch("[[::]ab]", "[ab]"));
}

test "wildmatchArray foo child dir" {
    const texts = [_][]const u8{ "foo/down", "" };
    try std.testing.expect(wildmatchArray("foo/*", &texts, 2));
}

test "wildmatch star vs double-star" {
    try std.testing.expect(wildmatch("foo*", "foobar"));
    try std.testing.expect(!wildmatch("foo*", "foo/bar"));
    try std.testing.expect(wildmatch("foo**", "foo/bar"));
}

test "wildmatchArray slash retry" {
    const texts = [_][]const u8{ "a/b/c", "" };
    try std.testing.expect(wildmatchArray("b/*", &texts, -1));
}
