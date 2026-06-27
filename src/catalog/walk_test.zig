//! Walk + filter integration tests.

const std = @import("std");
const filter = @import("../filter/mod.zig");
const walk = @import("walk.zig");
const list = @import("list.zig");

const io = std.testing.io;
const FilterEngine = filter.FilterEngine;

fn relPaths(catalog: *const list.FileList) ![]const []const u8 {
    const a = catalog.allocator;
    var out: std.ArrayList([]const u8) = .empty;
    errdefer out.deinit(a);
    for (catalog.entries.items) |e| {
        try out.append(a, e.rel_path);
    }
    return try out.toOwnedSlice(a);
}

fn contains(slice: []const []const u8, name: []const u8) bool {
    for (slice) |s| {
        if (std.mem.eql(u8, s, name)) return true;
    }
    return false;
}

test "walk excludes by pattern" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.writeFile(io, .{ .sub_path = "keep.txt", .data = "x" });
    try tmp.dir.writeFile(io, .{ .sub_path = "drop.o", .data = "x" });
    try tmp.dir.createDirPath(io, "sub");
    try tmp.dir.writeFile(io, .{ .sub_path = "sub/inside.o", .data = "x" });

    var engine = try FilterEngine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.parseFilterStr("- *.o", 0);
    try engine.parseFilterStr("- sub/", 0);

    var catalog = list.FileList.init(std.testing.allocator);
    defer catalog.deinit();

    const path = try tmp.dir.realPathFileAlloc(io, ".", std.testing.allocator);
    defer std.testing.allocator.free(path);

    var opts = @import("cli").ReflectOptions.defaults();
    opts.recurse = .on;

    try walk.walkSource(io, std.testing.allocator, &engine, path, &opts, &catalog);

    const paths = try relPaths(&catalog);
    defer std.testing.allocator.free(paths);

    try std.testing.expect(contains(paths, "keep.txt"));
    try std.testing.expect(!contains(paths, "drop.o"));
    try std.testing.expect(!contains(paths, "sub/inside.o"));
    try std.testing.expect(!contains(paths, "sub"));
}

test "walk without recurse lists top level only" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.writeFile(io, .{ .sub_path = "top.txt", .data = "x" });
    try tmp.dir.createDirPath(io, "nested");
    try tmp.dir.writeFile(io, .{ .sub_path = "nested/deep.txt", .data = "x" });

    var engine = try FilterEngine.init(std.testing.allocator, .{});
    defer engine.deinit();

    var catalog = list.FileList.init(std.testing.allocator);
    defer catalog.deinit();

    const path = try tmp.dir.realPathFileAlloc(io, ".", std.testing.allocator);
    defer std.testing.allocator.free(path);

    var opts = @import("cli").ReflectOptions.defaults();
    opts.recurse = .off;
    opts.xfer_dirs = .dirs;

    try walk.walkSource(io, std.testing.allocator, &engine, path, &opts, &catalog);

    const paths = try relPaths(&catalog);
    defer std.testing.allocator.free(paths);

    try std.testing.expect(contains(paths, "top.txt"));
    try std.testing.expect(contains(paths, "nested"));
    try std.testing.expect(!contains(paths, "nested/deep.txt"));
}

test "walk include before exclude order" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.writeFile(io, .{ .sub_path = "keep.o", .data = "x" });
    try tmp.dir.writeFile(io, .{ .sub_path = "drop.o", .data = "x" });

    var engine = try FilterEngine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.parseFilterStr("+ keep.o", 0);
    try engine.parseFilterStr("- *.o", 0);

    var catalog = list.FileList.init(std.testing.allocator);
    defer catalog.deinit();

    const path = try tmp.dir.realPathFileAlloc(io, ".", std.testing.allocator);
    defer std.testing.allocator.free(path);

    var opts = @import("cli").ReflectOptions.defaults();
    opts.recurse = .off;

    try walk.walkSource(io, std.testing.allocator, &engine, path, &opts, &catalog);

    const paths = try relPaths(&catalog);
    defer std.testing.allocator.free(paths);

    try std.testing.expect(contains(paths, "keep.o"));
    try std.testing.expect(!contains(paths, "drop.o"));
}
