const arch = @import("arch");
const pic = arch.pic;
const idt = arch.idt;
const ports = arch.ports;

// https://wiki.osdev.org/PS/2_Keyboard

const DATA_PORT = 0x60;

var shift_left: bool = false;
var shift_right: bool = false;
var ctrl: bool = false;
var alt: bool = false;
var caps_lock: bool = false;

pub const Key = union(enum) {
    char: u8,
    function: u8,
    scroll_up,
    scroll_down,
};

const RingBuffer = struct {
    head: u8,
    tail: u8,
    buffer: [256]Key,

    pub fn push(self: *RingBuffer, value: Key) void {
        const next = self.head +% 1;
        if (next == self.tail) return;

        self.buffer[self.head] = value;
        self.head = next;
    }

    pub fn pop(self: *RingBuffer) ?Key {
        if (self.head == self.tail) return null;
        const char = self.buffer[self.tail];
        self.tail +%= 1;
        return char;
    }
};

var rb: RingBuffer = undefined;

pub fn getKey() ?Key {
    return rb.pop();
}

// US QWERTY, normal
const scancode_normal = blk: {
    var table: [128]u8 = @splat(0);
    table[0x02] = '1';
    table[0x03] = '2';
    table[0x04] = '3';
    table[0x05] = '4';
    table[0x06] = '5';
    table[0x07] = '6';
    table[0x08] = '7';
    table[0x09] = '8';
    table[0x0A] = '9';
    table[0x0B] = '0';
    table[0x0C] = '-';
    table[0x0D] = '=';
    table[0x0E] = 0x08;
    table[0x0F] = '\t';
    table[0x10] = 'q';
    table[0x11] = 'w';
    table[0x12] = 'e';
    table[0x13] = 'r';
    table[0x14] = 't';
    table[0x15] = 'y';
    table[0x16] = 'u';
    table[0x17] = 'i';
    table[0x18] = 'o';
    table[0x19] = 'p';
    table[0x1A] = '[';
    table[0x1B] = ']';
    table[0x1C] = '\n';
    table[0x1E] = 'a';
    table[0x1F] = 's';
    table[0x20] = 'd';
    table[0x21] = 'f';
    table[0x22] = 'g';
    table[0x23] = 'h';
    table[0x24] = 'j';
    table[0x25] = 'k';
    table[0x26] = 'l';
    table[0x27] = ';';
    table[0x28] = '\'';
    table[0x29] = '`';
    table[0x2B] = '\\';
    table[0x2C] = 'z';
    table[0x2D] = 'x';
    table[0x2E] = 'c';
    table[0x2F] = 'v';
    table[0x30] = 'b';
    table[0x31] = 'n';
    table[0x32] = 'm';
    table[0x33] = ',';
    table[0x34] = '.';
    table[0x35] = '/';
    table[0x39] = ' ';
    break :blk table;
};

// US QWERTY, shifted
const scancode_shifted = blk: {
    var table: [128]u8 = @splat(0);
    table[0x02] = '!';
    table[0x03] = '@';
    table[0x04] = '#';
    table[0x05] = '$';
    table[0x06] = '%';
    table[0x07] = '^';
    table[0x08] = '&';
    table[0x09] = '*';
    table[0x0A] = '(';
    table[0x0B] = ')';
    table[0x0C] = '_';
    table[0x0D] = '+';
    table[0x0E] = 0x08;
    table[0x0F] = '\t';
    table[0x10] = 'Q';
    table[0x11] = 'W';
    table[0x12] = 'E';
    table[0x13] = 'R';
    table[0x14] = 'T';
    table[0x15] = 'Y';
    table[0x16] = 'U';
    table[0x17] = 'I';
    table[0x18] = 'O';
    table[0x19] = 'P';
    table[0x1A] = '{';
    table[0x1B] = '}';
    table[0x1C] = '\n';
    table[0x1E] = 'A';
    table[0x1F] = 'S';
    table[0x20] = 'D';
    table[0x21] = 'F';
    table[0x22] = 'G';
    table[0x23] = 'H';
    table[0x24] = 'J';
    table[0x25] = 'K';
    table[0x26] = 'L';
    table[0x27] = ':';
    table[0x28] = '"';
    table[0x29] = '~';
    table[0x2B] = '|';
    table[0x2C] = 'Z';
    table[0x2D] = 'X';
    table[0x2E] = 'C';
    table[0x2F] = 'V';
    table[0x30] = 'B';
    table[0x31] = 'N';
    table[0x32] = 'M';
    table[0x33] = '<';
    table[0x34] = '>';
    table[0x35] = '?';
    table[0x39] = ' ';
    break :blk table;
};

var extended: bool = false;

fn keyboardHandler(frame: *idt.InterruptFrame) void {
    _ = frame;

    const scancode = ports.inb(DATA_PORT);

    if (scancode == 0xE0) {
        extended = true;
        pic.sendEoi(.keyboard);
        return;
    }

    if (extended) {
        extended = false;
        // Extended key release
        if (scancode & 0x80 != 0) {
            pic.sendEoi(.keyboard);
            return;
        }
        switch (scancode) {
            0x49 => rb.push(.scroll_up),
            0x51 => rb.push(.scroll_down),
            else => {},
        }
        pic.sendEoi(.keyboard);
        return;
    }

    // Key release
    if (scancode & 0x80 != 0) {
        const released = scancode & 0x7F;
        switch (released) {
            0x2A => shift_left = false,
            0x36 => shift_right = false,
            0x1D => ctrl = false,
            0x38 => alt = false,
            else => {},
        }
        pic.sendEoi(.keyboard);
        return;
    }

    // Key press
    switch (scancode) {
        0x2A => {
            shift_left = true;
            pic.sendEoi(.keyboard);
            return;
        },
        0x36 => {
            shift_right = true;
            pic.sendEoi(.keyboard);
            return;
        },
        0x1D => {
            ctrl = true;
            pic.sendEoi(.keyboard);
            return;
        },
        0x38 => {
            alt = true;
            pic.sendEoi(.keyboard);
            return;
        },
        0x3A => {
            caps_lock = !caps_lock;
            pic.sendEoi(.keyboard);
            return;
        },
        0x3B, 0x3C, 0x3D, 0x3E, 0x3F, 0x40, 0x41, 0x42, 0x43, 0x44 => {
            rb.push(.{ .function = scancode - 0x3B });
            pic.sendEoi(.keyboard);
            return;
        },
        0x57, 0x58 => {
            rb.push(.{ .function = scancode - 0x57 + 10 });
            pic.sendEoi(.keyboard);
            return;
        },
        else => {},
    }

    // Translate scancode to ASCII
    const shifted = shift_left or shift_right;
    const c: u8 = if (shifted) scancode_shifted[scancode] else scancode_normal[scancode];

    if (c != 0) {
        rb.push(.{ .char = c });
    }
    pic.sendEoi(.keyboard);
}

pub fn init() void {
    idt.registerHandler(
        @enumFromInt(
            pic.PIC1_OFFSET + @intFromEnum(pic.Irq.keyboard),
        ),
        keyboardHandler,
    );
    pic.unmaskIrq(.keyboard);
}
