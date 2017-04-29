PREFIX ?= /usr/local
LDFLAGS += -framework CoreFoundation -ledit

all: hs2

hs2: hs2.o

install: hs2
	mkdir -p $(PREFIX)/{share/man/man1,bin}
	install -m 0755 hs2 $(PREFIX)/bin
	install -m 0644 hs2.1 $(PREFIX)/share/man/man1

uninstall:
	rm -fr $(PREFIX)/bin/hs2
	rm -fr $(PREFIX)/share/man/man1/hs2.1

clean:
	rm -rf hs2.o hs2

.PHONY: all install clean
