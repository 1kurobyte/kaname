const symbols = @import("symbols.zig");
const serial = @import("drivers").serial;
const terminal = @import("drivers").terminal;
const boot = @import("arch").boot;

const StackFrame = extern struct {
    prev: ?*StackFrame,
    ret: usize,
};

pub fn printStack(ebp: ?usize) void {
    symbols.ensureSorted();

    const actual_ebp = @frameAddress();

    const stack_lo = @intFromPtr(&boot.stack);
    const stack_hi = stack_lo + boot.STACK_SIZE;

    var frame: ?*StackFrame = @ptrFromInt(ebp orelse actual_ebp);
    var i: usize = 0;
    while (frame) |f| : (i += 1) {
        const frame_addr = @intFromPtr(f);

        if (frame_addr < stack_lo or frame_addr + @sizeOf(StackFrame) > stack_hi) break;
        if (!symbols.isKernelAddress(f.ret)) break;

        terminal.print("  #{d}: 0x{x} - {s}\n", .{ i, f.ret, symbols.resolve(f.ret) });
        serial.print("  #{d}: 0x{x} - {s}\n", .{ i, f.ret, symbols.resolve(f.ret) });
        frame = f.prev;
    }
}
