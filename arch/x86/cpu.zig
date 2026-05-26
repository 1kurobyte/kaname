pub inline fn idle() void {
    asm volatile ("hlt");
}

pub inline fn pause() void {
    asm volatile ("pause");
}

pub inline fn enableInterrupts() void {
    asm volatile ("sti");
}

pub inline fn disableInterrupts() void {
    asm volatile ("cli");
}

pub fn halt() noreturn {
    while (true) asm volatile ("cli; hlt");
}
