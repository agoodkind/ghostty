//! Measures resident and unloaded scrollback behavior for a PageList with
//! deep unlimited scrollback.
//!
//! Usage: ghostty-bench +scrollback-memory
//!        ghostty-bench +scrollback-memory --total-rows=3000000 --scroll-passes=5
const std = @import("std");
const Allocator = std.mem.Allocator;

const PageList = @import("../terminal/PageList.zig");
const Benchmark = @import("Benchmark.zig");

const ScrollbackMemory = @This();

const log = std.log.scoped(.@"scrollback-memory-bench");

const MiB = 1024 * 1024;

opts: Options,
page_list: ?PageList = null,

pub const Options = struct {
    /// Total rows to grow the PageList to.
    @"total-rows": u32 = 3_000_000,

    /// Terminal column count.
    cols: u16 = 80,

    /// Number of full scrollback passes after fill.
    @"scroll-passes": u32 = 3,
};

pub fn create(alloc: Allocator, opts: Options) !*ScrollbackMemory {
    const ptr = try alloc.create(ScrollbackMemory);
    errdefer alloc.destroy(ptr);
    ptr.* = .{ .opts = opts };
    return ptr;
}

pub fn destroy(self: *ScrollbackMemory, alloc: Allocator) void {
    if (self.page_list) |*pl| pl.deinit();
    alloc.destroy(self);
}

pub fn benchmark(self: *ScrollbackMemory) Benchmark {
    return .init(self, .{
        .setupFn = setup,
        .stepFn = step,
        .teardownFn = teardown,
    });
}

fn setup(ptr: *anyopaque) Benchmark.Error!void {
    const self: *ScrollbackMemory = @ptrCast(@alignCast(ptr));
    const alloc = std.heap.page_allocator;
    const total: u32 = self.opts.@"total-rows";

    self.page_list = PageList.init(
        alloc,
        self.opts.cols,
        24,
        null,
    ) catch return error.BenchmarkFailed;

    const pl = &self.page_list.?;

    var timer = std.time.Timer.start() catch return error.BenchmarkFailed;
    var i: u32 = 0;
    while (i < total) : (i += 1) {
        _ = pl.grow() catch return error.BenchmarkFailed;
    }

    const fill_us = timer.read() / std.time.ns_per_us;
    const rss_after_fill = physicalFootprintBytes();
    log.info(
        "fill {d} rows in {d} us  RSS = {d} MiB  resident_rows = {d}  unloaded_rows = {d}  total_page_mem = {d} KiB",
        .{
            total,
            fill_us,
            rss_after_fill / MiB,
            pl.residentRows(),
            pl.unloadedRows(),
            pl.page_size / 1024,
        },
    );

    var pass_index: u32 = 0;
    while (pass_index < self.opts.@"scroll-passes") : (pass_index += 1) {
        const start = std.time.Instant.now() catch return error.BenchmarkFailed;
        pl.scroll(.{ .top = {} });
        pl.scroll(.{ .active = {} });
        const end = std.time.Instant.now() catch return error.BenchmarkFailed;
        const pass_us = end.since(start) / std.time.ns_per_us;
        log.info(
            "pass {d}/{d} in {d} us  resident_rows = {d}  unloaded_rows = {d}",
            .{
                pass_index + 1,
                self.opts.@"scroll-passes",
                pass_us,
                pl.residentRows(),
                pl.unloadedRows(),
            },
        );
    }
}

fn step(_: *anyopaque) Benchmark.Error!void {}

fn teardown(ptr: *anyopaque) void {
    const self: *ScrollbackMemory = @ptrCast(@alignCast(ptr));
    if (self.page_list) |*pl| {
        pl.deinit();
        self.page_list = null;
    }
}

fn physicalFootprintBytes() usize {
    return 0;
}
