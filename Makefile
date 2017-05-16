CFLAGS?=-O3 -flto -I/usr/local/opt/openssl/include/ -fomit-frame-pointer -L/usr/local/opt/openssl/lib
PYTHON?=python
CYTHON?=cython

all: bismuth.exe fastminer.so

lint:
	$(PYTHON) -mpylint -d missing-docstring -r n *.py

bismuth.exe: bismuth.c
	$(CC) -DBISMUTH_MAIN $(CFLAGS) -o $@ $< -lcrypto

fastminer.c: fastminer.pyx
	$(CYTHON) fastminer.pyx

fastminer.so: fastminer.c bismuth.c
	$(CC) -pthread -fPIC -shared $(CFLAGS) -o $@ $+ `pkg-config python --cflags --libs` -lcrypto

clean:
	rm -f fastminer.c *.so *.exe