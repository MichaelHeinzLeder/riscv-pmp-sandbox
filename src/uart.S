/*
 * src/uart.S
 * Bare-metal M-mode NS16550A UART driver and hex formatting routines
 */

#include "sandbox.inc"

.section .text.mmode, "ax", @progbits

.global mmode_init_uart
.global mmode_putc
.global mmode_puts
.global mmode_put_n
.global mmode_put_hex32

/*
 * mmode_init_uart
 * Initializes NS16550A UART0 at 0x10000000 (8N1, FIFO enabled)
 */
mmode_init_uart:
    li      t0, UART0_BASE
    sb      zero, 1(t0)         /* IER = 0x00: disable interrupts */
    li      t1, 0x07
    sb      t1, 2(t0)           /* FCR = 0x07: enable and clear FIFOs */
    li      t1, 0x03
    sb      t1, 3(t0)           /* LCR = 0x03: 8 data bits, no parity, 1 stop bit */
    ret

/*
 * mmode_putc
 * Transmits a single byte in a0 over UART0
 */
mmode_putc:
    li      t0, UART0_BASE
1:
    lbu     t1, UART_LSR(t0)
    andi    t1, t1, UART_LSR_THRE
    beqz    t1, 1b
    sb      a0, UART_THR(t0)
    ret

/*
 * mmode_puts
 * Transmits a null-terminated ASCII string pointed to by a0
 */
mmode_puts:
    addi    sp, sp, -16
    sw      ra, 12(sp)
    sw      s0, 8(sp)
    mv      s0, a0
1:
    lbu     a0, 0(s0)
    beqz    a0, 2f
    call    mmode_putc
    addi    s0, s0, 1
    j       1b
2:
    lw      s0, 8(sp)
    lw      ra, 12(sp)
    addi    sp, sp, 16
    ret

/*
 * mmode_put_n
 * Transmits exactly a1 bytes from buffer a0 over UART0
 */
mmode_put_n:
    addi    sp, sp, -16
    sw      ra, 12(sp)
    sw      s0, 8(sp)
    sw      s1, 4(sp)
    mv      s0, a0
    mv      s1, a1
1:
    beqz    s1, 2f
    lbu     a0, 0(s0)
    call    mmode_putc
    addi    s0, s0, 1
    addi    s1, s1, -1
    j       1b
2:
    lw      s1, 4(sp)
    lw      s0, 8(sp)
    lw      ra, 12(sp)
    addi    sp, sp, 16
    ret

/*
 * mmode_put_hex32
 * Formats a 32-bit value in a0 as "0xXXXXXXXX" and transmits over UART0
 */
mmode_put_hex32:
    addi    sp, sp, -16
    sw      ra, 12(sp)
    sw      s0, 8(sp)
    sw      s1, 4(sp)
    mv      s0, a0

    li      a0, '0'
    call    mmode_putc
    li      a0, 'x'
    call    mmode_putc

    li      s1, 28              /* Start at bit 28 (most significant nibble) */
1:
    srl     a0, s0, s1
    andi    a0, a0, 0x0F
    li      t0, 10
    blt     a0, t0, 2f
    addi    a0, a0, ('a' - 10)
    j       3f
2:
    addi    a0, a0, '0'
3:
    call    mmode_putc
    addi    s1, s1, -4
    bgez    s1, 1b

    lw      s1, 4(sp)
    lw      s0, 8(sp)
    lw      ra, 12(sp)
    addi    sp, sp, 16
    ret
