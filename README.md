# riscv-pmp-sandbox

Bare-metal `rv32ima_zicsr` Machine Mode (M-mode) security monitor and Physical Memory Protection (PMP) sandbox written in 100% RISC-V Assembly for the QEMU `virt` platform. Enforces hardware ring isolation (`M-mode` vs. `U-mode`), `W^X` code pages, non-executable (`NX`) stacks, and syscall pointer range validation.

## Architecture

- **Hardware PMP Enforcement ([`src/pmp.S`](src/pmp.S), [`linker.ld`](linker.ld))**: Programs `pmpaddr0..3` and `pmpcfg0` in Top-of-Range (`TOR`) mode aligned on 4 KiB page boundaries to partition physical memory and MMIO between M-mode (`PRIV=11`) and U-mode (`PRIV=00`).
- **M-Mode Reset & Register Scrubbing ([`src/boot.S`](src/boot.S))**: Initializes UART0 (`0x10000000`), installs the direct-mode trap vector (`mtvec`), stores the M-mode kernel stack top in `mscratch`, zeroes general-purpose registers (`x1..x31` except `sp`) to prevent M-mode pointer disclosure, sets `mstatus.MPP = 00`, and transitions to U-mode via `mret`.
- **Trap Frame & Exception Containment ([`src/trap.S`](src/trap.S))**: Atomically exchanges `sp` with `mscratch` (`csrrw sp, mscratch, sp`), saves all 31 general-purpose registers and trap CSRs (`mepc`, `mstatus`, `mcause`) into a 144-byte stack frame, and deterministically contains synchronous security exceptions (`mcause` `1`, `2`, `5`, `7`).
- **Syscall Pointer Validation ([`src/trap.S`](src/trap.S))**: Validates `SYS_WRITE` buffers against `[_umode_rodata_start, _umode_rw_end)` with unsigned overflow checks before reading user memory from M-mode, preventing Confused Deputy disclosure of M-mode secrets or MMIO space.
- **Unprivileged Exploit Suite ([`src/umode_payload.S`](src/umode_payload.S))**: Executes in U-mode and exercises six attack vectors against the monitor, verifying that each violation traps into M-mode and returns `-EFAULT` (`-14`) or `-EACCES` (`-13`).

```text
.
├── Makefile
├── linker.ld
├── include/
│   └── sandbox.inc
└── src/
    ├── boot.S
    ├── pmp.S
    ├── trap.S
    ├── uart.S
    └── umode_payload.S
```

## Physical Memory Protection (PMP) Layout

| PMP Entry | Mode | Address Range | U-Mode Perms | M-Mode Perms | Purpose |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `pmp0` | `TOR` | `0x00000000 .. _mmode_end` | `---` | `RWX` | MMIO (`UART0`, `sifive_test`), M-mode code, `.rodata.mmode` secret canary, M-mode stack |
| `pmp1` | `TOR` | `_mmode_end .. _umode_text_end` | `R-X` | `RWX` | `.text.umode` executable code (`W^X` enforced) |
| `pmp2` | `TOR` | `_umode_text_end .. _umode_rodata_end` | `R--` | `RWX` | `.rodata.umode` constants |
| `pmp3` | `TOR` | `_umode_rodata_end .. _umode_rw_end` | `RW-` | `RWX` | `.data.umode` and `.bss.umode` U-mode stack (`NX` enforced) |

## Contained Exploit Vectors

| Test | Attack Vector | Mechanism Tested | Expected Trap / Return |
| :--- | :--- | :--- | :--- |
| `TEST 1` | Pass `mmode_secret_canary` address to `SYS_WRITE` | Confused Deputy / Syscall pointer bounds check | Rejected with `-EFAULT` (`-14`) |
| `TEST 2` | `lw` directly from `mmode_secret_canary` | `pmp0` read lock (`---`) | `mcause = 0x5` (Load access fault) |
| `TEST 3` | `sb` directly to `UART0_BASE` (`0x10000000`) | `pmp0` MMIO isolation (`---`) | `mcause = 0x7` (Store/AMO access fault) |
| `TEST 4` | `sw` instruction overwrite into `.text.umode` | `pmp1` `W^X` enforcement (`R-X`) | `mcause = 0x7` (Store/AMO access fault) |
| `TEST 5` | Write shellcode to U-mode stack and `jalr` to `sp` | `pmp3` `NX` stack enforcement (`RW-`) | `mcause = 0x1` (Instruction access fault) |
| `TEST 6` | Execute `csrr a0, mstatus` in U-mode | Privilege ring CSR isolation (`PRIV=00`) | `mcause = 0x2` (Illegal instruction) |

## Dependencies

- `gcc-riscv64-unknown-elf` (`riscv64-unknown-elf-gcc`, `riscv64-unknown-elf-objdump`)
- `qemu-system-riscv` (`qemu-system-riscv32`)

## Build & Run

```bash
make
make run
```

```text
=== RISC-V M-Mode / U-Mode Hardware PMP Security Monitor (rv32ima_zicsr) ===
[M-MODE] Hardware PMP TOR Table Configured (pmpcfg0 = 0x0b090d08):
  pmp0 [TOR] 0x00000000 .. 0x80002000 -> U: --- | M: RWX (MMIO + M-Mode Monitor)
  pmp1 [TOR] 0x80002000 .. 0x80003000 -> U: R-X | M: RWX (.text.umode, W^X)
  pmp2 [TOR] 0x80003000 .. 0x80004000 -> U: R-- | M: RWX (.rodata.umode)
  pmp3 [TOR] 0x80004000 .. 0x80005000 -> U: RW- | M: RWX (.data/.bss.umode, NX Stack)

[M-MODE] Scrubbing GPRs, setting mstatus.MPP=00 (U-Mode), jumping via mret to 0x80002028

[U-MODE] Running unprivileged exploit containment suite...

[TEST 1] Confused Deputy Syscall (SYS_WRITE on M-mode secret canary)
  [M-MODE TRAP] Syscall Pointer Rejected (-EFAULT): ptr=0x80000740 len=0x00000020 (outside U-mode memory)
  [U-MODE VERIFIED] Exploit deterministically blocked and contained.

[TEST 2] Direct M-Mode Memory Read (lw from .rodata.mmode)
  [M-MODE TRAP] Contained PMP Load Access Fault (Unauthorized Read)
                mcause=0x00000005 mepc=0x80002080 mtval=0x80000740 -> policy=CONTAIN_AND_RECOVER (a0=-EACCES)
  [U-MODE VERIFIED] Exploit deterministically blocked and contained.

[TEST 3] Direct MMIO Peripheral Write (sb to UART0_BASE 0x10000000)
  [M-MODE TRAP] Contained PMP Store/AMO Access Fault (Unauthorized Write)
                mcause=0x00000007 mepc=0x800020b0 mtval=0x10000000 -> policy=CONTAIN_AND_RECOVER (a0=-EACCES)
  [U-MODE VERIFIED] Exploit deterministically blocked and contained.

[TEST 4] W^X Code Self-Modification (sw into R-X .text.umode)
  [M-MODE TRAP] Contained PMP Store/AMO Access Fault (Unauthorized Write)
                mcause=0x00000007 mepc=0x800020e4 mtval=0x80002028 -> policy=CONTAIN_AND_RECOVER (a0=-EACCES)
  [U-MODE VERIFIED] Exploit deterministically blocked and contained.

[TEST 5] NX Stack Shellcode Execution (jalr to RW- U-mode stack)
  [M-MODE TRAP] Contained PMP Instruction Access Fault (NX Violation)
                mcause=0x00000001 mepc=0x80004270 mtval=0x80004270 -> policy=CONTAIN_AND_RECOVER (a0=-EACCES)
  [U-MODE VERIFIED] Exploit deterministically blocked and contained.

[TEST 6] Privileged CSR Access in U-Mode (csrr mstatus)
  [M-MODE TRAP] Contained Illegal Instruction / Privileged CSR Access
                mcause=0x00000002 mepc=0x8000215c mtval=0x30002573 -> policy=CONTAIN_AND_RECOVER (a0=-EACCES)
  [U-MODE VERIFIED] Exploit deterministically blocked and contained.

[U-MODE] All 6/6 hardware isolation & syscall boundary checks PASSED.

[M-MODE] U-Mode requested SYS_EXIT. Total contained exploit attempts: 0x00000006
[M-MODE] Halting machine cleanly via sifive_test.
```
