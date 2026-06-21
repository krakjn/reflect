//! Reflect transfer options, mirroring rsync 3.4.4's global option state.
//!
//! Defaults match the initial values in rsync/options.c unless noted.
//! Call `defaults()` to obtain a fully initialized option set.

const std = @import("std");
const build_options = @import("build_options");

pub const protocol_version: i32 = 32;
pub const rsync_port: i32 = 873;
pub const max_basis_dirs: usize = 20;
pub const default_max_alloc: usize = 1024 * 1024 * 1024;
pub const default_backup_suffix = "~";
pub const default_rsync_path = "rsync";
pub const compression_level_unspecified: i32 = std.math.minInt(i32);

pub const info_flag_count: usize = 13;
pub const debug_flag_count: usize = 24;

const help_text =
    \\@@@@@@@  @@@@@@@@ @@@@@@@@ @@@      @@@@@@@@  @@@@@@@ @@@@@@@ 
    \\@@!  @@@ @@!      @@!      @@!      @@!      !@@        @!!   
    \\@!@!!@!  @!!!:!   @!!!:!   @!!      @!!!:!   !@!        @!!   
    \\!!: :!!  !!:      !!:      !!:      !!:      :!!        !!:   
    \\:   : :  : .: :.  ::       : :..:.: : .: :.   :: :: :    :    
    \\
    \\reflect ->|<- is a tool to mirror files locally or remotely
    \\
    \\Usage: reflect [OPTION]... SRC [SRC]... DEST
    \\  or   reflect [OPTION]... SRC [SRC]... [USER@]HOST:DEST
    \\  or   reflect [OPTION]... SRC [SRC]... [USER@]HOST::DEST
    \\  or   reflect [OPTION]... SRC [SRC]... reflect://[USER@]HOST[:PORT]/DEST
    \\  or   reflect [OPTION]... [USER@]HOST:SRC [DEST]
    \\  or   reflect [OPTION]... [USER@]HOST::SRC [DEST]
    \\  or   reflect [OPTION]... reflect://[USER@]HOST[:PORT]/SRC [DEST]
    \\The ':' usages connect via remote shell, while '::' & 'reflect://' usages connect
    \\to a reflect daemon, and require SRC or DEST to start with a module name.
    \\
    \\Options:
    \\ -v, --verbose            increase verbosity
    \\     --info=FLAGS         fine-grained informational verbosity
    \\     --debug=FLAGS        fine-grained debug verbosity
    \\     --stderr=e|a|c       change stderr output mode (default: errors)
    \\ -q, --quiet              suppress non-error messages
    \\     --no-motd            suppress daemon-mode MOTD
    \\ -c, --checksum           skip based on checksum, not mod-time & size
    \\ -a, --archive            archive mode is -rlptgoD (no -A,-X,-U,-N,-H)
    \\ -r, --recursive          recurse into directories
    \\ -R, --relative           use relative path names
    \\     --no-implied-dirs    don't send implied dirs with --relative
    \\ -b, --backup             make backups (see --suffix & --backup-dir)
    \\     --backup-dir=DIR     make backups into hierarchy based in DIR
    \\     --suffix=SUFFIX      backup suffix (default ~ w/o --backup-dir)
    \\ -u, --update             skip files that are newer on the receiver
    \\     --inplace            update destination files in-place
    \\     --append             append data onto shorter files
    \\     --append-verify      --append w/old data in file checksum
    \\ -d, --dirs               transfer directories without recursing
    \\     --old-dirs, --old-d  works like --dirs when talking to old rsync
    \\     --mkpath             create destination's missing path components
    \\ -l, --links              copy symlinks as symlinks
    \\ -L, --copy-links         transform symlink into referent file/dir
    \\     --copy-unsafe-links  only "unsafe" symlinks are transformed
    \\     --safe-links         ignore symlinks that point outside the tree
    \\     --munge-links        munge symlinks to make them safe & unusable
    \\ -k, --copy-dirlinks      transform symlink to dir into referent dir
    \\ -K, --keep-dirlinks      treat symlinked dir on receiver as dir
    \\ -H, --hard-links         preserve hard links
    \\ -p, --perms              preserve permissions
    \\ -E, --executability      preserve executability
    \\     --chmod=CHMOD        affect file and/or directory permissions
    \\ -A, --acls               preserve ACLs (implies --perms)
    \\ -X, --xattrs             preserve extended attributes
    \\ -o, --owner              preserve owner (super-user only)
    \\ -g, --group              preserve group
    \\     --devices            preserve device files (super-user only)
    \\     --copy-devices       copy device contents as a regular file
    \\     --write-devices      write to devices as files (implies --inplace)
    \\     --specials           preserve special files
    \\ -D                       same as --devices --specials
    \\ -t, --times              preserve modification times
    \\ -U, --atimes             preserve access (use) times
    \\     --open-noatime       avoid changing the atime on opened files
    \\ -N, --crtimes            preserve create times (newness)
    \\ -O, --omit-dir-times     omit directories from --times
    \\ -J, --omit-link-times    omit symlinks from --times
    \\     --super              receiver attempts super-user activities
    \\     --fake-super         store/recover privileged attrs using xattrs
    \\ -S, --sparse             turn sequences of nulls into sparse blocks
    \\     --preallocate        allocate dest files before writing them
    \\ -n, --dry-run            perform a trial run with no changes made
    \\ -W, --whole-file         copy files whole (w/o delta-xfer algorithm)
    \\     --checksum-choice=STR choose the checksum algorithm (aka --cc)
    \\ -x, --one-file-system    don't cross filesystem boundaries
    \\ -B, --block-size=SIZE    force a fixed checksum block-size
    \\ -e, --rsh=COMMAND        specify the remote shell to use
    \\     --rsync-path=PROGRAM specify the reflect to run on remote machine
    \\     --existing           skip creating new files on receiver
    \\     --ignore-existing    skip updating files that exist on receiver
    \\     --remove-source-files sender removes synchronized files (non-dir)
    \\     --del                an alias for --delete-during
    \\     --delete             delete extraneous files from dest dirs
    \\     --delete-before      receiver deletes before xfer, not during
    \\     --delete-during      receiver deletes during the transfer
    \\     --delete-delay       find deletions during, delete after
    \\     --delete-after       receiver deletes after transfer, not during
    \\     --delete-excluded    also delete excluded files from dest dirs
    \\     --ignore-missing-args ignore missing source args without error
    \\     --delete-missing-args delete missing source args from destination
    \\     --ignore-errors      delete even if there are I/O errors
    \\     --force              force deletion of dirs even if not empty
    \\     --max-delete=NUM     don't delete more than NUM files
    \\     --max-size=SIZE      don't transfer any file larger than SIZE
    \\     --min-size=SIZE      don't transfer any file smaller than SIZE
    \\     --max-alloc=SIZE     change a limit relating to memory alloc
    \\     --partial            keep partially transferred files
    \\     --partial-dir=DIR    put a partially transferred file into DIR
    \\     --delay-updates      put all updated files into place at end
    \\ -m, --prune-empty-dirs   prune empty directory chains from file-list
    \\     --numeric-ids        don't map uid/gid values by user/group name
    \\     --usermap=STRING     custom username mapping
    \\     --groupmap=STRING    custom groupname mapping
    \\     --chown=USER:GROUP   simple username/groupname mapping
    \\     --timeout=SECONDS    set I/O timeout in seconds
    \\     --contimeout=SECONDS set daemon connection timeout in seconds
    \\ -I, --ignore-times       don't skip files that match size and time
    \\     --size-only          skip files that match in size
    \\ -@, --modify-window=NUM  set the accuracy for mod-time comparisons
    \\ -T, --temp-dir=DIR       create temporary files in directory DIR
    \\ -y, --fuzzy              find similar file for basis if no dest file
    \\     --compare-dest=DIR   also compare destination files relative to DIR
    \\     --copy-dest=DIR      ... and include copies of unchanged files
    \\     --link-dest=DIR      hardlink to files in DIR when unchanged
    \\ -z, --compress           compress file data during the transfer
    \\     --compress-choice=STR choose the compression algorithm (aka --zc)
    \\     --compress-level=NUM explicitly set compression level (aka --zl)
    \\     --compress-threads=NUM explicitly set compression threads (aka --zt)
    \\     --skip-compress=LIST skip compressing files with suffix in LIST
    \\ -C, --cvs-exclude        auto-ignore files in the same way CVS does
    \\ -f, --filter=RULE        add a file-filtering RULE
    \\ -F                       same as --filter='dir-merge /.rsync-filter'
    \\                          repeated: --filter='- .rsync-filter'
    \\     --exclude=PATTERN    exclude files matching PATTERN
    \\     --exclude-from=FILE  read exclude patterns from FILE
    \\     --include=PATTERN    don't exclude files matching PATTERN
    \\     --include-from=FILE  read include patterns from FILE
    \\     --files-from=FILE    read list of source-file names from FILE
    \\ -0, --from0              all *-from/filter files are delimited by 0s
    \\     --old-args           disable the modern arg-protection idiom
    \\ -s, --secluded-args      use the protocol to safely send the args
    \\     --trust-sender       trust the remote sender's file list
    \\     --copy-as=USER[:GROUP] specify user & optional group for the copy
    \\     --address=ADDRESS    bind address for outgoing socket to daemon
    \\     --port=PORT          specify double-colon alternate port number
    \\     --sockopts=OPTIONS   specify custom TCP options
    \\     --blocking-io        use blocking I/O for the remote shell
    \\     --outbuf=N|L|B       set out buffering to None, Line, or Block
    \\     --stats              give some file-transfer stats
    \\ -8, --8-bit-output       leave high-bit chars unescaped in output
    \\ -h, --human-readable     output numbers in a human-readable format
    \\     --progress           show progress during transfer
    \\ -P                       same as --partial --progress
    \\ -i, --itemize-changes    output a change-summary for all updates
    \\ -M, --remote-option=OPT  send OPTION to the remote side only
    \\     --out-format=FORMAT  output updates using the specified FORMAT
    \\     --log-file=FILE      log what we're doing to the specified FILE
    \\     --log-file-format=FMT log updates using the specified FMT
    \\     --password-file=FILE read daemon-access password from FILE
    \\     --early-input=FILE   use FILE for daemon's early exec input
    \\     --list-only          list the files instead of copying them
    \\     --bwlimit=RATE       limit socket I/O bandwidth
    \\     --stop-after=MINS    Stop reflect after MINS minutes have elapsed
    \\     --stop-at=y-m-dTh:m  Stop reflect at the specified point in time
    \\     --fsync              fsync every written file
    \\     --write-batch=FILE   write a batched update to FILE
    \\     --only-write-batch=FILE like --write-batch but w/o updating dest
    \\     --read-batch=FILE    read a batched update from FILE
    \\     --protocol=NUM       force an older protocol version to be used
    \\     --iconv=CONVERT_SPEC request charset conversion of filenames
    \\     --checksum-seed=NUM  set block/file checksum seed (advanced)
    \\ -4, --ipv4               prefer IPv4
    \\ -6, --ipv6               prefer IPv6
    \\ -V, --version            print the version + other info and exit
    \\     --help (*)           show this help (-h is help only on its own)
    \\
    \\Use "reflect --daemon --help" to see the daemon-mode command-line options.
    \\
    // \\Please see the rsync(1) and rsyncd.conf(5) manpages for full documentation.
    // \\See https://rsync.samba.org/ for updates, bug reports, and answers
;

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

pub const ParseError = error{
    OutOfMemory,
    ShortFlagDoesntAcceptValue,
    InvalidFlagName,
    InvalidFlagValue,
    MissingFlagValue,
};

pub const ParseFailure = struct {
    code: ParseError,
    raw_arg: []const u8,

    pub fn format(self: ParseFailure, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        const is_long = std.mem.startsWith(u8, self.raw_arg, "--");
        const is_short = std.mem.startsWith(u8, self.raw_arg, "-") and !is_long;
        const name = flagName(self.raw_arg);
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
            error.MissingFlagValue => {
                if (is_long) {
                    try writer.print("long flag '--{s}' requires a value", .{name});
                } else {
                    try writer.print("short flag '-{s}' requires a value", .{name});
                }
            },
            error.OutOfMemory => try writer.print("out of memory while parsing '{s}'", .{self.raw_arg}),
        }
    }
};

pub const ParsedArgs = struct {
    options: ReflectOptions,
    sources: []const []const u8,
    destination: ?[]const u8,
};

pub const ParseResult = union(enum) {
    ok: ParsedArgs,
    err: ParseFailure,
};

pub const ReflectOptions = struct {
    help: bool = false,
    version: bool = false,
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

const ParseLists = struct {
    filters: std.ArrayList([]const u8),
    excludes: std.ArrayList([]const u8),
    includes: std.ArrayList([]const u8),
    exclude_from: std.ArrayList([]const u8),
    include_from: std.ArrayList([]const u8),
    remote_options: std.ArrayList([]const u8),

    fn init() ParseLists {
        return .{
            .filters = .empty,
            .excludes = .empty,
            .includes = .empty,
            .exclude_from = .empty,
            .include_from = .empty,
            .remote_options = .empty,
        };
    }

    fn finish(self: *ParseLists, opts: *ReflectOptions) void {
        opts.filters = self.filters.items;
        opts.excludes = self.excludes.items;
        opts.includes = self.includes.items;
        opts.exclude_from = self.exclude_from.items;
        opts.include_from = self.include_from.items;
        opts.remote_options = self.remote_options.items;
    }
};

fn flagName(raw_arg: []const u8) []const u8 {
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

fn normalizeLongName(name: []const u8) []const u8 {
    if (std.mem.eql(u8, name, "cc")) return "checksum-choice";
    if (std.mem.eql(u8, name, "zc")) return "compress-choice";
    if (std.mem.eql(u8, name, "zl")) return "compress-level";
    if (std.mem.eql(u8, name, "zt")) return "compress-threads";
    if (std.mem.eql(u8, name, "log-format")) return "out-format";
    if (std.mem.eql(u8, name, "protect-args")) return "secluded-args";
    if (std.mem.eql(u8, name, "existing")) return "ignore-non-existing";
    return name;
}

fn longFlagNeedsValue(name: []const u8) bool {
    const n = normalizeLongName(name);
    if (std.mem.startsWith(u8, n, "no-")) return false;
    return std.mem.eql(u8, n, "info") or
        std.mem.eql(u8, n, "debug") or
        std.mem.eql(u8, n, "stderr") or
        std.mem.eql(u8, n, "chmod") or
        std.mem.eql(u8, n, "max-size") or
        std.mem.eql(u8, n, "min-size") or
        std.mem.eql(u8, n, "max-alloc") or
        std.mem.eql(u8, n, "block-size") or
        std.mem.eql(u8, n, "compare-dest") or
        std.mem.eql(u8, n, "copy-dest") or
        std.mem.eql(u8, n, "link-dest") or
        std.mem.eql(u8, n, "checksum-choice") or
        std.mem.eql(u8, n, "compress-choice") or
        std.mem.eql(u8, n, "skip-compress") or
        std.mem.eql(u8, n, "compress-level") or
        std.mem.eql(u8, n, "compress-threads") or
        std.mem.eql(u8, n, "filter") or
        std.mem.eql(u8, n, "exclude") or
        std.mem.eql(u8, n, "include") or
        std.mem.eql(u8, n, "exclude-from") or
        std.mem.eql(u8, n, "include-from") or
        std.mem.eql(u8, n, "bwlimit") or
        std.mem.eql(u8, n, "backup-dir") or
        std.mem.eql(u8, n, "suffix") or
        std.mem.eql(u8, n, "read-batch") or
        std.mem.eql(u8, n, "write-batch") or
        std.mem.eql(u8, n, "only-write-batch") or
        std.mem.eql(u8, n, "files-from") or
        std.mem.eql(u8, n, "usermap") or
        std.mem.eql(u8, n, "groupmap") or
        std.mem.eql(u8, n, "chown") or
        std.mem.eql(u8, n, "stop-after") or
        std.mem.eql(u8, n, "stop-at") or
        std.mem.eql(u8, n, "time-limit") or
        std.mem.eql(u8, n, "rsh") or
        std.mem.eql(u8, n, "rsync-path") or
        std.mem.eql(u8, n, "temp-dir") or
        std.mem.eql(u8, n, "iconv") or
        std.mem.eql(u8, n, "address") or
        std.mem.eql(u8, n, "port") or
        std.mem.eql(u8, n, "sockopts") or
        std.mem.eql(u8, n, "password-file") or
        std.mem.eql(u8, n, "early-input") or
        std.mem.eql(u8, n, "outbuf") or
        std.mem.eql(u8, n, "remote-option") or
        std.mem.eql(u8, n, "protocol") or
        std.mem.eql(u8, n, "checksum-seed") or
        std.mem.eql(u8, n, "log-file") or
        std.mem.eql(u8, n, "log-file-format") or
        std.mem.eql(u8, n, "out-format") or
        std.mem.eql(u8, n, "partial-dir") or
        std.mem.eql(u8, n, "copy-as") or
        std.mem.eql(u8, n, "modify-window") or
        std.mem.eql(u8, n, "max-delete") or
        std.mem.eql(u8, n, "timeout") or
        std.mem.eql(u8, n, "contimeout") or
        std.mem.eql(u8, n, "config");
}

fn shortFlagNeedsValue(flag: u8) bool {
    return switch (flag) {
        'e', 'f', 'M', 'B', '@', 'T' => true,
        else => false,
    };
}

fn parseIntFlag(value: []const u8) ParseError!i32 {
    return std.fmt.parseInt(i32, value, 10) catch return error.InvalidFlagValue;
}

fn parseSizeFlag(value: []const u8) ParseError!i64 {
    var mult: i64 = 1;
    var end = value.len;
    if (end > 0) {
        const suffix = std.ascii.toUpper(value[end - 1]);
        switch (suffix) {
            'K' => {
                mult = 1024;
                end -= 1;
            },
            'M' => {
                mult = 1024 * 1024;
                end -= 1;
            },
            'G' => {
                mult = 1024 * 1024 * 1024;
                end -= 1;
            },
            'B' => {
                if (end > 1 and std.ascii.toUpper(value[end - 2]) == 'K') {
                    mult = 1000;
                    end -= 2;
                } else if (end > 1 and std.ascii.toUpper(value[end - 2]) == 'M') {
                    mult = 1000 * 1000;
                    end -= 2;
                } else if (end > 1 and std.ascii.toUpper(value[end - 2]) == 'G') {
                    mult = 1000 * 1000 * 1000;
                    end -= 2;
                }
            },
            else => {},
        }
    }
    const base = std.fmt.parseInt(i64, value[0..end], 10) catch return error.InvalidFlagValue;
    return base * mult;
}

fn parseOutbuf(value: []const u8) ParseError!OutbufMode {
    if (value.len == 0) return error.InvalidFlagValue;
    const mode = std.ascii.toUpper(value[0]);
    return switch (mode) {
        'N', 'U' => .none,
        'L' => .line,
        'B', 'F' => .block,
        else => error.InvalidFlagValue,
    };
}

fn parseStderrMode(value: []const u8) ParseError!StderrMode {
    if (value.len == 0) return error.InvalidFlagValue;
    if (std.mem.startsWith(u8, "errors", value) or std.mem.startsWith(u8, "e", value)) return .errors;
    if (std.mem.startsWith(u8, "all", value) or std.mem.startsWith(u8, "a", value)) return .all;
    if (std.mem.startsWith(u8, "client", value) or std.mem.startsWith(u8, "c", value)) return .client;
    return error.InvalidFlagValue;
}

fn addBasisDir(opts: *ReflectOptions, dest_type: AltDestType, path: []const u8) ParseError!void {
    if (opts.basis_dir_count >= max_basis_dirs) return error.InvalidFlagValue;
    if (opts.alt_dest_type != .none and opts.alt_dest_type != dest_type) return error.InvalidFlagValue;
    opts.basis_dirs[opts.basis_dir_count] = path;
    opts.basis_dir_count += 1;
    opts.alt_dest_type = dest_type;
}

fn appendList(
    allocator: std.mem.Allocator,
    list: *std.ArrayList([]const u8),
    value: []const u8,
) ParseError!void {
    list.append(allocator, value) catch return error.OutOfMemory;
}

fn applyNegatedLongFlag(opts: *ReflectOptions, name: []const u8) ParseError!void {
    if (std.mem.eql(u8, name, "verbose") or std.mem.eql(u8, name, "v")) {
        opts.verbose = 0;
        return;
    }
    if (std.mem.eql(u8, name, "recursive") or std.mem.eql(u8, name, "r")) {
        opts.recurse = .off;
        return;
    }
    if (std.mem.eql(u8, name, "inc-recursive") or std.mem.eql(u8, name, "i-r")) {
        opts.allow_inc_recurse = false;
        return;
    }
    if (std.mem.eql(u8, name, "dirs") or std.mem.eql(u8, name, "d")) {
        opts.xfer_dirs = .off;
        return;
    }
    if (std.mem.eql(u8, name, "perms") or std.mem.eql(u8, name, "p")) {
        opts.preserve_perms = false;
        return;
    }
    if (std.mem.eql(u8, name, "acls") or std.mem.eql(u8, name, "A")) {
        opts.preserve_acls = false;
        return;
    }
    if (std.mem.eql(u8, name, "xattrs") or std.mem.eql(u8, name, "X")) {
        opts.preserve_xattrs = false;
        return;
    }
    if (std.mem.eql(u8, name, "times") or std.mem.eql(u8, name, "t")) {
        opts.preserve_mtimes = false;
        return;
    }
    if (std.mem.eql(u8, name, "atimes") or std.mem.eql(u8, name, "U")) {
        opts.preserve_atimes = false;
        return;
    }
    if (std.mem.eql(u8, name, "open-noatime")) {
        opts.open_noatime = false;
        return;
    }
    if (std.mem.eql(u8, name, "crtimes") or std.mem.eql(u8, name, "N")) {
        opts.preserve_crtimes = false;
        return;
    }
    if (std.mem.eql(u8, name, "omit-dir-times") or std.mem.eql(u8, name, "O")) {
        opts.omit_dir_times = false;
        return;
    }
    if (std.mem.eql(u8, name, "omit-link-times") or std.mem.eql(u8, name, "J")) {
        opts.omit_link_times = false;
        return;
    }
    if (std.mem.eql(u8, name, "super")) {
        opts.root_mode = .normal;
        return;
    }
    if (std.mem.eql(u8, name, "owner") or std.mem.eql(u8, name, "o")) {
        opts.preserve_uid = false;
        return;
    }
    if (std.mem.eql(u8, name, "group") or std.mem.eql(u8, name, "g")) {
        opts.preserve_gid = false;
        return;
    }
    if (std.mem.eql(u8, name, "D")) {
        opts.preserve_devices = false;
        opts.preserve_specials = false;
        return;
    }
    if (std.mem.eql(u8, name, "devices")) {
        opts.preserve_devices = false;
        return;
    }
    if (std.mem.eql(u8, name, "write-devices")) {
        opts.write_devices = false;
        return;
    }
    if (std.mem.eql(u8, name, "specials")) {
        opts.preserve_specials = false;
        return;
    }
    if (std.mem.eql(u8, name, "links") or std.mem.eql(u8, name, "l")) {
        opts.preserve_links = false;
        return;
    }
    if (std.mem.eql(u8, name, "munge-links")) {
        opts.munge_symlinks = false;
        return;
    }
    if (std.mem.eql(u8, name, "hard-links") or std.mem.eql(u8, name, "H")) {
        opts.preserve_hard_links = false;
        return;
    }
    if (std.mem.eql(u8, name, "relative") or std.mem.eql(u8, name, "R")) {
        opts.relative_paths = .off;
        return;
    }
    if (std.mem.eql(u8, name, "implied-dirs") or std.mem.eql(u8, name, "i-d")) {
        opts.implied_dirs = false;
        return;
    }
    if (std.mem.eql(u8, name, "one-file-system") or std.mem.eql(u8, name, "x")) {
        opts.one_file_system = false;
        return;
    }
    if (std.mem.eql(u8, name, "sparse") or std.mem.eql(u8, name, "S")) {
        opts.sparse_files = false;
        return;
    }
    if (std.mem.eql(u8, name, "inplace")) {
        opts.inplace = false;
        return;
    }
    if (std.mem.eql(u8, name, "append")) {
        opts.append_mode = .off;
        return;
    }
    if (std.mem.eql(u8, name, "whole-file") or std.mem.eql(u8, name, "W")) {
        opts.whole_file = .off;
        return;
    }
    if (std.mem.eql(u8, name, "checksum") or std.mem.eql(u8, name, "c")) {
        opts.always_checksum = false;
        return;
    }
    if (std.mem.eql(u8, name, "fuzzy") or std.mem.eql(u8, name, "y")) {
        opts.fuzzy_basis = 0;
        return;
    }
    if (std.mem.eql(u8, name, "compress") or std.mem.eql(u8, name, "z")) {
        opts.compress = false;
        opts.compress_choice = null;
        return;
    }
    if (std.mem.eql(u8, name, "progress")) {
        opts.progress = false;
        return;
    }
    if (std.mem.eql(u8, name, "partial")) {
        opts.keep_partial = false;
        return;
    }
    if (std.mem.eql(u8, name, "delay-updates")) {
        opts.delay_updates = false;
        return;
    }
    if (std.mem.eql(u8, name, "prune-empty-dirs") or std.mem.eql(u8, name, "m")) {
        opts.prune_empty_dirs = false;
        return;
    }
    if (std.mem.eql(u8, name, "itemize-changes") or std.mem.eql(u8, name, "i")) {
        opts.itemize_changes = false;
        return;
    }
    if (std.mem.eql(u8, name, "backup")) {
        opts.make_backups = false;
        return;
    }
    if (std.mem.eql(u8, name, "from0")) {
        opts.eol_nulls = false;
        return;
    }
    if (std.mem.eql(u8, name, "secluded-args") or std.mem.eql(u8, name, "protect-args") or std.mem.eql(u8, name, "s")) {
        opts.protect_args = .off;
        return;
    }
    if (std.mem.eql(u8, name, "numeric-ids")) {
        opts.numeric_ids = false;
        return;
    }
    if (std.mem.eql(u8, name, "timeout")) {
        opts.io_timeout = 0;
        return;
    }
    if (std.mem.eql(u8, name, "contimeout")) {
        opts.connect_timeout = 0;
        return;
    }
    if (std.mem.eql(u8, name, "force")) {
        opts.force_delete = false;
        return;
    }
    if (std.mem.eql(u8, name, "ignore-errors")) {
        opts.ignore_errors = false;
        return;
    }
    if (std.mem.eql(u8, name, "human-readable") or std.mem.eql(u8, name, "h")) {
        opts.human_readable = false;
        return;
    }
    if (std.mem.eql(u8, name, "8-bit-output") or std.mem.eql(u8, name, "8")) {
        opts.allow_8bit_output = false;
        return;
    }
    if (std.mem.eql(u8, name, "mkpath")) {
        opts.mkpath_dest_arg = false;
        return;
    }
    if (std.mem.eql(u8, name, "motd")) {
        opts.output_motd = false;
        return;
    }
    if (std.mem.eql(u8, name, "msgs2stderr")) {
        opts.stderr_mode = .client;
        return;
    }
    if (std.mem.eql(u8, name, "bwlimit")) {
        opts.bwlimit = 0;
        return;
    }
    if (std.mem.eql(u8, name, "blocking-io")) {
        opts.blocking_io = .off;
        return;
    }
    if (std.mem.eql(u8, name, "old-args")) {
        opts.old_style_args = .off;
        return;
    }
    return error.InvalidFlagName;
}

fn applyLongFlag(
    allocator: std.mem.Allocator,
    opts: *ReflectOptions,
    lists: *ParseLists,
    raw_name: []const u8,
    value: ?[]const u8,
) ParseError!void {
    const name = normalizeLongName(raw_name);
    if (std.mem.startsWith(u8, name, "no-")) {
        return applyNegatedLongFlag(opts, name[3..]);
    }

    if (std.mem.eql(u8, name, "help")) {
        opts.help = true;
        return;
    }
    if (std.mem.eql(u8, name, "version")) {
        opts.version = true;
        return;
    }
    if (std.mem.eql(u8, name, "verbose")) {
        opts.verbose +|= 1;
        return;
    }
    if (std.mem.eql(u8, name, "quiet")) {
        opts.quiet = true;
        return;
    }
    if (std.mem.eql(u8, name, "motd")) {
        opts.output_motd = true;
        return;
    }
    if (std.mem.eql(u8, name, "stats")) {
        opts.stats = true;
        return;
    }
    if (std.mem.eql(u8, name, "human-readable")) {
        opts.human_readable = true;
        return;
    }
    if (std.mem.eql(u8, name, "dry-run")) {
        opts.dry_run = true;
        return;
    }
    if (std.mem.eql(u8, name, "archive")) {
        opts.applyArchive();
        return;
    }
    if (std.mem.eql(u8, name, "recursive")) {
        opts.recurse = .on;
        return;
    }
    if (std.mem.eql(u8, name, "inc-recursive") or std.mem.eql(u8, name, "i-r")) {
        opts.allow_inc_recurse = true;
        return;
    }
    if (std.mem.eql(u8, name, "dirs")) {
        opts.xfer_dirs = .dirs;
        return;
    }
    if (std.mem.eql(u8, name, "old-dirs") or std.mem.eql(u8, name, "old-d")) {
        opts.xfer_dirs = .old_dirs;
        return;
    }
    if (std.mem.eql(u8, name, "perms")) {
        opts.preserve_perms = true;
        return;
    }
    if (std.mem.eql(u8, name, "executability")) {
        opts.preserve_executability = true;
        return;
    }
    if (std.mem.eql(u8, name, "acls")) {
        opts.preserve_acls = true;
        opts.preserve_perms = true;
        return;
    }
    if (std.mem.eql(u8, name, "xattrs")) {
        opts.preserve_xattrs = true;
        return;
    }
    if (std.mem.eql(u8, name, "times")) {
        opts.preserve_mtimes = true;
        return;
    }
    if (std.mem.eql(u8, name, "atimes")) {
        opts.preserve_atimes = true;
        return;
    }
    if (std.mem.eql(u8, name, "open-noatime")) {
        opts.open_noatime = true;
        return;
    }
    if (std.mem.eql(u8, name, "crtimes")) {
        opts.preserve_crtimes = true;
        return;
    }
    if (std.mem.eql(u8, name, "omit-dir-times")) {
        opts.omit_dir_times = true;
        return;
    }
    if (std.mem.eql(u8, name, "omit-link-times")) {
        opts.omit_link_times = true;
        return;
    }
    if (std.mem.eql(u8, name, "modify-window")) {
        const v = value orelse return error.MissingFlagValue;
        opts.modify_window = try parseIntFlag(v);
        opts.modify_window_set = true;
        return;
    }
    if (std.mem.eql(u8, name, "super")) {
        opts.root_mode = .super;
        return;
    }
    if (std.mem.eql(u8, name, "fake-super")) {
        opts.root_mode = .fake_super;
        return;
    }
    if (std.mem.eql(u8, name, "owner")) {
        opts.preserve_uid = true;
        return;
    }
    if (std.mem.eql(u8, name, "group")) {
        opts.preserve_gid = true;
        return;
    }
    if (std.mem.eql(u8, name, "devices")) {
        opts.preserve_devices = true;
        return;
    }
    if (std.mem.eql(u8, name, "copy-devices")) {
        opts.copy_devices = true;
        return;
    }
    if (std.mem.eql(u8, name, "write-devices")) {
        opts.write_devices = true;
        opts.inplace = true;
        return;
    }
    if (std.mem.eql(u8, name, "specials")) {
        opts.preserve_specials = true;
        return;
    }
    if (std.mem.eql(u8, name, "links")) {
        opts.preserve_links = true;
        return;
    }
    if (std.mem.eql(u8, name, "copy-links")) {
        opts.copy_links = true;
        return;
    }
    if (std.mem.eql(u8, name, "copy-unsafe-links")) {
        opts.copy_unsafe_links = true;
        return;
    }
    if (std.mem.eql(u8, name, "safe-links")) {
        opts.safe_symlinks = true;
        return;
    }
    if (std.mem.eql(u8, name, "munge-links")) {
        opts.munge_symlinks = true;
        return;
    }
    if (std.mem.eql(u8, name, "copy-dirlinks")) {
        opts.copy_dirlinks = true;
        return;
    }
    if (std.mem.eql(u8, name, "keep-dirlinks")) {
        opts.keep_dirlinks = true;
        return;
    }
    if (std.mem.eql(u8, name, "hard-links")) {
        opts.preserve_hard_links = true;
        return;
    }
    if (std.mem.eql(u8, name, "relative")) {
        opts.relative_paths = .on;
        return;
    }
    if (std.mem.eql(u8, name, "implied-dirs") or std.mem.eql(u8, name, "i-d")) {
        opts.implied_dirs = true;
        return;
    }
    if (std.mem.eql(u8, name, "chmod")) {
        opts.chmod = value orelse return error.MissingFlagValue;
        return;
    }
    if (std.mem.eql(u8, name, "ignore-times")) {
        opts.ignore_times = true;
        return;
    }
    if (std.mem.eql(u8, name, "size-only")) {
        opts.size_only = true;
        return;
    }
    if (std.mem.eql(u8, name, "one-file-system")) {
        opts.one_file_system = true;
        return;
    }
    if (std.mem.eql(u8, name, "update")) {
        opts.update_only = true;
        return;
    }
    if (std.mem.eql(u8, name, "ignore-non-existing") or std.mem.eql(u8, name, "existing")) {
        opts.ignore_non_existing = true;
        return;
    }
    if (std.mem.eql(u8, name, "ignore-existing")) {
        opts.ignore_existing = true;
        return;
    }
    if (std.mem.eql(u8, name, "max-size")) {
        const v = value orelse return error.MissingFlagValue;
        opts.max_size = try parseSizeFlag(v);
        return;
    }
    if (std.mem.eql(u8, name, "min-size")) {
        const v = value orelse return error.MissingFlagValue;
        opts.min_size = try parseSizeFlag(v);
        return;
    }
    if (std.mem.eql(u8, name, "max-alloc")) {
        const v = value orelse return error.MissingFlagValue;
        const size = try parseSizeFlag(v);
        if (size < 0) return error.InvalidFlagValue;
        opts.max_alloc = @intCast(size);
        return;
    }
    if (std.mem.eql(u8, name, "sparse")) {
        opts.sparse_files = true;
        return;
    }
    if (std.mem.eql(u8, name, "preallocate")) {
        opts.preallocate_files = true;
        return;
    }
    if (std.mem.eql(u8, name, "inplace")) {
        opts.inplace = true;
        return;
    }
    if (std.mem.eql(u8, name, "append")) {
        opts.append_mode = .append;
        return;
    }
    if (std.mem.eql(u8, name, "append-verify")) {
        opts.append_mode = .append_verify;
        return;
    }
    if (std.mem.eql(u8, name, "del") or std.mem.eql(u8, name, "delete-during")) {
        opts.delete_during = .during;
        return;
    }
    if (std.mem.eql(u8, name, "delete")) {
        opts.delete_mode = true;
        return;
    }
    if (std.mem.eql(u8, name, "delete-before")) {
        opts.delete_before = true;
        return;
    }
    if (std.mem.eql(u8, name, "delete-delay")) {
        opts.delete_during = .delay;
        return;
    }
    if (std.mem.eql(u8, name, "delete-after")) {
        opts.delete_after = true;
        return;
    }
    if (std.mem.eql(u8, name, "delete-excluded")) {
        opts.delete_excluded = true;
        return;
    }
    if (std.mem.eql(u8, name, "delete-missing-args")) {
        opts.missing_args = .delete;
        return;
    }
    if (std.mem.eql(u8, name, "ignore-missing-args")) {
        opts.missing_args = .ignore;
        return;
    }
    if (std.mem.eql(u8, name, "remove-source-files") or std.mem.eql(u8, name, "remove-sent-files")) {
        opts.remove_source_files = .on;
        return;
    }
    if (std.mem.eql(u8, name, "force")) {
        opts.force_delete = true;
        return;
    }
    if (std.mem.eql(u8, name, "ignore-errors")) {
        opts.ignore_errors = true;
        return;
    }
    if (std.mem.eql(u8, name, "max-delete")) {
        const v = value orelse return error.MissingFlagValue;
        opts.max_delete = try parseIntFlag(v);
        return;
    }
    if (std.mem.eql(u8, name, "filter")) {
        const v = value orelse return error.MissingFlagValue;
        try appendList(allocator, &lists.filters, v);
        return;
    }
    if (std.mem.eql(u8, name, "exclude")) {
        const v = value orelse return error.MissingFlagValue;
        try appendList(allocator, &lists.excludes, v);
        return;
    }
    if (std.mem.eql(u8, name, "include")) {
        const v = value orelse return error.MissingFlagValue;
        try appendList(allocator, &lists.includes, v);
        return;
    }
    if (std.mem.eql(u8, name, "exclude-from")) {
        const v = value orelse return error.MissingFlagValue;
        try appendList(allocator, &lists.exclude_from, v);
        return;
    }
    if (std.mem.eql(u8, name, "include-from")) {
        const v = value orelse return error.MissingFlagValue;
        try appendList(allocator, &lists.include_from, v);
        return;
    }
    if (std.mem.eql(u8, name, "cvs-exclude")) {
        opts.cvs_exclude = true;
        return;
    }
    if (std.mem.eql(u8, name, "whole-file")) {
        opts.whole_file = .on;
        return;
    }
    if (std.mem.eql(u8, name, "checksum")) {
        opts.always_checksum = true;
        return;
    }
    if (std.mem.eql(u8, name, "checksum-choice")) {
        opts.checksum_choice = value orelse return error.MissingFlagValue;
        return;
    }
    if (std.mem.eql(u8, name, "block-size")) {
        const v = value orelse return error.MissingFlagValue;
        const size = try parseSizeFlag(v);
        if (size < 0 or size > std.math.maxInt(i32)) return error.InvalidFlagValue;
        opts.block_size = @intCast(size);
        return;
    }
    if (std.mem.eql(u8, name, "compare-dest")) {
        const v = value orelse return error.MissingFlagValue;
        try addBasisDir(opts, .compare, v);
        return;
    }
    if (std.mem.eql(u8, name, "copy-dest")) {
        const v = value orelse return error.MissingFlagValue;
        try addBasisDir(opts, .copy, v);
        return;
    }
    if (std.mem.eql(u8, name, "link-dest")) {
        const v = value orelse return error.MissingFlagValue;
        try addBasisDir(opts, .link, v);
        return;
    }
    if (std.mem.eql(u8, name, "fuzzy")) {
        opts.fuzzy_basis = 1;
        return;
    }
    if (std.mem.eql(u8, name, "compress")) {
        opts.compress = true;
        return;
    }
    if (std.mem.eql(u8, name, "old-compress")) {
        opts.compress = true;
        opts.compress_choice = "zlib";
        return;
    }
    if (std.mem.eql(u8, name, "new-compress")) {
        opts.compress = true;
        opts.compress_choice = "zlibx";
        return;
    }
    if (std.mem.eql(u8, name, "compress-choice")) {
        opts.compress_choice = value orelse return error.MissingFlagValue;
        opts.compress = true;
        return;
    }
    if (std.mem.eql(u8, name, "skip-compress")) {
        opts.skip_compress = value orelse return error.MissingFlagValue;
        return;
    }
    if (std.mem.eql(u8, name, "compress-level")) {
        const v = value orelse return error.MissingFlagValue;
        opts.compress_level = try parseIntFlag(v);
        return;
    }
    if (std.mem.eql(u8, name, "compress-threads")) {
        const v = value orelse return error.MissingFlagValue;
        opts.compress_threads = try parseIntFlag(v);
        return;
    }
    if (std.mem.eql(u8, name, "progress")) {
        opts.progress = true;
        return;
    }
    if (std.mem.eql(u8, name, "partial")) {
        opts.keep_partial = true;
        return;
    }
    if (std.mem.eql(u8, name, "partial-dir")) {
        opts.partial_dir = value orelse return error.MissingFlagValue;
        opts.keep_partial = true;
        return;
    }
    if (std.mem.eql(u8, name, "delay-updates")) {
        opts.delay_updates = true;
        return;
    }
    if (std.mem.eql(u8, name, "prune-empty-dirs")) {
        opts.prune_empty_dirs = true;
        return;
    }
    if (std.mem.eql(u8, name, "log-file")) {
        opts.logfile_name = value orelse return error.MissingFlagValue;
        return;
    }
    if (std.mem.eql(u8, name, "log-file-format")) {
        opts.logfile_format = value orelse return error.MissingFlagValue;
        return;
    }
    if (std.mem.eql(u8, name, "out-format")) {
        opts.stdout_format = value orelse return error.MissingFlagValue;
        return;
    }
    if (std.mem.eql(u8, name, "itemize-changes")) {
        opts.itemize_changes = true;
        return;
    }
    if (std.mem.eql(u8, name, "bwlimit")) {
        const v = value orelse return error.MissingFlagValue;
        const size = try parseSizeFlag(v);
        if (size < 0) return error.InvalidFlagValue;
        opts.bwlimit = @intCast(@divTrunc(size + 512, 1024));
        return;
    }
    if (std.mem.eql(u8, name, "backup")) {
        opts.make_backups = true;
        return;
    }
    if (std.mem.eql(u8, name, "backup-dir")) {
        opts.backup_dir = value orelse return error.MissingFlagValue;
        opts.make_backups = true;
        return;
    }
    if (std.mem.eql(u8, name, "suffix")) {
        opts.backup_suffix = value orelse return error.MissingFlagValue;
        return;
    }
    if (std.mem.eql(u8, name, "list-only")) {
        opts.list_only = .on;
        return;
    }
    if (std.mem.eql(u8, name, "read-batch")) {
        opts.batch_name = value orelse return error.MissingFlagValue;
        opts.read_batch = true;
        return;
    }
    if (std.mem.eql(u8, name, "write-batch")) {
        opts.batch_name = value orelse return error.MissingFlagValue;
        opts.write_batch = true;
        return;
    }
    if (std.mem.eql(u8, name, "only-write-batch")) {
        opts.batch_name = value orelse return error.MissingFlagValue;
        opts.write_batch = true;
        return;
    }
    if (std.mem.eql(u8, name, "files-from")) {
        opts.files_from = value orelse return error.MissingFlagValue;
        return;
    }
    if (std.mem.eql(u8, name, "from0")) {
        opts.eol_nulls = true;
        return;
    }
    if (std.mem.eql(u8, name, "old-args")) {
        opts.old_style_args = .on;
        return;
    }
    if (std.mem.eql(u8, name, "secluded-args")) {
        opts.protect_args = .on;
        return;
    }
    if (std.mem.eql(u8, name, "trust-sender")) {
        opts.trust_sender = true;
        return;
    }
    if (std.mem.eql(u8, name, "numeric-ids")) {
        opts.numeric_ids = true;
        return;
    }
    if (std.mem.eql(u8, name, "usermap")) {
        opts.usermap = value orelse return error.MissingFlagValue;
        return;
    }
    if (std.mem.eql(u8, name, "groupmap")) {
        opts.groupmap = value orelse return error.MissingFlagValue;
        return;
    }
    if (std.mem.eql(u8, name, "chown")) {
        opts.chown = value orelse return error.MissingFlagValue;
        return;
    }
    if (std.mem.eql(u8, name, "timeout")) {
        const v = value orelse return error.MissingFlagValue;
        opts.io_timeout = try parseIntFlag(v);
        return;
    }
    if (std.mem.eql(u8, name, "contimeout")) {
        const v = value orelse return error.MissingFlagValue;
        opts.connect_timeout = try parseIntFlag(v);
        return;
    }
    if (std.mem.eql(u8, name, "fsync")) {
        opts.do_fsync = true;
        return;
    }
    if (std.mem.eql(u8, name, "rsh")) {
        opts.shell_cmd = value orelse return error.MissingFlagValue;
        return;
    }
    if (std.mem.eql(u8, name, "rsync-path")) {
        opts.rsync_path = value orelse return error.MissingFlagValue;
        return;
    }
    if (std.mem.eql(u8, name, "temp-dir")) {
        opts.tmpdir = value orelse return error.MissingFlagValue;
        return;
    }
    if (std.mem.eql(u8, name, "iconv")) {
        opts.iconv = value orelse return error.MissingFlagValue;
        return;
    }
    if (std.mem.eql(u8, name, "no-iconv")) {
        opts.iconv = null;
        return;
    }
    if (std.mem.eql(u8, name, "ipv4")) {
        opts.address_family = .ipv4;
        return;
    }
    if (std.mem.eql(u8, name, "ipv6")) {
        opts.address_family = .ipv6;
        return;
    }
    if (std.mem.eql(u8, name, "8-bit-output")) {
        opts.allow_8bit_output = true;
        return;
    }
    if (std.mem.eql(u8, name, "mkpath")) {
        opts.mkpath_dest_arg = true;
        return;
    }
    if (std.mem.eql(u8, name, "qsort")) {
        opts.use_qsort = true;
        return;
    }
    if (std.mem.eql(u8, name, "copy-as")) {
        opts.copy_as = value orelse return error.MissingFlagValue;
        return;
    }
    if (std.mem.eql(u8, name, "address")) {
        opts.bind_address = value orelse return error.MissingFlagValue;
        return;
    }
    if (std.mem.eql(u8, name, "port")) {
        const v = value orelse return error.MissingFlagValue;
        opts.rsync_port = try parseIntFlag(v);
        return;
    }
    if (std.mem.eql(u8, name, "sockopts")) {
        opts.sockopts = value orelse return error.MissingFlagValue;
        return;
    }
    if (std.mem.eql(u8, name, "password-file")) {
        opts.password_file = value orelse return error.MissingFlagValue;
        return;
    }
    if (std.mem.eql(u8, name, "early-input")) {
        opts.early_input_file = value orelse return error.MissingFlagValue;
        return;
    }
    if (std.mem.eql(u8, name, "blocking-io")) {
        opts.blocking_io = .on;
        return;
    }
    if (std.mem.eql(u8, name, "outbuf")) {
        const v = value orelse return error.MissingFlagValue;
        opts.outbuf_mode = try parseOutbuf(v);
        return;
    }
    if (std.mem.eql(u8, name, "remote-option")) {
        const v = value orelse return error.MissingFlagValue;
        if (v.len == 0 or v[0] != '-') return error.InvalidFlagValue;
        try appendList(allocator, &lists.remote_options, v);
        return;
    }
    if (std.mem.eql(u8, name, "protocol")) {
        const v = value orelse return error.MissingFlagValue;
        opts.protocol_version = try parseIntFlag(v);
        return;
    }
    if (std.mem.eql(u8, name, "checksum-seed")) {
        const v = value orelse return error.MissingFlagValue;
        opts.checksum_seed = try parseIntFlag(v);
        return;
    }
    if (std.mem.eql(u8, name, "stderr")) {
        const v = value orelse return error.MissingFlagValue;
        opts.stderr_mode = try parseStderrMode(v);
        return;
    }
    if (std.mem.eql(u8, name, "msgs2stderr")) {
        opts.stderr_mode = .all;
        return;
    }
    return error.InvalidFlagName;
}

fn applyShortFlag(
    allocator: std.mem.Allocator,
    opts: *ReflectOptions,
    lists: *ParseLists,
    flag: u8,
    value: ?[]const u8,
) ParseError!void {
    switch (flag) {
        'a' => opts.applyArchive(),
        'b' => opts.make_backups = true,
        'c' => opts.always_checksum = true,
        'd' => opts.xfer_dirs = .dirs,
        'D' => {
            opts.preserve_devices = true;
            opts.preserve_specials = true;
        },
        'e' => opts.shell_cmd = value orelse return error.MissingFlagValue,
        'E' => opts.preserve_executability = true,
        'f' => try appendList(allocator, &lists.filters, value orelse return error.MissingFlagValue),
        'g' => opts.preserve_gid = true,
        'h' => opts.human_readable = true,
        'H' => opts.preserve_hard_links = true,
        'i' => opts.itemize_changes = true,
        'I' => opts.ignore_times = true,
        'k' => opts.copy_dirlinks = true,
        'K' => opts.keep_dirlinks = true,
        'l' => opts.preserve_links = true,
        'L' => opts.copy_links = true,
        'm' => opts.prune_empty_dirs = true,
        'M' => {
            const v = value orelse return error.MissingFlagValue;
            if (v.len == 0 or v[0] != '-') return error.InvalidFlagValue;
            try appendList(allocator, &lists.remote_options, v);
        },
        'n' => opts.dry_run = true,
        'o' => opts.preserve_uid = true,
        'p' => opts.preserve_perms = true,
        'P' => opts.applyProgressPartial(),
        'q' => opts.quiet = true,
        'r' => opts.recurse = .on,
        'R' => opts.relative_paths = .on,
        's' => opts.protect_args = .on,
        'S' => opts.sparse_files = true,
        't' => opts.preserve_mtimes = true,
        'T' => opts.tmpdir = value orelse return error.MissingFlagValue,
        'u' => opts.update_only = true,
        'U' => opts.preserve_atimes = true,
        'v' => opts.verbose +|= 1,
        'V' => opts.version = true,
        'W' => opts.whole_file = .on,
        'x' => opts.one_file_system = true,
        'y' => opts.fuzzy_basis = 1,
        'z' => opts.compress = true,
        'A' => {
            opts.preserve_acls = true;
            opts.preserve_perms = true;
        },
        'B' => {
            const v = value orelse return error.MissingFlagValue;
            const size = try parseSizeFlag(v);
            if (size < 0 or size > std.math.maxInt(i32)) return error.InvalidFlagValue;
            opts.block_size = @intCast(size);
        },
        'C' => opts.cvs_exclude = true,
        'F' => {
            opts.f_option_count +|= 1;
            switch (opts.f_option_count) {
                1 => try appendList(allocator, &lists.filters, ": /.rsync-filter"),
                2 => try appendList(allocator, &lists.filters, "- .rsync-filter"),
                else => return error.InvalidFlagValue,
            }
        },
        'J' => opts.omit_link_times = true,
        'N' => opts.preserve_crtimes = true,
        'O' => opts.omit_dir_times = true,
        'X' => opts.preserve_xattrs = true,
        '0' => opts.eol_nulls = true,
        '4' => opts.address_family = .ipv4,
        '6' => opts.address_family = .ipv6,
        '8' => opts.allow_8bit_output = true,
        '@' => {
            const v = value orelse return error.MissingFlagValue;
            opts.modify_window = try parseIntFlag(v);
            opts.modify_window_set = true;
        },
        else => return error.InvalidFlagName,
    }
}

fn finalizeOptions(opts: *ReflectOptions) void {
    if (opts.stats) {
        opts.info_levels[@intFromEnum(InfoFlag.stats)] = if (opts.verbose > 1) 3 else 2;
    }
    if (opts.progress) {
        opts.info_levels[@intFromEnum(InfoFlag.progress)] = 1;
    }
    if (opts.fuzzy_basis > 0 and opts.basis_dir_count > 0) {
        opts.fuzzy_basis = @intCast(opts.basis_dir_count + 1);
    }
}

/// Parse command-line arguments into options plus source/destination paths.
pub fn parse(allocator: std.mem.Allocator, args: []const [:0]const u8) ParseResult {
    var opts = ReflectOptions.defaults();
    var lists = ParseLists.init();
    var positional = std.ArrayList([]const u8).empty;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.startsWith(u8, arg, "--")) {
            const name = flagName(arg);
            const inline_value: ?[]const u8 = if (std.mem.indexOf(u8, arg, "=")) |eq|
                arg[eq + 1 ..]
            else
                null;

            var value = inline_value;
            if (value == null and longFlagNeedsValue(name)) {
                i += 1;
                if (i >= args.len) {
                    return .{ .err = .{ .code = error.MissingFlagValue, .raw_arg = arg } };
                }
                value = args[i];
            }

            applyLongFlag(allocator, &opts, &lists, name, value) catch |err| {
                return .{ .err = .{ .code = err, .raw_arg = arg } };
            };
        } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
            if (std.mem.indexOf(u8, arg, "=") != null) {
                return .{ .err = .{ .code = error.ShortFlagDoesntAcceptValue, .raw_arg = arg } };
            }

            var j: usize = 1;
            while (j < arg.len) {
                const flag = arg[j];
                j += 1;

                if (shortFlagNeedsValue(flag)) {
                    const attached = if (j < arg.len) arg[j..] else blk: {
                        i += 1;
                        if (i >= args.len) {
                            return .{ .err = .{ .code = error.MissingFlagValue, .raw_arg = arg } };
                        }
                        break :blk args[i];
                    };
                    applyShortFlag(allocator, &opts, &lists, flag, attached) catch |err| {
                        return .{ .err = .{ .code = err, .raw_arg = arg } };
                    };
                    break;
                }

                applyShortFlag(allocator, &opts, &lists, flag, null) catch |err| {
                    return .{ .err = .{ .code = err, .raw_arg = arg } };
                };
            }
        } else {
            positional.append(allocator, arg) catch {
                return .{ .err = .{ .code = error.OutOfMemory, .raw_arg = arg } };
            };
        }
    }

    if (opts.help) {
        std.debug.print("{s}", .{help_text});
        return .{ .ok = .{
            .options = opts,
            .sources = &.{},
            .destination = null,
        } };
    }

    if (opts.version) {
        std.debug.print("reflect version: {s}\n", .{build_options.version});
        return .{ .ok = .{
            .options = opts,
            .sources = &.{},
            .destination = null,
        } };
    }

    lists.finish(&opts);
    finalizeOptions(&opts);

    const destination: ?[]const u8 = if (positional.items.len > 0)
        positional.items[positional.items.len - 1]
    else
        null;
    const sources: []const []const u8 = if (positional.items.len > 1)
        positional.items[0 .. positional.items.len - 1]
    else
        &.{};

    return .{ .ok = .{
        .options = opts,
        .sources = sources,
        .destination = destination,
    } };
}

test "parse short flags and positional args" {
    const gpa = std.testing.allocator;
    const result = parse(gpa, &.{ "-avn", "src/", "dest/" });
    const parsed = switch (result) {
        .ok => |p| p,
        .err => |e| std.debug.panic("parse failed: {s}", .{@errorName(e.code)}),
    };
    try std.testing.expect(parsed.options.dry_run);
    try std.testing.expect(parsed.options.preserve_links);
    try std.testing.expectEqual(@as(RecurseMode, .archive), parsed.options.recurse);
    try std.testing.expectEqual(@as(usize, 1), parsed.sources.len);
    try std.testing.expectEqualStrings("src/", parsed.sources[0]);
    try std.testing.expectEqualStrings("dest/", parsed.destination.?);
}

test "parse long flag with equals value" {
    const gpa = std.testing.allocator;
    const result = parse(gpa, &.{ "--exclude=*.o", "src/", "dest/" });
    const parsed = switch (result) {
        .ok => |p| p,
        .err => |e| std.debug.panic("parse failed: {s}", .{@errorName(e.code)}),
    };
    try std.testing.expectEqual(@as(usize, 1), parsed.options.excludes.len);
    try std.testing.expectEqualStrings("*.o", parsed.options.excludes[0]);
}

test "parse rejects unknown flag" {
    const gpa = std.testing.allocator;
    const result = parse(gpa, &.{ "--not-a-flag", "src/", "dest/" });
    try std.testing.expect(result == .err);
    if (result == .err) {
        try std.testing.expectEqual(error.InvalidFlagName, result.err.code);
    }
}
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
