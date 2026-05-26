const builtin = @import("builtin");

const impl = switch (builtin.target.cpu.arch) {
    .x86 => @import("x86/x86.zig"),
    .riscv32 => @import("riscv32/riscv32.zig"),
    else => @compileError("unsupported architecture"),
};

pub const boot = impl.boot;
pub const cpu = impl.cpu;
pub const platform = impl.platform;
pub const idt = impl.idt;
pub const gdt = impl.gdt;
pub const multiboot2 = impl.multiboot2;
pub const ports = impl.ports;
pub const pic = impl.pic;
pub const lapic = impl.lapic;
pub const msr = impl.msr;

pub const has_cpuid = @hasDecl(impl, "cpuid");
pub const cpuid = if (has_cpuid) impl.cpuid else struct {};
