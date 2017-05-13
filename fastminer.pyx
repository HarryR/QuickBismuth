import hashlib
import sys
import binascii
from libc.string cimport memcpy

__all__ = ['fastminer']


cdef extern:
    int bismuth_miner( char *address_hex, char *db_block_hash_hex, int diff_len, int max_N, char *output_success )
    const char *bismuth_version( )

__version__ = bismuth_version()

cdef _bin_convert(string):
    return ''.join(format(ord(x), 'b') for x in string)


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
    memcpy(found_nonce, <void*>seed_str, 32)
    if bismuth_miner(address, db_block_hash, diff_len, int(N), found_nonce):
        if verify(address, found_nonce, db_block_hash, diff_len):
            return found_nonce
