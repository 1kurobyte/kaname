pub const Irq = enum(u8) {
    keyboard = 1,
    cascade = 2,
    com2 = 3,
    com1 = 4,
    lpt2 = 5,
    floppy = 6,
    lpt1 = 7,
    rtc = 8,
    mouse = 12,
    fpu = 13,
    primary_ata = 14,
    secondary_ata = 15,
};

pub const PIC1_OFFSET: u8 = 0x20;
pub const PIC2_OFFSET: u8 = 0x28;

pub fn init() void {}

pub fn sendEoi(_: Irq) void {}

pub fn maskIrq(_: Irq) void {}

pub fn unmaskIrq(_: Irq) void {}

pub fn unmaskIrqRaw(_: u8) void {}

pub fn maskAll() void {}

pub fn unMaskAll() void {}
