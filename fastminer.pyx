from __future__ import print_function
import os
import argparse
import time
import socket
import hashlib
import sys
import logging as LOG
from collections import namedtuple
from libc.string cimport memcpy


cdef extern:
    int native_bismuth_miner( char *address_hex, char *db_block_hash_hex, int diff_len, int max_N, char *output_success, size_t *output_cyclecount )
    const char *native_bismuth_version()

__version__ = native_bismuth_version()


CONNECT_TIMEOUT = 5
POOL_PORT = 5659


MinerJob = namedtuple('MinerJob', ('diff', 'address', 'hash'))


class MinerProtocol(object):
    __slots__ = ('_sock', '_sockaddr', 'rewards')

    def __init__(self, sock, rewards=None):
        self._sock = sock
        self._sockaddr = sock.getpeername()
        self.rewards = rewards
        self._on_connect()

    def close(self):
        if self._sock:
            self._sock.close()
            self._sock = None

    def _on_connect(self):
        # Send our version identifier
        self._send('version', __version__, str(self.rewards))
        result = self._recv()
        if result != 'ok':
            raise socket.error("Protocol mismatch: %r" % (result,))
        LOG.info('Peer %r - Connected', self._sockaddr)
        return True

    def _getwork(self):
        try:
            return MinerJob(float(self._recv()), str(self._recv()), str(self._recv()))
        except Exception as ex:
            raise socket.error(ex)

    def fetch(self, job=None):
        if job is not None:
            return self.exch(job)
        self._send('miner_fetch')
        return self._getwork()

    def exch(self, job):
        if job is None:
            return self.fetch()
        self._send('miner_exch', job.diff, job.address, job.hash)
        return self._getwork()

    def _send(self, *args):
        for data in args:
            data = str(data)
            self._sock.sendall((str(len(data))).zfill(10))
            self._sock.sendall(data)

    def _recv(self, datalen=10):
        data = self._sock.recv(datalen)
        if not data:
            raise socket.error('No data')
        data = int(data)
        chunks = []
        bytes_recvd = 0
        while bytes_recvd < data:
            chunk = self._sock.recv(min(data - bytes_recvd, 2000))
            if chunk == b'':
                raise socket.error("Socket connection broken")
            chunks.append(chunk)
            bytes_recvd = bytes_recvd + len(chunk)
        segments = b''.join(chunks)
        return segments


def parse_args():
    parser = argparse.ArgumentParser(description='QuickBismuth Mining Node')
    parser.add_argument('-v', '--verbose', action='store_const',
                        dest="loglevel", const=LOG.INFO,
                        help="Log informational messages")
    parser.add_argument('--debug', action='store_const', dest="loglevel",
                        const=LOG.DEBUG, default=LOG.WARNING,
                        help="Log debugging messages")
    parser.add_argument('pool', metavar="CONNECT", default='66.11.126.43:' + str(POOL_PORT),
                        help="Pool server port", nargs='?')
    parser.add_argument('rewards', metavar='REWARDS', nargs='?', help='Mining rewards public-key address')
    opts = parser.parse_args()
    LOG.basicConfig(level=opts.loglevel, format="%(asctime)-15s %(levelname)-8s %(message)s")
    return opts


def main(args):
    opts = parse_args()

    # Connect to mining pool server
    peer = opts.pool.split(':')
    if len(peer) == 1:
        peer.append(POOL_PORT)
    peer[1] = int(peer[1])

    # Fetch jobs from server, and submit results in exchange for more work
    sock = None
    total_time = 0.0
    total_cycles = 0
    total_found = 0
    last_update = 0
    while True:
        try:
            sock = socket.create_connection(peer[:2], timeout=CONNECT_TIMEOUT)
            sock.settimeout(None)
            result = None
            miner = MinerProtocol(sock, opts.rewards)
            while True:
                try:
                    job = miner.fetch(result)
                except Exception:
                    LOG.exception('[!] Failed to fetch work')
                    break
                LOG.debug(' -  Fetched job: %r', job)

                # Use C module to find a suitable block-key
                block_key = None
                cyclecount = 500000
                mine_args = (job.diff, job.address, job.hash, cyclecount, os.urandom(32))

                cycles_begin = time.time()
                cyclecount, block_key = bismuth_mine(*mine_args)
                cycles_end = time.time()
                # cycles_duration = cycles_end - cycles_begin

                total_cycles += cyclecount
                total_time += cycles_end - cycles_begin
                success = block_key is not None
                if success:
                    total_found += 1

                if last_update < (cycles_end - 10):
                    LOG.info(' -  %.2f cycles/sec, %.2f avg submissions/min, difficulty %d',
                             total_cycles / total_time, (total_found / total_time) * 60, job.diff)
                    last_update = cycles_end

                if not success:
                    result = None
                    continue

                difficulty = bismuth_difficulty(job.address, block_key, job.hash)
                result = MinerJob(difficulty, job.hash, block_key)
                LOG.info("[*] Submitting: difficulty=%d block=%s nonce=%s",
                         result.diff, result.address, result.hash)
        except KeyboardInterrupt:
            break
        except socket.error:
            LOG.exception('[!] Pool %r - socket', peer)
            if sock:
                sock.close()
                sock = None
            result = None
        except Exception:
            LOG.exception("While mining...")
            break
        time.sleep(5)

    return 0





cdef _bin_convert(string):
    return ''.join(format(ord(x), 'b') for x in string)


def bismuth_difficulty(address, nonce, db_block_hash):
    needle = _bin_convert(db_block_hash)
    input = address + nonce + db_block_hash
    haystack = _bin_convert(hashlib.sha224(input).hexdigest())
    return max([N for N in range(1, len(needle) - 1) if needle[:N] in haystack])


def bismuth_verify(address, nonce, db_block_hash, diff_len):
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


def bismuth_mine(diff, address, db_block_hash, N=500000, seed=None):
    cdef int diff_len = int(diff)
    cdef char found_nonce[33]
    cdef char *seed_str = seed
    cdef size_t cyclecount = 0
    memcpy(found_nonce, <void*>seed_str, 32)
    if native_bismuth_miner(address, db_block_hash, diff_len, int(N), found_nonce, &cyclecount):
        if bismuth_verify(address, found_nonce, db_block_hash, diff_len):
            return cyclecount, found_nonce
    return cyclecount, None


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

