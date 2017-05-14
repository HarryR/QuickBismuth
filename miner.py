#!/usr/bin/env python
from __future__ import print_function
import os
import sys
import socket
import logging as LOG
from collections import namedtuple, defaultdict
import fastminer


CONNECT_TIMEOUT = 5


MinerJob = namedtuple('MinerJob', ('diff', 'address', 'hash'))


class MinerProtocol(object):
    def __init__(self, sock):
        self.peer = sock.getpeername()
        self.sock = sock
        self._on_connect()

    def close(self):
        if self.sock:
            self.sock.close()
            self.sock = None

    def _on_connect(self):
        # Send our version identifier
        try:
            self._send('version', fastminer.__version__)
            result = self._recv()
            if result != 'ok':
                raise RuntimeError("Protocol mismatch: %r" % (result,))
        except Exception as ex:
            raise RuntimeError("Connect/Hello error: %r" % (ex))
        LOG.info('Peer %r - Connected', self.peer)
        return True

    def _getwork(self):
        return MinerJob(float(self._recv()), str(self._recv()), str(self._recv()))

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
            self.sock.sendall((str(len(data))).zfill(10))
            self.sock.sendall(data)

    def _recv(self, datalen=10):
        data = self.sock.recv(datalen)
        if not data:
            return None
        data = int(data)
        chunks = []
        bytes_recvd = 0
        while bytes_recvd < data:
            chunk = self.sock.recv(min(data - bytes_recvd, 2000))
            if chunk == b'':
                raise RuntimeError("Socket connection broken")
            chunks.append(chunk)
            bytes_recvd = bytes_recvd + len(chunk)
        segments = b''.join(chunks)
        return segments


def main(args):
    if not len(args):
        print("Usage: miner.py <pool-dns-or-ip> [port]")
        return 1

    LOG.basicConfig(level='INFO')

    # Connect to mining pool server
    pool_ip = args[0]
    port = int(args[1]) if len(args) > 1 else 5659
    sock = socket.create_connection((pool_ip, port), timeout=CONNECT_TIMEOUT)
    sock.settimeout(None)

    # Setup protocol and statistics structs
    miner = MinerProtocol(sock)
    histogram = defaultdict(int)

    # Fetch jobs from server, and submit results in exchange for more work
    result = None
    while True:
        try:
            job = miner.fetch(result)
        except Exception:
            LOG.exception('Failed to fetch work')
            break
        LOG.debug('Fetched job: %r', job)

        # Use C module to find a suitable block-key
        block_key = None
        try:
            cyclecount = 500000
            block_key = fastminer.bismuth(job.diff, job.address, job.hash, cyclecount, os.urandom(32))
        except KeyboardInterrupt:
            break
        if block_key is None:
            result = None
            continue

        difficulty = fastminer.difficulty(job.address, block_key, job.hash)
        result = MinerJob(difficulty, job.hash, block_key)
        LOG.info(" [*] Submitting: difficulty=%d block=%s nonce=%s",
                 result.diff, result.address, result.hash)
        histogram[difficulty] += 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
