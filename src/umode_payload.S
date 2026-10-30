/*
 * src/umode_payload.S
 * Unprivileged U-mode security verification and exploit test suite
 *
 * Executes with mstatus.MPP = 00 (U-mode) and tests:
 *   1. Confused Deputy syscall attack (passing M-mode secret address to SYS_WRITE)
 *   2. Direct M-mode memory read (lw from .rodata.mmode -> mcause=5)
 *   3. Direct MMIO peripheral access (sb to UART0_BASE -> mcause=7)
 *   4. W^X violation (sw self-modifying code write to .text.umode -> mcause=7)
 *   5. NX stack shellcode execution (jalr to shellcode on U-mode stack -> mcause=1)
 *   6. Privilege escalation via CSR read (csrr mstatus in U-mode -> mcause=2)
 */

#include "sandbox.inc"

.section .text.umode, "ax", @progbits
.global umode_entry

/*
 * umode_print
 * Helper wrapper around ecall SYS_WRITE (a0 = null-terminated string in .rodata.umode)
 */
umode_print:
    mv      t0, a0
    li      a1, 0
1:
    lbu     t1, 0(t0)
    beqz    t1, 2f
    addi    t0, t0, 1
    addi    a1, a1, 1
    j       1b
2:
    li      a7, SYS_WRITE
    ecall
    ret

umode_entry:
    la      a0, ustr_banner
    call    umode_print

    /* ---------------------------------------------------------------------
     * Attack 1: Confused Deputy Syscall (Pass M-Mode Secret Address to SYS_WRITE)
     * --------------------------------------------------------------------- */
    la      a0, ustr_test1
    call    umode_print

    la      a0, mmode_secret_canary
    li      a1, 32
    li      a7, SYS_WRITE
    ecall

    li      t0, ERR_EFAULT
    bne     a0, t0, .Ltest_failed
    la      a0, ustr_pass
    call    umode_print

    /* ---------------------------------------------------------------------
     * Attack 2: Direct Load from M-Mode Memory (PMP Region 0 Load Fault)
     * --------------------------------------------------------------------- */
    la      a0, ustr_test2
    call    umode_print

    la      t0, mmode_secret_canary
    li      a0, 0
    lw      a0, 0(t0)           /* Traps to M-mode with mcause=5 (Load Access Fault) */

    li      t0, ERR_EACCES
    bne     a0, t0, .Ltest_failed
    la      a0, ustr_pass
    call    umode_print

    /* ---------------------------------------------------------------------
     * Attack 3: Direct MMIO Write to UART0_BASE (PMP Region 0 Store Fault)
     * --------------------------------------------------------------------- */
    la      a0, ustr_test3
    call    umode_print

    li      t0, UART0_BASE
    li      t1, 'X'
    li      a0, 0
    sb      t1, 0(t0)           /* Traps to M-mode with mcause=7 (Store Access Fault) */

    li      t0, ERR_EACCES
    bne     a0, t0, .Ltest_failed
    la      a0, ustr_pass
    call    umode_print

    /* ---------------------------------------------------------------------
     * Attack 4: W^X Code Self-Modification (Write to R-X .text.umode)
     * --------------------------------------------------------------------- */
    la      a0, ustr_test4
    call    umode_print

    la      t0, umode_entry
    li      t1, 0x00000013      /* nop (addi x0, x0, 0) */
    li      a0, 0
    sw      t1, 0(t0)           /* Traps to M-mode with mcause=7 (Store Access Fault) */

    li      t0, ERR_EACCES
    bne     a0, t0, .Ltest_failed
    la      a0, ustr_pass
    call    umode_print

    /* ---------------------------------------------------------------------
     * Attack 5: NX Stack Shellcode Execution (Jump to RW- U-Mode Stack)
     * --------------------------------------------------------------------- */
    la      a0, ustr_test5
    call    umode_print

    /* Write 2-instruction shellcode onto U-mode stack:
     *   0x02a00513: li a0, 0x2a
     *   0x00008067: ret (jalr x0, ra, 0)
     */
    addi    sp, sp, -16
    li      t0, 0x02a00513
    sw      t0, 0(sp)
    li      t0, 0x00008067
    sw      t0, 4(sp)
    fence.i

    li      a0, 0
    mv      t0, sp
    jalr    ra, t0, 0           /* Traps on fetch with mcause=1 (Instruction Access Fault) */
    addi    sp, sp, 16

    li      t0, ERR_EACCES
    bne     a0, t0, .Ltest_failed
    la      a0, ustr_pass
    call    umode_print

    /* ---------------------------------------------------------------------
     * Attack 6: Privilege Escalation via CSR Read (csrr mstatus in U-Mode)
     * --------------------------------------------------------------------- */
    la      a0, ustr_test6
    call    umode_print

    li      a0, 0
    csrr    a0, mstatus         /* Traps to M-mode with mcause=2 (Illegal Instruction) */

    li      t0, ERR_EACCES
    bne     a0, t0, .Ltest_failed
    la      a0, ustr_pass
    call    umode_print

    /* ---------------------------------------------------------------------
     * Verify Privilege Level & Contained Fault Count (SYS_GET_PRIV)
     * --------------------------------------------------------------------- */
    li      a7, SYS_GET_PRIV
    ecall
    bnez    a0, .Ltest_failed   /* a0 must be 0 (U-mode) */
    li      t0, 6
    bne     a1, t0, .Ltest_failed

    la      a0, ustr_summary
    call    umode_print

    /* Clean exit (status = 0) */
    li      a0, 0
    li      a7, SYS_EXIT
    ecall

.Ltest_failed:
    la      a0, ustr_fail
    call    umode_print
    li      a0, 1
    li      a7, SYS_EXIT
    ecall

.section .rodata.umode, "a", @progbits
ustr_banner:
    .asciz "[U-MODE] Running unprivileged exploit containment suite...\n\n"
ustr_test1:
    .asciz "[TEST 1] Confused Deputy Syscall (SYS_WRITE on M-mode secret canary)\n"
ustr_test2:
    .asciz "[TEST 2] Direct M-Mode Memory Read (lw from .rodata.mmode)\n"
ustr_test3:
    .asciz "[TEST 3] Direct MMIO Peripheral Write (sb to UART0_BASE 0x10000000)\n"
ustr_test4:
    .asciz "[TEST 4] W^X Code Self-Modification (sw into R-X .text.umode)\n"
ustr_test5:
    .asciz "[TEST 5] NX Stack Shellcode Execution (jalr to RW- U-mode stack)\n"
ustr_test6:
    .asciz "[TEST 6] Privileged CSR Access in U-Mode (csrr mstatus)\n"
ustr_pass:
    .asciz "  [U-MODE VERIFIED] Exploit deterministically blocked and contained.\n\n"
ustr_summary:
    .asciz "[U-MODE] All 6/6 hardware isolation & syscall boundary checks PASSED.\n"
ustr_fail:
    .asciz "[U-MODE FAIL] Isolation check failed!\n"
