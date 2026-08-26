# hardware/tests/Makefile — Native tests for shreed IPC lifecycle and safety

CC ?= gcc
CFLAGS := -std=gnu11 -Wall -Wextra -Werror -O2 -I../include
TEST := test-shreed
TEST_DAEMON := shreed-test-daemon
FULL_DAEMON_SRCS := ../daemon/shreed.c ../daemon/ipc.c ../daemon/events.c ../daemon/security.c
DAEMON_SRCS := ../daemon/ipc.c ../daemon/events.c ../daemon/security.c

.PHONY: all clean test

all: $(TEST) $(TEST_DAEMON)

$(TEST): test-shreed.c $(DAEMON_SRCS) ../include/shreed.h $(TEST_DAEMON)

	$(CC) $(CFLAGS) -o $@ test-shreed.c $(DAEMON_SRCS)

$(TEST_DAEMON): $(FULL_DAEMON_SRCS) ../include/shreed.h
	$(CC) $(CFLAGS) -o $@ $(FULL_DAEMON_SRCS)

test: $(TEST)
	./$(TEST) ./$(TEST_DAEMON)

clean:
	rm -f $(TEST) $(TEST_DAEMON)
