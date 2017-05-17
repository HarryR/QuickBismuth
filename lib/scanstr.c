#include "stdendian.h"

#if BYTE_ORDER == BIG_ENDIAN
#   define  MSBF16(x)   (*(uint16_t const*__attribute((aligned(1))))x)
#   define  MSBF32(x)   (*(uint32_t const*__attribute((aligned(1))))x)
#else
#   define  MSBF16(x)   bswap16(*(uint16_t const*__attribute((aligned(1))))x)
#   define  MSBF32(x)   bswap32(*(uint32_t const*__attribute((aligned(1))))x)
#endif

static char const *
scanstr2(char const *tgt, char const pat[2])
{
    uint16_t head = MSBF16(pat), wind = 0, next;

    while ((next = *(uint8_t const*)tgt++)) {
        wind = ( wind << 8 ) + next;
        if (wind == head)
            return tgt - 2;
    }
    return  NULL;
}

// NOTE: MSBF32(pat) will never read beyond pat[] in memory,
//          because pat has a null-terminator.
static char const *
scanstr3(char const *tgt, char const pat[3])
{
    uint32_t head = MSBF32(pat), wind = 0, next;

    while ((next = *(uint8_t const*)tgt++)) {
        wind = (wind + next) << 8;
        if (wind == head)
            return tgt - 3;
    }
    return  NULL;
}

static char const *
scanstrm(char const *tgt, char const *pat, int len)
{
    uint32_t head = MSBF32(pat), wind = 0, next;

    pat += 4, len -= 4;
    while ((next = *(uint8_t const*)tgt++)) {
        wind = ( wind << 8 ) + next;
        if (wind == head && !memcmp(tgt, pat, len))
            return tgt - 4;
    }
    return  NULL;
}

char const *scanstr(char const *tgt, char const *pat, unsigned len)
{
    // unsigned     len = strlen(pat);
    switch (len) {
    case  0: return tgt;
    case  1: return strchr( tgt,*pat);
    case  2: return scanstr2(tgt, pat);
    case  3: return scanstr3(tgt, pat);
    default: return scanstrm(tgt, pat, len);
    }
}