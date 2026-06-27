//! Local whole-file copy integration tests.

const std = @import("std");
const cli = @import("cli");
const catalog = @import("../catalog/mod.zig");
const filter = @import("../filter/mod.zig");
const walk = @import("../catalog/walk.zig");
const local = @import("local.zig");

const CopyStats = local.CopyStats;
const Io = std.Io;

const io = std.testing.io;

test "local whole-file copy preserves content" {
    var src_tmp = std.testing.tmpDir(.{ .iterate = true });
    defer src_tmp.cleanup();
    var dest_tmp = std.testing.tmpDir(.{ .iterate = true });
    defer dest_tmp.cleanup();

    try src_tmp.dir.writeFile(io, .{ .sub_path = "hello.txt", .data = "hello world" });
    try src_tmp.dir.createDirPath(io, "nested");
    try src_tmp.dir.writeFile(io, .{ .sub_path = "nested/x.txt", .data = "nested" });

    const src_path = try src_tmp.dir.realPathFileAlloc(io, ".", std.testing.allocator);
    defer std.testing.allocator.free(src_path);
    const dest_path = try dest_tmp.dir.realPathFileAlloc(io, ".", std.testing.allocator);
    defer std.testing.allocator.free(dest_path);

    var engine = try filter.FilterEngine.init(std.testing.allocator, .{});
    defer engine.deinit();

    var list = catalog.FileList.init(std.testing.allocator);
    defer list.deinit();

    var opts = cli.ReflectOptions.defaults();
    opts.applyArchive();
    opts.whole_file = .on;

    try walk.walkSource(io, std.testing.allocator, &engine, src_path, &opts, &list);

    var stats: CopyStats = .{};
    try local.runWholeFile(io, std.testing.allocator, &opts, &.{src_path}, dest_path, &list, &stats);

    const dest_file = try dest_tmp.dir.readFileAlloc(io, "hello.txt", std.testing.allocator, std.Io.Limit.limited(1024));
    defer std.testing.allocator.free(dest_file);
    try std.testing.expectEqualStrings("hello world", dest_file);

    const nested = try dest_tmp.dir.readFileAlloc(io, "nested/x.txt", std.testing.allocator, std.Io.Limit.limited(1024));
    defer std.testing.allocator.free(nested);
    try std.testing.expectEqualStrings("nested", nested);

    try std.testing.expectEqual(@as(i32, 2), stats.xferred_files);
}

test "update-only skips newer dest" {
    var src_tmp = std.testing.tmpDir(.{ .iterate = true });
    defer src_tmp.cleanup();
    var dest_tmp = std.testing.tmpDir(.{ .iterate = true });
    defer dest_tmp.cleanup();

    try src_tmp.dir.writeFile(io, .{ .sub_path = "f.txt", .data = "old" });
    try dest_tmp.dir.writeFile(io, .{ .sub_path = "f.txt", .data = "newer" });

    const src_stat = try src_tmp.dir.statFile(io, "f.txt", .{});
    const newer_mtime = Io.Timestamp{
        .nanoseconds = src_stat.mtime.nanoseconds + std.time.ns_per_s,
    };
    try dest_tmp.dir.setTimestamps(io, "f.txt", .{
        .access_timestamp = .unchanged,
        .modify_timestamp = std.Io.File.SetTimestamp.init(newer_mtime),
    });

    const src_path = try src_tmp.dir.realPathFileAlloc(io, ".", std.testing.allocator);
    defer std.testing.allocator.free(src_path);
    const dest_path = try dest_tmp.dir.realPathFileAlloc(io, ".", std.testing.allocator);
    defer std.testing.allocator.free(dest_path);

    var engine = try filter.FilterEngine.init(std.testing.allocator, .{});
    defer engine.deinit();

    var list = catalog.FileList.init(std.testing.allocator);
    defer list.deinit();

    var opts = cli.ReflectOptions.defaults();
    opts.applyArchive();
    opts.whole_file = .on;
    opts.update_only = true;

    try walk.walkSource(io, std.testing.allocator, &engine, src_path, &opts, &list);

    var stats: CopyStats = .{};
    try local.runWholeFile(io, std.testing.allocator, &opts, &.{src_path}, dest_path, &list, &stats);

    const dest_file = try dest_tmp.dir.readFileAlloc(io, "f.txt", std.testing.allocator, std.Io.Limit.limited(1024));
    defer std.testing.allocator.free(dest_file);
    try std.testing.expectEqualStrings("newer", dest_file);
    try std.testing.expectEqual(@as(i32, 0), stats.xferred_files);
}

test "creates missing destination directory" {
    var src_tmp = std.testing.tmpDir(.{ .iterate = true });
    defer src_tmp.cleanup();
    var parent_tmp = std.testing.tmpDir(.{ .iterate = true });
    defer parent_tmp.cleanup();

    try src_tmp.dir.writeFile(io, .{ .sub_path = "hello.txt", .data = "hello world" });

    const src_path = try src_tmp.dir.realPathFileAlloc(io, ".", std.testing.allocator);
    defer std.testing.allocator.free(src_path);
    const parent_path = try parent_tmp.dir.realPathFileAlloc(io, ".", std.testing.allocator);
    defer std.testing.allocator.free(parent_path);
    const dest_path = try std.fs.path.join(std.testing.allocator, &.{ parent_path, "missing_dest" });
    defer std.testing.allocator.free(dest_path);

    var engine = try filter.FilterEngine.init(std.testing.allocator, .{});
    defer engine.deinit();

    var list = catalog.FileList.init(std.testing.allocator);
    defer list.deinit();

    var opts = cli.ReflectOptions.defaults();
    opts.applyArchive();
    opts.whole_file = .on;

    const src_with_slash = try std.fmt.allocPrint(std.testing.allocator, "{s}/", .{src_path});
    defer std.testing.allocator.free(src_with_slash);

    try walk.walkSource(io, std.testing.allocator, &engine, src_path, &opts, &list);

    var stats: CopyStats = .{};
    try local.runWholeFile(io, std.testing.allocator, &opts, &.{src_with_slash}, dest_path, &list, &stats);

    const dest_file = try parent_tmp.dir.readFileAlloc(io, "missing_dest/hello.txt", std.testing.allocator, std.Io.Limit.limited(1024));
    defer std.testing.allocator.free(dest_file);
    try std.testing.expectEqualStrings("hello world", dest_file);
    try std.testing.expectEqual(@as(i32, 1), stats.xferred_files);
}
