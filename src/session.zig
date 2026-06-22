//! Runtime session state for a reflect invocation.
//!
//! Holds parsed options, role flags, transfer paths, statistics, and I/O handles.
//! Callers construct a `Session` once at startup and pass it through later slices.

const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;

const cli = @import("cli");
const error_mod = @import("error.zig");

pub const ExitCode = error_mod.ExitCode;
pub const ExitTracker = error_mod.ExitTracker;
pub const Failure = error_mod.Failure;
pub const IoErrors = error_mod.IoErrors;

/// Endpoints for the rsync wire protocol or local pipe pair.
pub const StreamPair = struct {
    in: i32 = -1,
    out: i32 = -1,

    pub const unset: StreamPair = .{};

    pub fn stdio() StreamPair {
        return .{
            .in = posix.STDIN_FILENO,
            .out = posix.STDOUT_FILENO,
        };
    }

    pub fn isSet(self: StreamPair) bool {
        return self.in >= 0 and self.out >= 0;
    }

    pub fn bind(self: *StreamPair, in: i32, out: i32) void {
        self.in = in;
        self.out = out;
    }
};

/// Multiplex/buffering state mirrored from rsync `io.c` (populated in later slices).
pub const IoState = struct {
    io: std.Io,
    streams: StreamPair = .unset,
    multiplex_in: bool = false,
    multiplex_out: bool = false,

    pub fn init(io: std.Io) IoState {
        return .{ .io = io };
    }

    pub fn bindStdio(self: *IoState) void {
        self.streams = StreamPair.stdio();
    }

    pub fn bind(self: *IoState, in: i32, out: i32) void {
        self.streams.bind(in, out);
    }

    /// Buffered stdout writer for transfer output (not debug logging).
    pub fn stdoutWriter(self: *IoState, buffer: []u8) std.Io.File.Writer {
        return .init(.stdout(), self.io, buffer);
    }

    /// Buffered stderr writer for diagnostics.
    pub fn stderrWriter(self: *IoState, buffer: []u8) std.Io.File.Writer {
        return .init(.stderr(), self.io, buffer);
    }
};

/// Which side of the connection this process represents.
pub const ProcessSide = enum {
    client,
    server,
    daemon,
};

/// Role during the generator/receiver fork on the destination side.
pub const TransferSide = enum {
    none,
    sender,
    receiver,
    generator,
};

pub const ConnectionKind = enum {
    none,
    local,
    remote_shell,
    daemon_via_shell,
    daemon_socket,
};

pub const Connection = struct {
    kind: ConnectionKind = .none,
    local: bool = false,

    pub fn isRemote(self: Connection) bool {
        return switch (self.kind) {
            .remote_shell, .daemon_via_shell, .daemon_socket => true,
            else => false,
        };
    }
};

/// Effective process roles derived from options (and later from forks).
pub const Roles = struct {
    side: ProcessSide = .client,
    transfer: TransferSide = .none,
    connection: Connection = .{},

    pub fn fromOptions(options: *const cli.ReflectOptions) Roles {
        const side: ProcessSide = if (options.am_daemon)
            .daemon
        else if (options.am_server)
            .server
        else
            .client;

        const transfer: TransferSide = if (options.am_sender)
            .sender
        else if (options.am_server)
            .none
        else
            .none;

        return .{
            .side = side,
            .transfer = transfer,
            .connection = .{ .kind = .none, .local = false },
        };
    }

    pub fn isClient(self: Roles) bool {
        return self.side == .client;
    }

    pub fn isServer(self: Roles) bool {
        return self.side == .server;
    }

    pub fn isDaemon(self: Roles) bool {
        return self.side == .daemon;
    }

    pub fn isSender(self: Roles) bool {
        return self.transfer == .sender;
    }

    pub fn isReceiver(self: Roles) bool {
        return self.transfer == .receiver;
    }

    pub fn isGenerator(self: Roles) bool {
        return self.transfer == .generator;
    }

    pub fn setTransferSide(self: *Roles, side: TransferSide) void {
        self.transfer = side;
    }

    pub fn setConnection(self: *Roles, kind: ConnectionKind, local: bool) void {
        self.connection = .{ .kind = kind, .local = local };
    }
};

/// Caller identity captured at startup (rsync `our_uid` / `orig_umask`).
pub const Identity = struct {
    uid: u32,
    gid: u32,
    is_root: bool,
    umask_before: u16,

    pub fn capture() Identity {
        const uid = posix.getuid();
        const gid = posix.getgid();
        const umask_before: u16 = if (builtin.os.tag == .windows)
            0
        else
            @truncate(posix.umask(0));

        return .{
            .uid = uid,
            .gid = gid,
            .is_root = uid == 0,
            .umask_before = umask_before,
        };
    }
};

/// Source/destination paths from argv (arena-backed slices).
pub const Paths = struct {
    sources: []const []const u8 = &.{},
    destination: ?[]const u8 = null,

    pub fn fromParsed(parsed: cli.ParsedArgs) Paths {
        return .{
            .sources = parsed.sources,
            .destination = parsed.destination,
        };
    }

    pub fn isInfoOnly(options: *const cli.ReflectOptions) bool {
        return options.help or options.version;
    }

    pub fn needsPositionalPaths(options: *const cli.ReflectOptions) bool {
        if (isInfoOnly(options)) return false;
        if (options.am_daemon) return false;
        if (options.read_batch) return false;
        return true;
    }

    /// Slice 0 validation: enough argv paths for the current mode.
    pub fn validate(self: Paths, options: *const cli.ReflectOptions) ?Failure {
        if (!needsPositionalPaths(options)) return null;

        if (self.sources.len == 0 and self.destination == null) {
            return .{ .exit = .syntax };
        }
        if (options.am_server) {
            // Server receives module path separately over the wire.
            return null;
        }
        if (self.sources.len == 0) {
            return .{ .exit = .file_select };
        }
        if (self.destination == null) {
            return .{ .exit = .syntax };
        }
        return null;
    }
};

/// Transfer statistics (`struct stats` in rsync.h).
pub const Stats = struct {
    total_size: i64 = 0,
    total_transferred_size: i64 = 0,
    total_written: i64 = 0,
    total_read: i64 = 0,
    literal_data: i64 = 0,
    matched_data: i64 = 0,
    flist_buildtime: i64 = 0,
    flist_xfertime: i64 = 0,
    flist_size: i64 = 0,

    num_files: i32 = 0,
    num_dirs: i32 = 0,
    num_symlinks: i32 = 0,
    num_devices: i32 = 0,
    num_specials: i32 = 0,

    created_files: i32 = 0,
    created_dirs: i32 = 0,
    created_symlinks: i32 = 0,
    created_devices: i32 = 0,
    created_specials: i32 = 0,

    deleted_files: i32 = 0,
    deleted_dirs: i32 = 0,
    deleted_symlinks: i32 = 0,
    deleted_devices: i32 = 0,
    deleted_specials: i32 = 0,

    xferred_files: i32 = 0,

    pub fn reset(self: *Stats) void {
        self.* = .{};
    }

    pub fn merge(self: *Stats, other: Stats) void {
        inline for (@typeInfo(Stats).@"struct".fields) |field| {
            @field(self, field.name) += @field(other, field.name);
        }
    }
};

/// Full runtime context for one reflect invocation.
pub const Session = struct {
    allocator: std.mem.Allocator,
    options: cli.ReflectOptions,
    paths: Paths,
    roles: Roles,
    identity: Identity,
    io: IoState,
    stats: Stats,
    exit: ExitTracker,
    io_errors: IoErrors,
    start_time: i64,

    pub fn fromParsed(
        allocator: std.mem.Allocator,
        io: std.Io,
        parsed: cli.ParsedArgs,
    ) Session {
        return .{
            .allocator = allocator,
            .options = parsed.options,
            .paths = Paths.fromParsed(parsed),
            .roles = Roles.fromOptions(&parsed.options),
            .identity = Identity.capture(),
            .io = IoState.init(io),
            .stats = .{},
            .exit = .{},
            .io_errors = .none,
            .start_time = std.time.timestamp(),
        };
    }

    pub fn isInfoOnly(self: *const Session) bool {
        return Paths.isInfoOnly(&self.options);
    }

    pub fn isDryRun(self: *const Session) bool {
        return self.options.dry_run or self.options.write_batch;
    }

    pub fn wantsTransfer(self: *const Session) bool {
        return self.options.do_xfers and !self.isDryRun() and self.options.list_only == .off;
    }

    pub fn negotiatedProtocol(self: *const Session) i32 {
        return self.options.protocol_version;
    }

    pub fn effectiveWholeFile(self: *const Session) bool {
        return self.options.usesWholeFile(self.roles.connection.local);
    }

    pub fn validate(self: *const Session) ?Failure {
        return self.paths.validate(&self.options);
    }

    pub fn fail(self: *Session, failure: Failure) ExitCode {
        self.exit.setFailure(failure);
        return self.finish();
    }

    pub fn noteIoErrors(self: *Session, errs: IoErrors) void {
        self.io_errors = IoErrors.merge(self.io_errors, errs);
        self.exit.mergeIo(errs);
    }

    pub fn finish(self: *Session) ExitCode {
        return self.exit.finish();
    }

    pub fn elapsedSeconds(self: *const Session) i64 {
        return std.time.timestamp() - self.start_time;
    }
};

test "Session fromParsed captures options and paths" {
    const parsed = cli.parse(std.testing.allocator, &.{ "-avn", "src/", "dest/" });
    const ok = switch (parsed) {
        .ok => |p| p,
        .err => return error.TestExpectedEqual,
    };

    var session = Session.fromParsed(std.testing.allocator, undefined, ok);
    try std.testing.expect(session.options.dry_run);
    try std.testing.expect(session.options.preserve_links);
    try std.testing.expect(session.isDryRun());
    try std.testing.expect(!session.wantsTransfer());
    try std.testing.expectEqual(@as(usize, 1), session.paths.sources.len);
    try std.testing.expectEqualStrings("src/", session.paths.sources[0]);
    try std.testing.expectEqualStrings("dest/", session.paths.destination.?);
    try std.testing.expect(session.validate() == null);
}

test "Session validate requires destination for client transfer" {
    const parsed = cli.parse(std.testing.allocator, &.{"src/"});
    const ok = switch (parsed) {
        .ok => |p| p,
        .err => return error.TestExpectedEqual,
    };

    const session = Session.fromParsed(std.testing.allocator, undefined, ok);
    const failure = session.validate() orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(ExitCode.syntax, failure.exitCode());
}

test "help-only session skips path validation" {
    const parsed = cli.parse(std.testing.allocator, &.{"--help"});
    const ok = switch (parsed) {
        .ok => |p| p,
        .err => return error.TestExpectedEqual,
    };

    const session = Session.fromParsed(std.testing.allocator, undefined, ok);
    try std.testing.expect(session.isInfoOnly());
    try std.testing.expect(session.validate() == null);
}

test "Roles from server argv" {
    var opts = cli.ReflectOptions.defaults();
    opts.am_server = true;
    opts.am_sender = true;
    const roles = Roles.fromOptions(&opts);
    try std.testing.expect(roles.isServer());
    try std.testing.expect(roles.isSender());
}

test "Stats merge accumulates counters" {
    var a: Stats = .{ .num_files = 2, .total_size = 100 };
    const b: Stats = .{ .num_files = 3, .total_size = 50 };
    a.merge(b);
    try std.testing.expectEqual(@as(i32, 5), a.num_files);
    try std.testing.expectEqual(@as(i64, 150), a.total_size);
}
