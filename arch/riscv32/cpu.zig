pub inline fn idle() void {}

pub inline fn pause() void {}

pub inline fn enableInterrupts() void {}

pub inline fn disableInterrupts() void {}

pub fn halt() noreturn {
    while (true) {}
}
