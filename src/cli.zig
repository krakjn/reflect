const std = @import("std");
const Io = std.Io;

const ParseError = error{
    OutOfMemory,
    ShortFlagDoesntAcceptValue,
    InvalidFlagName,
    InvalidFlagValue,
};

const ParseFailure = struct {
    code: ParseError,
    raw_arg: []const u8,

    pub fn format(self: ParseFailure, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        const is_long = std.mem.startsWith(u8, self.raw_arg, "--");
        const is_short = std.mem.startsWith(u8, self.raw_arg, "-") and !is_long;
        const name = get_flag_name(self.raw_arg);
        const value: ?[]const u8 = if (std.mem.indexOf(u8, self.raw_arg, "=")) |index|
            self.raw_arg[index + 1 ..]
        else
            null;

        switch (self.code) {
            error.ShortFlagDoesntAcceptValue => {
                try writer.print("short flag '-{s}' does not accept a value", .{name});
                if (value) |v| try writer.print(" (got '{s}')", .{v});
            },
            error.InvalidFlagName => {
                if (is_long) {
                    try writer.print("invalid long flag '--{s}'", .{name});
                } else if (is_short) {
                    try writer.print("invalid short flag '-{s}'", .{name});
                } else {
                    try writer.print("invalid flag '{s}'", .{self.raw_arg});
                }
            },
            error.InvalidFlagValue => {
                if (is_long) {
                    try writer.print("invalid value for long flag '--{s}'", .{name});
                    if (value) |v| try writer.print(": '{s}'", .{v});
                } else if (is_short) {
                    try writer.print("invalid value for short flag '-{s}'", .{name});
                    if (value) |v| try writer.print(": '{s}'", .{v});
                } else {
                    try writer.print("invalid flag value in '{s}'", .{self.raw_arg});
                }
            },
            error.OutOfMemory => try writer.print("out of memory while parsing '{s}'", .{self.raw_arg}),
        }
    }
};

const ParseResult = union(enum) {
    ok: std.ArrayList(Flag),
    err: ParseFailure,
};

const FlagType = enum {
    Short,
    Long,
    Source,
    Destination,
};

const Flag = struct {
    ftype: FlagType,
    name: ?[]const u8,
    value: ?[]const u8,
};

fn get_flag_name(raw_arg: []const u8) []const u8 {
    var name_part = raw_arg;
    if (std.mem.startsWith(u8, raw_arg, "--")) {
        name_part = raw_arg[2..];
    } else if (std.mem.startsWith(u8, raw_arg, "-")) {
        name_part = raw_arg[1..];
    }
    if (std.mem.indexOf(u8, name_part, "=")) |eq_index| {
        return name_part[0..eq_index];
    }
    return name_part;
}

pub fn parse(allocator: std.mem.Allocator, args: []const [:0]const u8) ParseResult {
    var flags: std.ArrayList(Flag) = .empty;
    // defer flags.deinit(allocator);

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        const is_long = std.mem.startsWith(u8, arg, "--");
        const is_short = std.mem.startsWith(u8, arg, "-") and !is_long;

        if (is_long) {
            if (std.mem.indexOf(u8, arg, "=")) |index| {
                const value = arg[index + 1 ..];
                flags.append(allocator, .{
                    .ftype = .Long,
                    .name = get_flag_name(arg),
                    .value = value,
                }) catch return .{ .err = .{
                    .code = error.OutOfMemory,
                    .raw_arg = arg,
                } };
            } else {
                flags.append(allocator, .{
                    .ftype = .Long,
                    .name = get_flag_name(arg),
                    .value = null,
                }) catch return .{ .err = .{
                    .code = error.OutOfMemory,
                    .raw_arg = arg,
                } };
            }
        } else if (is_short) {
            if (std.mem.indexOf(u8, arg, "=") != null) {
                return .{ .err = .{
                    .code = error.ShortFlagDoesntAcceptValue,
                    .raw_arg = arg,
                } };
            }
            flags.append(allocator, .{
                .ftype = .Short,
                .name = get_flag_name(arg),
                .value = null,
            }) catch return .{ .err = .{
                .code = error.OutOfMemory,
                .raw_arg = arg,
            } };
        } else {
            const is_last_arg = i == (args.len - 1);
            flags.append(allocator, .{
                .ftype = if (is_last_arg) FlagType.Destination else FlagType.Source,
                .name = null,
                .value = arg,
            }) catch return .{ .err = .{
                .code = error.OutOfMemory,
                .raw_arg = arg,
            } };
        }
    }
    return .{ .ok = flags };
}

pub fn show_capture(captures: std.ArrayList(Flag)) void {
    for (captures.items) |flag| {
        std.log.info("type {}, name {s}, value {s}", .{
            flag.ftype,
            flag.name orelse "no-name",
            flag.value orelse "no-val",
        });
    }
}
