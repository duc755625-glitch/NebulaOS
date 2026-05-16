ROOT := $(abspath ..)
BUILD := $(ROOT)/../out/kernel
SRC := $(ROOT)/src

CC := gcc
LD := ld
CFLAGS := -std=gnu11 -ffreestanding -O2 -Wall -Wextra -Wno-unused-parameter
LDFLAGS := -nostdlib -T link.ld

OBJS := $(BUILD)/main.o $(BUILD)/console.o

all: $(BUILD)/kernel.elf

$(BUILD):
	@mkdir -p $(BUILD)

$(BUILD)/main.o: $(SRC)/main.c | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/console.o: $(SRC)/console.c | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/kernel.elf: $(OBJS) $(ROOT)/link.ld
	$(LD) $(LDFLAGS) -o $@ $(OBJS)

clean:
	rm -rf $(BUILD)

