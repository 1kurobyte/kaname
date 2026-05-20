const std = @import("std");
const config = @import("config");

const InformationRequestTag = extern struct {
    type: u16 = 1,
    flags: u16 = 0,
    size: u32 = @sizeOf(InformationRequestTag),
    requests: [2]u32 = .{ 1, 8 },
};

const ConsoleTag = extern struct {
    type: u16 = 4,
    flags: u16 = 1, // optional
    size: u32 = @sizeOf(ConsoleTag),
    console_flags: u32 = (1 << 1), // text mode
    _pad: u32 = 0,
};

const FramebufferTag = extern struct {
    type: u16 = 5,
    flags: u16 = 1, // optional
    size: u32 = @sizeOf(FramebufferTag),
    width: u32 = 1280,
    height: u32 = 800,
    depth: u32 = 32,
    _pad: u32 = 0,
};

const EndTag = extern struct {
    type: u16 = 0,
    flags: u16 = 0,
    size: u32 = 8,
};

const Multiboot2Header = if (config.full) extern struct {
    magic: u32 = 0xE85250D6,
    architecture: u32 = 0, // i386
    header_length: u32 = @sizeOf(Multiboot2Header),
    checksum: u32 = 0,
    info_req: InformationRequestTag = .{},
    console: ConsoleTag = .{},
    framebuffer: FramebufferTag = .{},
    end: EndTag = .{},
} else extern struct {
    magic: u32 = 0xE85250D6,
    architecture: u32 = 0, // i386
    header_length: u32 = @sizeOf(Multiboot2Header),
    checksum: u32 = 0,
    info_req: InformationRequestTag = .{},
    console: ConsoleTag = .{},
    end: EndTag = .{},
};

fn makeHeader() Multiboot2Header {
    var h = Multiboot2Header{};
    h.checksum = 0 -% (h.magic +% h.architecture +% h.header_length);
    return h;
}

comptime {
    std.debug.assert(@sizeOf(InformationRequestTag) % 8 == 0);
    std.debug.assert(@sizeOf(ConsoleTag) % 8 == 0);
    std.debug.assert(@sizeOf(FramebufferTag) % 8 == 0);
    std.debug.assert(@sizeOf(EndTag) % 8 == 0);
}

export var multiboot2_header: Multiboot2Header align(8) linksection(".multiboot2") = makeHeader();

pub const STACK_SIZE = 4 * 4096;
pub export var stack: [STACK_SIZE]u8 align(16) linksection(".bss") = undefined;

// Enable x87 FPU
const _fpu_init =
    \\
    \\mov %%cr0, %%eax
    \\and $0xFFFFFFFB, %%eax
    \\or  $0x00000002, %%eax
    \\mov %%eax, %%cr0
    \\fninit
    \\
;

const _sse_init =
    \\
    \\pushl %%eax
    \\pushl %%ebx
    \\mov $1, %%eax
    \\cpuid
    \\popl %%ebx
    \\test $0x02000000, %%edx
    \\jz .Lno_sse
    \\
    \\mov %%cr4, %%eax
    \\or $0x00000600, %%eax
    \\mov %%eax, %%cr4
    \\.Lno_sse:
    \\popl %%eax
    \\
;

export fn _start() callconv(.naked) noreturn {
    asm volatile (
        \\xor %%ebp, %%ebp
        \\movl $stack + 16384, %%esp
        // Reset EFLAGS
        \\pushl $0
        \\popf
        // Push multiboot information structure pointer
        \\pushl %%ebx
        // Push magic value
        \\pushl %%eax
    ++ _fpu_init ++ _sse_init ++
        \\call main
        \\cli
        \\.Lhalt:
        \\hlt
        \\jmp .Lhalt
    );
}
