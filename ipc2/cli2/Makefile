
DEBUG_CFLAGS ?= -g

#CC=cc
CC=@clang
WARNINGS ?= -Weverything -Wno-objc-missing-property-synthesis -Wno-implicit-atomic-properties -Wno-direct-ivar-access -Wno-cstring-format-directive -Wno-padded -Wno-covered-switch-default -Wno-missing-prototypes -Werror-implicit-function-declaration
EXTRA_CFLAGS ?= -framework Foundation -framework CoreFoundation -mmacosx-version-min=10.10

CFLAGS  += $(DEBUG_CFLAGS) -fmodules -fobjc-arc $(WARNINGS) $(EXTRA_CFLAGS)
LDFLAGS += $(EXTRA_LDFLAGS)

all: hs

hs: hs.m
	$(CC) $< $(CFLAGS) $(LDFLAGS) -o $@

