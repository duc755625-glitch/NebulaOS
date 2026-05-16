# NebulaOS x86_64 boot stub build (NASM)
#
# This produces a standalone ELF object (educational scaffolding)
# in nebulaos/build/asm/ without impacting the current boot pipeline.

ROOT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../../../..)
BUILD_DIR := $(ROOT_DIR)/build/asm

NASM ?= nasm
LD ?= ld
OBJCOPY ?= objcopy

STAGE0_DIR := $(ROOT_DIR)/arch/x86_64/boot/stage0
LINKER_DIR := $(ROOT_DIR)/arch/x86_64/boot/linker

STAGE0_OBJ := $(BUILD_DIR)/stage0.o
STAGE0_ELF := $(BUILD_DIR)/stage0.elf

CFLAGS := -f elf64

all: $(STAGE0_ELF)

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

$(STAGE0_OBJ): $(STAGE0_DIR)/boot_entry.asm | $(BUILD_DIR)
	$(NASM) -f elf64 -g -F dwarf "$<" -o "$@"

$(STAGE0_ELF): $(STAGE0_OBJ) | $(BUILD_DIR)
	$(LD) -T "$(LINKER_DIR)/linker.ld" -o "$@" "$<"

clean:
	rm -rf "$(BUILD_DIR)"/*

.PHONY: all clean

