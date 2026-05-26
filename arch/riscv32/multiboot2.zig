pub const BOOTLOADER_MAGIC: u32 = 0;

pub const Info = extern struct {
    _unused: u32 = 0,
};

pub const Tag = extern struct {
    _unused: u32 = 0,
};

pub const MmapTag = extern struct {
    _unused: u32 = 0,
};

pub const FramebufferTag = extern struct {
    _unused: u32 = 0,
};

pub const AcpiRsdpV1Tag = extern struct {
    _unused: u32 = 0,
};

pub const AcpiRsdpV2Tag = extern struct {
    _unused: u32 = 0,
};

pub const ElfSectionTag = extern struct {
    _unused: u32 = 0,
};

pub fn parse(_: *Info, _: anytype) void {}
