/*
 * linker.ld
 * Page-aligned physical memory layout for RISC-V M-mode / U-mode PMP isolation
 * Target: QEMU virt (RAM base 0x80000000)
 */

OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 256K
}

SECTIONS
{
    . = ORIGIN(RAM);

    /* =====================================================================
     * REGION 0: Machine Mode (M-mode) Monitor
     * PMP Entry 0 (TOR): [0x00000000 .. _mmode_end) -> U-mode: --- (No Access)
     * Protects all lower MMIO (UART0, sifive_test) and M-mode code/secrets/stack
     * ===================================================================== */
    _mmode_start = .;

    .text.mmode : ALIGN(4096) {
        *(.text.boot)
        *(.text.mmode)
    } > RAM

    .rodata.mmode : ALIGN(16) {
        *(.rodata.mmode)
    } > RAM

    .data.mmode : ALIGN(16) {
        *(.data.mmode)
    } > RAM

    .bss.mmode (NOLOAD) : ALIGN(16) {
        *(.bss.mmode)
        . = ALIGN(16);
        _mmode_stack_bottom = .;
        . += 4096;
        _mmode_stack_top = .;
    } > RAM

    . = ALIGN(4096);
    _mmode_end = .;

    /* =====================================================================
     * REGION 1: User Mode (U-mode) Executable Code (W^X enforced)
     * PMP Entry 1 (TOR): [_mmode_end .. _umode_text_end) -> U-mode: R-X
     * ===================================================================== */
    _umode_text_start = .;

    .text.umode : ALIGN(4096) {
        *(.text.umode)
    } > RAM

    . = ALIGN(4096);
    _umode_text_end = .;

    /* =====================================================================
     * REGION 2: User Mode (U-mode) Read-Only Data
     * PMP Entry 2 (TOR): [_umode_text_end .. _umode_rodata_end) -> U-mode: R--
     * ===================================================================== */
    _umode_rodata_start = .;

    .rodata.umode : ALIGN(4096) {
        *(.rodata.umode)
    } > RAM

    . = ALIGN(4096);
    _umode_rodata_end = .;

    /* =====================================================================
     * REGION 3: User Mode (U-mode) Read-Write Data & Non-Executable Stack
     * PMP Entry 3 (TOR): [_umode_rodata_end .. _umode_rw_end) -> U-mode: RW-
     * ===================================================================== */
    _umode_rw_start = .;

    .data.umode : ALIGN(4096) {
        *(.data.umode)
    } > RAM

    .bss.umode (NOLOAD) : ALIGN(16) {
        *(.bss.umode)
        . = ALIGN(16);
        _umode_stack_bottom = .;
        . += 4096;
        _umode_stack_top = .;
    } > RAM

    . = ALIGN(4096);
    _umode_rw_end = .;
}
