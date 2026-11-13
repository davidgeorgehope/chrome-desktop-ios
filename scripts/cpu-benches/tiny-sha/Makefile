CC ?= cc
CFLAGS ?= -O2 -std=c11 -Wall -Wextra
tiny-sha: main.o sha256.o
	$(CC) $(CFLAGS) -o $@ main.o sha256.o
clean:
	rm -f tiny-sha main.o sha256.o
