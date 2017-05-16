import hashlib
import sys
import binascii
from libc.string cimport memcpy

__all__ = ['fastminer']


cdef extern:
    int bismuth_miner( char *address_hex, char *db_block_hash_hex, int diff_len, int max_N, char *output_success, size_t *output_cyclecount )
    const char *bismuth_version( )

__version__ = bismuth_version()

cdef _bin_convert(string):
    return ''.join(format(ord(x), 'b') for x in string)


def difficulty(address, nonce, db_block_hash):
    needle = _bin_convert(db_block_hash)
    input = address + nonce + db_block_hash
    haystack = _bin_convert(hashlib.sha224(input).hexdigest())
    return max([N for N in range(1, len(needle) - 1) if needle[:N] in haystack])


def verify(address, nonce, db_block_hash, diff_len):
    mining_search_bin = _bin_convert(db_block_hash)[0:diff_len]
    mining_input = address + nonce + db_block_hash
    mining_hash = hashlib.sha224(mining_input).hexdigest()
    mining_bin = _bin_convert(mining_hash)
    """
    print "---"
    print "VERIFY PYTHON:"
    print "\tNonce:", nonce
    print "\tDB Block hash:", db_block_hash
    print "\tMining input:", mining_input
    print "\tMining hash:", mining_hash  
    print "\tHaystack:", mining_bin
    print "\tNeedle:", mining_search_bin
    print "---"
    """
    if mining_search_bin in mining_bin:
        return True


def bismuth(diff, address, db_block_hash, N=500000, seed=None):
    cdef int diff_len = int(diff)
    cdef char found_nonce[33]
    cdef char *seed_str = seed
    cdef size_t cyclecount = 0
    memcpy(found_nonce, <void*>seed_str, 32)
    if bismuth_miner(address, db_block_hash, diff_len, int(N), found_nonce, &cyclecount):
        if verify(address, found_nonce, db_block_hash, diff_len):
            return cyclecount, found_nonce
    return cyclecount, None
