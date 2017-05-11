CFLAGS=-O3 -flto -I/usr/local/opt/openssl/include/ -fomit-frame-pointer -L/usr/local/opt/openssl/lib

all: fastbismuth.exe fastminer.so

fastbismuth.exe: fastmark.c
	$(CC) -DFASTMARK_MAIN $(CFLAGS) -o $@ $< -lcrypto

fastminer.c: fastminer.pyx
	cython fastminer.pyx

fastminer.so: fastminer.c
	$(CC) -pthread -shared $(CFLAGS) -o $@ $< `pkg-config python --cflags --libs` -lcrypto