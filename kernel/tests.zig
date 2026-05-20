//! Host-runnable test root for `zig build test` and `zig build cov`.
//!
//! These tests run as an ordinary Linux process, so this module is built for
//! the native target (see build.zig), NOT the freestanding kernel target.
//! Only reference host-safe code here: anything that uses inline asm, port
//! I/O, or the `arch`/`drivers` modules cannot run hosted and will crash the
//! test runner (and kcov). Add imports as more host-safe units land.

test {
    _ = @import("mm/pmm.zig");
}
