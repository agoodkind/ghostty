const std = @import("std");
const Allocator = std.mem.Allocator;

const ScrollbackStore = @This();

alloc: Allocator,
file: std.fs.File,
path: []u8,
next_offset: u64 = 0,

pub const Record = struct {
    offset: u64,
    len: usize,
};

pub fn init(alloc: Allocator) !ScrollbackStore {
    var random_bytes: [16]u8 = undefined;
    const tmp_dir = temporaryDirectory();

    var attempt: usize = 0;
    while (attempt < 32) : (attempt += 1) {
        std.crypto.random.bytes(&random_bytes);
        const hex_name = std.fmt.bytesToHex(random_bytes, .lower);
        const file_name = try std.fmt.allocPrint(alloc, "ghostty-scrollback-{s}", .{hex_name});
        defer alloc.free(file_name);

        const path = try std.fs.path.join(alloc, &.{ tmp_dir, file_name });
        errdefer alloc.free(path);

        const file = std.fs.createFileAbsolute(path, .{
            .read = true,
            .truncate = true,
            .exclusive = true,
        }) catch |err| switch (err) {
            error.PathAlreadyExists => {
                alloc.free(path);
                continue;
            },
            else => |e| return e,
        };

        return .{
            .alloc = alloc,
            .file = file,
            .path = path,
        };
    }

    return error.PathAlreadyExists;
}

pub fn deinit(self: *ScrollbackStore) void {
    self.file.close();
    std.fs.deleteFileAbsolute(self.path) catch {};
    self.alloc.free(self.path);
    self.* = undefined;
}

pub fn write(self: *ScrollbackStore, bytes: []const u8) !Record {
    const offset = self.next_offset;
    try self.file.pwriteAll(bytes, offset);
    self.next_offset += bytes.len;
    return .{
        .offset = offset,
        .len = bytes.len,
    };
}

pub fn read(self: *ScrollbackStore, record: Record, bytes: []u8) !void {
    if (bytes.len != record.len) return error.InvalidRecordSize;
    const read_len = try self.file.preadAll(bytes, record.offset);
    if (read_len != bytes.len) return error.UnexpectedEof;
}

fn temporaryDirectory() []const u8 {
    if (std.posix.getenv("TMPDIR")) |path| {
        if (path.len > 0) return path;
    }

    if (std.posix.getenv("TMP")) |path| {
        if (path.len > 0) return path;
    }

    return "/tmp";
}
