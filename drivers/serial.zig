const ports = @import("arch").ports;
const std = @import("std");

// https://wiki.osdev.org/Serial_Ports

const COM1: u16 = 0x3F8;
const COM2: u16 = 0x2F8;
const COM3: u16 = 0x3E8;
const COM4: u16 = 0x2E8;
const COM5: u16 = 0x5F8;
const COM6: u16 = 0x4F8;
const COM7: u16 = 0x5E8;
const COM8: u16 = 0x4E8;

// Todo: Probe all serial ports

const SerialError = error{TestFailed};

pub fn init() SerialError!void {
    ports.outb(COM1 + 1, 0x00); // disable interrupts
    ports.outb(COM1 + 3, 0x80); // enable DLAB
    ports.outb(COM1 + 0, 0x01); // baud rate low: 115200
    ports.outb(COM1 + 1, 0x00); // baud rate high
    ports.outb(COM1 + 3, 0x03); // 8 bits, no parity, one stop bit
    ports.outb(COM1 + 2, 0x00); // disable FIFO

    // ports.outb(COM1 + 4, 0x1E); // loopback mode
    // ports.outb(COM1 + 0, 0xAE); // test serial
    // if (ports.inb(COM1 + 0) != 0xAE) {
    //     return error.TestFailed;
    // }

    ports.outb(COM1 + 4, 0x03); // normal operation mode
}

fn serialReceived() bool {
    return ports.inb(COM1 + 5) & 1 != 0;
}

fn isTransmitEmpty() bool {
    return ports.inb(COM1 + 5) & 0x20 != 0;
}

pub fn putchar(c: u8) void {
    while (!isTransmitEmpty()) {}
    ports.outb(COM1, c);
}

pub fn getchar() u8 {
    while (!serialReceived()) {}
    return ports.inb(COM1);
}

pub fn write(s: []const u8) void {
    for (s) |c| putchar(c);
}

const Writer = struct {
    const W = std.Io.Writer;

    fn drain(w: *W, data: []const []const u8, splat: usize) W.Error!usize {
        _ = w;
        var total: usize = 0;
        for (data[0 .. data.len - 1]) |bytes| {
            @This().write(bytes);
            total += bytes.len;
        }
        const pattern = data[data.len - 1];
        for (0..splat) |_| @This().write(pattern);
        return total + pattern.len * splat;
    }

    fn write(bytes: []const u8) void {
        var prev: u8 = 0;
        for (bytes) |c| {
            if (c == '\n' and prev != '\r') putchar('\r');
            putchar(c);
            prev = c;
        }
    }

    pub fn getWriter() W {
        return .{ .vtable = &.{ .drain = drain }, .buffer = &.{} };
    }
};

pub fn print(comptime format: []const u8, args: anytype) void {
    var w = Writer.getWriter();
    w.print(format, args) catch {};
}
