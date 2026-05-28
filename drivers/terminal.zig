const vga = @import("vga.zig");
const std = @import("std");

pub const COLS: usize = vga.VGA_WIDTH;
pub const ROWS: usize = vga.VGA_HEIGHT - 1;
pub const SCROLLBACK: usize = 200;
const BUF_SIZE: usize = COLS * SCROLLBACK;

const Terminal = struct {
    status: [COLS]u16,
    buffer: [BUF_SIZE]u16,

    cursor_row: usize, // absolute in buffer
    cursor_col: usize,

    view_row: usize, // first visible line
    total_rows: usize,

    dirty_first: usize,
    dirty_last: usize,

    status_color: vga.EntryColor,
    color: vga.EntryColor,

    pub fn init(self: *Terminal, color: vga.Color) void {
        self.cursor_row = 0;
        self.cursor_col = 0;
        self.view_row = 0;
        self.total_rows = 1;
        self.color = vga.EntryColor.init(color, .black);
        const blank = vga.vgaEntry(' ', self.color);
        for (0..BUF_SIZE) |i| {
            self.buffer[i] = blank;
        }
        self.markAllDirty();
    }

    fn markAllDirty(self: *Terminal) void {
        self.dirty_first = 0;
        self.dirty_last = ROWS - 1;
    }

    fn markClean(self: *Terminal) void {
        self.dirty_first = ROWS;
        self.dirty_last = 0;
    }

    fn markRowDirty(self: *Terminal, abs_row: usize) void {
        if (abs_row < self.view_row) return;
        const vis = abs_row - self.view_row;
        if (vis >= ROWS) return;
        if (self.dirty_first > self.dirty_last) {
            self.dirty_first = vis;
            self.dirty_last = vis;
        } else {
            if (vis < self.dirty_first) self.dirty_first = vis;
            if (vis > self.dirty_last) self.dirty_last = vis;
        }
    }

    pub fn flush(self: *Terminal) void {
        if (self.dirty_first <= self.dirty_last) {
            var vis = self.dirty_first;
            while (vis <= self.dirty_last) : (vis += 1) {
                const src_row = self.view_row + vis;
                const screen_row = vis + 1;
                if (src_row < SCROLLBACK) {
                    for (0..COLS) |col| {
                        vga.putEntryAt(self.buffer[src_row * COLS + col], col, screen_row);
                    }
                } else {
                    for (0..COLS) |col| {
                        vga.putEntryAt(vga.vgaEntry(' ', self.color), col, screen_row);
                    }
                }
            }
            self.markClean();
        }
        const content_row = if (self.cursor_row >= self.view_row) self.cursor_row - self.view_row else 0;
        vga.setPosition(content_row + 1, self.cursor_col);
        vga.updateCursor();
    }

    pub fn putchar(self: *Terminal, c: u8) void {
        switch (c) {
            '\n' => self.newline(),
            '\r' => self.cursor_col = 0,
            '\t' => {
                const next = (self.cursor_col + 8) & ~@as(usize, 7);
                self.cursor_col = if (next >= COLS) COLS - 1 else next;
            },
            0x08 => self.backspace(),
            else => {
                if (c >= 0x20) {
                    self.buffer[self.cursor_row * COLS + self.cursor_col] = vga.vgaEntry(c, self.color);
                    self.markRowDirty(self.cursor_row);
                    self.cursor_col += 1;
                    if (self.cursor_col >= COLS) {
                        self.cursor_col = 0;
                        self.advanceRow();
                    }
                }
            },
        }
    }

    pub fn write(self: *Terminal, data: []const u8) void {
        for (data) |c| {
            self.putchar(c);
        }
        self.flush();
    }

    pub fn backspace(self: *Terminal) void {
        if (self.cursor_col > 0) {
            self.cursor_col -= 1;
        } else if (self.cursor_row > 0) {
            self.cursor_row -= 1;
            self.cursor_col = COLS - 1;
        }
        self.buffer[self.cursor_row * COLS + self.cursor_col] = vga.vgaEntry(' ', self.color);
        self.markRowDirty(self.cursor_row);
    }

    pub fn clear(self: *Terminal) void {
        const blank = vga.vgaEntry(' ', self.color);
        for (0..BUF_SIZE) |i| {
            self.buffer[i] = blank;
        }
        self.cursor_row = 0;
        self.cursor_col = 0;
        self.view_row = 0;
        self.total_rows = 1;
        self.markAllDirty();
        self.flush();
    }

    fn newline(self: *Terminal) void {
        self.cursor_col = 0;
        self.advanceRow();
    }

    fn liveViewRow(self: *Terminal) usize {
        if (self.cursor_row >= ROWS - 1) {
            return self.cursor_row - (ROWS - 1);
        }
        return 0;
    }

    fn advanceRow(self: *Terminal) void {
        const old_view_row = self.view_row;
        self.cursor_row += 1;

        if (self.cursor_row >= SCROLLBACK) {
            // Shift scrollback buffer
            for (0..(SCROLLBACK - 1) * COLS) |i| {
                self.buffer[i] = self.buffer[i + COLS];
            }
            const blank = vga.vgaEntry(' ', self.color);
            const last_start = (SCROLLBACK - 1) * COLS;
            for (0..COLS) |i| {
                self.buffer[last_start + i] = blank;
            }
            self.cursor_row = SCROLLBACK - 1;
            self.markAllDirty();
        }

        if (self.cursor_row >= self.total_rows) {
            self.total_rows = self.cursor_row + 1;
        }

        self.view_row = self.liveViewRow();
        if (self.view_row != old_view_row) {
            self.markAllDirty();
        } else {
            self.markRowDirty(self.cursor_row);
        }
    }

    pub fn scrollUp(self: *Terminal) void {
        if (self.view_row == 0) return;
        if (self.view_row >= ROWS) {
            self.view_row -= ROWS;
        } else {
            self.view_row = 0;
        }
        self.markAllDirty();
        self.flush();
    }

    pub fn scrollDown(self: *Terminal) void {
        const live_view = self.liveViewRow();
        if (self.view_row >= live_view) return;
        self.view_row += ROWS;
        if (self.view_row > live_view) {
            self.view_row = live_view;
        }
        self.markAllDirty();
        self.flush();
    }
};

var terminals: [12]Terminal = undefined;
var active_idx: usize = 0;

pub fn renderStatusBar() void {
    const ticks = @import("arch").pit.getTicks();
    const seconds = ticks / 100;
    const minutes = seconds / 60;
    const hours = minutes / 60;

    const active_color = vga.EntryColor.init(.black, .cyan);
    const inactive_color = vga.EntryColor.init(.white, .black);
    const fill_color = vga.EntryColor.init(.cyan, .black);

    for (0..terminals.len) |i| {
        const n = i + 1;
        const label = [5]u8{ ' ', 'F', @truncate(n / 10 + '0'), @truncate(n % 10 + '0'), ' ' };
        for (label, 0..) |c, j| {
            vga.putEntryAt(vga.vgaEntry(c, if (i == active_idx) active_color else inactive_color), i * 5 + j, 0);
        }
    }
    const fill_start = terminals.len * 5;

    for (fill_start..COLS - 9) |i| vga.putEntryAt(vga.vgaEntry(' ', fill_color), i, 0);
    var buffer: [9]u8 = @splat(0);
    _ = std.fmt.bufPrint(&buffer, "{d:>2}:{d:0>2}:{d:0>2}", .{ hours, minutes % 60, seconds % 60 }) catch {};
    for (buffer, COLS - 9..) |c, i| {
        vga.putEntryAt(vga.vgaEntry(c, inactive_color), i, 0);
    }
}

pub fn switchActive(idx: usize) void {
    active_idx = idx;
    renderStatusBar();
    terminals[idx].markAllDirty();
    terminals[idx].flush();
}

pub fn scrollUp() void {
    terminals[active_idx].scrollUp();
}

pub fn scrollDown() void {
    terminals[active_idx].scrollDown();
}

pub fn write(data: []const u8) void {
    terminals[active_idx].write(data);
}

pub fn putchar(c: u8) void {
    terminals[active_idx].putchar(c);
    terminals[active_idx].flush();
}

pub fn clearScreen() void {
    terminals[active_idx].clear();
}

pub fn init() void {
    vga.init();
    active_idx = 0;
    for (&terminals) |*terminal| {
        terminal.init(.green);
    }
    switchActive(0);
}

pub fn setColor(color: vga.EntryColor) void {
    terminals[active_idx].color = color;
}

pub fn initPrompts() void {
    for (&terminals) |*t| {
        for ("> ") |c| t.putchar(c);
    }
    terminals[active_idx].flush();
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
        terminals[active_idx].write(bytes);
    }

    pub fn getWriter() W {
        return .{ .vtable = &.{ .drain = drain }, .buffer = &.{} };
    }
};

pub fn print(comptime format: []const u8, args: anytype) void {
    var w = Writer.getWriter();
    w.print(format, args) catch {};
}
