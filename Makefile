CFLAGS=-O3 -flto -I/usr/local/opt/openssl/include/ -fomit-frame-pointer -L/usr/local/opt/openssl/lib

all: bismuth.exe fastminer.so

bismuth.exe: bismuth.c
	$(CC) -DBISMUTH_MAIN $(CFLAGS) -o $@ $< -lcrypto

fastminer.c: fastminer.pyx
	cython fastminer.pyx

fastminer.so: fastminer.c bismuth.c
	$(CC) -pthread -fPIC -shared $(CFLAGS) -o $@ $+ `pkg-config python --cflags --libs` -lcrypto

clean:
	rm -f fastminer.c *.so *.exe