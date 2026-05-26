const gdt = @import("gdt.zig");
const idt = @import("idt.zig");
const pic = @import("pic.zig");

pub fn init() void {
    gdt.init();
    idt.init();
    pic.init();
}
