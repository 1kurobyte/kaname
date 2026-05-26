ENTRY(start)

SECTIONS {
  . = 0x80000000;

  _kernel_start = .;

  .text : ALIGN(4K) {
    *(.init);
    *(.text);
  }
  .bss : ALIGN(4K) {
    PROVIDE(__bss_start = .);
    *(.bss);
    . += 4096;
    PROVIDE(__stack_top = .);
    . += 4096;
    PROVIDE(__global_pointer = .);
    PROVIDE(__bss_end = .);
  }
  .rodata : ALIGN(4K) {
    *(.rodata);
  }
  .data : ALIGN(4K) {
    *(.data);
  }

  _kernel_end = .;
}
