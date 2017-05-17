# -DUSE_SSE4_STRSTR
# -DUSE_FAST_STRSTR
# -DUSE_SCANSTR

OPTFLAGS?=-O3 -flto -fomit-frame-pointer -DUSE_SCANSTR

#OPTFLAGS=-O0 -ggdb

OS = $(shell uname -s)
ARCH = $(shell uname -m)


PACKAGES=python libcrypto


CFLAGS?=-fPIC $(OPTFLAGS) `pkg-config $(PACKAGES) --cflags`
PYTHON?=python
CYTHON?=cython
PLATFORM=$(shell uname -s)-$(shell uname -p)
RELEASE_ZIP=bin/release-$(PLATFORM).zip
LDLIBS?=`pkg-config $(PACKAGES) --libs`

ifeq ($(OS),Linux)
	LDLIBS += /usr/lib/x86_64-linux-gnu/libcrypto.a
endif

ifeq ($(OS),Darwin)
	CFLAGS += -I/usr/local/opt/openssl/include/ -L/usr/local/opt/openssl/lib
	LDLIBS += /usr/local/opt/openssl/lib/libcrypto.a
endif

EXE_EXT = $(PLATFORM).exe

MINER_EXE = QuickBismuth.Miner.$(EXE_EXT)

all: bin/bismuth.exe bin/$(MINER_EXE)

lint:
	$(PYTHON) -mpylint -d missing-docstring -r n *.py

bin/bismuth.exe: bismuth.c
	$(CC) -DBISMUTH_MAIN $(CFLAGS) -o $@ $< -lcrypto

bin/fastminer.c: fastminer.pyx
	$(CYTHON) --embed -o $@ -D fastminer.pyx

bin/$(MINER_EXE): bismuth.c bin/fastminer.c
	$(CC) -pthread $(CFLAGS) -o $@ $+ $(LDLIBS)


release: $(RELEASE_ZIP)

$(RELEASE_ZIP): bin/$(MINER_EXE) 
	strip $<
	cd bin && upx -9 $(MINER_EXE) zip ../$@ $(MINER_EXE)

clean:
	rm -f bin/*
