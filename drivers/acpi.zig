const std = @import("std");
const abi = @import("abi");

pub const Rsdp = abi.acpi.Rsdp;
pub const Xsdp = abi.acpi.Xsdp;

pub const SdtHeader = extern struct {
    signature: [4]u8,
    length: u32,
    revision: u8,
    checksum: u8,
    oem_id: [6]u8,
    oem_table_id: [8]u8,
    oem_revision: u32,
    creator_id: u32,
    creator_revision: u32,

    pub fn isValid(self: *const SdtHeader) bool {
        var sum: u8 = 0;
        const bytes = @as([*]const u8, @ptrCast(self));
        for (bytes[0..self.length]) |b| sum +%= b;
        return sum == 0;
    }
};

pub const AddressSpace = enum(u8) {
    system_memory = 0,
    system_io = 1,
    pci_config_space = 2,
    embedded_controller = 3,
    system_management_bus = 4,
    system_cmos = 5,
    pci_device_bar_target = 6,
    intelligent_platform_management_infrastructure = 7,
    gpio = 8,
    generic_serial_bus = 9,
    platform_communication_channel = 0x0A,
    _, // reserved & OEM defined
};

pub const AccessSize = enum(u8) {
    undefined = 0,
    byte = 1,
    word = 2,
    dword = 3,
    qword = 4,
    _,
};

pub const GenericAddressStructure = extern struct {
    address_space: AddressSpace,
    bit_width: u8,
    bit_offset: u8,
    access_size: AccessSize,
    address: u64,
};

pub const PreferredPMProfile = enum(u8) {
    unspecified = 0,
    desktop = 1,
    mobile = 2,
    workstation = 3,
    enterprise_server = 4,
    soho_server = 5,
    appliance_pc = 6,
    performance_server = 7,
    _,
};

pub const FadtFlags = packed struct(u32) {
    wbindw: u1,
    wbindw_flush: u1,
    proc_c1: u1,
    p_lvl2_up: u1,
    pwr_button: u1,
    slp_button: u1,
    fix_rtc: u1,
    rtc_s4: u1,
    tmr_val_ext: u1,
    dck_cap: u1,
    reset_reg_sup: u1,
    sealed_case: u1,
    headless: u1,
    cpu_sw_slp: u1,
    pci_exp_wak: u1,
    use_platform_clock: u1,
    s4_rtc_sts_valud: u1,
    remote_power_on_capable: u1,
    force_apic_cluster_model: u1,
    force_apic_physical_destination_mode: u1,
    hw_reduced_acpi: u1,
    low_power_s0_idle_capable: u1,
    reserved: u10,
};

pub const Fadt = extern struct {
    header: SdtHeader,
    firmware_ctrl: u32,
    dsdt: u32,
    reserved0: u8,
    preferred_pm_profile: PreferredPMProfile,
    sci_interrupt: u16,
    smi_cmd: u32,
    acpi_enable: u8,
    acpi_disable: u8,
    s4bios_req: u8,
    pstate_control: u8,
    pm1a_ev_block: u32,
    pm1b_ev_block: u32,
    pm1a_ctrl_block: u32,
    pm1b_ctrl_block: u32,
    pm2_ctrl_block: u32,
    pm_timer_block: u32,
    gpe0_block: u32,
    gpe1_block: u32,
    pm1_ev_length: u8,
    pm1_ctrl_length: u8,
    pm2_ctrl_length: u8,
    pm_timer_length: u8,
    gpe0_length: u8,
    gpe1_length: u8,
    gpe1_base: u8,
    cstate_ctrl: u8,
    worst_c2_latency: u16,
    worst_c3_latency: u16,
    flush_size: u16,
    flush_stride: u16,
    duty_offset: u8,
    duty_width: u8,
    day_alarm: u8,
    month_alarm: u8,
    century: u8,

    boot_architecture_flags: u16,
    reserved1: u8,
    flags: FadtFlags,

    reset_reg: GenericAddressStructure,
    reset_value: u8,
    reserved2: [3]u8,

    x_firmware_ctrl: u64,
    x_dsdt: u64,

    x_pm1a_ev_block: GenericAddressStructure,
    x_pm1b_ev_block: GenericAddressStructure,
    x_pm1a_ctrl_block: GenericAddressStructure,
    x_pm1b_ctrl_block: GenericAddressStructure,
    x_pm2_ctrl_block: GenericAddressStructure,
    x_pm_timer_block: GenericAddressStructure,
    x_gpe0_block: GenericAddressStructure,
    x_gpe1_block: GenericAddressStructure,

    pub fn isValid(self: *const Fadt) bool {
        return self.header.isValid();
    }
};

fn sigToInt(sig: [4]u8) u32 {
    return @as(u32, @bitCast(sig));
}

pub fn init(sdt_addr: u32) void {
    // @setRuntimeSafety(false); // prevent alignment panic
    const sdt = @as(*SdtHeader, @ptrFromInt(sdt_addr));
    const entriesCount = (sdt.length - @sizeOf(SdtHeader)) / @sizeOf(usize);
    const entries = @as([*]const usize, @ptrFromInt(sdt_addr + @sizeOf(SdtHeader)))[0..entriesCount];

    for (entries) |addr| {
        const table = @as(*SdtHeader, @ptrFromInt(addr));
        switch (sigToInt(table.signature)) {
            sigToInt("FACP".*) => fadt = @ptrFromInt(addr),
            else => {},
        }
    }
}

fn findS5(dsdt: [*]const u8, len: usize) ?[*]const u8 {
    var i: usize = 0;
    while (i + 4 <= len) : (i += 1) {
        if (std.mem.eql(u8, dsdt[i .. i + 4], "_S5_")) {
            return dsdt[i..];
        }
    }
    return null;
}

fn getSlpTypa(s5: [*]const u8) u8 {
    return s5[8];
}

pub var fadt: *const Fadt = undefined;

pub fn shutdown() void {
    @setRuntimeSafety(false);
    const serial = @import("serial.zig");
    const terminal = @import("terminal.zig");
    const ports = @import("arch").ports;
    const dsdt: *const SdtHeader = @ptrFromInt(fadt.dsdt);
    const dsdt_bytes: [*]const u8 = @ptrCast(dsdt);
    const s5 = findS5(dsdt_bytes, dsdt.length) orelse {
        terminal.print("S5 not found\n", .{});
        return;
    };
    const slp_typa = getSlpTypa(s5);

    serial.print("ACPI shutdown\n", .{});

    const SLP_EN: u16 = 1 << 13;
    const SLP_TYP_SHIFT: u16 = 10;
    const val: u16 = (@as(u16, slp_typa) << @as(u4, @truncate(SLP_TYP_SHIFT))) | SLP_EN;

    if (ports.inb(@truncate(fadt.pm1a_ctrl_block)) & 1 == 0) {
        ports.outb(@truncate(fadt.smi_cmd), fadt.acpi_enable);
        while (ports.inb(@truncate(fadt.pm1a_ctrl_block)) & 1 == 0) {}
    }

    serial.print("Writing 0x{X} to 0x{X}\n", .{ val, fadt.pm1a_ctrl_block });
    terminal.print("Writing 0x{X} to 0x{X}\n", .{ val, fadt.pm1a_ctrl_block });

    ports.outw(@truncate(fadt.pm1a_ctrl_block), val);
    if (fadt.pm1b_ctrl_block != 0) {
        ports.outw(@truncate(fadt.pm1b_ctrl_block), val);
    }

    asm volatile ("hlt");
    serial.print("Shutdown failed. Halting.\n", .{});
    terminal.print("Shutdown failed. Halting.\n", .{});

    // Shutdown didn't occur, halt indefinitely
    while (true) {
        asm volatile ("cli; hlt");
    }
}
