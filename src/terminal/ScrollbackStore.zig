const std = @import("std");
const Allocator = std.mem.Allocator;
const osfile = @import("../os/file.zig");

const ScrollbackStore = @This();

alloc: Allocator,
file: std.fs.File,
path: []u8,
next_offset: u64 = 0,

pub const Record = struct {
    offset: u64,
    len: usize,
};

pub const ReadError = error{
    InvalidRecordSize,
    UnexpectedEof,
} || std.fs.File.PReadError;

pub fn init(alloc: Allocator) !ScrollbackStore {
    var attempt: usize = 0;
    while (attempt < 32) : (attempt += 1) {
        const path = try osfile.randomTmpPath(alloc, "ghostty-scrollback-");
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

pub fn read(self: *ScrollbackStore, record: Record, bytes: []u8) ReadError!void {
    if (bytes.len != record.len) return error.InvalidRecordSize;
    const read_len = try self.file.preadAll(bytes, record.offset);
    if (read_len != bytes.len) return error.UnexpectedEof;
}
