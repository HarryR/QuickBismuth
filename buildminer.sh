#!/bin/sh
cc -O3 -flto -DFASTMARK_MAIN -I/usr/local/opt/openssl/include/ -fomit-frame-pointer -o fastmark.exe fastmark.c -L/usr/local/opt/openssl/lib -lcrypto
time ./fastmark.exe 6c68766ef2b0e8d9391d081f5889ad611e201cbfacdec8e697c0368f 53becc9a7eb13c90d9135307343c964a1e5d19ea2427fa79b2e2a716 20
cython --embed fastminer.pyx && gcc -pthread -shared -O3 -I/usr/local/opt/openssl/include/ -o fastminer.so `pkg-config python --cflags --libs` fastminer.c fastmark.c -L/usr/local/opt/openssl/lib -lcrypto

