const gdt = @import("gdt.zig");

// https://wiki.osdev.org/Interrupt_Descriptor_Table
// https://wiki.osdev.org/Exceptions

const InterruptVector = enum(u8) {
    divide_error = 0,
    debug = 1,
    nmi = 2,
    breakpoint = 3,
    overflow = 4,
    bound_range_exceeded = 5,
    invalid_opcode = 6,
    device_not_available = 7,
    double_fault = 8,
    coprocessor_segment_overrun = 9, // obsolete
    invalid_tss = 10,
    segment_not_present = 11,
    stack_segment_fault = 12,
    general_protection = 13,
    page_fault = 14,
    // 15 reserved
    x87_floating_point = 16,
    alignment_check = 17,
    machine_check = 18,
    simd_floating_point = 19,
    virtualization_exception = 20,
    control_protection_exception = 21,

    hypervisor_injection = 28,
    vmm_communication = 29,
    security_exception = 30,

    _,
};

const IDT_SIZE = 256;

const GateType = enum(u4) {
    task_gate = 0x5,
    interrupt_16 = 0x6,
    trap_16 = 0x7,
    interrupt_32 = 0xE,
    trap_32 = 0xF,
};

const IdtEntry = packed struct(u64) {
    offset_low: u16,
    selector: u16,
    reserved0: u8 = 0,
    gate_type: GateType,
    reserved1: u1 = 0,
    ring: u2,
    present: u1,
    offset_high: u16,

    const nil: IdtEntry = @bitCast(@as(u64, 0));

    fn make(offset: u32, selector: u16, ring: u2, gate_type: GateType) IdtEntry {
        return .{
            .offset_low = @truncate(offset),
            .selector = selector,
            .present = 1,
            .ring = ring,
            .gate_type = gate_type,
            .offset_high = @truncate(offset >> 16),
        };
    }
};

const IdtDescriptor = packed struct {
    size: u16,
    offset: u32,
};

comptime {
    if (@sizeOf(IdtEntry) != 8) @compileError("IdtEntry must be exactly 8 bytes");
    if (@bitSizeOf(IdtDescriptor) != 48) @compileError("IdtDescriptor must be exactly 48 bits");
}

pub const InterruptFrame = extern struct {
    edi: u32,
    esi: u32,
    ebp: u32,
    esp: u32,
    ebx: u32,
    edx: u32,
    ecx: u32,
    eax: u32,
    vector: u32,
    error_code: u32,
    eip: u32,
    cs: u32,
    eflags: u32,
};

pub const InterruptHandler = *const fn (*InterruptFrame) void;

var handlers: [IDT_SIZE]?InterruptHandler = @splat(null);
var idt_entries: [IDT_SIZE]IdtEntry = @splat(IdtEntry.nil);

fn hasErrorCode(vector: InterruptVector) bool {
    return switch (vector) {
        .double_fault, .invalid_tss, .segment_not_present, .stack_segment_fault, .general_protection, .page_fault, .alignment_check, .control_protection_exception => true,
        else => false,
    };
}

fn makeIsrStub(comptime vector: InterruptVector) *const fn () callconv(.naked) void {
    return &struct {
        fn stub() callconv(.naked) void {
            if (!comptime hasErrorCode(vector)) {
                // Push dummy error code
                asm volatile ("push $0");
            }
            // Push vector number
            asm volatile ("push %[vector]"
                :
                : [vector] "i" (@as(u32, @intFromEnum(vector))),
            );
            asm volatile ("jmp isrCommonStub");
        }
    }.stub;
}

const isr_stubs = blk: {
    var stubs: [IDT_SIZE]*const fn () callconv(.naked) void = undefined;
    for (0..IDT_SIZE) |i| {
        stubs[i] = makeIsrStub(@enumFromInt(i));
    }
    break :blk stubs;
};

export fn isrCommonStub() callconv(.naked) void {
    // Save all general-purpose registers
    asm volatile ("pusha");
    // Pass stack pointer (pointing to InterruptFrame) as argument
    asm volatile (
        \\mov %%esp, %%eax
        \\push %%eax
        \\call interruptDispatch
        \\add $4, %%esp
    );
    // Restore registers, clean up vector and error code, return from interrupt
    asm volatile (
        \\popa
        \\add $8, %%esp
        \\iret
    );
}

export fn interruptDispatch(frame: *InterruptFrame) void {
    if (frame.vector < IDT_SIZE) {
        if (handlers[frame.vector]) |handler| {
            handler(frame);
        }
    }
}

pub fn registerHandler(vector: InterruptVector, handler: InterruptHandler) void {
    handlers[@intFromEnum(vector)] = handler;
}

pub fn setGateUser(vector: InterruptVector) void {
    const addr = @intFromPtr(isr_stubs[@intFromEnum(vector)]);
    idt_entries[@intFromEnum(vector)] = IdtEntry.make(addr, gdt.KERNEL_CODE_SEG, 0, .interrupt_32);
}

pub fn init() void {
    for (0..IDT_SIZE) |i| {
        const addr = @intFromPtr(isr_stubs[i]);
        idt_entries[i] = IdtEntry.make(addr, gdt.KERNEL_CODE_SEG, 0, .interrupt_32);
    }

    const descriptor = IdtDescriptor{
        .size = @sizeOf(@TypeOf(idt_entries)) - 1,
        .offset = @intFromPtr(&idt_entries),
    };

    asm volatile ("lidt (%[ptr])"
        :
        : [ptr] "r" (&descriptor),
    );
}

pub fn enableInterrupts() void {
    asm volatile ("sti");
}

pub fn disableInterrupts() void {
    asm volatile ("cli");
}
