const ports = @import("ports.zig");
const idt = @import("idt.zig");
const pic = @import("pic.zig");

// https://wiki.osdev.org/Programmable_Interval_Timer

const PIT_CHANNEL0: u16 = 0x40;
const PIT_CHANNEL1: u16 = 0x41;
const PIT_CHANNEL2: u16 = 0x42;
const PIT_COMMAND: u16 = 0x43;
const PIT_DIVISOR: u16 = 11932;

var tick_count: u64 = 0;

fn timerHandler(frame: *idt.InterruptFrame) void {
    _ = frame;
    tick_count += 1;
    pic.sendEoiRaw(0x20);
}

pub fn getTicks() u64 {
    return tick_count;
}

pub fn init() void {
    idt.disableInterrupts();
    ports.outb(PIT_COMMAND, 0x34);
    ports.outb(PIT_CHANNEL0, @truncate(PIT_DIVISOR));
    ports.outb(PIT_CHANNEL0, @truncate(PIT_DIVISOR >> 8));
    idt.registerRawHandler(0x20, timerHandler);
    pic.unmaskIrqRaw(0);
}
