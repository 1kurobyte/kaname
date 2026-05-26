ENTRY(_start)

SECTIONS
  {
  . = 1M;

  _kernel_start = .;

  .text ALIGN(4K) : ALIGN(4K)
    {
    KEEP(*(.multiboot2))
    *(.text)
  }

  .rodata ALIGN(4K) : ALIGN(4K)
    {
    *(.rodata)
  }

  .data ALIGN(4K) : ALIGN(4K)
    {
    *(.data)
  }

  .bss ALIGN(4K) : ALIGN(4K)
    {
    *(COMMON)
    *(.bss)
  }

  _kernel_end = .;
}
