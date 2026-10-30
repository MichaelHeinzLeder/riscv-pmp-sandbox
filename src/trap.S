/*
 * src/trap.S
 * M-mode trap entry, 31-register context preservation, syscall pointer validation,
 * and PMP/privilege exception containment
 */

#include "sandbox.inc"

.section .text.mmode, "ax", @progbits
.global mmode_trap_entry

.balign 4
mmode_trap_entry:
    /*
     * Atomically swap U-mode sp with M-mode stack pointer stored in mscratch.
     * No register is clobbered prior to establishing the M-mode stack frame.
     */
    csrrw   sp, mscratch, sp
    addi    sp, sp, -TRAP_FRAME_SIZE

    /* Save general-purpose registers x1, x3..x31 */
    sw      ra,  TF_RA(sp)
    sw      gp,  TF_GP(sp)
    sw      tp,  TF_TP(sp)
    sw      t0,  TF_T0(sp)
    sw      t1,  TF_T1(sp)
    sw      t2,  TF_T2(sp)
    sw      s0,  TF_S0(sp)
    sw      s1,  TF_S1(sp)
    sw      a0,  TF_A0(sp)
    sw      a1,  TF_A1(sp)
    sw      a2,  TF_A2(sp)
    sw      a3,  TF_A3(sp)
    sw      a4,  TF_A4(sp)
    sw      a5,  TF_A5(sp)
    sw      a6,  TF_A6(sp)
    sw      a7,  TF_A7(sp)
    sw      s2,  TF_S2(sp)
    sw      s3,  TF_S3(sp)
    sw      s4,  TF_S4(sp)
    sw      s5,  TF_S5(sp)
    sw      s6,  TF_S6(sp)
    sw      s7,  TF_S7(sp)
    sw      s8,  TF_S8(sp)
    sw      s9,  TF_S9(sp)
    sw      s10, TF_S10(sp)
    sw      s11, TF_S11(sp)
    sw      t3,  TF_T3(sp)
    sw      t4,  TF_T4(sp)
    sw      t5,  TF_T5(sp)
    sw      t6,  TF_T6(sp)

    /* Retrieve original U-mode sp from mscratch and save in trap frame */
    csrr    t0, mscratch
    sw      t0, TF_SP(sp)

    /* Save CSR state (mepc, mstatus, mcause) */
    csrr    t0, mepc
    sw      t0, TF_MEPC(sp)
    csrr    t1, mstatus
    sw      t1, TF_MSTATUS(sp)
    csrr    t2, mcause
    sw      t2, TF_MCAUSE(sp)

    /* Distinguish asynchronous interrupts (mcause < 0) from synchronous exceptions */
    bltz    t2, .Ltrap_unhandled

    /* Check if this trap is a U-mode system call (mcause == EXC_ECALL_UMODE == 8) */
    li      t3, EXC_ECALL_UMODE
    beq     t2, t3, .Lhandle_syscall

    /* Otherwise, handle synchronous hardware security fault (PMP / Illegal CSR) */
    j       .Lhandle_security_fault

/* =========================================================================
 * U-Mode Syscall Dispatcher (mcause == 8)
 * ========================================================================= */
.Lhandle_syscall:
    /* Advance mepc by 4 bytes past the ecall instruction */
    lw      t0, TF_MEPC(sp)
    addi    t0, t0, 4
    sw      t0, TF_MEPC(sp)

    lw      t0, TF_A7(sp)       /* Syscall number in a7 */

    li      t1, SYS_WRITE
    beq     t0, t1, .Lsys_write

    li      t1, SYS_GET_PRIV
    beq     t0, t1, .Lsys_get_priv

    li      t1, SYS_EXIT
    beq     t0, t1, .Lsys_exit

    /* Unknown syscall -> return -ENOSYS */
    li      t0, ERR_ENOSYS
    sw      t0, TF_A0(sp)
    j       .Ltrap_restore

/*
 * SYS_WRITE (a7 = 1, a0 = buf_ptr, a1 = len)
 * Enforces strict U-mode pointer validation to prevent Confused Deputy reads
 * of M-mode memory or MMIO registers.
 */
.Lsys_write:
    lw      s0, TF_A0(sp)       /* buf_ptr */
    lw      s1, TF_A1(sp)       /* len */

    /* Zero-length write succeeds immediately */
    beqz    s1, .Lsys_write_ok

    /* Reject negative or excessive lengths (> 4096) */
    bltz    s1, .Lsys_write_efault
    li      t0, 4096
    bgtu    s1, t0, .Lsys_write_efault

    /* Compute end = buf_ptr + len and check for unsigned wrap-around */
    add     s2, s0, s1
    bltu    s2, s0, .Lsys_write_efault

    /*
     * Validate that [buf_ptr, buf_ptr + len) lies entirely inside U-mode
     * readable memory: [_umode_rodata_start, _umode_rw_end)
     */
    la      t0, _umode_rodata_start
    bltu    s0, t0, .Lsys_write_efault

    la      t1, _umode_rw_end
    bgtu    s2, t1, .Lsys_write_efault

    /* Pointer validated: transmit buffer over UART0 */
    mv      a0, s0
    mv      a1, s1
    call    mmode_put_n

.Lsys_write_ok:
    sw      s1, TF_A0(sp)       /* Return number of bytes written */
    j       .Ltrap_restore

.Lsys_write_efault:
    /* Log blocked Confused Deputy syscall attempt */
    la      a0, str_efault_prefix
    call    mmode_puts
    mv      a0, s0
    call    mmode_put_hex32
    la      a0, str_efault_len
    call    mmode_puts
    mv      a0, s1
    call    mmode_put_hex32
    la      a0, str_efault_suffix
    call    mmode_puts

    /* Increment total blocked exploit counter */
    la      t0, mmode_fault_count
    lw      t1, 0(t0)
    addi    t1, t1, 1
    sw      t1, 0(t0)

    li      t0, ERR_EFAULT
    sw      t0, TF_A0(sp)
    j       .Ltrap_restore

/*
 * SYS_GET_PRIV (a7 = 2)
 * Extracts previous privilege mode from saved mstatus.MPP[12:11]
 * and returns total trapped security violations in a1.
 */
.Lsys_get_priv:
    lw      t0, TF_MSTATUS(sp)
    srli    t0, t0, 11
    andi    t0, t0, 0x3         /* 0 = U-mode, 3 = M-mode */
    sw      t0, TF_A0(sp)

    la      t1, mmode_fault_count
    lw      t1, 0(t1)
    sw      t1, TF_A1(sp)
    j       .Ltrap_restore

/*
 * SYS_EXIT (a7 = 93, a0 = exit_code)
 * Logs summary and triggers clean QEMU virt hardware shutdown via sifive_test
 */
.Lsys_exit:
    la      a0, str_exit_msg
    call    mmode_puts
    la      t0, mmode_fault_count
    lw      a0, 0(t0)
    call    mmode_put_hex32
    la      a0, str_exit_end
    call    mmode_puts

    lw      t0, TF_A0(sp)
    bnez    t0, 1f
    li      t1, SIFIVE_TEST_PASS
    j       2f
1:
    li      t1, SIFIVE_TEST_FAIL
2:
    li      t2, SIFIVE_TEST_BASE
    sw      t1, 0(t2)
3:
    wfi
    j       3b

/* =========================================================================
 * Synchronous Security Exception Containment (PMP & Privilege Violations)
 * ========================================================================= */
.Lhandle_security_fault:
    mv      s0, t2              /* s0 = mcause */
    lw      s1, TF_MEPC(sp)     /* s1 = mepc */
    csrr    s2, mtval           /* s2 = mtval (faulting address or instruction) */

    /* Increment hardware security violation counter */
    la      t0, mmode_fault_count
    lw      t1, 0(t0)
    addi    t1, t1, 1
    sw      t1, 0(t0)

    /* Print detailed hardware trap diagnostic */
    la      a0, str_trap_prefix
    call    mmode_puts

    /* Print human-readable fault name based on mcause */
    li      t0, EXC_INSTR_ACCESS
    beq     s0, t0, .Lname_instr_access
    li      t0, EXC_ILLEGAL_INSTR
    beq     s0, t0, .Lname_illegal_instr
    li      t0, EXC_LOAD_ACCESS
    beq     s0, t0, .Lname_load_access
    li      t0, EXC_STORE_ACCESS
    beq     s0, t0, .Lname_store_access
    la      a0, str_cause_other
    j       .Lprint_cause_done

.Lname_instr_access:
    la      a0, str_cause_instr
    j       .Lprint_cause_done
.Lname_illegal_instr:
    la      a0, str_cause_illegal
    j       .Lprint_cause_done
.Lname_load_access:
    la      a0, str_cause_load
    j       .Lprint_cause_done
.Lname_store_access:
    la      a0, str_cause_store

.Lprint_cause_done:
    call    mmode_puts

    la      a0, str_trap_mcause
    call    mmode_puts
    mv      a0, s0
    call    mmode_put_hex32

    la      a0, str_trap_mepc
    call    mmode_puts
    mv      a0, s1
    call    mmode_put_hex32

    la      a0, str_trap_mtval
    call    mmode_puts
    mv      a0, s2
    call    mmode_put_hex32

    la      a0, str_trap_recovered
    call    mmode_puts

    /*
     * Fault Recovery Policy:
     * - If mcause == EXC_INSTR_ACCESS (1), U-mode jumped to a non-executable
     *   region (e.g., NX stack via jalr ra, target). Redirect mepc back to the
     *   caller's return address (TF_RA) so execution resumes after the call.
     * - For data access faults (5, 7) or illegal CSR instructions (2) in
     *   32-bit rv32ima code, advance mepc by 4 bytes past the faulting instruction.
     */
    li      t0, EXC_INSTR_ACCESS
    bne     s0, t0, 1f
    lw      t1, TF_RA(sp)
    sw      t1, TF_MEPC(sp)
    j       2f
1:
    addi    t1, s1, 4
    sw      t1, TF_MEPC(sp)
2:
    /* Set U-mode return value a0 = ERR_EACCES (-13) to indicate trapped fault */
    li      t0, ERR_EACCES
    sw      t0, TF_A0(sp)
    j       .Ltrap_restore

.Ltrap_unhandled:
    la      a0, str_unhandled
    call    mmode_puts
    li      t1, SIFIVE_TEST_FAIL
    li      t2, SIFIVE_TEST_BASE
    sw      t1, 0(t2)
1:
    wfi
    j       1b

/* =========================================================================
 * Context Restore & Return to U-Mode
 * ========================================================================= */
.Ltrap_restore:
    /* Ensure mstatus.MPP remains 00 (U-mode) before mret */
    lw      t0, TF_MSTATUS(sp)
    li      t1, ~MSTATUS_MPP_MASK
    and     t0, t0, t1
    csrw    mstatus, t0

    /* Restore updated mepc */
    lw      t0, TF_MEPC(sp)
    csrw    mepc, t0

    /* Place U-mode sp back into mscratch so the final csrrw restores both sp and mscratch */
    lw      t0, TF_SP(sp)
    csrw    mscratch, t0

    /* Restore general-purpose registers */
    lw      ra,  TF_RA(sp)
    lw      gp,  TF_GP(sp)
    lw      tp,  TF_TP(sp)
    lw      t0,  TF_T0(sp)
    lw      t1,  TF_T1(sp)
    lw      t2,  TF_T2(sp)
    lw      s0,  TF_S0(sp)
    lw      s1,  TF_S1(sp)
    lw      a0,  TF_A0(sp)
    lw      a1,  TF_A1(sp)
    lw      a2,  TF_A2(sp)
    lw      a3,  TF_A3(sp)
    lw      a4,  TF_A4(sp)
    lw      a5,  TF_A5(sp)
    lw      a6,  TF_A6(sp)
    lw      a7,  TF_A7(sp)
    lw      s2,  TF_S2(sp)
    lw      s3,  TF_S3(sp)
    lw      s4,  TF_S4(sp)
    lw      s5,  TF_S5(sp)
    lw      s6,  TF_S6(sp)
    lw      s7,  TF_S7(sp)
    lw      s8,  TF_S8(sp)
    lw      s9,  TF_S9(sp)
    lw      s10, TF_S10(sp)
    lw      s11, TF_S11(sp)
    lw      t3,  TF_T3(sp)
    lw      t4,  TF_T4(sp)
    lw      t5,  TF_T5(sp)
    lw      t6,  TF_T6(sp)

    /* Deallocate M-mode trap frame and swap M-mode sp back into mscratch */
    addi    sp, sp, TRAP_FRAME_SIZE
    csrrw   sp, mscratch, sp
    mret

.section .bss.mmode, "aw", @nobits
.global mmode_fault_count
.balign 4
mmode_fault_count:
    .space 4

.section .rodata.mmode, "a", @progbits
str_efault_prefix:
    .asciz "  [M-MODE TRAP] Syscall Pointer Rejected (-EFAULT): ptr="
str_efault_len:
    .asciz " len="
str_efault_suffix:
    .asciz " (outside U-mode memory)\n"

str_trap_prefix:
    .asciz "  [M-MODE TRAP] Contained "
str_cause_instr:
    .asciz "PMP Instruction Access Fault (NX Violation)"
str_cause_illegal:
    .asciz "Illegal Instruction / Privileged CSR Access"
str_cause_load:
    .asciz "PMP Load Access Fault (Unauthorized Read)"
str_cause_store:
    .asciz "PMP Store/AMO Access Fault (Unauthorized Write)"
str_cause_other:
    .asciz "Synchronous Hardware Exception"

str_trap_mcause:
    .asciz "\n                mcause="
str_trap_mepc:
    .asciz " mepc="
str_trap_mtval:
    .asciz " mtval="
str_trap_recovered:
    .asciz " -> policy=CONTAIN_AND_RECOVER (a0=-EACCES)\n"

str_exit_msg:
    .asciz "\n[M-MODE] U-Mode requested SYS_EXIT. Total contained exploit attempts: "
str_exit_end:
    .asciz "\n[M-MODE] Halting machine cleanly via sifive_test.\n"
str_unhandled:
    .asciz "\n[M-MODE PANIC] Unhandled asynchronous interrupt.\n"
