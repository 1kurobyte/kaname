pub const InterruptVector = enum(u8) { _ };

pub const InterruptFrame = extern struct {
    _unused: u32 = 0,
};

pub const InterruptHandler = *const fn (*InterruptFrame) void;

pub fn init() void {}

pub fn enableInterrupts() void {}

pub fn disableInterrupts() void {}

pub fn registerHandler(_: InterruptVector, _: InterruptHandler) void {}

pub fn registerRawHandler(_: u8, _: InterruptHandler) void {}

pub fn setGateUser(_: InterruptVector) void {}
