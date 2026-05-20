const abi = @import("abi");

// https://www.gnu.org/software/grub/manual/multiboot2/multiboot.html

pub const BOOTLOADER_MAGIC: u32 = 0x36d76289;

pub const Info = extern struct {
    total_size: u32,
    reserved: u32,
};

pub const TagType = enum(u32) {
    end = 0,
    cmdline = 1,
    // boot_loader_name = 2,
    // module = 3,
    // basic_meminfo = 4,
    // bootdev = 5,
    mmap = 6,
    // vbe = 7,
    framebuffer = 8,
    // elf_sections = 9,
    // apm = 10,
    // efi32_systable = 11,
    // efi64_systable = 12,
    // smbios = 13,
    acpi_rsdp_v1 = 14,
    acpi_rsdp_v2 = 15,
    // network = 16,
    // efi_mmap = 17,
    // efi_boot_not_terminated = 18,
    // efi32_image_handle = 19,
    // efi64_image_handle = 20,
    _,
};

pub const Tag = extern struct {
    type: TagType,
    size: u32,
};

pub const BootdevTag = extern struct {
    base: Tag,
    biosdev: u32,
    partition: u32,
    sub_partition: u32,
};

pub const CmdlineTag = extern struct {
    base: Tag,

    pub fn string(self: *CmdlineTag) [*:0]u8 {
        return @ptrFromInt(@intFromPtr(self) + @sizeOf(Tag));
    }
};

pub const ModuleTag = extern struct {
    base: Tag,
    mod_start: u32,
    mod_end: u32,

    pub fn string(self: *ModuleTag) [*:0]u8 {
        return @ptrFromInt(@intFromPtr(self) + @sizeOf(Tag));
    }
};

pub const ElfsectionTag = extern struct {
    base: Tag,
    num: u16,
    entsize: u16,
    shndx: u16,
    reserved: u16,
    // headers: undefined,
};

pub const MmapEntry = extern struct {
    base_addr: u64,
    length: u64,
    type: enum(u32) {
        available = 1,
        reserved = 2,
        acpi_info = 3,
        hibernation_reserved = 4,
        defective_ram = 5,
    },
    reserved: u32,
};

pub const MmapTag = extern struct {
    base: Tag,
    entry_size: u32,
    entry_version: u32,

    pub fn entries(self: *MmapTag) []MmapEntry {
        const raw: [*]MmapEntry = @ptrFromInt(@intFromPtr(self) + @sizeOf(MmapTag));
        const count = (self.base.size - @sizeOf(MmapTag)) / self.entry_size;

        return raw[0..count];
    }
};

pub const BootloaderNameTag = extern struct {
    base: Tag,

    pub fn string(self: *BootloaderNameTag) [*:0]u8 {
        return @ptrFromInt(@intFromPtr(self) + @sizeOf(Tag));
    }
};

pub const ApmTag = extern struct {
    base: Tag,
    version: u16,
    cseg: u16,
    offset: u32,
    cseg_16: u16,
    dseg: u16,
    flags: u16,
    cseg_len: u16,
    cseg_16_len: u16,
    dseg_len: u16,
};

pub const VbeTag = extern struct {
    base: Tag,
    vbe_mode: u16,
    vbe_interface_off: u16,
    vbe_interface_seg: u16,
    vbe_interface_len: u16,
    vbe_control_info: abi.vbe.VbeInfoBlock,
    vbe_mode_info: abi.vbe.VbeModeInfoBlock,
};

pub const FramebufferPalette = extern struct {
    red: u8,
    green: u8,
    blue: u8,
};

pub const FramebufferIndexed = extern struct {
    num_colors: u32,

    pub fn palette(self: *FramebufferIndexed) [*]FramebufferPalette {
        return @ptrFromInt(@intFromPtr(self) + @sizeOf(FramebufferIndexed));
    }
};

pub const FramebufferDirect = extern struct {
    red_pos: u8,
    red_mask: u8,
    green_pos: u8,
    green_mask: u8,
    blue_pos: u8,
    blue_mask: u8,
};

pub const FramebufferType = enum(u8) {
    indexed = 0,
    direct = 1,
    ega_text = 2,
};

pub const FramebufferColorInfo = union(FramebufferType) {
    indexed: FramebufferIndexed,
    direct: FramebufferDirect,
    ega_text: void,
};

pub const FramebufferTag = extern struct {
    base: Tag,
    addr: u64,
    pitch: u32,
    width: u32,
    height: u32,
    bpp: u8,
    type: FramebufferType,
    reserved: u8,

    pub fn colorInfo(self: *FramebufferTag) FramebufferColorInfo {
        const addr = @intFromPtr(self) + @sizeOf(FramebufferTag);
        return switch (self.type) {
            .indexed => .{ .indexed = @as(*FramebufferIndexed, @ptrFromInt(addr)).* },
            .direct => .{ .direct = @as(*FramebufferDirect, @ptrFromInt(addr)).* },
            .ega_text => .{ .ega_text = {} },
        };
    }
};

pub const AcpiRsdpV1Tag = extern struct {
    base: Tag,
    rsdp: abi.acpi.Rsdp,
};

pub const AcpiRsdpV2Tag = extern struct {
    base: Tag,
    rsdp: abi.acpi.Xsdp,
};

pub fn parse(info: *Info, handlers: anytype) void {
    var addr = @intFromPtr(info) + 8;
    const end = @intFromPtr(info) + info.total_size;

    while (addr < end) {
        const tag: *Tag = @ptrFromInt(addr);

        switch (tag.type) {
            .end => break,
            .cmdline => if (@hasDecl(handlers, "onCmdline"))
                handlers.onCmdline(@ptrFromInt(addr)),
            .mmap => if (@hasDecl(handlers, "onMmap"))
                handlers.onMmap(@ptrFromInt(addr)),
            .framebuffer => if (@hasDecl(handlers, "onFramebuffer"))
                handlers.onFramebuffer(@ptrFromInt(addr)),
            .acpi_rsdp_v1 => if (@hasDecl(handlers, "onACPIv1"))
                handlers.onACPIv1(@ptrFromInt(addr)),
            .acpi_rsdp_v2 => if (@hasDecl(handlers, "onACPIv2"))
                handlers.onACPIv2(@ptrFromInt(addr)),
            _ => {},
        }
        addr += (tag.size + 7) & ~@as(usize, 7);
    }
}

comptime {
    const assert = @import("std").debug.assert;

    assert(@sizeOf(Tag) == 8);
    assert(@sizeOf(MmapEntry) == 24);
    assert(@offsetOf(MmapEntry, "base_addr") == 0);
    assert(@offsetOf(MmapEntry, "length") == 8);
    assert(@sizeOf(MmapTag) == 16);
    assert(@sizeOf(VbeTag) == 784);
}
