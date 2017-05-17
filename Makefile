CFLAGS?=-O3 -flto -I/usr/local/opt/openssl/include/ -fomit-frame-pointer -L/usr/local/opt/openssl/lib
PYTHON?=python
CYTHON?=cython

all: bin/bismuth.exe bin/miner.exe bin/fastminer.so

lint:
	$(PYTHON) -mpylint -d missing-docstring -r n *.py

bin/bismuth.exe: bismuth.c
	$(CC) -DBISMUTH_MAIN $(CFLAGS) -o $@ $< -lcrypto

bin/fastminer.c: fastminer.pyx
	$(CYTHON) -o $@ -D fastminer.pyx

bin/fastminer.so: bin/fastminer.c bismuth.c
	$(CC) -pthread -fPIC -shared $(CFLAGS) -o $@ $+ `pkg-config python --cflags --libs` -lcrypto

bin/miner.c:
	$(CYTHON) -D --embed -o bin/miner.c miner.py

bin/miner.exe: bismuth.c bin/fastminer.c bin/miner.c
	$(CC) -pthread -fPIC $(CFLAGS) -o $@ $+ `pkg-config python --cflags --libs` -lcrypto 
	strip -R .note -R .comment $@
	upx -9 $@

clean:
	rm -f bin/*
