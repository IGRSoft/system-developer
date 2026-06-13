# Tiny C fixture. The default target builds warning-clean and leak-free.
# The planted memory leak lives behind ENABLE_BUG so the happy path stays green.
#
#   make            # build clean (no leak)
#   make ENABLE_BUG=1   # compile the leaking path (for valgrind/LSan demos)
#   make run        # build and run
#   make clean

CC      ?= cc
CFLAGS  ?= -std=c17 -Wall -Wextra -O2
LDFLAGS ?=

BIN := wordcount

ifeq ($(ENABLE_BUG),1)
CPPFLAGS += -DENABLE_BUG
endif

.PHONY: all run clean

all: $(BIN)

$(BIN): wordcount.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ $< $(LDFLAGS)

run: $(BIN)
	./$(BIN)

clean:
	rm -f $(BIN)
