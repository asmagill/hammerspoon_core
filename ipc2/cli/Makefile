
DEBUG_CFLAGS ?= -g

TARGET = hs
#CC=cc
CC=@clang
WARNINGS ?= -Weverything -Wno-objc-missing-property-synthesis -Wno-implicit-atomic-properties -Wno-direct-ivar-access -Wno-cstring-format-directive -Wno-padded -Wno-covered-switch-default -Wno-missing-prototypes -Werror-implicit-function-declaration
EXTRA_CFLAGS ?= -framework Foundation -framework CoreFoundation -mmacosx-version-min=10.10
EXTRA_LDFLAGS ?=  -ledit

CFLAGS  += $(DEBUG_CFLAGS) -fmodules -fobjc-arc $(WARNINGS) $(EXTRA_CFLAGS)
LDFLAGS += $(EXTRA_LDFLAGS)

all: $(TARGET)

$(TARGET): $(TARGET).m
	$(CC) $< $(CFLAGS) $(LDFLAGS) -o $@

clean:
	rm -fr $(TARGET) *.dSYM
