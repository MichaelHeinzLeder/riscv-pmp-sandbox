/*
 * src/pmp.S
 * Hardware Physical Memory Protection (PMP) configuration in Top-of-Range (TOR) mode
 *
 * Enforces strict privilege and W^X isolation for U-mode:
 *   Entry 0: [0x00000000        .. _mmode_end)        -> U-mode: --- (M-mode & MMIO locked out)
 *   Entry 1: [_mmode_end        .. _umode_text_end)   -> U-mode: R-X (U-mode code, non-writable)
 *   Entry 2: [_umode_text_end   .. _umode_rodata_end) -> U-mode: R-- (U-mode rodata, non-writable/non-exec)
 *   Entry 3: [_umode_rodata_end .. _umode_rw_end)     -> U-mode: RW- (U-mode data & stack, non-executable)
 */

#include "sandbox.inc"

.section .text.mmode, "ax", @progbits
.global mmode_init_pmp

mmode_init_pmp:
    addi    sp, sp, -16
    sw      ra, 12(sp)

    /* pmpaddr CSRs store physical addresses shifted right by 2 (word address) */
    la      t0, _mmode_end
    srli    t0, t0, 2
    csrw    pmpaddr0, t0

    la      t0, _umode_text_end
    srli    t0, t0, 2
    csrw    pmpaddr1, t0

    la      t0, _umode_rodata_end
    srli    t0, t0, 2
    csrw    pmpaddr2, t0

    la      t0, _umode_rw_end
    srli    t0, t0, 2
    csrw    pmpaddr3, t0

    /*
     * Pack pmpcfg0 bytes [pmp3cfg | pmp2cfg | pmp1cfg | pmp0cfg]:
     *   pmp0cfg = PMP_A_TOR                           (0x08: --- for U-mode)
     *   pmp1cfg = PMP_A_TOR | PMP_R | PMP_X           (0x0D: R-X for U-mode)
     *   pmp2cfg = PMP_A_TOR | PMP_R                   (0x09: R-- for U-mode)
     *   pmp3cfg = PMP_A_TOR | PMP_R | PMP_W           (0x0B: RW- for U-mode)
     */
    li      t0, (PMP_A_TOR) | \
                ((PMP_A_TOR | PMP_R | PMP_X) << 8) | \
                ((PMP_A_TOR | PMP_R) << 16) | \
                ((PMP_A_TOR | PMP_R | PMP_W) << 24)
    csrw    pmpcfg0, t0
    fence.i

    /* Log configured hardware PMP table */
    la      a0, str_pmp_hdr
    call    mmode_puts

    /* Entry 0 */
    la      a0, str_pmp0_a
    call    mmode_puts
    li      a0, 0
    call    mmode_put_hex32
    la      a0, str_pmp_sep
    call    mmode_puts
    la      a0, _mmode_end
    call    mmode_put_hex32
    la      a0, str_pmp0_b
    call    mmode_puts

    /* Entry 1 */
    la      a0, str_pmp1_a
    call    mmode_puts
    la      a0, _umode_text_start
    call    mmode_put_hex32
    la      a0, str_pmp_sep
    call    mmode_puts
    la      a0, _umode_text_end
    call    mmode_put_hex32
    la      a0, str_pmp1_b
    call    mmode_puts

    /* Entry 2 */
    la      a0, str_pmp2_a
    call    mmode_puts
    la      a0, _umode_rodata_start
    call    mmode_put_hex32
    la      a0, str_pmp_sep
    call    mmode_puts
    la      a0, _umode_rodata_end
    call    mmode_put_hex32
    la      a0, str_pmp2_b
    call    mmode_puts

    /* Entry 3 */
    la      a0, str_pmp3_a
    call    mmode_puts
    la      a0, _umode_rw_start
    call    mmode_put_hex32
    la      a0, str_pmp_sep
    call    mmode_puts
    la      a0, _umode_rw_end
    call    mmode_put_hex32
    la      a0, str_pmp3_b
    call    mmode_puts

    lw      ra, 12(sp)
    addi    sp, sp, 16
    ret

.section .rodata.mmode, "a", @progbits
str_pmp_hdr:
    .asciz "[M-MODE] Hardware PMP TOR Table Configured (pmpcfg0 = 0x0b090d08):\n"
str_pmp_sep:
    .asciz " .. "
str_pmp0_a:
    .asciz "  pmp0 [TOR] "
str_pmp0_b:
    .asciz " -> U: --- | M: RWX (MMIO + M-Mode Monitor)\n"
str_pmp1_a:
    .asciz "  pmp1 [TOR] "
str_pmp1_b:
    .asciz " -> U: R-X | M: RWX (.text.umode, W^X)\n"
str_pmp2_a:
    .asciz "  pmp2 [TOR] "
str_pmp2_b:
    .asciz " -> U: R-- | M: RWX (.rodata.umode)\n"
str_pmp3_a:
    .asciz "  pmp3 [TOR] "
str_pmp3_b:
    .asciz " -> U: RW- | M: RWX (.data/.bss.umode, NX Stack)\n\n"
