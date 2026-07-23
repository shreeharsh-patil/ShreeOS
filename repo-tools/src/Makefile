# repo-tools/src/Makefile — Package builder tool for lpm

CROSS_COMPILE ?=
CC := $(CROSS_COMPILE)gcc
CFLAGS := -std=gnu11 -Wall -Wextra -Os -g -I../../pkgmanager/src
LDFLAGS := -static

SRCS := lpm-build.c ../../pkgmanager/src/json.c ../../pkgmanager/src/manifest.c
TARGET := lpm-build

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(SRCS)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

clean:
	rm -f $(TARGET) *.o
