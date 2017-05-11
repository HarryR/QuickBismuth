#include <stdio.h>
#include <time.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <stdbool.h>

#include <openssl/sha.h>
#include <openssl/md5.h>
#include <libgen.h>


static int
hex2data(unsigned char *data, const char *hexstring, unsigned int len)
{
    const char *pos = hexstring;
    char *endptr;
    size_t count = 0;

    if ((hexstring[0] == '\0') || (strlen(hexstring) % 2)) {
        //hexstring contains no data
        //or hexstring has an odd length
        return -1;
    }

    for(count = 0; count < len; count++) {
        char buf[5] = {'0', 'x', pos[0], pos[1], 0};
        data[count] = strtol(buf, &endptr, 0);
        pos += 2 * sizeof(char);

        if (endptr[0] != '\0') {
            //non-hexadecimal character encountered
            return -1;
        }
    }

    return 0;
}


static inline void
conv_to_hex( unsigned char *str, size_t len, char *out )
{
	static const char * hex = "0123456789abcdef";
	for( size_t N = 0; N < len; N++ )
	{
		unsigned char raw = str[N];
		*out++ = hex[ (raw >> 4) & 0xF ];
		*out++ = hex[ raw & 0xF ];
	}
}


static inline int
byte_to_binary(char a, char *out)
{
	// The python strips leading zeroes
    int z, m = 0, k = 0;
    for (z = 0; z < 8; z++)
    {
    	char tmp = !!((a << z) & 0x80);
    	if( k == 0 ) {
    		if( tmp == 0 )
    			continue;
    		k = 1;
    	}
    	*out++ = '0' + tmp;
    	m++;
    }
    return m;
}


static inline size_t
raw2hexbin( unsigned char *str, size_t len, char *out )
{
	char *begin = out;
	static const char * hex = "0123456789abcdef";
	for( size_t N = 0; N < len; N++ )
	{
		unsigned char raw = str[N];
		out += byte_to_binary(hex[ (raw >> 4) & 0xF ], out);
		out += byte_to_binary(hex[ raw & 0xF ], out);
	}
	return out - begin;
}


static inline size_t
raw2bin( unsigned char *str, size_t len, char *out ) {
	char *begin = out;
	for( size_t N = 0; N < len; N++ )
	{
		out += byte_to_binary(str[N], out);
	}
	return out - begin;
}


/**
 * Finds the first occurrence of the sub-string needle in the string haystack.
 * Returns NULL if needle was not found.
 */
static inline char *
fast_strstr(const char *haystack, const char *needle)
{
    if (!*needle) // Empty needle.
        return (char *) haystack;

    const char    needle_first  = *needle;

    // First characters of haystack and needle are the same now. Both are
    // guaranteed to be at least one character long.
    // Now computes the sum of the first needle_len characters of haystack
    // minus the sum of characters values of needle.

    const char   *i_haystack    = haystack + 1
             ,   *i_needle      = needle   + 1;

    unsigned int  sums_diff     = *haystack;
    bool          identical     = true;

    while (*i_haystack && *i_needle) {
        sums_diff += *i_haystack;
        sums_diff -= *i_needle;
        identical &= *i_haystack++ == *i_needle++;
    }

    // i_haystack now references the (needle_len + 1)-th character.

    if (*i_needle) // haystack is smaller than needle.
        return NULL;
    else if (identical)
        return (char *) haystack;

    size_t        needle_len    = i_needle - needle;
    size_t        needle_len_1  = needle_len - 1;

    // Loops for the remaining of the haystack, updating the sum iteratively.
    const char   *sub_start;
    for (sub_start = haystack; *i_haystack; i_haystack++) {
        sums_diff -= *sub_start++;
        sums_diff += *i_haystack;

        // Since the sum of the characters is already known to be equal at that
        // point, it is enough to check just needle_len-1 characters for
        // equality.
        if (
               sums_diff == 0
            && needle_first == *sub_start // Avoids some calls to memcmp.
            && memcmp(sub_start, needle, needle_len_1) == 0
        )
            return (char *) sub_start;
    }

    return NULL;
}


#define SHA224_DIGEST_HEXLENGTH (SHA224_DIGEST_LENGTH * 2)
#define SHA224_DIGEST_HEXBINLENGTH (SHA224_DIGEST_HEXLENGTH * 8)
#define MD5_DIGEST_HEXLENGTH (MD5_DIGEST_LENGTH * 2)
#define MINING_HASH_LEN (SHA224_DIGEST_HEXLENGTH + MD5_DIGEST_HEXLENGTH + SHA224_DIGEST_HEXLENGTH)

int mine_bismuth( char *address_hex, char *db_block_hash_hex, int diff_len, int max_N, char *output_success )
{
	MD5_CTX nonce_ctx;
	unsigned char nonce_raw[MD5_DIGEST_LENGTH];

	SHA256_CTX mining_ctx;
	unsigned char mining_input[MINING_HASH_LEN + 1];
	unsigned char mining_search[SHA224_DIGEST_HEXBINLENGTH + 1];
	unsigned char mining_hash_raw[SHA224_DIGEST_LENGTH];
	unsigned char mining_hash_hexbin[(sizeof(mining_hash_raw) * 2 * 8) + 1];

	int count = 0;

	char db_block_hash[SHA224_DIGEST_LENGTH+1];
	hex2data(db_block_hash, db_block_hash_hex, SHA224_DIGEST_HEXLENGTH);

	raw2hexbin(db_block_hash, SHA224_DIGEST_LENGTH, mining_search);
	mining_search[diff_len] = 0;

	// Initialise mining input buffer with fixed strings
	memset(mining_input, 0, sizeof(mining_input));
	memcpy(mining_input, address_hex, SHA224_DIGEST_HEXLENGTH);
	conv_to_hex(db_block_hash, SHA224_DIGEST_LENGTH, &mining_input[SHA224_DIGEST_HEXLENGTH + MD5_DIGEST_HEXLENGTH]);
	mining_input[MINING_HASH_LEN] = 0;

	// Initialise shitty random
	MD5_Init(&nonce_ctx);
	MD5_Update(&nonce_ctx, (const unsigned char *)output_success, 32);
	MD5_Update(&nonce_ctx, (const unsigned char *)address_hex, strlen(address_hex));
	MD5_Update(&nonce_ctx, (const unsigned char *)db_block_hash_hex, strlen(db_block_hash_hex));

	// Main loop
	char *found = NULL;
	while( found == NULL && count++ < max_N )
	{
		// Cycle the NONCE, save into middle of mining_hash
		MD5_Update(&nonce_ctx, nonce_raw, MD5_DIGEST_LENGTH);
		MD5_Final(nonce_raw, &nonce_ctx);
		conv_to_hex(nonce_raw, MD5_DIGEST_LENGTH, &mining_input[SHA224_DIGEST_HEXLENGTH]);

		// Hash mining input buffer with SHA224
		SHA224_Init(&mining_ctx);
		SHA224_Update(&mining_ctx, mining_input, MINING_HASH_LEN);
		SHA224_Final(mining_hash_raw, &mining_ctx);

		// Find search substring within mining hash
		size_t mining_hash_hexbin_len = raw2hexbin(mining_hash_raw, sizeof(mining_hash_raw), mining_hash_hexbin);
		mining_hash_hexbin[mining_hash_hexbin_len] = 0;

		found = fast_strstr( mining_hash_hexbin, mining_search );	
	}

	// Success route - output nonce for validation
	if( found ) {
		conv_to_hex(nonce_raw, MD5_DIGEST_LENGTH, output_success);
		output_success[MD5_DIGEST_HEXLENGTH] = 0;

		char mining_hash_hex[SHA224_DIGEST_HEXLENGTH+1];
		conv_to_hex(mining_hash_raw, SHA224_DIGEST_LENGTH, mining_hash_hex);
		mining_hash_hex[SHA224_DIGEST_HEXLENGTH] = 0;
		
		printf("C LIBRARY:\n");
		printf("\tNonce: %s\n", output_success);
		printf("\tDB Block hash: %s\n", db_block_hash_hex);
		printf("\tMining input: %s\n", mining_input);
		printf("\tMining hash: %s\n", mining_hash_hex);
		printf("\tHaystack: %s\n", mining_hash_hexbin);
		printf("\tNeedle: %s\n", mining_search);
		printf("\tCount: %d\n", count);
		return 1;
	}

	return 0;
}

#ifdef FASTMARK_MAIN

int
main( int argc, char **argv )
{
	char *address_hex;	
	char *db_block_hash_hex;
	int diff;

	if( argc < 4 )
	{
		fprintf(stderr, "Usage: %s <address> <db_block_hash> <diff>\n", basename(argv[0]));
		exit(2);
	}
	address_hex = argv[1];
	db_block_hash_hex = argv[2];
	if( strlen(address_hex) != (SHA224_DIGEST_LENGTH*2) || strlen(db_block_hash_hex) != (SHA224_DIGEST_LENGTH*2) ) {
		fprintf(stderr, "Error: address or block hash length incorrect!\n");
		exit(3);
	}

	if( sscanf(argv[3], "%d", &diff) != 1 ) {
		fprintf(stderr, "Error: cannot parse diff: %s\n", argv[3]);
		exit(3);
	}

	char found_nonce[MD5_DIGEST_HEXLENGTH+1];
	memset(found_nonce, 0, sizeof(found_nonce));
	if( mine_bismuth( address_hex, db_block_hash_hex, diff, 10000000, found_nonce) ) {		
		printf("%s\n", found_nonce);
	}
	exit(1);
}

#endif
