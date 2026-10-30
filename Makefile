CROSS_COMPILE ?= riscv64-unknown-elf-
CC            := $(CROSS_COMPILE)gcc
OBJDUMP       := $(CROSS_COMPILE)objdump
QEMU          ?= qemu-system-riscv32

ARCH_FLAGS    := -march=rv32ima_zicsr_zifencei -mabi=ilp32
CFLAGS        := $(ARCH_FLAGS) -nostdlib -nostartfiles -ffreestanding -Wall -Wextra -Werror -Iinclude
LDFLAGS       := -T linker.ld -Wl,--Map=build/sandbox.map -Wl,--no-warn-rwx-segments

SRCS          := src/boot.S src/uart.S src/pmp.S src/trap.S src/umode_payload.S
BUILD_DIR     := build
TARGET        := $(BUILD_DIR)/riscv-pmp-sandbox.elf
DUMP          := $(BUILD_DIR)/riscv-pmp-sandbox.dump

.PHONY: all run disasm clean

all: $(TARGET)

$(TARGET): $(SRCS) linker.ld include/sandbox.inc
	@mkdir -p $(BUILD_DIR)
	$(CC) $(CFLAGS) $(LDFLAGS) $(SRCS) -o $(TARGET)

disasm: $(TARGET)
	$(OBJDUMP) -D -M no-aliases $(TARGET) > $(DUMP)

run: $(TARGET)
	$(QEMU) -machine virt -bios none -nographic -kernel $(TARGET)

clean:
	rm -rf $(BUILD_DIR)
