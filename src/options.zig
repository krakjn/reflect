//! Reflect transfer options, mirroring rsync 3.4.4's global option state.
//!
//! Defaults match the initial values in rsync/options.c unless noted.
//! Call `defaults()` to obtain a fully initialized option set.

const std = @import("std");

pub const protocol_version: i32 = 32;
pub const rsync_port: i32 = 873;
pub const max_basis_dirs: usize = 20;
pub const default_max_alloc: usize = 1024 * 1024 * 1024;
pub const default_backup_suffix = "~";
pub const default_rsync_path = "rsync";
pub const compression_level_unspecified: i32 = std.math.minInt(i32);

pub const info_flag_count: usize = 13;
pub const debug_flag_count: usize = 24;

pub const InfoFlag = enum(u8) {
    backup,
    copy,
    del,
    flist,
    misc,
    mount,
    name,
    nonreg,
    progress,
    remove,
    skip,
    stats,
    symsafe,
};

pub const DebugFlag = enum(u8) {
    acl,
    backup,
    bind,
    chdir,
    connect,
    cmd,
    del,
    deltasum,
    dup,
    exit,
    filter,
    flist,
    fuzzy,
    genr,
    hash,
    hlink,
    iconv,
    io,
    nstr,
    own,
    proto,
    recv,
    send,
    time,
};

/// --stderr=e|a|c
pub const StderrMode = enum(u8) {
    /// Send all messages to stderr (rsync: msgs2stderr = 1, "all").
    all = 1,
    /// Send client-side messages to stderr (rsync: msgs2stderr = 0, "client").
    client = 0,
    /// Send only errors to stderr (rsync: msgs2stderr = 2, "errors"; default).
    errors = 2,
};

/// --outbuf=N|L|B
pub const OutbufMode = enum(u8) {
    none,
    line,
    block,
};

/// rsync recurse: 0 = off, 1 = archive implied, 2 = explicit --recursive.
pub const RecurseMode = enum(u8) {
    off = 0,
    archive = 1,
    on = 2,
};

/// rsync xfer_dirs: -1 = default, 0 = off, 2 = --dirs, 4 = --old-dirs.
pub const XferDirsMode = enum(i8) {
    default = -1,
    off = 0,
    dirs = 2,
    old_dirs = 4,
};

/// rsync relative_paths: -1 = default, 0 = off, 1 = --relative.
pub const RelativePathsMode = enum(i8) {
    default = -1,
    off = 0,
    on = 1,
};

/// rsync protect_args / --secluded-args: -1 = auto, 0 = off, 1 = on, 2 = forced on server.
pub const ProtectArgsMode = enum(i8) {
    auto = -1,
    off = 0,
    on = 1,
    forced = 2,
};

/// rsync old_style_args: -1 = auto, 0 = off, 1 = --old-args.
pub const OldArgsMode = enum(i8) {
    auto = -1,
    off = 0,
    on = 1,
};

/// rsync blocking_io: -1 = auto, 0 = off, 1 = --blocking-io.
pub const BlockingIoMode = enum(i8) {
    auto = -1,
    off = 0,
    on = 1,
};

/// rsync whole_file: -1 = auto (local vs remote), 0 = off, 1 = --whole-file.
pub const WholeFileMode = enum(i8) {
    auto = -1,
    off = 0,
    on = 1,
};

/// rsync am_root: 0 = normal, 1 = root, 2 = --super, -1 = --fake-super.
pub const RootMode = enum(i8) {
    fake_super = -1,
    normal = 0,
    root = 1,
    super = 2,
};

/// rsync append_mode: 0 = off, 1 = --append, 2 = --append-verify.
pub const AppendMode = enum(u8) {
    off = 0,
    append = 1,
    append_verify = 2,
};

/// rsync remove_source_files: 0 = off, 1 = --remove-source-files, 2 = deprecated alias.
pub const RemoveSourceFilesMode = enum(u8) {
    off = 0,
    on = 1,
    deprecated_sent = 2,
};

/// rsync missing_args: 0 = error, 1 = --ignore-missing-args, 2 = --delete-missing-args.
pub const MissingArgsMode = enum(u8) {
    fail = 0,
    ignore = 1,
    delete = 2,
};

/// rsync delete_during: 0 = off, 1 = --delete-during/--del, 2 = --delete-delay.
pub const DeleteDuringMode = enum(u8) {
    off = 0,
    during = 1,
    delay = 2,
};

/// rsync list_only: 0 = off, 2 = --list-only.
pub const ListOnlyMode = enum(u8) {
    off = 0,
    on = 2,
};

/// compare-dest / copy-dest / link-dest selection.
pub const AltDestType = enum(u8) {
    none = 0,
    compare = 1,
    copy = 2,
    link = 3,
};

/// rsync --ipv4 / --ipv6 preference (default_af_hint: 0 = any).
pub const AddressFamilyHint = enum(u8) {
    any = 0,
    ipv4 = 1,
    ipv6 = 2,
};

pub const ReflectOptions = struct {
    // --- verbosity & output ---
    verbose: u8 = 0,
    info_levels: [info_flag_count]i16 = .{0} ** info_flag_count,
    debug_levels: [debug_flag_count]i16 = .{0} ** debug_flag_count,
    stderr_mode: StderrMode = .errors,
    quiet: bool = false,
    output_motd: bool = true,
    stats: bool = false,
    human_readable: bool = true,
    allow_8bit_output: bool = false,
    outbuf_mode: ?OutbufMode = null,
    progress: bool = false,
    itemize_changes: bool = false,
    stdout_format: ?[]const u8 = null,
    logfile_name: ?[]const u8 = null,
    logfile_format: ?[]const u8 = null,

    // --- transfer behavior ---
    dry_run: bool = false,
    do_xfers: bool = true,
    list_only: ListOnlyMode = .off,
    do_fsync: bool = false,
    whole_file: WholeFileMode = .auto,
    always_checksum: bool = false,
    checksum_choice: ?[]const u8 = null,
    checksum_seed: i32 = 0,
    block_size: i32 = 0,
    sparse_files: bool = false,
    preallocate_files: bool = false,
    inplace: bool = false,
    append_mode: AppendMode = .off,
    update_only: bool = false,
    ignore_times: bool = false,
    size_only: bool = false,
    modify_window: i32 = 0,
    modify_window_set: bool = false,
    ignore_existing: bool = false,
    ignore_non_existing: bool = false,
    max_size: i64 = -1,
    min_size: i64 = -1,
    max_alloc: usize = default_max_alloc,
    bwlimit: i32 = 0,
    stop_at_utime: i64 = 0,

    // --- recursion & paths ---
    recurse: RecurseMode = .off,
    allow_inc_recurse: bool = true,
    xfer_dirs: XferDirsMode = .default,
    relative_paths: RelativePathsMode = .default,
    implied_dirs: bool = true,
    one_file_system: bool = false,
    mkpath_dest_arg: bool = false,
    prune_empty_dirs: bool = false,
    use_qsort: bool = false,

    // --- preservation ---
    preserve_links: bool = false,
    copy_links: bool = false,
    copy_unsafe_links: bool = false,
    safe_symlinks: bool = false,
    munge_symlinks: bool = false,
    copy_dirlinks: bool = false,
    keep_dirlinks: bool = false,
    preserve_hard_links: bool = false,
    preserve_perms: bool = false,
    preserve_executability: bool = false,
    chmod: ?[]const u8 = null,
    preserve_acls: bool = false,
    preserve_xattrs: bool = false,
    preserve_uid: bool = false,
    preserve_gid: bool = false,
    preserve_devices: bool = false,
    copy_devices: bool = false,
    write_devices: bool = false,
    preserve_specials: bool = false,
    preserve_mtimes: bool = false,
    preserve_atimes: bool = false,
    open_noatime: bool = false,
    preserve_crtimes: bool = false,
    omit_dir_times: bool = false,
    omit_link_times: bool = false,
    root_mode: RootMode = .normal,

    // --- deletion ---
    delete_mode: bool = false,
    delete_before: bool = false,
    delete_during: DeleteDuringMode = .off,
    delete_after: bool = false,
    delete_excluded: bool = false,
    remove_source_files: RemoveSourceFilesMode = .off,
    missing_args: MissingArgsMode = .fail,
    force_delete: bool = false,
    ignore_errors: bool = false,
    max_delete: i32 = std.math.minInt(i32),

    // --- backup ---
    make_backups: bool = false,
    backup_dir: ?[]const u8 = null,
    backup_suffix: ?[]const u8 = null,

    // --- partial / delay ---
    keep_partial: bool = false,
    partial_dir: ?[]const u8 = null,
    delay_updates: bool = false,

    // --- alternate destinations ---
    alt_dest_type: AltDestType = .none,
    basis_dirs: [max_basis_dirs]?[]const u8 = .{null} ** max_basis_dirs,
    basis_dir_count: usize = 0,
    fuzzy_basis: u8 = 0,

    // --- compression ---
    compress: bool = false,
    compress_choice: ?[]const u8 = null,
    compress_level: i32 = compression_level_unspecified,
    compress_threads: i32 = 0,
    skip_compress: ?[]const u8 = null,

    // --- filtering ---
    cvs_exclude: bool = false,
    filters: []const []const u8 = &.{},
    excludes: []const []const u8 = &.{},
    includes: []const []const u8 = &.{},
    exclude_from: []const []const u8 = &.{},
    include_from: []const []const u8 = &.{},
    f_option_count: u8 = 0,

    // --- file list input ---
    files_from: ?[]const u8 = null,
    eol_nulls: bool = false,

    // --- arg protection ---
    protect_args: ProtectArgsMode = .auto,
    old_style_args: OldArgsMode = .auto,
    trust_sender: bool = false,

    // --- identity mapping ---
    numeric_ids: bool = false,
    usermap: ?[]const u8 = null,
    groupmap: ?[]const u8 = null,
    chown: ?[]const u8 = null,
    copy_as: ?[]const u8 = null,

    // --- network & remote shell ---
    shell_cmd: ?[]const u8 = null,
    rsync_path: []const u8 = default_rsync_path,
    rsync_port: i32 = 0,
    bind_address: ?[]const u8 = null,
    sockopts: ?[]const u8 = null,
    blocking_io: BlockingIoMode = .auto,
    address_family: AddressFamilyHint = .any,
    connect_timeout: i32 = 0,
    io_timeout: i32 = 0,
    daemon_bwlimit: i32 = 0,

    // --- batch mode ---
    batch_name: ?[]const u8 = null,
    write_batch: bool = false,
    read_batch: bool = false,

    // --- misc ---
    tmpdir: ?[]const u8 = null,
    iconv: ?[]const u8 = null,
    password_file: ?[]const u8 = null,
    early_input_file: ?[]const u8 = null,
    protocol_version: i32 = protocol_version,
    remote_options: []const []const u8 = &.{},

    // --- internal / server-side (present in rsync globals) ---
    am_server: bool = false,
    am_sender: bool = false,
    am_daemon: bool = false,
    no_detach: bool = false,
    config_file: ?[]const u8 = null,

    /// Returns rsync-equivalent defaults. Mirrors post-parse initialization
    /// where verbosity 0 enables INFO_NONREG at level 1.
    pub fn defaults() ReflectOptions {
        var opts: ReflectOptions = .{};
        opts.info_levels[@intFromEnum(InfoFlag.nonreg)] = 1;
        return opts;
    }

    /// Apply archive mode (-a): -rlptgoD (no -A,-X,-U,-N,-H).
    pub fn applyArchive(self: *ReflectOptions) void {
        if (self.recurse == .off)
            self.recurse = .archive;
        self.preserve_links = true;
        self.preserve_perms = true;
        self.preserve_mtimes = true;
        self.preserve_gid = true;
        self.preserve_uid = true;
        self.preserve_devices = true;
        self.preserve_specials = true;
    }

    /// Apply -P: --partial --progress.
    pub fn applyProgressPartial(self: *ReflectOptions) void {
        self.keep_partial = true;
        self.progress = true;
    }

    /// Effective backup suffix after rsync's post-parse defaulting.
    pub fn effectiveBackupSuffix(self: *const ReflectOptions) []const u8 {
        if (self.backup_suffix) |suffix| return suffix;
        if (self.backup_dir != null) return "";
        return default_backup_suffix;
    }

    /// Whether delta transfer is disabled (whole-file mode resolved).
    pub fn usesWholeFile(self: *const ReflectOptions, is_local: bool) bool {
        return switch (self.whole_file) {
            .on => true,
            .off => false,
            .auto => is_local,
        };
    }
};

test "defaults match rsync initial globals" {
    const opts = ReflectOptions.defaults();

    try std.testing.expect(!opts.dry_run);
    try std.testing.expect(opts.do_xfers);
    try std.testing.expect(!opts.compress);
    try std.testing.expectEqual(@as(i32, compression_level_unspecified), opts.compress_level);
    try std.testing.expectEqual(@as(WholeFileMode, .auto), opts.whole_file);
    try std.testing.expectEqual(@as(XferDirsMode, .default), opts.xfer_dirs);
    try std.testing.expectEqual(@as(RelativePathsMode, .default), opts.relative_paths);
    try std.testing.expect(opts.implied_dirs);
    try std.testing.expect(opts.allow_inc_recurse);
    try std.testing.expect(opts.human_readable);
    try std.testing.expectEqual(@as(StderrMode, .errors), opts.stderr_mode);
    try std.testing.expectEqual(@as(i32, protocol_version), opts.protocol_version);
    try std.testing.expectEqual(@as(usize, default_max_alloc), opts.max_alloc);
    try std.testing.expectEqual(@as(i16, 1), opts.info_levels[@intFromEnum(InfoFlag.nonreg)]);
    try std.testing.expectEqualStrings(default_rsync_path, opts.rsync_path);
}

test "archive mode sets expected preservation flags" {
    var opts = ReflectOptions.defaults();
    opts.applyArchive();
    try std.testing.expectEqual(@as(RecurseMode, .archive), opts.recurse);
    try std.testing.expect(opts.preserve_links);
    try std.testing.expect(opts.preserve_perms);
    try std.testing.expect(opts.preserve_mtimes);
    try std.testing.expect(opts.preserve_gid);
    try std.testing.expect(opts.preserve_uid);
    try std.testing.expect(opts.preserve_devices);
    try std.testing.expect(opts.preserve_specials);
    try std.testing.expect(!opts.preserve_acls);
    try std.testing.expect(!opts.preserve_hard_links);
}

test "effective backup suffix" {
    const opts = ReflectOptions.defaults();
    try std.testing.expectEqualStrings("~", opts.effectiveBackupSuffix());

    var with_dir = ReflectOptions.defaults();
    with_dir.backup_dir = "/backups";
    try std.testing.expectEqualStrings("", with_dir.effectiveBackupSuffix());

    var custom = ReflectOptions.defaults();
    custom.backup_suffix = ".bak";
    try std.testing.expectEqualStrings(".bak", custom.effectiveBackupSuffix());
}
