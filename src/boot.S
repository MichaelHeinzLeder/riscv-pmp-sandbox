/*
 * src/boot.S
 * M-mode reset vector, trap vector installation, register scrubbing, and mret to U-mode
 */

#include "sandbox.inc"

.section .text.boot, "ax", @progbits
.global _start

_start:
    /* Park any secondary harts (only Hart 0 runs the security monitor) */
    csrr    t0, mhartid
    bnez    t0, .Lpark_hart

    /* Clear mstatus and mip before setting up trap handling */
    csrw    mstatus, zero
    csrw    mip, zero
    csrw    mie, zero

    /* Initialize M-mode stack pointer and store M-mode stack base in mscratch */
    la      sp, _mmode_stack_top
    csrw    mscratch, sp

    /* Install direct-mode M-mode trap vector (mtvec[1:0] = 00) */
    la      t0, mmode_trap_entry
    csrw    mtvec, t0

    /* Initialize NS16550A UART0 and print boot banner */
    call    mmode_init_uart
    la      a0, str_boot_banner
    call    mmode_puts

    /* Program Physical Memory Protection (PMP) CSRs */
    call    mmode_init_pmp

    /* Log privilege transition to U-mode */
    la      a0, str_drop_priv
    call    mmode_puts
    la      a0, umode_entry
    call    mmode_put_hex32
    la      a0, str_newline
    call    mmode_puts

    /*
     * Configure mstatus.MPP = 00 (U-mode) and mepc = umode_entry.
     * Keep M-mode stack top in mscratch so the trap handler can swap sp atomically.
     */
    la      t0, _mmode_stack_top
    csrw    mscratch, t0

    li      t0, MSTATUS_MPP_MASK
    csrc    mstatus, t0         /* Clear MPP[12:11] -> 00 (User Mode) */

    la      t0, umode_entry
    csrw    mepc, t0

    /* Set U-mode stack pointer and scrub all other GPRs to prevent M-mode pointer leaks */
    la      sp, _umode_stack_top
    li      ra, 0
    li      gp, 0
    li      tp, 0
    li      t0, 0
    li      t1, 0
    li      t2, 0
    li      s0, 0
    li      s1, 0
    li      a0, 0
    li      a1, 0
    li      a2, 0
    li      a3, 0
    li      a4, 0
    li      a5, 0
    li      a6, 0
    li      a7, 0
    li      s2, 0
    li      s3, 0
    li      s4, 0
    li      s5, 0
    li      s6, 0
    li      s7, 0
    li      s8, 0
    li      s9, 0
    li      s10, 0
    li      s11, 0
    li      t3, 0
    li      t4, 0
    li      t5, 0
    li      t6, 0

    /* Drop privilege from M-mode (11) to U-mode (00) and jump to mepc */
    mret

.Lpark_hart:
    wfi
    j       .Lpark_hart

.section .rodata.mmode, "a", @progbits
.global mmode_secret_canary
.balign 16
mmode_secret_canary:
    .word   0xDEADC0DE
    .asciz  "MMODE_MASTER_KEY{rv32_pmp_ring_isolation}"

str_boot_banner:
    .asciz "\n=== RISC-V M-Mode / U-Mode Hardware PMP Security Monitor (rv32ima_zicsr) ===\n"
str_drop_priv:
    .asciz "[M-MODE] Scrubbing GPRs, setting mstatus.MPP=00 (U-Mode), jumping via mret to "
str_newline:
    .asciz "\n\n"
