pub const STACK_SIZE = 4 * 4096;
pub export var stack: [STACK_SIZE]u8 align(16) linksection(".bss") = undefined;

export fn _start() callconv(.naked) noreturn {
    asm volatile (
        \\.option push
        \\.option norelax
        \\la gp, __global_pointer$
        \\.option pop
        \\la sp, __stack_top
        \\la t0, __bss_start
        \\la t1, __bss_end
        \\1:
        \\bgeu t0, t1, 2f
        \\sw zero, 0(t0)
        \\addi t0, t0, 4
        \\j 1b
        \\2:
        \\tail main
    );
}
