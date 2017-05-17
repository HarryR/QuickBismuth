CFLAGS?=-O3 -flto -I/usr/local/opt/openssl/include/ -fomit-frame-pointer -L/usr/local/opt/openssl/lib
PYTHON?=python
CYTHON?=cython
PLATFORM=$(shell uname -s).$(shell uname -p)
RELEASE_ZIP=bin/release-$(PLATFORM).zip

all: bin/bismuth.exe bin/fastminer.exe bin/fastminer.so $(RELEASE_ZIP)

lint:
	$(PYTHON) -mpylint -d missing-docstring -r n *.py

bin/bismuth.exe: bismuth.c
	$(CC) -DBISMUTH_MAIN $(CFLAGS) -o $@ $< -lcrypto

bin/fastminer.c: fastminer.pyx
	$(CYTHON) -o $@ -D fastminer.pyx

bin/fastminer.so: bin/fastminer.c bismuth.c
	$(CC) -pthread -fPIC -shared $(CFLAGS) -o $@ $+ `pkg-config python --cflags --libs` -lcrypto

bin/miner.c:
	$(CYTHON) -D --embed -o bin/miner.c fastminer.pyx

bin/fastminer.exe: bismuth.c bin/miner.c
	$(CC) -pthread -fPIC $(CFLAGS) -o $@ $+ `pkg-config python --cflags --libs` -lcrypto 
	strip -R .note -R .comment $@
	upx -9 $@

$(RELEASE_ZIP): bin/fastminer.exe miner.py
	cd bin && cp ../miner.py . && zip ../$@ fastminer.exe miner.py

clean:
	rm -f bin/*
