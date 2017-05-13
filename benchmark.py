import fastminer
import sys
import os
import time


def main():
    with open('benchmarks/%d-%s.csv' % (time.time(), fastminer.__version__), 'w') as handle:
        output = "\t".join(['diff', 'hit', 'persec', 'algo'])
        print(output)
        handle.write(output + "\n")
        try:
            for diff in range(8, 40):
                foundlist = []
                count = 0
                totaltime = 0.0
                while True:
                    address = os.urandom(28).encode('hex')
                    block_hash = os.urandom(28).encode('hex')
                    begin = time.time()
                    cyclecount = 100000
                    nonce = fastminer.bismuth(diff, address, block_hash, cyclecount, address)
                    end = time.time()
                    totaltime += (end - begin)
                    if nonce:
                        foundlist.append(end - begin)
                        # print("D:%d Found in %.2f" % (diff, end - begin,))
                    else:
                        # print("D:%d Not found in %.2f" % (diff, end - begin,))
                        pass
                    count += 1
                    if len(foundlist) > 50 or count > 100:
                        break
                persec = (len(foundlist) / totaltime) if len(foundlist) else 0
                output = "%d\t%.2f\t%.2f\t%s" % (
                         diff, len(foundlist) / (count / 100.0),
                         persec, fastminer.__version__)
                print(output)
                handle.write(output + "\n")
        except KeyboardInterrupt:
            pass

if __name__ == "__main__":
    sys.exit(main())
