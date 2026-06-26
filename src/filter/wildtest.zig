//! Run rsync wildtest.txt vectors against wildmatch.zig.

const std = @import("std");
const wildmatch = @import("wildmatch.zig");

const WildtestCase = struct {
    line: usize,
    expect_match: bool,
    text: []const u8,
    pattern: []const u8,
};

pub fn parseLine(line: []const u8, line_no: usize) !?WildtestCase {
    var trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
    if (trimmed.len == 0 or trimmed[0] == '#') return null;

    var i: usize = 0;
    var flags: [2]bool = undefined;
    inline for (0..2) |idx| {
        if (i >= trimmed.len) return error.InvalidSyntax;
        switch (trimmed[i]) {
            '1' => flags[idx] = true,
            '0' => flags[idx] = false,
            else => return error.InvalidSyntax,
        }
        i += 1;
        if (i >= trimmed.len or (trimmed[i] != ' ' and trimmed[i] != '\t')) return error.InvalidSyntax;
        while (i < trimmed.len and (trimmed[i] == ' ' or trimmed[i] == '\t')) i += 1;
    }
    const expect_match = flags[0];
    _ = flags[1];

    var strings: [2][]const u8 = undefined;
    inline for (0..2) |idx| {
        if (i >= trimmed.len) return error.InvalidSyntax;
        const quote = trimmed[i];
        if (quote == '\'' or quote == '"' or quote == '`') {
            i += 1;
            const start = i;
            while (i < trimmed.len and trimmed[i] != quote) i += 1;
            if (i >= trimmed.len) return error.UnmatchedQuote;
            strings[idx] = trimmed[start..i];
            i += 1;
        } else {
            const start = i;
            while (i < trimmed.len and trimmed[i] != ' ' and trimmed[i] != '\t') i += 1;
            strings[idx] = trimmed[start..i];
        }
        while (i < trimmed.len and (trimmed[i] == ' ' or trimmed[i] == '\t')) i += 1;
    }

    return .{
        .line = line_no,
        .expect_match = expect_match,
        .text = strings[0],
        .pattern = strings[1],
    };
}

pub fn runCases(cases: []const WildtestCase) !usize {
    var failures: usize = 0;
    for (cases) |c| {
        const matched = wildmatch.wildmatch(c.pattern, c.text);
        if (matched != c.expect_match) {
            std.debug.print(
                "wildmatch failure on line {d}:\n  text: {s}\n  pattern: {s}\n  expected {s} match\n",
                .{ c.line, c.text, c.pattern, if (c.expect_match) "a" else "NO" },
            );
            failures += 1;
        }
    }
    return failures;
}

pub fn loadWildtestFile(allocator: std.mem.Allocator, io: std.Io, path: []const u8) ![]WildtestCase {
    const file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    const data = try readAll(allocator, io, file);
    defer allocator.free(data);

    var cases = std.ArrayList(WildtestCase).empty;
    errdefer cases.deinit(allocator);

    var line_no: usize = 0;
    var line_start: usize = 0;
    var i: usize = 0;
    while (i <= data.len) : (i += 1) {
        if (i == data.len or data[i] == '\n') {
            line_no += 1;
            const line = data[line_start..i];
            line_start = i + 1;
            if (try parseLine(line, line_no)) |c| {
                const owned: WildtestCase = .{
                    .line = c.line,
                    .expect_match = c.expect_match,
                    .text = try allocator.dupe(u8, c.text),
                    .pattern = try allocator.dupe(u8, c.pattern),
                };
                try cases.append(allocator, owned);
            }
        }
    }
    return try cases.toOwnedSlice(allocator);
}

fn freeCases(allocator: std.mem.Allocator, cases: []WildtestCase) void {
    for (cases) |c| {
        allocator.free(c.text);
        allocator.free(c.pattern);
    }
    allocator.free(cases);
}

fn readAll(allocator: std.mem.Allocator, io: std.Io, file: std.Io.File) ![]u8 {
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

test "wildtest.txt vectors" {
    const a = std.testing.allocator;
    var threaded = std.Io.Threaded.init(a, .{});
    const io = threaded.io();
    const cases = loadWildtestFile(a, io, "rsync/wildtest.txt") catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("skip wildtest.txt: rsync/ not present\n", .{});
            return;
        },
        else => return err,
    };
    defer freeCases(a, cases);

    const failures = try runCases(cases);
    try std.testing.expectEqual(@as(usize, 0), failures);
}

test "parseLine quoted empty string" {
    const c = (try parseLine("1 1 '' \"\"", 1)).?;
    try std.testing.expect(c.expect_match);
    try std.testing.expectEqualStrings("", c.text);
    try std.testing.expectEqualStrings("", c.pattern);
}
