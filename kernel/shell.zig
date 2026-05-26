const std = @import("std");
const arch = @import("arch");
const terminal = @import("drivers").terminal;
const acpi = @import("drivers").acpi;
const keyboard = @import("drivers").keyboard;
const STACK_SIZE = arch.boot.STACK_SIZE;

const Command = struct {
    name: []const u8,
    description: []const u8,
    func: *const fn (args: []const u8) void,
};

const commands = [_]Command{
    .{ .name = "help", .description = "List commands", .func = cmdHelp },
    .{ .name = "uname", .description = "Print system information", .func = cmdUname },
    .{ .name = "shutdown", .description = "Shutdown system", .func = cmdShutdown },
    .{ .name = "cpuinfo", .description = "CPU information", .func = cmdCpuinfo },
    .{ .name = "clear", .description = "Clear screen", .func = cmdClear },
    .{ .name = "stack", .description = "Print kernel stack", .func = cmdStack },
    .{ .name = "symbols", .description = "Print available functions", .func = cmdSymbols },
    .{ .name = "panic", .description = "Manually cause a kernel panic", .func = cmdPanic },
    .{ .name = "halt", .description = "Halt the machine", .func = cmdHalt },
};

fn cmdHelp(_: []const u8) void {
    const maxlen = blk: {
        var max: usize = 0;
        for (commands) |cmd| max = @max(max, cmd.name.len);
        break :blk max;
    };
    for (commands) |cmd| {
        terminal.print("{s}", .{cmd.name});
        // pad with spaces
        var i = cmd.name.len;
        while (i < maxlen + 2) : (i += 1) terminal.putchar(' ');
        terminal.print("{s}\n", .{cmd.description});
    }
}

fn cmdUname(_: []const u8) void {
    terminal.print("KFS {s}\n", .{@import("config").version});
}

fn cmdShutdown(_: []const u8) void {
    acpi.shutdown();
}

fn printFlags(features: anytype) void {
    inline for (std.meta.fields(@TypeOf(features))) |field| {
        if (field.type == bool) {
            if (@field(features, field.name)) {
                terminal.print("{s} ", .{field.name});
            }
        }
    }
}

fn cmdCpuinfo(_: []const u8) void {
    if (comptime arch.has_cpuid) {
        const cpuid = arch.cpuid;
        terminal.print(
            \\processor     : 0
            \\vendor_id     : {s}
            \\cpu family    : {}
            \\model         : {}
            \\model name    : {s}
            \\stepping      : {}
            \\flags         :
        , .{
            cpuid.vendorString(),
            cpuid.effectiveFamily(cpuid.familyInfo()),
            cpuid.effectiveModel(cpuid.familyInfo()),
            std.mem.trimEnd(u8, &cpuid.brandString(), &.{0}),
            cpuid.familyInfo().stepping,
        });
        printFlags(cpuid.features());
        printFlags(cpuid.extFeatures());
        terminal.print(
            \\
            \\address sizes : {} bits physical, {} bits virtual
            \\
        , .{
            cpuid.addressSizes().eax.physical_address_bits,
            cpuid.addressSizes().eax.linear_address_bits,
        });
    } else {
        terminal.print("cpuinfo: unsupported on this architecture\n", .{});
    }
}

fn cmdClear(_: []const u8) void {
    terminal.clearScreen();
}

fn cmdStack(_: []const u8) void {
    const fp = @frameAddress();

    const header_str = "=== Stack Trace ";
    terminal.print(header_str ++ (@as([80 - header_str.len]u8, @splat('='))), .{});
    @import("debug/stack.zig").printStack(fp);
    terminal.print(&@as([80]u8, @splat('=')), .{});
}

fn cmdSymbols(_: []const u8) void {
    @import("debug/symbols.zig").printSymbols();
}

fn cmdPanic(_: []const u8) void {
    @panic("manual kernel panic");
}

fn cmdHalt(_: []const u8) void {
    terminal.write("System halted.\n");
    arch.cpu.halt();
}

fn dispatch(input: []const u8) void {
    for (commands) |cmd| {
        if (std.mem.eql(u8, input, cmd.name)) {
            cmd.func(input);
            terminal.write("> ");
            return;
        }
    }
    terminal.print("unknown command: {s}\n> ", .{input});
}

pub fn init() void {
    var line_buf: [256]u8 = undefined;
    var line_len: usize = 0;

    while (true) {
        if (keyboard.getKey()) |t| {
            switch (t) {
                .char => |c| switch (c) {
                    '\n' => {
                        terminal.putchar('\n');
                        dispatch(line_buf[0..line_len]);
                        line_len = 0;
                    },
                    0x08 => {
                        if (line_len > 0) {
                            line_len -= 1;
                            terminal.putchar(0x08);
                        }
                    },
                    else => {
                        if (line_len < line_buf.len - 1) {
                            line_buf[line_len] = c;
                            line_len += 1;
                            terminal.putchar(c);
                        }
                    },
                },
                .function => |func| {
                    // assumes terminal can support all 12 function keys
                    terminal.switchActive(func);
                },
                .scroll_up => terminal.scrollUp(),
                .scroll_down => terminal.scrollDown(),
            }
        }
        arch.cpu.idle();
    }
}
