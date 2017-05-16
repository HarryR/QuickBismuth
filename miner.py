#!/usr/bin/env python
from __future__ import print_function
import os
import sys
import argparse
import time
import socket
import logging as LOG
from collections import namedtuple
import fastminer


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
        try:
            self._send('version', ' '.join([fastminer.__version__, self.rewards]))
            result = self._recv()
            if result != 'ok':
                raise socket.error("Protocol mismatch: %r" % (result,))
        except Exception as ex:
            raise socket.error("Connect/Hello error: %r" % (ex))
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
    parser.add_argument('pool', metavar="CONNECT", default='127.0.0.1:' + str(POOL_PORT),
                        help="Pool server port")
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
                LOG.debug(' - Fetched job: %r', job)

                # Use C module to find a suitable block-key
                block_key = None
                cyclecount = 500000
                mine_args = (job.diff, job.address, job.hash, cyclecount, os.urandom(32))
                cyclecount, block_key = fastminer.bismuth(*mine_args)
                if block_key is None:
                    result = None
                    continue

                difficulty = fastminer.difficulty(job.address, block_key, job.hash)
                result = MinerJob(difficulty, job.hash, block_key)
                LOG.info("[*] Submitting: difficulty=%d block=%s nonce=%s",
                         result.diff, result.address, result.hash)
        except KeyboardInterrupt:
            break
        except socket.error as ex:
            LOG.warning('[!] Pool %r - socket: %r', peer, ex)
            if sock:
                sock.close()
                sock = None
            result = None
        time.sleep(5)

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
