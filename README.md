# FastBismuth is a Python module to mine Bismuth quickly

The `miner.py` file is slow and is Python, even with Cython the overhead of the python runtime are significant in comparison to optimised C code.

Included in this source package are two files:

 * fastmark.c - Implementation of Bismuth mining algorithm in C
 * fastminer.pyx - Python interface to native C code

This module can be integrated into the `miner.py` file to speed up the Bismuth mining process.
