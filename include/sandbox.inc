/*
 * include/sandbox.inc
 * Hardware MMIO addresses, PMP configuration bits, MCAUSE codes, and ABI constants
 * Target: RISC-V 32-bit (rv32ima_zicsr) on QEMU virt machine
 */

#ifndef SANDBOX_INC
#define SANDBOX_INC

/* QEMU virt MMIO base addresses */
.equ UART0_BASE,            0x10000000
.equ UART_THR,              0x00        /* Transmit Holding Register */
.equ UART_LSR,              0x05        /* Line Status Register */
.equ UART_LSR_THRE,         0x20        /* Transmit Holding Register Empty */

.equ SIFIVE_TEST_BASE,      0x00100000  /* QEMU virt finisher MMIO device */
.equ SIFIVE_TEST_PASS,      0x5555      /* Clean poweroff with exit code 0 */
.equ SIFIVE_TEST_FAIL,      0x3333      /* Poweroff with non-zero exit code */

/* RISC-V mstatus bitfields */
.equ MSTATUS_MPP_MASK,      0x00001800  /* Bits [12:11]: Machine Previous Privilege */
.equ MSTATUS_MPP_UMODE,     0x00000000  /* 00 = User Mode (U-mode) */
.equ MSTATUS_MPP_MMODE,     0x00001800  /* 11 = Machine Mode (M-mode) */

/* RISC-V PMP configuration byte bits (Priv Spec Vol II, Sec 3.7) */
.equ PMP_R,                 (1 << 0)    /* Read permission */
.equ PMP_W,                 (1 << 1)    /* Write permission */
.equ PMP_X,                 (1 << 2)    /* Execute permission */
.equ PMP_A_OFF,             (0 << 3)    /* Null region (disabled) */
.equ PMP_A_TOR,             (1 << 3)    /* Top of Range (TOR) mode */
.equ PMP_A_NA4,             (2 << 3)    /* Naturally aligned 4-byte region */
.equ PMP_A_NAPOT,           (3 << 3)    /* Naturally aligned power-of-two region */
.equ PMP_L,                 (1 << 7)    /* Lock bit (enforces on M-mode too) */

/* RISC-V Synchronous Exception Codes (mcause[30:0] when mcause[31] == 0) */
.equ EXC_INSTR_MISALIGNED,  0
.equ EXC_INSTR_ACCESS,      1           /* PMP / physical instruction fetch fault */
.equ EXC_ILLEGAL_INSTR,     2           /* Unimplemented or privileged CSR/op in U-mode */
.equ EXC_BREAKPOINT,        3
.equ EXC_LOAD_MISALIGNED,   4
.equ EXC_LOAD_ACCESS,       5           /* PMP / physical load access fault */
.equ EXC_STORE_MISALIGNED,  6
.equ EXC_STORE_ACCESS,      7           /* PMP / physical store/AMO access fault */
.equ EXC_ECALL_UMODE,       8           /* Environment call from U-mode */
.equ EXC_ECALL_SMODE,       9
.equ EXC_ECALL_MMODE,       11

/* Syscall numbers (passed in a7) */
.equ SYS_WRITE,             1           /* a0 = ptr, a1 = len -> returns bytes or -EFAULT */
.equ SYS_GET_PRIV,          2           /* queries trap-recorded MPP privilege -> returns 0 */
.equ SYS_EXIT,              93          /* a0 = exit status -> terminates sandbox */

/* Error codes */
.equ ERR_OK,                0
.equ ERR_EFAULT,            -14         /* Bad address (pointer validation failure) */
.equ ERR_ENOSYS,            -38         /* Invalid syscall number */
.equ ERR_EACCES,            -13         /* Hardware trap / access violation caught */

/* Trap frame offsets on M-mode stack (136 bytes total, 16-byte aligned) */
.equ TF_RA,                 0
.equ TF_SP,                 4           /* Saved U-mode sp from mscratch */
.equ TF_GP,                 8
.equ TF_TP,                 12
.equ TF_T0,                 16
.equ TF_T1,                 20
.equ TF_T2,                 24
.equ TF_S0,                 28
.equ TF_S1,                 32
.equ TF_A0,                 36
.equ TF_A1,                 40
.equ TF_A2,                 44
.equ TF_A3,                 48
.equ TF_A4,                 52
.equ TF_A5,                 56
.equ TF_A6,                 60
.equ TF_A7,                 64
.equ TF_S2,                 68
.equ TF_S3,                 72
.equ TF_S4,                 76
.equ TF_S5,                 80
.equ TF_S6,                 84
.equ TF_S7,                 88
.equ TF_S8,                 92
.equ TF_S9,                 96
.equ TF_S10,                100
.equ TF_S11,                104
.equ TF_T3,                 108
.equ TF_T4,                 112
.equ TF_T5,                 116
.equ TF_T6,                 120
.equ TF_MEPC,               124
.equ TF_MSTATUS,            128
.equ TF_MCAUSE,             132
.equ TRAP_FRAME_SIZE,       144         /* Multiple of 16 bytes for ABI alignment */

#endif
