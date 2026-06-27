//! Public `libreflect` surface.
const std = @import("std");
const Io = std.Io;

pub const errors = @import("error.zig");
pub const session = @import("session.zig");
pub const filter = @import("filter/mod.zig");
pub const catalog = @import("catalog/mod.zig");
pub const log = @import("log/mod.zig");
pub const plan = @import("plan/mod.zig");
pub const platform = @import("platforms/mod.zig").platform;

pub const ExitCode = errors.ExitCode;
pub const ExitTracker = errors.ExitTracker;
pub const Failure = errors.Failure;
pub const IoErrors = errors.IoErrors;

pub const Session = session.Session;
pub const Stats = session.Stats;
pub const Roles = session.Roles;
pub const Paths = session.Paths;
pub const IoState = session.IoState;
pub const StreamPair = session.StreamPair;
pub const Identity = session.Identity;
pub const Connection = session.Connection;
pub const ConnectionKind = session.ConnectionKind;
pub const ProcessSide = session.ProcessSide;
pub const TransferSide = session.TransferSide;

pub const FilterEngine = filter.FilterEngine;
pub const FilterResult = filter.FilterResult;
pub const NameFlags = filter.NameFlags;

pub const FileEntry = catalog.FileEntry;
pub const FileList = catalog.FileList;
pub const WalkOptions = catalog.WalkOptions;

pub const ItemFlags = log.ItemFlags;
pub const emitCatalog = plan.emitCatalog;

/// Accepting an `Io.Writer` instance is a handy way to write reusable code.
pub fn printAnotherMessage(writer: *Io.Writer) Io.Writer.Error!void {
    try writer.print("Run `zig build test` to run the tests.\n", .{});
}

export fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try std.testing.expect(add(3, 7) == 10);
}

test {
    std.testing.refAllDecls(filter);
    std.testing.refAllDecls(catalog);
    std.testing.refAllDecls(log);
    std.testing.refAllDecls(plan);
}
