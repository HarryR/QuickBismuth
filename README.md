# QuickBismuth is a Python module to fastly mine the Bismuth

<img src="logo.png" align="left" height="100" />

The `miner.py` script connects to pool servers and requests blocks to mine, proof of work is submitted and used to evenly distribute the rewards when blocks are mined.

If Cython is available a native C module is compiled which boosts mining speed, this stub can be used to customise your miner dependant on your hardware.

Included in the source package is:

 * `miner.py` - Bismuth pool connection
 * `fastminer.pyx` - Cython interface module
 * `bismuth.c` - Fast Bismuth C miner
 * `benchmark.py` - Verify and compare miner speeds
 * `LICENSE` - source code distribution rights
