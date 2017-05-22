from __future__ import print_function
import os
import argparse
import time
import socket
import hashlib
import sys
import logging as LOG
import threading
from threading import Lock, Thread, Condition
from collections import namedtuple
from libc.string cimport memcpy


def thread_id():
    return threading.current_thread().name


cdef extern:
    int native_bismuth_miner( char *address_hex, char *db_block_hash_hex, int diff_len, int max_N, char *output_success, size_t *output_cyclecount )
    const char *native_bismuth_version()

__version__ = native_bismuth_version()


CONNECT_TIMEOUT = 5
POOL_PORT = 5657


MinerJob = namedtuple('MinerJob', ('diff', 'address', 'hash'))
MinerThreadResult = namedtuple('MinerThreadResult', ('job', 'cyclecount', 'block_key'))


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
        LOG.info('[*] Peer %r - Connected', self._sockaddr)
        return True

    def _getwork(self):
        diff = self._recv()
        if diff == 'wait':
            return None
        return MinerJob(float(diff), str(self._recv()), str(self._recv()))

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
    parser.add_argument('-t', '--threads', default=1, type=int, help="Number of mining threads")
    parser.add_argument('-p', '--pool', metavar="CONNECT", default='66.11.126.43:' + str(POOL_PORT),
                        help="Pool server port")
    parser.add_argument('rewards', metavar='REWARDS', nargs='?', help='Mining rewards public-key address')
    opts = parser.parse_args()
    LOG.basicConfig(level=opts.loglevel, format="%(asctime)-15s %(levelname)-8s %(message)s")
    return opts


class MinerThreadPool(object):
    __slots__ = ('_stop', 'nthreads', '_threads', '_lock', 'cond', 'results', 'job')
    def __init__(self, nthreads):
        self._stop = False
        self.nthreads = nthreads
        self._threads = list()
        self._lock = Lock()
        self.cond = Condition()
        self.results = list()
        self.job = None

    def wait(self, timeout=5):
        self.cond.acquire()
        LOG.debug('Waiting for sync condition')
        self.cond.wait(timeout)
        self.cond.release()

    def sync(self, new_job=None, timeout=5):
        LOG.debug('Acquiring sync condition')
        self.wait(timeout)

        LOG.debug('Locking MinerThreadPool')
        self.lock()
        try:
            old_job = self.job
            if new_job:
                self.job = new_job
            results = self.results
            self.results = list()
        finally:
            LOG.debug('Unlocking MinerThreadPool')
            self.unlock()
        return (old_job, results)

    def lock(self):
        LOG.debug('MinerThreadPool.lock begin - thread %r', thread_id())
        result = self._lock.acquire()
        LOG.debug('MinerThreadPool.lock success - thread %r', thread_id())
        return result

    def unlock(self):
        return self._lock.release()

    def _run(self):
        while True:
            self.lock()
            if self._stop:
                self.unlock()
                break
            job = self.job
            if not job:
                self.unlock()
                time.sleep(1)
                continue
            self.unlock()

            mine_args = (job.diff, job.address, job.hash, 500000, os.urandom(32))
            cyclecount, block_key = bismuth_mine(*mine_args)
            print("Finished", cyclecount)

            self.lock()
            try:
                self.results.append((job, cyclecount, block_key))
                self.cond.acquire()
                self.cond.notify_all()
                self.cond.release()
            finally:
                self.unlock()

    def stop(self):
        self._stop = True
        for thr in self._threads:
            print("joined", thr)
            thr.join()

    def start(self):
        for N in range(0, self.nthreads):
            thr = Thread(target=self._run, name='Miner-%d' % (N,))
            thr.start()


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
    time_begin = time.time()
    last_update = 0
    
    sock = socket.create_connection(peer[:2], timeout=CONNECT_TIMEOUT)
    sock.settimeout(None)
    miner_proto = MinerProtocol(sock, opts.rewards)
    miner_threads = MinerThreadPool(opts.threads)
    miner_threads.start()

    try:
        job = None
        while True:
            LOG.debug('Starting loop')
            # Periodically update user with statistics
            now = time.time()
            total_time = now - time_begin
            if last_update < (now - 10):
                if job:
                    LOG.info(' -  %.2f cycles/sec, %.2f avg submissions/min, difficulty %r',
                             total_cycles / total_time, (total_found / total_time) * 60, int(job.diff))
                else:
                    LOG.info(' -  Waiting for mining job...')
                last_update = now

            # Sync the thread pool status, retrieve results, update it with new job
            need_fetch = job is None        
            old_job, results_list = miner_threads.sync(job)

            # Loop through results, submitting results and updating counters
            for result_job, result_cycles, result_key in results_list:
                total_cycles += result_cycles

                result = None
                if result_key:
                    total_found += 1
                    difficulty = bismuth_difficulty(result_job.address, result_key, result_job.hash)
                    result = MinerJob(difficulty, result_job.hash, result_key)
                    LOG.info("[*] Submitting: difficulty=%d block=%s nonce=%s",
                             result.diff, result.address, result.hash)
                try:
                    job = miner_proto.fetch(result)
                except Exception:
                    LOG.exception('[!] Failed to fetch work')
                    break
                need_fetch = False

            # If there were no results from thread pool, or we need a new job, fetch a job
            if need_fetch:
                try:
                    job = miner_proto.fetch()
                    LOG.debug(' -  Fetched job: %r', job)
                except Exception:
                    LOG.exception('[!] Failed to fetch work')
                    break
    except KeyboardInterrupt:
        LOG.warning("Ctrl+C caught, graceful seppuku in honor of keyboard gods")

    miner_threads.stop()
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

