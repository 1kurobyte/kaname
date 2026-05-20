const std = @import("std");
const serial = @import("drivers").serial;
const terminal = @import("drivers").terminal;

const Symbol = struct {
    func: *const anyopaque,
    name: []const u8,
};

var symbols_sorted = false;

pub fn ensureSorted() void {
    if (symbols_sorted) return;

    var i: usize = 1;
    while (i < symbols.len) : (i += 1) {
        const key = symbols[i];
        var j: usize = i;
        while (j > 0 and @intFromPtr(symbols[j - 1].func) > @intFromPtr(key.func)) : (j -= 1) {
            symbols[j] = symbols[j - 1];
        }
        symbols[j] = key;
    }
    symbols_sorted = true;
}

fn buildSymbolTable(comptime modules: anytype) []const Symbol {
    comptime {
        var syms: [4096]Symbol = undefined;
        var count: usize = 0;

        const Visitor = struct {
            fn visit(buf: []Symbol, n: *usize, comptime module: type) void {
                inline for (std.meta.declarations(module)) |decl| {
                    const T = @TypeOf(@field(module, decl.name));

                    if (T == type) {
                        const inner = comptime @field(module, decl.name);
                        const info = comptime @typeInfo(inner);
                        if (info == .@"struct" or info == .@"opaque") {
                            visit(buf, n, inner);
                        }
                    } else if (comptime @typeInfo(T) == .@"fn") {
                        buf[n.*] = .{
                            .func = @field(module, decl.name),
                            .name = @typeName(module) ++ "." ++ decl.name,
                        };
                        n.* += 1;
                    }
                }
            }
        };

        for (modules) |module| {
            Visitor.visit(&syms, &count, module);
        }

        const final = syms[0..count].*;
        return &final;
    }
}

const built = buildSymbolTable(.{
    @import("abi"),
    @import("arch"),
    @import("drivers"),
    @import("../kernel.zig"),
    @import("../shell.zig"),
    @import("../42.zig"),
    @import("stack.zig"),
    @import("symbols.zig"),
});

var symbols: [built.len]Symbol = blk: {
    var buf: [built.len]Symbol = undefined;
    @memcpy(buf[0..built.len], built);
    break :blk buf;
};

pub fn printSymbols() void {
    ensureSorted();
    const header_str = std.fmt.comptimePrint("=== Symbol Table ({d} entries) ", .{symbols.len});
    terminal.print(header_str ++ (@as([80 - header_str.len]u8, @splat('='))), .{});
    for (symbols) |sym| {
        terminal.print("  0x{x:0>8} - {s}\n", .{ @intFromPtr(sym.func), sym.name });
    }
    terminal.print(&@as([80]u8, @splat('=')), .{});
}

pub fn resolve(addr: usize) []const u8 {
    ensureSorted();

    var lo: usize = 0;
    var hi: usize = symbols.len;
    while (lo + 1 < hi) {
        const mid = lo + (hi - lo) / 2;
        if (@intFromPtr(symbols[mid].func) <= addr) {
            lo = mid;
        } else {
            hi = mid;
        }
    }

    const sym_addr = @intFromPtr(symbols[lo].func);
    if (sym_addr > addr) return "???";
    return symbols[lo].name;
}

pub fn isKernelAddress(addr: usize) bool {
    ensureSorted();
    const first = @intFromPtr(symbols[0].func);
    const last = @intFromPtr(symbols[symbols.len - 1].func);
    return addr >= first and addr <= last;
}

pub fn printNearest(addr: usize) void {
    ensureSorted();
    for (symbols, 0..) |sym, i| {
        const sym_addr = @intFromPtr(sym.func);
        if (sym_addr > addr) {
            if (i > 0) {
                terminal.print("  below: 0x{x} - {s}\n", .{ @intFromPtr(symbols[i - 1].func), symbols[i - 1].name });
                serial.print("  below: 0x{x} - {s}\n", .{ @intFromPtr(symbols[i - 1].func), symbols[i - 1].name });
            }
            terminal.print("  above: 0x{x} - {s}\n", .{ sym_addr, sym.name });
            serial.print("  above: 0x{x} - {s}\n", .{ sym_addr, sym.name });
            return;
        }
    }
}
