const std = @import("std");

pub const PAGE_SIZE: u64 = 4096;

const MAX_PHYS: u64 = 4 * 1024 * 1024 * 1024;
const MAX_FRAMES: usize = MAX_PHYS / PAGE_SIZE;
const BITMAP_WORDS: usize = MAX_FRAMES / 32;

pub const Region = struct {
    start: u64,
    end: u64,
};

var bitmap: [BITMAP_WORDS]u32 = @splat(0xFFFFFFFF);
var total_free_at_init: usize = 0;
var used_count: usize = 0;
var search_hint: usize = 0;
var initialized: bool = false;

fn setBit(frame: usize) void {
    const bit: u5 = @intCast(frame % 32);
    bitmap[frame / 32] |= @as(u32, 1) << bit;
}

fn clearBit(frame: usize) void {
    const bit: u5 = @intCast(frame % 32);
    bitmap[frame / 32] &= ~(@as(u32, 1) << bit);
}

fn testBit(frame: usize) bool {
    const bit: u5 = @intCast(frame % 32);
    return (bitmap[frame / 32] & (@as(u32, 1) << bit)) != 0;
}

fn frameOf(addr: u64) usize {
    return @intCast(addr / PAGE_SIZE);
}

pub fn init(usable: []const Region, reserved: []const Region) void {
    for (usable) |region| {
        const start = std.mem.alignForward(u64, region.start, PAGE_SIZE);
        const end = region.end & ~(PAGE_SIZE - 1);
        if (end <= start) continue;

        var addr = start;
        while (addr < end and addr < MAX_PHYS) : (addr += PAGE_SIZE) {
            clearBit(frameOf(addr));
        }
    }

    for (reserved) |region| {
        if (region.end <= region.start) continue;
        const start = region.start & ~(PAGE_SIZE - 1);
        const end = std.mem.alignForward(u64, region.end, PAGE_SIZE);

        var addr = start;
        while (addr < end and addr < MAX_PHYS) : (addr += PAGE_SIZE) {
            setBit(frameOf(addr));
        }
    }

    var free: usize = 0;
    for (bitmap) |word| free += @popCount(~word);
    total_free_at_init = free;

    initialized = true;
}

pub fn allocFrame() ?u64 {
    if (!initialized) return null;

    var pass: u8 = 0;
    while (pass < 2) : (pass += 1) {
        const start_frame = if (pass == 0) search_hint else 0;
        const end_frame = if (pass == 0) MAX_FRAMES else search_hint;

        var i = start_frame;
        while (i < end_frame) {
            const w = i / 32;
            if (bitmap[w] == 0xFFFFFFFF) {
                i = (w + 1) * 32;
                continue;
            }
            if (!testBit(i)) {
                setBit(i);
                used_count += 1;
                search_hint = i + 1;
                return @as(u64, i) * PAGE_SIZE;
            }
            i += 1;
        }
    }
    return null;
}

pub fn freeFrame(phys: u64) void {
    if (!initialized) return;
    if (phys >= MAX_PHYS) return;
    if (phys % PAGE_SIZE != 0) return;
    const frame = frameOf(phys);
    if (!testBit(frame)) return;
    clearBit(frame);
    used_count -= 1;
    if (frame < search_hint) search_hint = frame;
}

pub fn usedFrames() usize {
    return used_count;
}

pub fn freeFrames() usize {
    return total_free_at_init - used_count;
}

pub fn totalFrames() usize {
    return total_free_at_init;
}

const testing = std.testing;

fn resetForTest() void {
    bitmap = @splat(0xFFFFFFFF);
    total_free_at_init = 0;
    used_count = 0;
    search_hint = 0;
    initialized = false;
}

test "init counts usable frames and applies reserved ranges" {
    resetForTest();
    init(
        &.{.{ .start = 0, .end = 16 * PAGE_SIZE }},
        &.{.{ .start = PAGE_SIZE, .end = 2 * PAGE_SIZE }},
    );
    try testing.expectEqual(@as(usize, 15), totalFrames());
    try testing.expectEqual(@as(usize, 15), freeFrames());
    try testing.expectEqual(@as(usize, 0), usedFrames());
}

test "allocFrame hands out distinct page-aligned frames" {
    resetForTest();
    init(&.{.{ .start = 0, .end = 4 * PAGE_SIZE }}, &.{});

    const a = allocFrame().?;
    const b = allocFrame().?;
    try testing.expect(a != b);
    try testing.expectEqual(@as(u64, 0), a % PAGE_SIZE);
    try testing.expectEqual(@as(u64, 0), b % PAGE_SIZE);
    try testing.expectEqual(@as(usize, 2), usedFrames());
}

test "allocFrame returns null once exhausted" {
    resetForTest();
    init(&.{.{ .start = 0, .end = 2 * PAGE_SIZE }}, &.{});
    _ = allocFrame().?;
    _ = allocFrame().?;
    try testing.expectEqual(@as(?u64, null), allocFrame());
}

test "freeFrame returns a frame to the pool" {
    resetForTest();
    init(&.{.{ .start = 0, .end = 4 * PAGE_SIZE }}, &.{});
    const frame = allocFrame().?;
    try testing.expectEqual(@as(usize, 1), usedFrames());
    freeFrame(frame);
    try testing.expectEqual(@as(usize, 0), usedFrames());
    try testing.expectEqual(frame, allocFrame().?);
}

test "freeFrame ignores bad input and double frees" {
    resetForTest();
    init(&.{.{ .start = 0, .end = 4 * PAGE_SIZE }}, &.{});
    const frame = allocFrame().?;
    freeFrame(frame + 1); // not page-aligned
    freeFrame(MAX_PHYS); // out of range
    try testing.expectEqual(@as(usize, 1), usedFrames());
    freeFrame(frame);
    freeFrame(frame); // double free is silent
    try testing.expectEqual(@as(usize, 0), usedFrames());
}

test "allocFrame before init returns null" {
    resetForTest();
    try testing.expectEqual(@as(?u64, null), allocFrame());
}
