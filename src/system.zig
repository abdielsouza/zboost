const std = @import("std");

/// Represents the command-line arguments passed to the program.
/// This struct provides methods to access individual arguments, get the total number of arguments, and iterate over them.
///
/// Example usage:
/// ```zig
/// const std = @import("std");
/// const system = @import("system.zig");
/// const argv = system.Argv.init(std.process.args());
///
/// // Accessing individual arguments
/// const firstArg = argv.get(0);
/// if (firstArg) |arg| {
///     std.debug.print("First argument: {s}\n", .{arg});
/// }
///
/// // Getting the total number of arguments
/// const argCount = argv.len();
/// std.debug.print("Total arguments: {d}\n", .{argCount});
///
/// // Iterating over arguments
/// for (argv.iter()) |arg| {
///     std.debug.print("Argument: {s}\n", .{arg});
/// }
/// ```
///
/// This struct is designed to be simple and efficient, providing a convenient interface for working with command-line arguments in Zig programs.
pub const Argv = struct {
    args: []const []const u8,

    /// Creates an Argv instance from a raw argument slice.
    pub fn init(args: []const []const u8) Argv {
        return Argv{
            .args = args,
        };
    }

    /// Creates an Argv instance using the current process arguments.
    pub fn initDefault() Argv {
        return Argv{
            .args = std.process.args(),
        };
    }

    /// Returns the argument at `index`, or `null` if the index is out of range.
    pub fn get(self: *Argv, index: usize) ?[]const u8 {
        if (index >= self.args.len) {
            return null;
        }
        return self.args[index];
    }

    /// Returns the number of command-line arguments.
    pub fn len(self: *Argv) usize {
        return self.args.len;
    }

    /// Returns an iterator over the argument list.
    pub fn iter(self: *Argv) std.mem.Iterator([]const u8) {
        return std.mem.Iterator(self.args);
    }
};

/// Provides functionality to load, read, and manipulate .env files dynamically.
/// This struct allows loading environment variables from a .env file, accessing them, modifying them, and saving changes back to the file.
///
/// Example usage:
/// ```zig
/// const std = @import("std");
/// const system = @import("system.zig");
///
/// var env = system.Env.init(std.heap.page_allocator);
/// defer env.deinit();
///
/// // Load from .env file
/// try env.loadFromFile(".env");
///
/// // Get a value
/// if (env.get("DATABASE_URL")) |url| {
///     std.debug.print("DB URL: {s}\n", .{url});
/// }
///
/// // Set a new variable
/// try env.set("API_KEY", "secret123");
///
/// // Save back to file
/// try env.saveToFile(".env");
/// ```
pub const Env = struct {
    allocator: std.mem.Allocator,
    variables: std.StringHashMap([]const u8),

    /// Creates an Env instance that stores .env variables in memory.
    pub fn init(allocator: std.mem.Allocator) Env {
        return Env{
            .allocator = allocator,
            .variables = std.StringHashMap([]const u8).init(allocator),
        };
    }

    /// Releases all memory used by the Env instance.
    pub fn deinit(self: *Env) void {
        var it = self.variables.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.variables.deinit();
    }

    /// Loads variables from a `.env` file into memory.
    pub fn loadFromFile(self: *Env, file_path: []const u8) !void {
        const file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();

        var buf_reader = std.io.bufferedReader(file.reader());
        var in_stream = buf_reader.reader();

        var buf: [1024]u8 = undefined;
        while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
            const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
            if (trimmed.len == 0 or trimmed[0] == '#') continue;

            if (std.mem.indexOf(u8, trimmed, "=")) |eq_pos| {
                const key = std.mem.trim(u8, trimmed[0..eq_pos], &std.ascii.whitespace);
                const value = std.mem.trim(u8, trimmed[eq_pos + 1 ..], &std.ascii.whitespace);

                const key_dup = try self.allocator.dupe(u8, key);
                const value_dup = try self.allocator.dupe(u8, value);

                try self.variables.put(key_dup, value_dup);
            }
        }
    }

    /// Returns the value for `key` or `null` if the variable is absent.
    pub fn get(self: *Env, key: []const u8) ?[]const u8 {
        return self.variables.get(key);
    }

    /// Adds or updates a variable in memory.
    pub fn set(self: *Env, key: []const u8, value: []const u8) !void {
        const key_dup = try self.allocator.dupe(u8, key);
        const value_dup = try self.allocator.dupe(u8, value);

        if (self.variables.fetchPut(key_dup, value_dup)) |old| {
            self.allocator.free(old.key);
            self.allocator.free(old.value);
        }
    }

    /// Removes a variable by `key` and returns `true` if removed.
    pub fn remove(self: *Env, key: []const u8) bool {
        if (self.variables.fetchRemove(key)) |kv| {
            self.allocator.free(kv.key);
            self.allocator.free(kv.value);
            return true;
        }
        return false;
    }

    /// Writes all loaded variables to a `.env` file.
    pub fn saveToFile(self: *Env, file_path: []const u8) !void {
        const file = try std.fs.cwd().createFile(file_path, .{});
        defer file.close();

        var it = self.variables.iterator();
        while (it.next()) |entry| {
            try file.writer().print("{s}={s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
    }

    /// Returns an iterator over the loaded environment variables.
    pub fn iterator(self: *Env) std.StringHashMap([]const u8).Iterator {
        return self.variables.iterator();
    }
};

/// Provides functionality for file system operations such as checking file existence, creating/removing directories,
/// listing directory contents, and file management operations.
///
/// Example usage:
/// ```zig
/// const std = @import("std");
/// const system = @import("system.zig");
///
/// var fs = system.FileSystem.init(std.heap.page_allocator);
/// defer fs.deinit();
///
/// // Check if file exists
/// if (try fs.exists("data.txt")) {
///     std.debug.print("File exists\n", .{});
/// }
///
/// // Create a directory
/// try fs.createDir("output");
///
/// // List directory contents
/// var entries = try fs.listDir("output");
/// defer entries.deinit();
/// for (entries.items) |entry| {
///     std.debug.print("Entry: {s}\n", .{entry.name});
/// }
///
/// // Copy a file
/// try fs.copy("input.txt", "output.txt");
///
/// // Get file size
/// const size = try fs.getSize("output.txt");
/// std.debug.print("File size: {d} bytes\n", .{size});
/// ```
pub const FileSystem = struct {
    allocator: std.mem.Allocator,

    /// Creates a new FileSystem helper instance.
    pub fn init(allocator: std.mem.Allocator) FileSystem {
        return FileSystem{
            .allocator = allocator,
        };
    }

    /// No-op deinit for FileSystem.
    pub fn deinit(_: *FileSystem) void {}

    /// Returns `true` when the path exists.
    pub fn exists(self: *FileSystem, path: []const u8) !bool {
        _ = self;
        _ = std.fs.cwd().statFile(path) catch |err| {
            if (err == error.FileNotFound) {
                return false;
            }
            return err;
        };
        return true;
    }

    /// Returns `true` if the path points to a regular file.
    pub fn isFile(self: *FileSystem, path: []const u8) !bool {
        _ = self;
        const stat = try std.fs.cwd().statFile(path);
        return stat.kind == .file;
    }

    /// Returns `true` if the path points to a directory.
    pub fn isDir(self: *FileSystem, path: []const u8) !bool {
        _ = self;
        const stat = try std.fs.cwd().statFile(path);
        return stat.kind == .directory;
    }

    /// Creates a directory at the given path.
    pub fn createDir(self: *FileSystem, path: []const u8) !void {
        _ = self;
        try std.fs.cwd().makeDir(path);
    }

    /// Creates directories recursively for the given path.
    pub fn createDirRecursive(self: *FileSystem, path: []const u8) !void {
        _ = self;
        try std.fs.cwd().makePath(path);
    }

    /// Removes an empty directory.
    pub fn removeDir(self: *FileSystem, path: []const u8) !void {
        _ = self;
        try std.fs.cwd().deleteDir(path);
    }

    /// Removes a directory and all its contents.
    pub fn removeDirRecursive(self: *FileSystem, path: []const u8) !void {
        _ = self;
        try std.fs.cwd().deleteTree(path);
    }

    /// Removes a file.
    pub fn remove(self: *FileSystem, path: []const u8) !void {
        _ = self;
        try std.fs.cwd().deleteFile(path);
    }

    /// Copies a file from `src` to `dest`.
    pub fn copy(self: *FileSystem, src: []const u8, dest: []const u8) !void {
        _ = self;
        const src_file = try std.fs.cwd().openFile(src, .{});
        defer src_file.close();

        const dest_file = try std.fs.cwd().createFile(dest, .{});
        defer dest_file.close();

        var buf: [8192]u8 = undefined;
        while (true) {
            const bytes_read = try src_file.read(&buf);
            if (bytes_read == 0) break;
            try dest_file.writeAll(buf[0..bytes_read]);
        }
    }

    /// Returns the size of the file at `path`.
    pub fn getSize(self: *FileSystem, path: []const u8) !u64 {
        _ = self;
        const stat = try std.fs.cwd().statFile(path);
        return stat.size;
    }

    pub const DirEntry = struct {
        name: []const u8,
        kind: std.fs.File.Kind,
    };

    /// Lists entries for a directory path.
    pub fn listDir(self: *FileSystem, path: []const u8) !std.ArrayList(DirEntry) {
        var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
        defer dir.close();

        var entries = try std.ArrayList(DirEntry).initCapacity(self.allocator, 0);
        var iter = dir.iterate();

        while (try iter.next()) |entry| {
            const name_dup = try self.allocator.dupe(u8, entry.name);
            try entries.append(self.allocator, DirEntry{
                .name = name_dup,
                .kind = entry.kind,
            });
        }

        return entries;
    }
};

/// Provides utility functions for path manipulation such as joining paths, extracting components,
/// and handling common path operations.
///
/// Example usage:
/// ```zig
/// const std = @import("std");
/// const system = @import("system.zig");
///
/// var path = system.Path.init(std.heap.page_allocator);
/// defer path.deinit();
///
/// // Join paths
/// const full_path = try path.join(&.{ "home", "user", "documents" });
/// std.debug.print("Path: {s}\n", .{full_path});
///
/// // Get file name
/// const name = path.getFileName("/home/user/file.txt");
/// std.debug.print("File: {s}\n", .{name});
///
/// // Get directory
/// const dir = path.getDirectory("/home/user/file.txt");
/// std.debug.print("Dir: {s}\n", .{dir});
///
/// // Get home directory
/// if (try path.getHome()) |home| {
///     std.debug.print("Home: {s}\n", .{home});
/// }
/// ```
pub const Path = struct {
    allocator: std.mem.Allocator,

    /// Creates a new Path helper instance.
    pub fn init(allocator: std.mem.Allocator) Path {
        return Path{
            .allocator = allocator,
        };
    }

    /// No-op deinit for Path.
    pub fn deinit(_: *Path) void {}

    /// Joins multiple path components into a single path string.
    pub fn join(self: *Path, components: []const []const u8) ![]const u8 {
        return try std.fs.path.join(self.allocator, components);
    }

    /// Returns the basename of the given path.
    pub fn getFileName(file_path: []const u8) []const u8 {
        return std.fs.path.basename(file_path);
    }

    /// Returns the directory portion of the given path.
    pub fn getDirectory(file_path: []const u8) []const u8 {
        return std.fs.path.dirname(file_path) orelse ".";
    }

    /// Returns the current user's home directory, if available.
    pub fn getHome(self: *Path) !?[]const u8 {
        return try self.allocator.dupe(u8, try Path.getHomeDir());
    }

    fn getHomeDir() ![]const u8 {
        if (std.posix.getenv("HOME")) |home| {
            return home;
        }
        return error.HomeDirectoryNotFound;
    }

    /// Returns the system temporary directory.
    pub fn getTempDir(self: *Path) ![]const u8 {
        if (std.posix.getenv("TMPDIR")) |tmpdir| {
            return try self.allocator.dupe(u8, tmpdir);
        }
        if (std.posix.getenv("TMP")) |tmp| {
            return try self.allocator.dupe(u8, tmp);
        }
        return try self.allocator.dupe(u8, "/tmp");
    }

    /// Returns the absolute form of the provided path.
    pub fn getAbsolute(self: *Path, file_path: []const u8) ![]const u8 {
        if (std.fs.path.isAbsolute(file_path)) {
            return try self.allocator.dupe(u8, file_path);
        }

        const cwd = try std.fs.cwd().realpathAlloc(self.allocator, ".");
        defer self.allocator.free(cwd);

        return try std.fs.path.join(self.allocator, &.{ cwd, file_path });
    }

    /// Normalizes a path by resolving `.` and `..` segments.
    pub fn normalize(self: *Path, file_path: []const u8) ![]const u8 {
        return try self.allocator.dupe(u8, std.fs.path.resolve(self.allocator, &.{file_path}) catch |e| return e);
    }
};

/// Provides utilities for the current process, such as working directory control, PID access,
/// user identification, and sleep/exit helpers.
///
/// Example usage:
/// ```zig
/// const std = @import("std");
/// const system = @import("system.zig");
///
/// var process = system.Process.init(std.heap.page_allocator);
/// defer process.deinit();
///
/// const cwd = try process.getWorkingDir();
/// std.debug.print("CWD: {s}\n", .{cwd});
/// process.allocator.free(cwd);
///
/// std.debug.print("PID: {d}\n", .{@intCast(usize, process.getPid())});
/// try process.sleep(1);
/// ```
pub const Process = struct {
    allocator: std.mem.Allocator,

    /// Creates a new Process helper instance.
    pub fn init(allocator: std.mem.Allocator) Process {
        return Process{
            .allocator = allocator,
        };
    }

    /// No-op deinit for Process.
    pub fn deinit(_: *Process) void {}

    /// Returns the current working directory.
    pub fn getWorkingDir(self: *Process) ![]const u8 {
        const cwd = try std.fs.cwd().realpathAlloc(self.allocator, ".");
        return cwd;
    }

    /// Sets the current working directory.
    pub fn setWorkingDir(self: *Process, path: []const u8) !void {
        _ = self;
        try std.fs.cwd().chdir(path);
    }

    /// Returns the current process ID.
    pub fn getPid(self: *Process) usize {
        _ = self;
        return @intCast(std.os.linux.getpid());
    }

    /// Returns the current user name from the environment, if available.
    pub fn getCurrentUser(self: *Process) !?[]const u8 {
        if (std.posix.getenv("USER")) |user| {
            return try self.allocator.dupe(u8, user);
        }
        if (std.posix.getenv("USERNAME")) |user| {
            return try self.allocator.dupe(u8, user);
        }
        return null;
    }

    /// Sleeps for the given number of seconds.
    pub fn sleep(self: *Process, seconds: u64) !void {
        _ = self;
        try std.time.sleep(std.time.ns_per_s * seconds);
    }

    /// Terminates the current process with the provided exit code.
    pub fn exit(self: *Process, code: i32) noreturn {
        _ = self;
        std.os.exit(code);
    }
};

/// Provides basic information about the host operating system and runtime environment.
///
/// Example usage:
/// ```zig
/// const std = @import("std");
/// const system = @import("system.zig");
///
/// var info = system.SystemInfo.init(std.heap.page_allocator);
/// defer info.deinit();
///
/// const hostname = try info.getHostname();
/// std.debug.print("Hostname: {s}\n", .{hostname});
/// info.allocator.free(hostname);
///
/// std.debug.print("OS: {s}\n", .{info.getOsType()});
/// std.debug.print("CPU cores: {d}\n", .{info.getCpuCount()});
/// ```
pub const SystemInfo = struct {
    allocator: std.mem.Allocator,

    /// Creates a new SystemInfo helper instance.
    pub fn init(allocator: std.mem.Allocator) SystemInfo {
        return SystemInfo{
            .allocator = allocator,
        };
    }

    /// No-op deinit for SystemInfo.
    pub fn deinit(_: *SystemInfo) void {}

    /// Returns the hostname of the machine, or "unknown" if it is not set.
    pub fn getHostname(self: *SystemInfo) ![]const u8 {
        if (std.posix.getenv("HOSTNAME")) |hostname| {
            return try self.allocator.dupe(u8, hostname);
        }
        if (std.posix.getenv("COMPUTERNAME")) |hostname| {
            return try self.allocator.dupe(u8, hostname);
        }
        return try self.allocator.dupe(u8, "unknown");
    }

    /// Returns the operating system type as a string.
    pub fn getOsType(self: *SystemInfo) []const u8 {
        _ = self;
        return switch (@import("builtin").os.tag) {
            .linux => "linux",
            .macos => "macos",
            .windows => "windows",
            .freebsd => "freebsd",
            .openbsd => "openbsd",
            .netbsd => "netbsd",
            .dragonfly => "dragonfly",
            .illumos => "illumos",
            .zos => "zos",
            else => "unknown",
        };
    }

    /// Returns the architecture type as a string.
    pub fn getArchitecture(self: *SystemInfo) []const u8 {
        _ = self;
        return switch (@import("builtin").cpu.arch) {
            .x86 => "x86",
            .x86_64 => "x86_64",
            .arm => "arm",
            .aarch64 => "aarch64",
            .riscv32 => "riscv32",
            .riscv64 => "riscv64",
            .mips => "mips",
            .mips64 => "mips64",
            .powerpc => "powerpc",
            .powerpc64 => "powerpc64",
            .s390x => "s390x",
            else => "unknown",
        };
    }

    /// Returns the number of available CPU cores.
    pub fn getCpuCount(self: *SystemInfo) !usize {
        _ = self;
        return try std.Thread.getCpuCount();
    }
};

test "Argv basic functionality" {
    const args = &.{ "program", "arg1", "arg2" };
    var argv = Argv.init(args);

    try std.testing.expect(argv.len() == 3);
    try std.testing.expect(std.mem.eql(u8, argv.get(0).?, "program"));
    try std.testing.expect(std.mem.eql(u8, argv.get(1).?, "arg1"));
    try std.testing.expect(std.mem.eql(u8, argv.get(2).?, "arg2"));
    try std.testing.expect(argv.get(3) == null);
}

test "FileSystem utilities" {
    const allocator = std.heap.page_allocator;
    var fs = FileSystem.init(allocator);

    var path_buf: [64]u8 = undefined;
    const temp_dir = try std.fmt.bufPrint(&path_buf, ".zboost_test_{d}", .{@as(usize, @intCast(std.os.linux.getpid()))});
    defer fs.removeDirRecursive(temp_dir) catch {};

    try fs.createDir(temp_dir);

    const source_file = try std.fs.path.join(allocator, &.{ temp_dir, "source.txt" });
    defer allocator.free(source_file);
    const dest_file = try std.fs.path.join(allocator, &.{ temp_dir, "copy.txt" });
    defer allocator.free(dest_file);

    const file = try std.fs.cwd().createFile(source_file, .{ .truncate = true });
    defer file.close();
    try file.writeAll("hello");

    try std.testing.expect(try fs.exists(source_file));
    try std.testing.expect(try fs.isFile(source_file));
    try std.testing.expect(!try fs.isDir(source_file));
    try std.testing.expect(try fs.getSize(source_file) == 5);

    try fs.copy(source_file, dest_file);
    try std.testing.expect(try fs.exists(dest_file));
    try std.testing.expect(try fs.isFile(dest_file));

    var entries = try fs.listDir(temp_dir);
    defer {
        for (entries.items) |entry| allocator.free(entry.name);
        entries.deinit(allocator);
    }

    var found_source = false;
    var found_copy = false;
    for (entries.items) |entry| {
        if (std.mem.eql(u8, entry.name, "source.txt")) found_source = true;
        if (std.mem.eql(u8, entry.name, "copy.txt")) found_copy = true;
    }

    try std.testing.expect(found_source);
    try std.testing.expect(found_copy);

    try fs.remove(dest_file);
    try std.testing.expect(!try fs.exists(dest_file));
}

test "Path utilities" {
    var path = Path.init(std.heap.page_allocator);
    defer path.deinit();

    const joined = try path.join(&.{ "tmp", "sub", "file.txt" });
    defer std.heap.page_allocator.free(joined);
    try std.testing.expect(std.mem.eql(u8, joined, "tmp/sub/file.txt"));

    try std.testing.expect(std.mem.eql(u8, Path.getFileName("a/b/c.txt"), "c.txt"));
    try std.testing.expect(std.mem.eql(u8, Path.getDirectory("a/b/c.txt"), "a/b"));

    const abs = try path.getAbsolute("system.zig");
    defer std.heap.page_allocator.free(abs);
    try std.testing.expect(std.fs.path.isAbsolute(abs));

    const temp_dir = try path.getTempDir();
    defer std.heap.page_allocator.free(temp_dir);
    try std.testing.expect(temp_dir.len > 0);
}

test "Process utilities" {
    var process = Process.init(std.heap.page_allocator);
    defer process.deinit();

    try std.testing.expect(process.getPid() == std.os.linux.getpid());

    const cwd = try process.getWorkingDir();
    defer std.heap.page_allocator.free(cwd);
    const real_cwd = try std.fs.cwd().realpathAlloc(std.heap.page_allocator, ".");
    defer std.heap.page_allocator.free(real_cwd);
    try std.testing.expect(std.mem.eql(u8, cwd, real_cwd));

    if (std.posix.getenv("USER")) |user| {
        const current = try process.getCurrentUser();
        defer if (current) |c| std.heap.page_allocator.free(c);
        try std.testing.expect(std.mem.eql(u8, current.?, user));
    }
}

test "SystemInfo utilities" {
    var info = SystemInfo.init(std.heap.page_allocator);
    defer info.deinit();

    const hostname = try info.getHostname();
    defer std.heap.page_allocator.free(hostname);
    try std.testing.expect(hostname.len > 0);

    const os_type = info.getOsType();
    try std.testing.expect(os_type.len > 0);

    const arch = info.getArchitecture();
    try std.testing.expect(arch.len > 0);

    try std.testing.expect(try info.getCpuCount() > 0);
}
