const builtin = @import("builtin");
const std = @import("std");
const pmm = @import("mm");
const idt = @import("idt.zig");

pub const PAGE_SIZE: usize = 0x1000;

pub const VirtualAddress = struct {
    value: usize,

    pub fn init(value: usize) VirtualAddress {
        return .{ .value = value };
    }
};

pub const PhysicalAddress = struct {
    value: u64,

    pub fn init(value: u64) PhysicalAddress {
        return .{ .value = value };
    }
};

pub const Permissions = struct {
    write: bool = false,
    execute: bool = false,
    user: bool = false,

    cache_disable: bool = false,
    write_through: bool = false,

    global: bool = false,
};

pub const PageSize = enum {
    @"4k",
    @"2m",
    @"4m",
    @"1g",
};

pub const MapError = error{
    OutOfMemory,
    AlreadyMapped,
    InvalidAddress,
    UnsupportedSize,
    NotInitialized,
    NotImplemented,
};

pub const Mapping = struct {
    virt: VirtualAddress,
    phys: PhysicalAddress,
    perm: Permissions,
    size: PageSize = .@"4k",
};

pub const AddressSpace = struct {
    root: u64,
};

extern const _kernel_start: u8;
extern const _kernel_end: u8;

pub const PageDirectoryEntry32 = packed struct(u32) {
    present: bool,
    read_write: bool,
    user: bool,
    write_through: bool,
    cache_disable: bool,
    accessed: bool,
    ignored0: u1,
    page_size: bool,
    ignored1: u1,
    available: u3,
    page_table_base: u20,

    pub fn toPhysical(self: @This()) u32 {
        return @as(u32, self.page_table_base) << 12;
    }
};

pub const PageDirectoryEntry32Large = packed struct(u32) {
    present: bool,
    read_write: bool,
    user: bool,
    write_through: bool,
    cache_disable: bool,
    accessed: bool,
    dirty: bool,
    page_size: bool,
    global: bool,
    available: u3,
    pat: bool,
    reserved: u9 = 0,
    page_frame: u10,

    pub fn toPhysical(self: @This()) u32 {
        return @as(u32, self.page_frame) << 22;
    }
};

pub const PageTableEntry32 = packed struct(u32) {
    present: bool,
    read_write: bool,
    user: bool,
    write_through: bool,
    cache_disable: bool,
    accessed: bool,
    dirty: bool,
    pat: bool,
    global: bool,
    available: u3,
    page_frame: u20,

    pub fn toPhysical(self: @This()) u32 {
        return @as(u32, self.page_frame) << 12;
    }
};

pub const PageDirectoryPointerEntryPae = packed struct(u64) {
    present: bool,
    reserved0: u2 = 0,
    write_through: bool,
    cache_disable: bool,
    reserved1: u4 = 0,
    available: u3,
    page_directory_base: u40,
    reserved2: u12 = 0,

    pub fn toPhysical(self: @This()) u64 {
        return @as(u64, self.page_directory_base) << 12;
    }
};

pub const PageDirectoryEntryPae = packed struct(u64) {
    present: bool,
    read_write: bool,
    user: bool,
    write_through: bool,
    cache_disable: bool,
    accessed: bool,
    dirty: bool,
    page_size: bool,
    global: bool,
    available: u3,
    address: u40,
    available2: u11,
    no_execute: bool,

    pub fn toPhysical(self: @This()) u64 {
        return @as(u64, self.address) << 12;
    }
};

pub const PageTableEntryPae = packed struct(u64) {
    present: bool,
    read_write: bool,
    user: bool,
    write_through: bool,
    cache_disable: bool,
    accessed: bool,
    dirty: bool,
    pat: bool,
    global: bool,
    available: u3,
    page_frame: u40,
    available2: u11,
    no_execute: bool,

    pub fn toPhysical(self: @This()) u64 {
        return @as(u64, self.page_frame) << 12;
    }
};

pub const PageMapLevel4Entry = packed struct(u64) {
    present: bool,
    read_write: bool,
    user: bool,
    write_through: bool,
    cache_disable: bool,
    accessed: bool,
    ignored0: u1,
    page_size: bool,
    ignored1: u4,
    page_directory_pointer_base: u40,
    available: u11,
    no_execute: bool,

    pub fn toPhysical(self: @This()) u64 {
        return @as(u64, self.page_directory_pointer_base) << 12;
    }
};

pub const PageDirectoryPointerEntry64 = packed struct(u64) {
    present: bool,
    read_write: bool,
    user: bool,
    write_through: bool,
    cache_disable: bool,
    accessed: bool,
    ignored0: u1,
    page_size: bool,
    ignored1: u4,
    address: u40,
    available: u11,
    no_execute: bool,

    pub fn toPhysical(self: @This()) u64 {
        return @as(u64, self.address) << 12;
    }
};

pub const PageDirectoryEntry64 = packed struct(u64) {
    present: bool,
    read_write: bool,
    user: bool,
    write_through: bool,
    cache_disable: bool,
    accessed: bool,
    dirty: bool,
    page_size: bool,
    global: bool,
    available: u3,
    address: u40,
    available2: u11,
    no_execute: bool,

    pub fn toPhysical(self: @This()) u64 {
        return @as(u64, self.address) << 12;
    }
};

pub const PageTableEntry64 = packed struct(u64) {
    present: bool,
    read_write: bool,
    user: bool,
    write_through: bool,
    cache_disable: bool,
    accessed: bool,
    dirty: bool,
    pat: bool,
    global: bool,
    available: u3,
    page_frame: u40,
    available2: u11,
    no_execute: bool,

    pub fn toPhysical(self: @This()) u64 {
        return @as(u64, self.page_frame) << 12;
    }
};

const Vtable32 = struct {
    init: *const fn () MapError!void,
    map: *const fn (*AddressSpace, VirtualAddress, PhysicalAddress, Permissions) MapError!void,
    unmap: *const fn (*AddressSpace, VirtualAddress) void,
    translate: *const fn (*AddressSpace, VirtualAddress) ?PhysicalAddress,
};

const non_pae_vtable_32: Vtable32 = .{
    .init = init32,
    .map = map32,
    .unmap = unmap32,
    .translate = translate32,
};

// const pae_vtable_32: Vtable32 = .{ ... };

var active_vtable_32: *const Vtable32 = &non_pae_vtable_32;

fn select32() void {
    // Future:
    //   if (cpuid.hasFeature(.pae)) {
    //       active_vtable_32 = &pae_vtable_32;
    //       return;
    //   }
    active_vtable_32 = &non_pae_vtable_32;
}

fn init64() MapError!void {
    return error.NotImplemented;
}

fn map64(space: *AddressSpace, virt: VirtualAddress, phys: PhysicalAddress, perm: Permissions) MapError!void {
    _ = space;
    _ = virt;
    _ = phys;
    _ = perm;
    return error.NotImplemented;
}

fn unmap64(space: *AddressSpace, virt: VirtualAddress) void {
    _ = space;
    _ = virt;
}

fn translate64(space: *AddressSpace, virt: VirtualAddress) ?PhysicalAddress {
    _ = space;
    _ = virt;
    return null;
}

pub fn readCr2() usize {
    return asm volatile ("mov %%cr2, %[result]"
        : [result] "=r" (-> usize),
    );
}

pub fn readCr3() u64 {
    return asm volatile ("mov %%cr3, %[result]"
        : [result] "=r" (-> usize),
    );
}

fn writeCr3(phys: u64) void {
    const value: usize = @intCast(phys);
    asm volatile ("mov %[v], %%cr3"
        :
        : [v] "r" (value),
        : "memory");
}

fn enablePagingBit() void {
    asm volatile (
        \\mov %%cr0, %%eax
        \\or $0x80000000, %%eax
        \\mov %%eax, %%cr0
        ::: .{ .eax = true, .memory = true });
}

pub fn flush(virt: VirtualAddress) void {
    asm volatile ("invlpg (%[addr])"
        :
        : [addr] "r" (virt.value),
        : "memory");
}

const ENTRIES_32: usize = 1024;
const RECURSIVE_INDEX_32: usize = 1023;
const PD_VADDR_32: u32 = 0xFFFFF000;
const PT_BASE_VADDR_32: u32 = 0xFFC00000;

const PageDirectory32 = [ENTRIES_32]PageDirectoryEntry32;
const PageTable32 = [ENTRIES_32]PageTableEntry32;

inline fn pdAt(pdi: u10) *volatile PageDirectoryEntry32 {
    const pd: *volatile PageDirectory32 = @ptrFromInt(PD_VADDR_32);
    return &pd[pdi];
}

inline fn ptAt(pdi: u10, pti: u10) *volatile PageTableEntry32 {
    const pt: *volatile PageTable32 = @ptrFromInt(PT_BASE_VADDR_32 + @as(u32, pdi) * PAGE_SIZE);
    return &pt[pti];
}

fn emptyPde32() PageDirectoryEntry32 {
    return @bitCast(@as(u32, 0));
}

fn emptyPte32() PageTableEntry32 {
    return @bitCast(@as(u32, 0));
}

fn pdeForTable32(pt_phys: u64) PageDirectoryEntry32 {
    return .{
        .present = true,
        .read_write = true,
        .user = true,
        .write_through = false,
        .cache_disable = false,
        .accessed = false,
        .ignored0 = 0,
        .page_size = false,
        .ignored1 = 0,
        .available = 0,
        .page_table_base = @intCast(pt_phys >> 12),
    };
}

fn pteFromMapping32(phys: u64, perm: Permissions) PageTableEntry32 {
    return .{
        .present = true,
        .read_write = perm.write,
        .user = perm.user,
        .write_through = perm.write_through,
        .cache_disable = perm.cache_disable,
        .accessed = false,
        .dirty = false,
        .pat = false,
        .global = perm.global,
        .available = 0,
        .page_frame = @intCast(phys >> 12),
    };
}

fn zeroFramePhys(phys: u64) void {
    const ptr: [*]volatile u32 = @ptrFromInt(@as(usize, @intCast(phys)));
    var i: usize = 0;
    while (i < PAGE_SIZE / @sizeOf(u32)) : (i += 1) ptr[i] = 0;
}

fn map32(space: *AddressSpace, virt: VirtualAddress, phys: PhysicalAddress, perm: Permissions) MapError!void {
    if (space.root != readCr3()) return error.NotImplemented;
    if (phys.value & (PAGE_SIZE - 1) != 0) return error.InvalidAddress;
    if (virt.value & (PAGE_SIZE - 1) != 0) return error.InvalidAddress;

    const pdi: u10 = @truncate(virt.value >> 22);
    const pti: u10 = @truncate(virt.value >> 12);

    const pde_ptr = pdAt(pdi);
    if (!pde_ptr.present) {
        const new_pt = pmm.allocFrame() orelse return error.OutOfMemory;
        pde_ptr.* = pdeForTable32(new_pt);
        flush(VirtualAddress.init(PT_BASE_VADDR_32 + @as(u32, pdi) * PAGE_SIZE));

        const pt: *volatile PageTable32 = @ptrFromInt(PT_BASE_VADDR_32 + @as(u32, pdi) * PAGE_SIZE);
        var i: usize = 0;
        while (i < ENTRIES_32) : (i += 1) pt[i] = emptyPte32();
    }

    const pte_ptr = ptAt(pdi, pti);
    if (pte_ptr.present) return error.AlreadyMapped;
    pte_ptr.* = pteFromMapping32(phys.value, perm);
    flush(virt);
}

fn unmap32(space: *AddressSpace, virt: VirtualAddress) void {
    if (space.root != readCr3()) return;
    const pdi: u10 = @truncate(virt.value >> 22);
    const pti: u10 = @truncate(virt.value >> 12);

    if (!pdAt(pdi).present) return;
    ptAt(pdi, pti).* = emptyPte32();
    flush(virt);
}

fn translate32(space: *AddressSpace, virt: VirtualAddress) ?PhysicalAddress {
    if (space.root != readCr3()) return null;
    const pdi: u10 = @truncate(virt.value >> 22);
    const pti: u10 = @truncate(virt.value >> 12);

    const pde = pdAt(pdi).*;
    if (!pde.present) return null;
    const pte = ptAt(pdi, pti).*;
    if (!pte.present) return null;

    const base: u64 = pte.toPhysical();
    const offset: u64 = virt.value & (PAGE_SIZE - 1);
    return PhysicalAddress.init(base | offset);
}

fn init32() MapError!void {
    idt.registerHandler(.page_fault, pageFaultHandler);

    const pd_phys = pmm.allocFrame() orelse return error.OutOfMemory;
    zeroFramePhys(pd_phys);
    const pd: *volatile PageDirectory32 = @ptrFromInt(@as(usize, @intCast(pd_phys)));

    const identity_limit: u64 = 16 * 1024 * 1024;
    var pdi: u32 = 0;
    while (pdi * ENTRIES_32 * PAGE_SIZE < identity_limit) : (pdi += 1) {
        const pt_phys = pmm.allocFrame() orelse return error.OutOfMemory;
        zeroFramePhys(pt_phys);
        const pt: *volatile PageTable32 = @ptrFromInt(@as(usize, @intCast(pt_phys)));

        const base_frame: u64 = @as(u64, pdi) * ENTRIES_32;
        var pti: usize = 0;
        while (pti < ENTRIES_32) : (pti += 1) {
            const frame_phys = (base_frame + pti) * PAGE_SIZE;
            pt[pti] = .{
                .present = true,
                .read_write = true,
                .user = false,
                .write_through = false,
                .cache_disable = false,
                .accessed = false,
                .dirty = false,
                .pat = false,
                .global = false,
                .available = 0,
                .page_frame = @intCast(frame_phys >> 12),
            };
        }
        pd[pdi] = pdeForTable32(pt_phys);
    }

    pd[RECURSIVE_INDEX_32] = pdeForTable32(pd_phys);

    writeCr3(pd_phys);
    enablePagingBit();
}

fn pageFaultHandler(frame: *idt.InterruptFrame) void {
    _ = frame;
    _ = readCr2();
    while (true) asm volatile ("cli; hlt");
}

pub fn init(usable: []const pmm.Region, reserved: []const pmm.Region) MapError!void {
    pmm.init(usable, reserved);
    return switch (builtin.cpu.arch) {
        .x86 => blk: {
            select32();
            break :blk active_vtable_32.init();
        },
        .x86_64 => init64(),
        else => @compileError("unsupported architecture"),
    };
}

pub fn kernelStart() usize {
    return @intFromPtr(&_kernel_start);
}

pub fn kernelEnd() usize {
    return @intFromPtr(&_kernel_end);
}

pub fn map(
    space: *AddressSpace,
    virt: VirtualAddress,
    phys: PhysicalAddress,
    perm: Permissions,
) MapError!void {
    return switch (builtin.cpu.arch) {
        .x86 => active_vtable_32.map(space, virt, phys, perm),
        .x86_64 => map64(space, virt, phys, perm),
        else => @compileError("unsupported architecture"),
    };
}

pub fn mapRange(
    space: *AddressSpace,
    virt: VirtualAddress,
    phys: PhysicalAddress,
    size: usize,
    perm: Permissions,
) MapError!void {
    if (size == 0) return;
    if (virt.value & (PAGE_SIZE - 1) != 0) return error.InvalidAddress;
    if (phys.value & (PAGE_SIZE - 1) != 0) return error.InvalidAddress;

    const pages = (size + PAGE_SIZE - 1) / PAGE_SIZE;
    var i: usize = 0;
    while (i < pages) : (i += 1) {
        try map(
            space,
            VirtualAddress.init(virt.value + i * PAGE_SIZE),
            PhysicalAddress.init(phys.value + i * PAGE_SIZE),
            perm,
        );
    }
}

pub fn unmap(space: *AddressSpace, virt: VirtualAddress) void {
    switch (builtin.cpu.arch) {
        .x86 => active_vtable_32.unmap(space, virt),
        .x86_64 => unmap64(space, virt),
        else => @compileError("unsupported architecture"),
    }
}

pub fn translate(space: *AddressSpace, virt: VirtualAddress) ?PhysicalAddress {
    return switch (builtin.cpu.arch) {
        .x86 => active_vtable_32.translate(space, virt),
        .x86_64 => translate64(space, virt),
        else => @compileError("unsupported architecture"),
    };
}

/// `AddressSpace` referring to whatever's currently in CR3. After init()
/// returns, this is the kernel's own page directory.
pub fn currentAddressSpace() AddressSpace {
    return .{ .root = readCr3() };
}
