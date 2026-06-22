//! Exit codes and error values aligned with rsync `errcode.h`.
//!
//! Internal failures are represented as `Failure`; process exit status uses
//! `ExitCode`. Use `ExitTracker` to combine codes the way rsync's main path does.

const std = @import("std");
const cli = @import("cli");

/// Process exit status. Numeric values match rsync 3.4.x (`errcode.h`).
pub const ExitCode = enum(u8) {
    ok = 0,
    syntax = 1,
    protocol = 2,
    file_select = 3,
    unsupported = 4,
    start_client = 5,

    socket_io = 10,
    file_io = 11,
    stream_io = 12,
    message_io = 13,
    ipc = 14,
    crashed = 15,
    terminated = 16,

    signal_usr1 = 19,
    signal = 20,
    wait_child = 21,
    out_of_memory = 22,
    partial = 23,
    vanished = 24,
    del_limit = 25,

    timeout = 30,
    conn_timeout = 35,

    cmd_failed = 124,
    cmd_killed = 125,
    cmd_run = 126,
    cmd_not_found = 127,

    pub fn toInt(self: ExitCode) u8 {
        return @intFromEnum(self);
    }

    /// Human-readable name for logs (matches rsync/log.c themes).
    pub fn name(self: ExitCode) []const u8 {
        return switch (self) {
            .ok => "success",
            .syntax => "syntax or usage error",
            .protocol => "protocol incompatibility",
            .file_select => "error selecting input/output files or dirs",
            .unsupported => "requested action not supported",
            .start_client => "error starting client-server protocol",
            .socket_io => "error in socket IO",
            .file_io => "error in file IO",
            .stream_io => "error in protocol data stream",
            .message_io => "error in program diagnostics",
            .ipc => "error in IPC code",
            .crashed => "sibling process crashed",
            .terminated => "sibling process terminated abnormally",
            .signal_usr1 => "sent SIGUSR1",
            .signal => "interrupted by signal",
            .wait_child => "waitpid error",
            .out_of_memory => "error allocating memory",
            .partial => "partial transfer due to error",
            .vanished => "file(s) vanished on sender",
            .del_limit => "skipped deletes due to --max-delete",
            .timeout => "timeout in data send/receive",
            .conn_timeout => "timeout waiting for daemon connection",
            .cmd_failed => "remote command failed",
            .cmd_killed => "remote command killed by signal",
            .cmd_run => "remote command cannot be run",
            .cmd_not_found => "remote command not found",
        };
    }

    /// Rsync keeps the highest non-zero exit code seen during a run.
    pub fn max(a: ExitCode, b: ExitCode) ExitCode {
        return if (@intFromEnum(a) >= @intFromEnum(b)) a else b;
    }

    pub fn isSuccess(self: ExitCode) bool {
        return self == .ok;
    }
};

/// Bit flags accumulated during transfer (`IOERR_*` in rsync.h).
pub const IoErrors = struct {
    general: bool = false,
    vanished: bool = false,
    del_limit: bool = false,

    pub const none: IoErrors = .{};

    pub fn fromBits(bits: u8) IoErrors {
        return .{
            .general = bits & (1 << 0) != 0,
            .vanished = bits & (1 << 1) != 0,
            .del_limit = bits & (1 << 2) != 0,
        };
    }

    pub fn toBits(self: IoErrors) u8 {
        var bits: u8 = 0;
        if (self.general) bits |= 1 << 0;
        if (self.vanished) bits |= 1 << 1;
        if (self.del_limit) bits |= 1 << 2;
        return bits;
    }

    pub fn merge(a: IoErrors, b: IoErrors) IoErrors {
        return @bitCast(a.toBits() | b.toBits());
    }

    pub fn any(self: IoErrors) bool {
        return self.toBits() != 0;
    }

    /// Map accumulated I/O flags to rsync exit codes (see generator/main cleanup).
    pub fn toExitCode(self: IoErrors) ExitCode {
        if (self.vanished) return .vanished;
        if (self.del_limit) return .del_limit;
        if (self.general) return .partial;
        return .ok;
    }
};

/// Rich error for in-process propagation; always resolves to an `ExitCode`.
pub const Failure = union(enum) {
    exit: ExitCode,
    parse: cli.ParseFailure,
    message: Message,

    pub const Message = struct {
        code: ExitCode,
        text: []const u8,
    };

    pub fn exitCode(self: Failure) ExitCode {
        return switch (self) {
            .exit => |code| code,
            .parse => .syntax,
            .message => |m| m.code,
        };
    }

    pub fn format(self: Failure, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (self) {
            .exit => |code| try writer.print("{s}", .{code.name()}),
            .parse => |failure| try failure.format(writer),
            .message => |m| try writer.print("{s}: {s}", .{ m.code.name(), m.text }),
        }
    }
};

/// Tracks the exit status for a session or subprocess tree.
pub const ExitTracker = struct {
    code: ExitCode = .ok,
    io: IoErrors = .none,

    pub fn set(self: *ExitTracker, code: ExitCode) void {
        self.code = ExitCode.max(self.code, code);
    }

    pub fn setFailure(self: *ExitTracker, failure: Failure) void {
        self.set(failure.exitCode());
    }

    pub fn mergeIo(self: *ExitTracker, io_err: IoErrors) void {
        self.io = IoErrors.merge(self.io, io_err);
    }

    pub fn finish(self: *ExitTracker) ExitCode {
        const from_io = self.io.toExitCode();
        self.code = ExitCode.max(self.code, from_io);
        return self.code;
    }

    pub fn get(self: ExitTracker) ExitCode {
        return ExitCode.max(self.code, self.io.toExitCode());
    }
};

test "ExitCode max matches rsync ordering" {
    try std.testing.expectEqual(ExitCode.syntax, ExitCode.max(.ok, .syntax));
    try std.testing.expectEqual(ExitCode.partial, ExitCode.max(.syntax, .partial));
    try std.testing.expectEqual(ExitCode.vanished, ExitCode.max(.partial, .vanished));
}

test "IoErrors maps to exit codes" {
    try std.testing.expectEqual(ExitCode.ok, IoErrors.none.toExitCode());
    try std.testing.expectEqual(ExitCode.partial, (IoErrors{ .general = true }).toExitCode());
    try std.testing.expectEqual(ExitCode.vanished, (IoErrors{ .vanished = true }).toExitCode());
    try std.testing.expectEqual(ExitCode.del_limit, (IoErrors{ .del_limit = true }).toExitCode());
}

test "ExitTracker finish merges io flags" {
    var tracker: ExitTracker = .{};
    tracker.mergeIo(.{ .general = true });
    try std.testing.expectEqual(ExitCode.partial, tracker.finish());
}

test "parse failure resolves to syntax exit" {
    const failure: Failure = .{ .parse = .{
        .code = error.InvalidFlagName,
        .raw_arg = "--nope",
    } };
    try std.testing.expectEqual(ExitCode.syntax, failure.exitCode());
}
