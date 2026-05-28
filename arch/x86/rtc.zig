const ports = @import("ports.zig");

// https://wiki.osdev.org/RTC
// https://wiki.osdev.org/CMOS

const CMOS_ADDRESS = 0x70;
const CMOS_DATA = 0x71;

fn isUpdateInProgress() bool {
    ports.outb(CMOS_ADDRESS, 0x0A);
    return ports.inb(CMOS_DATA) & 0x80 == 0x80;
}

fn getRegister(reg: u8) u8 {
    ports.outb(CMOS_ADDRESS, reg);
    return ports.inb(CMOS_DATA);
}

/// returns current day ticks (temp)
pub fn read() u64 {
    while (isUpdateInProgress()) {}
    var second = getRegister(0x00);
    var minute = getRegister(0x02);
    var hour = getRegister(0x04);
    var day = getRegister(0x07);
    var month = getRegister(0x08);
    var year = getRegister(0x09);
    // skip ACPI parsing to check century flag

    while (!isUpdateInProgress()) {
        const last_second = second;
        const last_minute = minute;
        const last_hour = hour;
        const last_day = day;
        const last_month = month;
        const last_year = year;
        second = getRegister(0x00);
        minute = getRegister(0x02);
        hour = getRegister(0x04);
        day = getRegister(0x07);
        month = getRegister(0x08);
        year = getRegister(0x09);
        if (last_second == second and last_minute == minute and last_hour == hour and last_day == day and last_month == month and last_year == year)
            break;
    }

    const registerB = getRegister(0x0B);

    // Convert BCD to binary values if necessary
    if (registerB & 0x04 == 0) {
        second = (second & 0x0F) + ((second / 16) * 10);
        minute = (minute & 0x0F) + ((minute / 16) * 10);
        hour = ((hour & 0x0F) + (((hour & 0x70) / 16) * 10)) | (hour & 0x80);
        day = (day & 0x0F) + ((day / 16) * 10);
        month = (month & 0x0F) + ((month / 16) * 10);
        year = (year & 0x0F) + ((year / 16) * 10);
    }

    // Convert 12 hour clock to 24 hour clock if necessary
    if (registerB & 0x02 == 0 and hour & 0x80 != 0) {
        hour = ((hour & 0x7F) + 12) % 24;
    }

    return @as(u64, second) + 60 * (@as(u64, minute) + 60 * @as(u64, hour));
}
