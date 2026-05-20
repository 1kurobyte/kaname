const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{
        .whitelist = &.{
            .{ .cpu_arch = .x86, .os_tag = .freestanding, .abi = .none },
            .{ .cpu_arch = .x86_64, .os_tag = .freestanding, .abi = .none },
        },
        .default_target = .{
            .cpu_arch = .x86,
            .os_tag = .freestanding,
            .abi = .none,
        },
    });

    const cpu_arch: std.Target.Cpu.Arch = .x86;

    const abi = b.createModule(.{
        .root_source_file = b.path("abi/abi.zig"),
        .target = target,
        .optimize = optimize,
    });

    const mm = b.createModule(.{
        .root_source_file = b.path("kernel/mm/pmm.zig"),
        .target = target,
        .optimize = optimize,
        .omit_frame_pointer = false,
    });

    const arch = b.createModule(.{
        .root_source_file = b.path("arch/arch.zig"),
        .target = target,
        .optimize = optimize,
        .omit_frame_pointer = false,
        .imports = &.{
            .{ .name = "abi", .module = abi },
            .{ .name = "mm", .module = mm },
        },
    });

    const drivers = b.createModule(.{
        .root_source_file = b.path("drivers/drivers.zig"),
        .target = target,
        .optimize = optimize,
        .omit_frame_pointer = false,
        .imports = &.{
            .{ .name = "arch", .module = arch },
            .{ .name = "abi", .module = abi },
        },
    });

    const kernel_module = b.createModule(.{
        .root_source_file = b.path("kernel/kernel.zig"),
        .target = target,
        .optimize = optimize,
        .omit_frame_pointer = false,
        .imports = &.{
            .{ .name = "arch", .module = arch },
            .{ .name = "abi", .module = abi },
            .{ .name = "drivers", .module = drivers },
            .{ .name = "mm", .module = mm },
        },
    });

    const kernel = b.addExecutable(.{
        .name = "kaname.kernel",
        .root_module = kernel_module,
    });

    const git_version = b.run(&.{ "git", "describe", "--tags", "--dirty" });
    const version = std.mem.trim(u8, git_version, " \n\r");

    const options = b.addOptions();
    options.addOption([]const u8, "version", version);
    options.addOption(bool, "full", b.option(bool, "full", "Enable all optional subsystems") orelse false);

    const config = options.createModule();

    kernel.root_module.addImport("config", config);
    arch.addImport("config", config);

    const linker_script = switch (cpu_arch) {
        .x86 => b.path("arch/x86/linker.ld"),
        else => @panic("unsupported architecture"),
    };
    kernel.setLinkerScript(linker_script);

    b.installArtifact(kernel);

    const iso_step = b.step("iso-grub", "Build bootable GRUB ISO image");

    const mkdir_cmd = b.addSystemCommand(&.{ "mkdir", "-p", "iso-grub/boot/grub" });

    const cp_kernel_cmd = b.addSystemCommand(&.{"cp"});
    cp_kernel_cmd.addArtifactArg(kernel);
    cp_kernel_cmd.addArg("iso/boot/kaname.kernel");
    cp_kernel_cmd.step.dependOn(&mkdir_cmd.step);

    const cp_grub_cmd = b.addSystemCommand(&.{ "cp", "meta/grub.cfg", "iso-grub/boot/grub/grub.cfg" });
    cp_grub_cmd.step.dependOn(&mkdir_cmd.step);

    const mkrescue = b.addSystemCommand(&.{
        "grub-mkrescue",
        "-o",
        "kaname-grub.iso",
        "iso-grub",
        "--compress=xz",
        "--core-compress=xz",
        "--fonts=",
        "--themes=",
        "--locales=",
        "--modules=",
    });

    mkrescue.step.dependOn(&cp_kernel_cmd.step);
    mkrescue.step.dependOn(&cp_grub_cmd.step);

    iso_step.dependOn(&mkrescue.step);

    const run_step = b.step("run-grub", "Run kernel in QEMU using GRUB ISO");

    const qemu_version = "qemu-system-" ++ switch (cpu_arch) {
        .aarch64 => "aarch64",
        .arm => "arm",
        .avr => "avr",
        .loongarch64 => "loongarch64",
        .m68k => "m68k",
        .mips => "mips",
        .mips64 => "mips64",
        .mips64el => "mips64el",
        .mipsel => "mipsel",
        .or1k => "or1k",
        .powerpc => "ppc",
        .powerpc64 => "ppc64",
        .riscv32 => "riscv32",
        .riscv64 => "riscv64",
        .s390x => "s390x",
        .sparc => "sparc",
        .sparc64 => "sparc64",
        .x86 => "i386",
        .x86_64 => "x86_64",
        .xtensa => "xtensa",
        else => @panic("unsupported CPU architecture"),
    };

    const qemu = b.addSystemCommand(&.{
        qemu_version,
        "-cdrom",
        "kaname-grub.iso",
        "-serial",
        "stdio",
    });
    qemu.step.dependOn(&mkrescue.step);

    run_step.dependOn(&qemu.step);

    const limine_iso_step = b.step("iso-limine", "Build bootable Limine ISO image");

    const limine_dir = "/usr/share/limine";
    const limine_iso_dir = "iso-limine";

    const mkdir_limine = b.addSystemCommand(&.{ "mkdir", "-p", limine_iso_dir ++ "/boot/limine" });

    const cp_kernel_limine = b.addSystemCommand(&.{"cp"});
    cp_kernel_limine.addArtifactArg(kernel);
    cp_kernel_limine.addArg(limine_iso_dir ++ "/boot/kaname.kernel");
    cp_kernel_limine.step.dependOn(&mkdir_limine.step);

    const cp_limine_conf = b.addSystemCommand(&.{
        "cp", "meta/limine.conf", limine_iso_dir ++ "/boot/limine/limine.conf",
    });
    cp_limine_conf.step.dependOn(&mkdir_limine.step);

    // Copy Limine boot files from system installation
    const cp_limine_sys = b.addSystemCommand(&.{
        "cp",                                             limine_dir ++ "/limine-bios.sys",
        limine_iso_dir ++ "/boot/limine/limine-bios.sys",
    });
    cp_limine_sys.step.dependOn(&mkdir_limine.step);

    const cp_limine_bios_cd = b.addSystemCommand(&.{
        "cp",                                                limine_dir ++ "/limine-bios-cd.bin",
        limine_iso_dir ++ "/boot/limine/limine-bios-cd.bin",
    });
    cp_limine_bios_cd.step.dependOn(&mkdir_limine.step);

    const cp_limine_uefi_cd = b.addSystemCommand(&.{
        "cp",                                                limine_dir ++ "/limine-uefi-cd.bin",
        limine_iso_dir ++ "/boot/limine/limine-uefi-cd.bin",
    });
    cp_limine_uefi_cd.step.dependOn(&mkdir_limine.step);

    const xorriso_limine = b.addSystemCommand(&.{
        "xorriso",          "-as",                            "mkisofs",
        "-b",               "boot/limine/limine-bios-cd.bin", "-no-emul-boot",
        "-boot-load-size",  "4",                              "-boot-info-table",
        "--efi-boot",       "boot/limine/limine-uefi-cd.bin", "-efi-boot-part",
        "--efi-boot-image", "--protective-msdos-label",       limine_iso_dir,
        "-o",               "kaname-limine.iso",
    });
    xorriso_limine.step.dependOn(&cp_kernel_limine.step);
    xorriso_limine.step.dependOn(&cp_limine_conf.step);
    xorriso_limine.step.dependOn(&cp_limine_sys.step);
    xorriso_limine.step.dependOn(&cp_limine_bios_cd.step);
    xorriso_limine.step.dependOn(&cp_limine_uefi_cd.step);

    const limine_install = b.addSystemCommand(&.{ "limine", "bios-install", "kaname-limine.iso" });
    limine_install.step.dependOn(&xorriso_limine.step);

    limine_iso_step.dependOn(&limine_install.step);

    const run_limine_step = b.step("run-limine", "Run kernel in QEMU using Limine ISO");

    const qemu_limine = b.addSystemCommand(&.{
        qemu_version,
        "-cdrom",
        "kaname-limine.iso",
        "-serial",
        "stdio",
    });
    qemu_limine.step.dependOn(&limine_install.step);

    run_limine_step.dependOn(&qemu_limine.step);
}
