/**
 * Computes xxHash hashes of arbitrary data. xxHash hashes are either uint32_t,
 * uint64_t or uint128_t quantities that are like a
 * checksum or CRC, but are more robust and very performant.
 *
$(SCRIPT inhibitQuickIndex = 1;)

$(DIVC quickindex,
$(BOOKTABLE ,
$(TR $(TH Category) $(TH Functions)
)
$(TR $(TDNW Template API) $(TD $(MYREF XXHTemplate)
)
)
$(TR $(TDNW OOP API) $(TD $(MYREF XXH32Digest))
)
$(TR $(TDNW Helpers) $(TD $(MYREF xxh32Of))
)
)
)

 * This module conforms to the APIs defined in `std.digest`. To understand the
 * differences between the template and the OOP API, see $(MREF std, digest).
 *
 * This module publicly imports $(MREF std, digest) and can be used as a stand-alone
 * module.
 *
 * License:   $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 *
 * CTFE:
 * Digests do not work in CTFE
 *
 * Authors:
 * Carsten Schlote, Piotr Szturmaj, Kai Nacke, Johannes Pfau $(BR)
 * The routines and algorithms are provided by the xxhash.[ch] source
 * provided at $(I git@github.com:Cyan4973/xxHash.git).
 *
 * References:
 *      $(LINK2 https://github.com/Cyan4973/xxHash, GitHub website of project)
 *
 * Source: $(PHOBOSSRC std/digest/xxh.d)
 *
 */

/* xxh.d - A wrapper for the original C implementation */
module xxhdd;

version (X86)
    version = HaveUnalignedLoads;
else version (X86_64)
    version = HaveUnalignedLoads;

//TODO: Properly detect this requirement.
//version = CheckACCAlignment;

//TODO: Check, if this code is an advantage over XXH provided code
//      The code from core.int128 doesn't inline.
//version = Have128BitInteger;

version (Have128BitInteger)
{
    import core.int128;
}

///
@safe unittest
{
    //Template API
    import xxhash3 : XXH_32;

    //Feeding data
    ubyte[1024] data;
    XXH_32 xxh;
    xxh.start();
    xxh.put(data[]);
    xxh.start(); //Start again
    xxh.put(data[]);
    auto hash = xxh.finish();
}

///
@safe unittest
{
    //OOP API
    import xxhash3 : XXH32Digest;

    auto xxh = new XXH32Digest();
    ubyte[] hash = xxh.digest("abc");
    assert(toHexString(hash) == "32D153FF", "Got " ~ toHexString(hash));

    //Feeding data
    ubyte[1024] data;
    xxh.put(data[]);
    xxh.reset(); //Start again
    xxh.put(data[]);
    hash = xxh.finish();
}

public import std.digest;

/* --- Port of C sources (release 0.8.1) to D language below ---------------- */

enum XXH_NO_STREAM = false;
enum XXH_SIZE_OPT = 0;
enum XXH_FORCE_ALIGN_CHECK = true;
enum XXH32_ENDJMP = false;

private import core.bitop : rol, bswap;
private import std.exception : enforce;
private import object : Exception;

/** Thrown on XXH errors. */
class XXHException : Exception
{
    import std.exception : basicExceptionCtors;
    ///
    mixin basicExceptionCtors;
}
///
@safe unittest
{
    import std.exception : enforce, assertThrown;
    assertThrown(enforce!XXHException(false, "Throw me..."));
}

/* *************************************
*  Misc
***************************************/

alias XXH32_hash_t = uint;
alias XXH64_hash_t = ulong;
/** Storage for 128bit hash digest */
align(16) struct XXH128_hash_t
{
    XXH64_hash_t low64; /** `value & 0xFFFFFFFFFFFFFFFF` */
    XXH64_hash_t high64; /** `value >> 64` */
}

alias XXH32_canonical_t = ubyte[XXH32_hash_t.sizeof];
static assert(XXH32_canonical_t.sizeof == 4, "32bit integers should be 4 bytes?");
alias XXH64_canonical_t = ubyte[XXH64_hash_t.sizeof];
static assert(XXH64_hash_t.sizeof == 8, "64bit integers should be 8 bytes?");
alias XXH128_canonical_t = ubyte[XXH128_hash_t.sizeof];
static assert(XXH128_hash_t.sizeof == 16, "128bit integers should be 16 bytes?");

enum XXH_VERSION_MAJOR = 0; /** XXHASH Major version */
enum XXH_VERSION_MINOR = 8; /** XXHASH Minor version */
enum XXH_VERSION_RELEASE = 1; /** XXHASH Build/Release version */

/** Version number, encoded as two digits each */
enum XXH_VERSION_NUMBER =
    (XXH_VERSION_MAJOR * 100 * 100 +
     XXH_VERSION_MINOR * 100 +
     XXH_VERSION_RELEASE);

/** Get version number */
uint xxh_versionNumber() @safe pure nothrow @nogc
{
    return XXH_VERSION_NUMBER;
}
///
@safe unittest
{
    assert(XXH_VERSION_NUMBER == xxh_versionNumber(), "Version mismatch");
}

/** The error code of public API functions */
enum XXH_errorcode
{
    XXH_OK = 0, /** OK */
    XXH_ERROR /** Error */
}

/** Structure for XXH32 streaming API.
 *
 * See: XXH64_state_s, XXH3_state_s
 */
struct XXH32_state_t
{
    XXH32_hash_t total_len_32; /** Total length hashed, modulo 2^32 */
    XXH32_hash_t large_len; /** Whether the hash is >= 16 (handles total_len_32 overflow) */
    XXH32_hash_t[4] v; /** Accumulator lanes */
    XXH32_hash_t[4] mem32; /** Internal buffer for partial reads. Treated as unsigned char[16]. */
    XXH32_hash_t memsize; /** Amount of data in mem32 */
    XXH32_hash_t reserved; /** Reserved field. Do not read nor write to it. */
}

/* Structure for XXH64 streaming API.
 *
 * See: XXH32_state_s, XXH3_state_s
 */
struct XXH64_state_t
{
    XXH64_hash_t total_len; /** Total length hashed. This is always 64-bit. */
    XXH64_hash_t[4] v; /** Accumulator lanes */
    XXH64_hash_t[4] mem64; /** Internal buffer for partial reads. Treated as unsigned char[32]. */
    XXH32_hash_t memsize; /** Amount of data in mem64 */
    XXH32_hash_t reserved32; /** Reserved field, needed for padding anyways*/
    XXH64_hash_t reserved64; /** Reserved field. Do not read or write to it. */
} /* typedef'd to XXH64_state_t */


/* ***************************
*  Memory reads
*****************************/

/** Enum to indicate whether a pointer is aligned.
 */
private enum XXH_alignment
{
    XXH_aligned, /** Aligned */
    XXH_unaligned /** Possibly unaligned */
}

private uint xxh_read32(const void* ptr) @trusted pure nothrow @nogc
{
    uint val;
    version (HaveUnalignedLoads)
        val = *(cast(uint*) ptr);
    else
        (cast(ubyte*)&val)[0 .. uint.sizeof] = (cast(ubyte*) ptr)[0 .. uint.sizeof];
    return val;
}

private uint xxh_readLE32(const void* ptr) @safe pure nothrow @nogc
{
    version (LittleEndian)
        return xxh_read32(ptr);
    else
        return bswap(xxh_read32(ptr));
}

private uint xxh_readBE32(const void* ptr) @safe pure nothrow @nogc
{
    version (LittleEndian)
        return bswap(xxh_read32(ptr));
    else
        return xxh_read32(ptr);
}

private uint xxh_readLE32_align(const void* ptr, XXH_alignment align_) @trusted pure nothrow @nogc
{
    if (align_ == XXH_alignment.XXH_unaligned)
    {
        return xxh_readLE32(ptr);
    }
    else
    {
        version (LittleEndian)
            return *cast(const uint*) ptr;
        else
            return bswap(*cast(const uint*) ptr);
    }
}

/* *******************************************************************
*  32-bit hash functions
*********************************************************************/

enum XXH_PRIME32_1 = 0x9E3779B1U; /** 0b10011110001101110111100110110001 */
enum XXH_PRIME32_2 = 0x85EBCA77U; /** 0b10000101111010111100101001110111 */
enum XXH_PRIME32_3 = 0xC2B2AE3DU; /** 0b11000010101100101010111000111101 */
enum XXH_PRIME32_4 = 0x27D4EB2FU; /** 0b00100111110101001110101100101111 */
enum XXH_PRIME32_5 = 0x165667B1U; /** 0b00010110010101100110011110110001 */

/**  Normal stripe processing routine.
 *
 * This shuffles the bits so that any bit from @p input impacts several bits in
 * acc.
 *
 * Param: acc = The accumulator lane.
 * Param: input = The stripe of input to mix.
 * Return: The mixed accumulator lane.
 */
private uint xxh32_round(uint acc, uint input) @safe pure nothrow @nogc
{
    acc += input * XXH_PRIME32_2;
    acc = rol(acc, 13);
    acc *= XXH_PRIME32_1;
    return acc;
}

/** Mixes all bits to finalize the hash.
 *
 * The final mix ensures that all input bits have a chance to impact any bit in
 * the output digest, resulting in an unbiased distribution.
 *
 * Param: hash = The hash to avalanche.
 * Return The avalanched hash.
 */
private uint xxh32_avalanche(uint hash) @safe pure nothrow @nogc
{
    hash ^= hash >> 15;
    hash *= XXH_PRIME32_2;
    hash ^= hash >> 13;
    hash *= XXH_PRIME32_3;
    hash ^= hash >> 16;
    return hash;
}

/* Alias wrapper for xxh_readLE32_align() */
private uint xxh_get32bits(const void* p, XXH_alignment align_) @safe pure nothrow @nogc
{
    return xxh_readLE32_align(p, align_);
}

/** Processes the last 0-15 bytes of @p ptr.
 *
 * There may be up to 15 bytes remaining to consume from the input.
 * This final stage will digest them to ensure that all input bytes are present
 * in the final mix.
 *
 * Param: hash = The hash to finalize.
 * Param: ptr = The pointer to the remaining input.
 * Param: len = The remaining length, modulo 16.
 * Param: align = Whether @p ptr is aligned.
 * Return: The finalized hash.
 * See: xxh64_finalize().
 */
private uint xxh32_finalize(uint hash, const(ubyte)* ptr, size_t len, XXH_alignment align_)
    @trusted pure nothrow @nogc
{
    static void XXH_PROCESS1(ref uint hash, ref const(ubyte)* ptr)
    {
        hash += (*ptr++) * XXH_PRIME32_5;
        hash = rol(hash, 11) * XXH_PRIME32_1;
    }

    void XXH_PROCESS4(ref uint hash, ref const(ubyte)* ptr)
    {
        hash += xxh_get32bits(ptr, align_) * XXH_PRIME32_3;
        ptr += 4;
        hash = rol(hash, 17) * XXH_PRIME32_4;
    }

    /* Compact rerolled version; generally faster */
    if (!XXH32_ENDJMP)
    {
        len &= 15;
        while (len >= 4)
        {
            XXH_PROCESS4(hash, ptr);
            len -= 4;
        }
        while (len > 0)
        {
            XXH_PROCESS1(hash, ptr);
            --len;
        }
        return xxh32_avalanche(hash);
    }
    else
    {
        switch (len & 15) /* or switch (bEnd - p) */
        {
        case 12:
            XXH_PROCESS4(hash, ptr);
            goto case;
        case 8:
            XXH_PROCESS4(hash, ptr);
            goto case;
        case 4:
            XXH_PROCESS4(hash, ptr);
            return xxh32_avalanche(hash);

        case 13:
            XXH_PROCESS4(hash, ptr);
            goto case;
        case 9:
            XXH_PROCESS4(hash, ptr);
            goto case;
        case 5:
            XXH_PROCESS4(hash, ptr);
            XXH_PROCESS1(hash, ptr);
            return xxh32_avalanche(hash);

        case 14:
            XXH_PROCESS4(hash, ptr);
            goto case;
        case 10:
            XXH_PROCESS4(hash, ptr);
            goto case;
        case 6:
            XXH_PROCESS4(hash, ptr);
            XXH_PROCESS1(hash, ptr);
            XXH_PROCESS1(hash, ptr);
            return xxh32_avalanche(hash);

        case 15:
            XXH_PROCESS4(hash, ptr);
            goto case;
        case 11:
            XXH_PROCESS4(hash, ptr);
            goto case;
        case 7:
            XXH_PROCESS4(hash, ptr);
            goto case;
        case 3:
            XXH_PROCESS1(hash, ptr);
            goto case;
        case 2:
            XXH_PROCESS1(hash, ptr);
            goto case;
        case 1:
            XXH_PROCESS1(hash, ptr);
            goto case;
        case 0:
            return xxh32_avalanche(hash);
        default:
            assert(0, "Internal error");
        }
        return hash; /* reaching this point is deemed impossible */
    }
}

/** The implementation for XXH32().
 *
 * Params:
 *  input = Directly passed from XXH32().
 *  len = Ditto
 *  seed = Ditto
 *  align_ = Whether input is aligned.
 * Return: The calculated hash.
 */
private uint xxh32_endian_align(
    const(ubyte)* input, size_t len, uint seed, XXH_alignment align_)
    @trusted pure nothrow @nogc
{
    uint h32;

    if (len >= 16)
    {
        const ubyte* bEnd = input + len;
        const ubyte* limit = bEnd - 15;
        uint v1 = seed + XXH_PRIME32_1 + XXH_PRIME32_2;
        uint v2 = seed + XXH_PRIME32_2;
        uint v3 = seed + 0;
        uint v4 = seed - XXH_PRIME32_1;

        do
        {
            v1 = xxh32_round(v1, xxh_get32bits(input, align_));
            input += 4;
            v2 = xxh32_round(v2, xxh_get32bits(input, align_));
            input += 4;
            v3 = xxh32_round(v3, xxh_get32bits(input, align_));
            input += 4;
            v4 = xxh32_round(v4, xxh_get32bits(input, align_));
            input += 4;
        }
        while (input < limit);

        h32 = rol(v1, 1) + rol(v2, 7) + rol(v3, 12) + rol(v4, 18);
    }
    else
    {
        h32 = seed + XXH_PRIME32_5;
    }

    h32 += cast(uint) len;

    return xxh32_finalize(h32, input, len & 15, align_);
}

/* XXH PUBLIC API - hidden in D module ! */
/** Calculate a XXH32 digest on provided data
 *
 * Params:
 *   input = Pointer to data
 *   len = length of datablock
 *   seed = seed value
 * Returns: a XXH32_hash_t
 */
private XXH32_hash_t XXH32(const void* input, size_t len, XXH32_hash_t seed)
    @safe pure nothrow @nogc
{
    static if (!XXH_NO_STREAM && XXH_SIZE_OPT >= 2)
    {
        /* Simple version, good for code maintenance, but unfortunately slow for small inputs */
        XXH32_state_t state;
        auto rc = xxh32_reset(&state, seed);
        if (rc == XXH_errorcode.XXH_OK)
        {
            rc = xxh32_update(&state, cast(const(ubyte)*) input, len);
            if (rc == XXH_errorcode.XXH_OK)
            {
                return xxh32_digest(&state);
            }
        }
        return XXH_errorcode.XXH_ERROR;
    }
    else
    {
        if (XXH_FORCE_ALIGN_CHECK)
        {
            if (((cast(size_t) input) & 3) == 0)
            { /* Input is 4-bytes aligned, leverage the speed benefit */
                return xxh32_endian_align(cast(const(ubyte)*) input, len,
                        seed, XXH_alignment.XXH_aligned);
            }
        }

        return xxh32_endian_align(cast(const(ubyte)*) input, len, seed,
                XXH_alignment.XXH_unaligned);
    }
}

/* XXH PUBLIC API - hidden in D module */
/** Reset state with seed
 *
 * Params:
 *   state = Pointer to state structure
 *   seed = A seed value
 * Returns: XXH_errorcode.OK or XXH_errorcode.FAIL
 */
private XXH_errorcode xxh32_reset(XXH32_state_t* statePtr, XXH32_hash_t seed)
    @safe pure nothrow @nogc
in (statePtr != null, "statePtr is null")
{
    *statePtr = XXH32_state_t.init;
    statePtr.v[0] = seed + XXH_PRIME32_1 + XXH_PRIME32_2;
    statePtr.v[1] = seed + XXH_PRIME32_2;
    statePtr.v[2] = seed + 0;
    statePtr.v[3] = seed - XXH_PRIME32_1;
    return XXH_errorcode.XXH_OK;
}

/* XXH PUBLIC API - hidden in D module */
/** Update the state with some more data
 *
 * Params:
 *   state = Pointer to state structure
 *   input = A pointer to data
 *   len = length of input data
 * Returns: XXH_errorcode.OK or XXH_errorcode.FAIL
 */
private XXH_errorcode xxh32_update(XXH32_state_t* state, const void* input, size_t len)
    @trusted pure nothrow @nogc
in
{
    if (input == null) assert(len == 0, "input null ptr only allowed with len == 0");
}
do
{
    if (input == null && len == 0)
        return XXH_errorcode.XXH_OK;
    else if (input == null && len != 0)
        return XXH_errorcode.XXH_ERROR;
    else
    {
        const(ubyte)* p = cast(const(ubyte)*) input;
        const ubyte* bEnd = p + len;

        state.total_len_32 += cast(XXH32_hash_t) len;
        state.large_len |= cast(XXH32_hash_t)((len >= 16) | (state.total_len_32 >= 16));

        if (state.memsize + len < 16)
        {
            /* fill in tmp buffer */
            (cast(ubyte*) state.mem32)[state.memsize .. state.memsize + len] = (cast(ubyte*) input)[0 .. len];
            state.memsize += cast(XXH32_hash_t) len;
            return XXH_errorcode.XXH_OK;
        }

        if (state.memsize)
        {
            /* some data left from previous update */
            (cast(ubyte*) state.mem32)[state.memsize .. state.memsize + (16 - state.memsize)] =
                (cast(ubyte*) input)[0 .. (16 - state.memsize)];
            {
                const(uint)* p32 = cast(const(uint)*)&state.mem32[0];
                state.v[0] = xxh32_round(state.v[0], xxh_readLE32(p32));
                p32++;
                state.v[1] = xxh32_round(state.v[1], xxh_readLE32(p32));
                p32++;
                state.v[2] = xxh32_round(state.v[2], xxh_readLE32(p32));
                p32++;
                state.v[3] = xxh32_round(state.v[3], xxh_readLE32(p32));
            }
            p += 16 - state.memsize;
            state.memsize = 0;
        }

        if (p <= bEnd - 16)
        {
            const ubyte* limit = bEnd - 16;

            do
            {
                state.v[0] = xxh32_round(state.v[0], xxh_readLE32(p));
                p += 4;
                state.v[1] = xxh32_round(state.v[1], xxh_readLE32(p));
                p += 4;
                state.v[2] = xxh32_round(state.v[2], xxh_readLE32(p));
                p += 4;
                state.v[3] = xxh32_round(state.v[3], xxh_readLE32(p));
                p += 4;
            }
            while (p <= limit);

        }

        if (p < bEnd)
        {
            (cast(ubyte*) state.mem32)[0 .. cast(size_t)(bEnd - p) ] =
                (cast(ubyte*) p)[0 .. cast(size_t)(bEnd - p) ];
            state.memsize = cast(XXH32_hash_t)(bEnd - p);
        }
    }

    return XXH_errorcode.XXH_OK;
}

/* XXH PUBLIC API - hidden in D module */
/** Finalize state and return the final XXH32 digest
 *
 * Params:
 *   state = Pointer to state structure
 * Returns: the final XXH32 digest
 */
private XXH32_hash_t xxh32_digest(const XXH32_state_t* state)
    @trusted pure nothrow @nogc
{
    uint h32;

    if (state.large_len)
    {
        h32 = rol(state.v[0], 1) + rol(state.v[1], 7) +
               rol(state.v[2], 12) + rol(state.v[3], 18);
    }
    else
    {
        h32 = state.v[2] /* == seed */  + XXH_PRIME32_5;
    }

    h32 += state.total_len_32;

    return xxh32_finalize(h32, cast(const ubyte*) state.mem32, state.memsize,
            XXH_alignment.XXH_aligned);
}

/* XXH PUBLIC API - hidden in D module */
/** Covert the XXH32_hash_t to a byte array of same size
 *
 * Params:
 *   dst = Pointer to target storage
 *   hash = a XXH32_hash_t value
 * Returns: nothing
 */
private void xxh32_canonicalFromHash(XXH32_canonical_t* dst, XXH32_hash_t hash)
    @trusted pure nothrow @nogc
{
    static assert((XXH32_canonical_t).sizeof == (XXH32_hash_t).sizeof,
                    "(XXH32_canonical_t).sizeof != (XXH32_hash_t).sizeof");
    version (LittleEndian)
        hash = bswap(hash);
    (cast(ubyte*) dst) [0 .. dst.sizeof] = (cast(ubyte*) &hash) [0 .. dst.sizeof];
}

/* XXH PUBLIC API - hidden in D module */
/** Covert the XXH32_hash_t to a byte array of same size
 *
 * Params:
 *   src = Pointer to source storage
 * Returns: the converted value as XXH32_hash_t
 */
 private XXH32_hash_t xxh32_hashFromCanonical(const XXH32_canonical_t* src) @safe pure nothrow @nogc
{
    return xxh_readBE32(src);
}

/* ----------------------------------------------------------------------------------------*/

/* Helper functions to read 64bit data quantities from memory follow */

private ulong xxh_read64(const void* ptr)
    @trusted pure nothrow @nogc
{
    ulong val;
    version (HaveUnalignedLoads)
        val = *(cast(ulong*) ptr);
    else
        (cast(ubyte*)&val)[0 .. ulong.sizeof] = (cast(ubyte*) ptr)[0 .. ulong.sizeof];
    return val;
}

private ulong xxh_readLE64(const void* ptr)
    @safe pure nothrow @nogc
{
    version (LittleEndian)
        return xxh_read64(ptr);
    else
        return bswap(xxh_read64(ptr));
}

private ulong xxh_readBE64(const void* ptr)
    @safe pure nothrow @nogc
{
    version (LittleEndian)
        return bswap(xxh_read64(ptr));
    else
        return xxh_read64(ptr);
}

private ulong xxh_readLE64_align(const void* ptr, XXH_alignment align_)
    @trusted pure nothrow @nogc
{
    if (align_ == XXH_alignment.XXH_unaligned)
    {
        return xxh_readLE64(ptr);
    }
    else
    {
        version (LittleEndian)
            return *cast(const ulong*) ptr;
        else
            return bswap(*cast(const ulong*) ptr);
    }
}

enum XXH_PRIME64_1 = 0x9E3779B185EBCA87; /** 0b1001111000110111011110011011000110000101111010111100101010000111 */
enum XXH_PRIME64_2 = 0xC2B2AE3D27D4EB4F; /** 0b1100001010110010101011100011110100100111110101001110101101001111 */
enum XXH_PRIME64_3 = 0x165667B19E3779F9; /** 0b0001011001010110011001111011000110011110001101110111100111111001 */
enum XXH_PRIME64_4 = 0x85EBCA77C2B2AE63; /** 0b1000010111101011110010100111011111000010101100101010111001100011 */
enum XXH_PRIME64_5 = 0x27D4EB2F165667C5; /** 0b0010011111010100111010110010111100010110010101100110011111000101 */

private ulong xxh64_round(ulong acc, ulong input)
    @safe pure nothrow @nogc
{
    acc += input * XXH_PRIME64_2;
    acc = rol(acc, 31);
    acc *= XXH_PRIME64_1;
    return acc;
}

private ulong xxh64_mergeRound(ulong acc, ulong val)
    @safe pure nothrow @nogc
{
    val = xxh64_round(0, val);
    acc ^= val;
    acc = acc * XXH_PRIME64_1 + XXH_PRIME64_4;
    return acc;
}

private ulong xxh64_avalanche(ulong hash)
    @safe pure nothrow @nogc
{
    hash ^= hash >> 33;
    hash *= XXH_PRIME64_2;
    hash ^= hash >> 29;
    hash *= XXH_PRIME64_3;
    hash ^= hash >> 32;
    return hash;
}

ulong xxh_get64bits(const void* p, XXH_alignment align_)
    @safe pure nothrow @nogc
{
    return xxh_readLE64_align(p, align_);
}

/** Processes the last 0-31 bytes of data at ptr addr.
 *
 * There may be up to 31 bytes remaining to consume from the input.
 * This final stage will digest them to ensure that all input bytes are present
 * in the final mix.
 *
 * Param: hash = The hash to finalize.
 * Param: ptr = The pointer to the remaining input.
 * Param: len = The remaining length, modulo 32.
 * Param: align = Whether @p ptr is aligned.
 * Return: The finalized hash
 * See: xxh32_finalize().
 */
private ulong xxh64_finalize(ulong hash, const(ubyte)* ptr, size_t len, XXH_alignment align_)
    @trusted pure nothrow @nogc
in
{
    if (ptr == null) assert(len == 0, "input null ptr only allowed with len == 0");
}
do
{
    len &= 31;
    while (len >= 8)
    {
        const ulong k1 = xxh64_round(0, xxh_get64bits(ptr, align_));
        ptr += 8;
        hash ^= k1;
        hash = rol(hash, 27) * XXH_PRIME64_1 + XXH_PRIME64_4;
        len -= 8;
    }
    if (len >= 4)
    {
        hash ^= cast(ulong)(xxh_get32bits(ptr, align_)) * XXH_PRIME64_1;
        ptr += 4;
        hash = rol(hash, 23) * XXH_PRIME64_2 + XXH_PRIME64_3;
        len -= 4;
    }
    while (len > 0)
    {
        hash ^= (*ptr++) * XXH_PRIME64_5;
        hash = rol(hash, 11) * XXH_PRIME64_1;
        --len;
    }
    return xxh64_avalanche(hash);
}

/** The implementation for XXH64().
 *
 * Params:
 *   input = pointer to input data, directly passed from XXH64()
 *   len = length of input data, directly passed from XXH64()
 *   seed = Seed value, directly passed from XXH64()
 *   align = Whether input pointer is aligned.
 * Return: The calculated hash.
 */
private ulong xxh64_endian_align(
    const(ubyte)* input, size_t len,
    ulong seed, XXH_alignment align_)
    @trusted pure nothrow @nogc
in
{
    if (input == null) assert(len == 0, "input null ptr only allowed with len == 0");
}
do
{
    ulong h64;

    if (len >= 32)
    {
        const ubyte* bEnd = input + len;
        const ubyte* limit = bEnd - 31;
        ulong v1 = seed + XXH_PRIME64_1 + XXH_PRIME64_2;
        ulong v2 = seed + XXH_PRIME64_2;
        ulong v3 = seed + 0;
        ulong v4 = seed - XXH_PRIME64_1;

        do
        {
            v1 = xxh64_round(v1, xxh_get64bits(input, align_));
            input += 8;
            v2 = xxh64_round(v2, xxh_get64bits(input, align_));
            input += 8;
            v3 = xxh64_round(v3, xxh_get64bits(input, align_));
            input += 8;
            v4 = xxh64_round(v4, xxh_get64bits(input, align_));
            input += 8;
        }
        while (input < limit);

        h64 = rol(v1, 1) + rol(v2, 7) + rol(v3, 12) + rol(v4, 18);
        h64 = xxh64_mergeRound(h64, v1);
        h64 = xxh64_mergeRound(h64, v2);
        h64 = xxh64_mergeRound(h64, v3);
        h64 = xxh64_mergeRound(h64, v4);

    }
    else
    {
        h64 = seed + XXH_PRIME64_5;
    }

    h64 += cast(ulong) len;

    return xxh64_finalize(h64, input, len, align_);
}

/* XXH PUBLIC API - hidden in D module */

private XXH64_hash_t XXH64(const void* input, size_t len, XXH64_hash_t seed)
    @safe pure nothrow @nogc
{
    static if (!XXH_NO_STREAM && XXH_SIZE_OPT >= 2)
    {
        /* Simple version, good for code maintenance, but unfortunately slow for small inputs */
        XXH64_state_t state;
        auto rc = xxh64_reset(&state, seed);
        if (rc == XXH_errorcode.XXH_OK)
        {
            rc = xxh64_update(&state, cast(const(ubyte)*) input, len);
            if (rc == XXH_errorcode.XXH_OK)
            {
                return xxh64_digest(&state);
            }
        }
        return XXH_errorcode.XXH_ERROR;
    }
    else
    {
        if (XXH_FORCE_ALIGN_CHECK)
        {
            if (((cast(size_t) input) & 7) == 0)
            { /* Input is aligned, let's leverage the speed advantage */
                return xxh64_endian_align(cast(const(ubyte)*) input, len,
                        seed, XXH_alignment.XXH_aligned);
            }
        }

        return xxh64_endian_align(cast(const(ubyte)*) input, len, seed,
                XXH_alignment.XXH_unaligned);
    }
}

/* XXH PUBLIC API - hidden in D module */
private XXH_errorcode xxh64_reset(XXH64_state_t* statePtr, XXH64_hash_t seed)
    @safe pure nothrow @nogc
{
    assert(statePtr != null, "statePtr == null");
    *statePtr = XXH64_state_t.init;
    statePtr.v[0] = seed + XXH_PRIME64_1 + XXH_PRIME64_2;
    statePtr.v[1] = seed + XXH_PRIME64_2;
    statePtr.v[2] = seed + 0;
    statePtr.v[3] = seed - XXH_PRIME64_1;
    return XXH_errorcode.XXH_OK;
}

/* XXH PUBLIC API - hidden in D module */
private XXH_errorcode xxh64_update(XXH64_state_t* state, const void* input, size_t len)
    @trusted pure nothrow @nogc
in
{
    if (input == null) assert(len == 0, "input null ptr only allowed with len == 0");
}
do
{
    if (input == null && len == 0)
        return XXH_errorcode.XXH_OK;
    else if (input == null && len != 0)
        return XXH_errorcode.XXH_ERROR;
    else
    {
        const(ubyte)* p = cast(const(ubyte)*) input;
        const ubyte* bEnd = p + len;

        state.total_len += len;

        if (state.memsize + len < 32)
        {
            /* fill in tmp buffer */
            (cast(ubyte*) state.mem64) [state.memsize .. state.memsize + len] =
                 (cast(ubyte*) input) [0 .. len];
            state.memsize += cast(uint) len;
            return XXH_errorcode.XXH_OK;
        }

        if (state.memsize)
        {
            /* tmp buffer is full */
            (cast(ubyte*) state.mem64) [state.memsize .. state.memsize + (32 - state.memsize)] =
                 (cast(ubyte*) input) [0 .. (32 - state.memsize)];
            state.v[0] = xxh64_round(state.v[0], xxh_readLE64(&state.mem64[0]));
            state.v[1] = xxh64_round(state.v[1], xxh_readLE64(&state.mem64[1]));
            state.v[2] = xxh64_round(state.v[2], xxh_readLE64(&state.mem64[2]));
            state.v[3] = xxh64_round(state.v[3], xxh_readLE64(&state.mem64[3]));
            p += 32 - state.memsize;
            state.memsize = 0;
        }

        if (p + 32 <= bEnd)
        {
            const ubyte* limit = bEnd - 32;

            do
            {
                state.v[0] = xxh64_round(state.v[0], xxh_readLE64(p));
                p += 8;
                state.v[1] = xxh64_round(state.v[1], xxh_readLE64(p));
                p += 8;
                state.v[2] = xxh64_round(state.v[2], xxh_readLE64(p));
                p += 8;
                state.v[3] = xxh64_round(state.v[3], xxh_readLE64(p));
                p += 8;
            }
            while (p <= limit);

        }

        if (p < bEnd)
        {
            (cast(void*) &state.mem64[0]) [0 .. cast(size_t) (bEnd - p)] =
                (cast(void*) p) [0 .. cast(size_t) (bEnd - p)];
            state.memsize = cast(XXH32_hash_t)(bEnd - p);
        }
    }

    return XXH_errorcode.XXH_OK;
}

/* XXH PUBLIC API - hidden in D module */
private XXH64_hash_t xxh64_digest(const XXH64_state_t* state)
    @trusted pure nothrow @nogc
{
    ulong h64;

    if (state.total_len >= 32)
    {
        h64 = rol(state.v[0], 1) + rol(state.v[1],
                7) + rol(state.v[2], 12) + rol(state.v[3], 18);
        h64 = xxh64_mergeRound(h64, state.v[0]);
        h64 = xxh64_mergeRound(h64, state.v[1]);
        h64 = xxh64_mergeRound(h64, state.v[2]);
        h64 = xxh64_mergeRound(h64, state.v[3]);
    }
    else
    {
        h64 = state.v[2] /*seed*/  + XXH_PRIME64_5;
    }

    h64 += cast(ulong) state.total_len;

    return xxh64_finalize(h64, cast(const ubyte*) state.mem64,
            cast(size_t) state.total_len, XXH_alignment.XXH_aligned);
}


/* XXH PUBLIC API - hidden in D module */
private void xxh64_canonicalFromHash(XXH64_canonical_t* dst, XXH64_hash_t hash)
    @trusted pure nothrow @nogc
{
    static assert((XXH64_canonical_t).sizeof == (XXH64_hash_t).sizeof,
                    "(XXH64_canonical_t).sizeof != (XXH64_hash_t).sizeof");
    version (LittleEndian)
        hash = bswap(hash);
    (cast(ubyte*) dst) [0 .. dst.sizeof] = (cast(ubyte*) &hash) [0 .. dst.sizeof];
}

/* XXH PUBLIC API - hidden in D module */
private XXH64_hash_t xxh64_hashFromCanonical(const XXH64_canonical_t* src)
    @safe pure nothrow @nogc
{
    return xxh_readBE64(src);
}

/* *********************************************************************
*  XXH3
*  New generation hash designed for speed on small keys and vectorization
************************************************************************ */

enum XXH3_SECRET_SIZE_MIN = 136; /// The bare minimum size for a custom secret.
enum XXH3_SECRET_DEFAULT_SIZE = 192; /* minimum XXH3_SECRET_SIZE_MIN */
enum XXH_SECRET_DEFAULT_SIZE = 192; /* minimum XXH3_SECRET_SIZE_MIN */
enum XXH3_INTERNALBUFFER_SIZE = 256; ///The size of the internal XXH3 buffer.

/* Structure for XXH3 streaming API.
 *
 * Note: ** This structure has a strict alignment requirement of 64 bytes!! **
 * Do not allocate this with `malloc()` or `new`, it will not be sufficiently aligned.
 *
 * Do never access the members of this struct directly.
 *
 * See: XXH3_INITSTATE() for stack initialization.
 * See: XXH32_state_s, XXH64_state_s
 */
private align(64) struct XXH3_state_t
{
    align(64) XXH64_hash_t[8] acc;
    /** The 8 accumulators. See XXH32_state_s::v and XXH64_state_s::v */
    align(64) ubyte[XXH3_SECRET_DEFAULT_SIZE] customSecret;
    /** Used to store a custom secret generated from a seed. */
    align(64) ubyte[XXH3_INTERNALBUFFER_SIZE] buffer;
    /** The internal buffer. See: XXH32_state_s::mem32 */
    XXH32_hash_t bufferedSize;
    /** The amount of memory in buffer, See: XXH32_state_s::memsize */
    XXH32_hash_t useSeed;
    /** Reserved field. Needed for padding on 64-bit. */
    size_t nbStripesSoFar;
    /** Number or stripes processed. */
    XXH64_hash_t totalLen;
    /** Total length hashed. 64-bit even on 32-bit targets. */
    size_t nbStripesPerBlock;
    /** Number of stripes per block. */
    size_t secretLimit;
    /** Size of customSecret or extSecret */
    XXH64_hash_t seed;
    /** Seed for _withSeed variants. Must be zero otherwise, See: XXH3_INITSTATE() */
    XXH64_hash_t reserved64;
    /** Reserved field. */
    const(ubyte)* extSecret;
    /** Reference to an external secret for the _withSecret variants, null
     *   for other variants. */
    /* note: there may be some padding at the end due to alignment on 64 bytes */
} /* typedef'd to XXH3_state_t */

static assert(XXH_SECRET_DEFAULT_SIZE >= XXH3_SECRET_SIZE_MIN, "default keyset is not large enough");

/** Pseudorandom secret taken directly from FARSH. */
private align(64) immutable ubyte[XXH3_SECRET_DEFAULT_SIZE] xxh3_kSecret = [
    0xb8, 0xfe, 0x6c, 0x39, 0x23, 0xa4, 0x4b, 0xbe, 0x7c, 0x01, 0x81, 0x2c,
    0xf7, 0x21, 0xad, 0x1c, 0xde, 0xd4, 0x6d, 0xe9, 0x83, 0x90, 0x97, 0xdb,
    0x72, 0x40, 0xa4, 0xa4, 0xb7, 0xb3, 0x67, 0x1f, 0xcb, 0x79, 0xe6, 0x4e,
    0xcc, 0xc0, 0xe5, 0x78, 0x82, 0x5a, 0xd0, 0x7d, 0xcc, 0xff, 0x72, 0x21,
    0xb8, 0x08, 0x46, 0x74, 0xf7, 0x43, 0x24, 0x8e, 0xe0, 0x35, 0x90, 0xe6,
    0x81, 0x3a, 0x26, 0x4c, 0x3c, 0x28, 0x52, 0xbb, 0x91, 0xc3, 0x00, 0xcb,
    0x88, 0xd0, 0x65, 0x8b, 0x1b, 0x53, 0x2e, 0xa3, 0x71, 0x64, 0x48, 0x97,
    0xa2, 0x0d, 0xf9, 0x4e, 0x38, 0x19, 0xef, 0x46, 0xa9, 0xde, 0xac, 0xd8,
    0xa8, 0xfa, 0x76, 0x3f, 0xe3, 0x9c, 0x34, 0x3f, 0xf9, 0xdc, 0xbb, 0xc7,
    0xc7, 0x0b, 0x4f, 0x1d, 0x8a, 0x51, 0xe0, 0x4b, 0xcd, 0xb4, 0x59, 0x31,
    0xc8, 0x9f, 0x7e, 0xc9, 0xd9, 0x78, 0x73, 0x64, 0xea, 0xc5, 0xac, 0x83,
    0x34, 0xd3, 0xeb, 0xc3, 0xc5, 0x81, 0xa0, 0xff, 0xfa, 0x13, 0x63, 0xeb,
    0x17, 0x0d, 0xdd, 0x51, 0xb7, 0xf0, 0xda, 0x49, 0xd3, 0x16, 0x55, 0x26,
    0x29, 0xd4, 0x68, 0x9e, 0x2b, 0x16, 0xbe, 0x58, 0x7d, 0x47, 0xa1, 0xfc,
    0x8f, 0xf8, 0xb8, 0xd1, 0x7a, 0xd0, 0x31, 0xce, 0x45, 0xcb, 0x3a, 0x8f,
    0x95, 0x16, 0x04, 0x28, 0xaf, 0xd7, 0xfb, 0xca, 0xbb, 0x4b, 0x40, 0x7e,
];

/* This performs a 32x32 -> 64 bit multiplikation */
private ulong xxh_mult32to64(uint x, uint y) @safe pure nothrow @nogc
{
    return (cast(ulong)(x) * cast(ulong)(y));
}

/** Calculates a 64 to 128-bit long multiply.
 *
 * Param: lhs , rhs The 64-bit integers to be multiplied
 * Return: The 128-bit result represented in an XXH128_hash_t structure.
 */
private XXH128_hash_t xxh_mult64to128(ulong lhs, ulong rhs) @safe pure nothrow @nogc
{
    version (Have128BitInteger)
    {
        Cent cent_lhs; cent_lhs.lo = lhs;
        Cent cent_rhs; cent_rhs.lo = rhs;
        const Cent product = mul(cent_lhs, cent_rhs);
        XXH128_hash_t r128;
        r128.low64 = product.lo;
        r128.high64 = product.hi;
    }
    else
    {
        /* First calculate all of the cross products. */
        const ulong lo_lo = xxh_mult32to64(lhs & 0xFFFFFFFF, rhs & 0xFFFFFFFF);
        const ulong hi_lo = xxh_mult32to64(lhs >> 32, rhs & 0xFFFFFFFF);
        const ulong lo_hi = xxh_mult32to64(lhs & 0xFFFFFFFF, rhs >> 32);
        const ulong hi_hi = xxh_mult32to64(lhs >> 32, rhs >> 32);

        /* Now add the products together. These will never overflow. */
        const ulong cross = (lo_lo >> 32) + (hi_lo & 0xFFFFFFFF) + lo_hi;
        const ulong upper = (hi_lo >> 32) + (cross >> 32) + hi_hi;
        const ulong lower = (cross << 32) | (lo_lo & 0xFFFFFFFF);

        XXH128_hash_t r128;
        r128.low64 = lower;
        r128.high64 = upper;
    }
    return r128;
}

/** Calculates a 64-bit to 128-bit multiply, then XOR folds it.
 *
 * The reason for the separate function is to prevent passing too many structs
 * around by value. This will hopefully inline the multiply, but we don't force it.
 *
 * Param: lhs , rhs The 64-bit integers to multiply
 * Return: The low 64 bits of the product XOR'd by the high 64 bits.
 * See: xxh_mult64to128()
 */
private ulong xxh3_mul128_fold64(ulong lhs, ulong rhs) @safe pure nothrow @nogc
{
    XXH128_hash_t product = xxh_mult64to128(lhs, rhs);
    return product.low64 ^ product.high64;
}

/* Seems to produce slightly better code on GCC for some reason. */
static private ulong xxh_xorshift64(ulong v64, int shift) @safe pure nothrow @nogc
in(0 <= shift && shift < 64, "shift out of range")
{
    return v64 ^ (v64 >> shift);
}

/*
 * This is a fast avalanche stage,
 * suitable when input bits are already partially mixed
 */
static private XXH64_hash_t xxh3_avalanche(ulong h64) @safe pure nothrow @nogc
{
    h64 = xxh_xorshift64(h64, 37);
    h64 *= 0x165667919E3779F9;
    h64 = xxh_xorshift64(h64, 32);
    return h64;
}

/*
 * This is a stronger avalanche,
 * inspired by Pelle Evensen's rrmxmx
 * preferable when input has not been previously mixed
 */
static private XXH64_hash_t xxh3_rrmxmx(ulong h64, ulong len) @safe pure nothrow @nogc
{
    /* this mix is inspired by Pelle Evensen's rrmxmx */
    h64 ^= rol(h64, 49) ^ rol(h64, 24);
    h64 *= 0x9FB21C651E98DF25;
    h64 ^= (h64 >> 35) + len;
    h64 *= 0x9FB21C651E98DF25;
    return xxh_xorshift64(h64, 28);
}

/* ==========================================
 * Short keys
 * ==========================================
 * One of the shortcomings of XXH32 and XXH64 was that their performance was
 * sub-optimal on short lengths. It used an iterative algorithm which strongly
 * favored lengths that were a multiple of 4 or 8.
 *
 * Instead of iterating over individual inputs, we use a set of single shot
 * functions which piece together a range of lengths and operate in constant time.
 *
 * Additionally, the number of multiplies has been significantly reduced. This
 * reduces latency, especially when emulating 64-bit multiplies on 32-bit.
 *
 * Depending on the platform, this may or may not be faster than XXH32, but it
 * is almost guaranteed to be faster than XXH64.
 */

/*
 * At very short lengths, there isn't enough input to fully hide secrets, or use
 * the entire secret.
 *
 * There is also only a limited amount of mixing we can do before significantly
 * impacting performance.
 *
 * Therefore, we use different sections of the secret and always mix two secret
 * samples with an XOR. This should have no effect on performance on the
 * seedless or withSeed variants because everything _should_ be constant folded
 * by modern compilers.
 *
 * The XOR mixing hides individual parts of the secret and increases entropy.
 *
 * This adds an extra layer of strength for custom secrets.
 */
private XXH64_hash_t xxh3_len_1to3_64b(
    const ubyte* input, size_t len, const ubyte* secret, XXH64_hash_t seed)
    @trusted pure nothrow @nogc
in(input != null, "input == null")
in(1 <= len && len <= 3, "len out of range")
in(secret != null, "secret == null")
{
    /*
     * len = 1: combined = { input[0], 0x01, input[0], input[0] }
     * len = 2: combined = { input[1], 0x02, input[0], input[1] }
     * len = 3: combined = { input[2], 0x03, input[0], input[1] }
     */
    {
        const ubyte c1 = input[0];
        const ubyte c2 = input[len >> 1];
        const ubyte c3 = input[len - 1];
        const uint combined = (cast(uint) c1 << 16) | (
                cast(uint) c2 << 24) | (cast(uint) c3 << 0) | (cast(uint) len << 8);
        const ulong bitflip = (xxh_readLE32(secret) ^ xxh_readLE32(secret + 4)) + seed;
        const ulong keyed = cast(ulong) combined ^ bitflip;
        return xxh64_avalanche(keyed);
    }
}

private XXH64_hash_t xxh3_len_4to8_64b(
    const ubyte* input, size_t len, const ubyte* secret, XXH64_hash_t seed)
    @trusted pure nothrow @nogc
in(input != null, "input == null")
in(secret != null, "secret == null")
in(4 <= len && len <= 8, "len out of range")
{
    seed ^= cast(ulong) bswap(cast(uint) seed) << 32;
    {
        const uint input1 = xxh_readLE32(input);
        const uint input2 = xxh_readLE32(input + len - 4);
        const ulong bitflip = (xxh_readLE64(secret + 8) ^ xxh_readLE64(secret + 16)) - seed;
        const ulong input64 = input2 + ((cast(ulong) input1) << 32);
        const ulong keyed = input64 ^ bitflip;
        return xxh3_rrmxmx(keyed, len);
    }
}

private XXH64_hash_t xxh3_len_9to16_64b(
    const ubyte* input, size_t len, const ubyte* secret, XXH64_hash_t seed)
    @trusted pure nothrow @nogc
in(input != null, "input == null")
in(secret != null, "secret == null")
in(9 <= len && len <= 16, "len out of range")
{
    {
        const ulong bitflip1 = (xxh_readLE64(secret + 24) ^ xxh_readLE64(secret + 32)) + seed;
        const ulong bitflip2 = (xxh_readLE64(secret + 40) ^ xxh_readLE64(secret + 48)) - seed;
        const ulong input_lo = xxh_readLE64(input) ^ bitflip1;
        const ulong input_hi = xxh_readLE64(input + len - 8) ^ bitflip2;
        const ulong acc = len + bswap(input_lo) + input_hi + xxh3_mul128_fold64(input_lo,
                input_hi);
        return xxh3_avalanche(acc);
    }
}

private bool xxh_likely(bool exp)
    @safe pure nothrow @nogc
{
    return exp;
}

private bool xxh_unlikely(bool exp)
    @safe pure nothrow @nogc
{
    return exp;
}

private XXH64_hash_t xxh3_len_0to16_64b(
    const ubyte* input, size_t len, const ubyte* secret, XXH64_hash_t seed)
    @trusted pure nothrow @nogc
in(len <= 16, "len > 16")
{
    {
        if (xxh_likely(len > 8))
            return xxh3_len_9to16_64b(input, len, secret, seed);
        if (xxh_likely(len >= 4))
            return xxh3_len_4to8_64b(input, len, secret, seed);
        if (len)
            return xxh3_len_1to3_64b(input, len, secret, seed);
        return xxh64_avalanche(seed ^ (xxh_readLE64(secret + 56) ^ xxh_readLE64(secret + 64)));
    }
}

/*
 * DISCLAIMER: There are known *seed-dependent* multicollisions here due to
 * multiplication by zero, affecting hashes of lengths 17 to 240.
 *
 * However, they are very unlikely.
 *
 * Keep this in mind when using the unseeded xxh3_64bits() variant: As with all
 * unseeded non-cryptographic hashes, it does not attempt to defend itself
 * against specially crafted inputs, only random inputs.
 *
 * Compared to classic UMAC where a 1 in 2^31 chance of 4 consecutive bytes
 * cancelling out the secret is taken an arbitrary number of times (addressed
 * in xxh3_accumulate_512), this collision is very unlikely with random inputs
 * and/or proper seeding:
 *
 * This only has a 1 in 2^63 chance of 8 consecutive bytes cancelling out, in a
 * function that is only called up to 16 times per hash with up to 240 bytes of
 * input.
 *
 * This is not too bad for a non-cryptographic hash function, especially with
 * only 64 bit outputs.
 *
 * The 128-bit variant (which trades some speed for strength) is NOT affected
 * by this, although it is always a good idea to use a proper seed if you care
 * about strength.
 */
private ulong xxh3_mix16B(const(ubyte)* input, const(ubyte)* secret, ulong seed64)
    @trusted pure nothrow @nogc
{
    {
        const ulong input_lo = xxh_readLE64(input);
        const ulong input_hi = xxh_readLE64(input + 8);
        return xxh3_mul128_fold64(
            input_lo ^ (xxh_readLE64(secret) + seed64),
            input_hi ^ (xxh_readLE64(secret + 8) - seed64));
    }
}

/* For mid range keys, XXH3 uses a Mum-hash variant. */
private XXH64_hash_t xxh3_len_17to128_64b(
    const(ubyte)* input, size_t len, const(ubyte)* secret, size_t secretSize, XXH64_hash_t seed)
    @trusted pure nothrow @nogc
in(secretSize >= XXH3_SECRET_SIZE_MIN, "secretSize < XXH3_SECRET_SIZE_MIN")
in(16 < len && len <= 128, "len out of range")
{
    ulong acc = len * XXH_PRIME64_1;
    if (len > 32)
    {
        if (len > 64)
        {
            if (len > 96)
            {
                acc += xxh3_mix16B(input + 48, secret + 96, seed);
                acc += xxh3_mix16B(input + len - 64, secret + 112, seed);
            }
            acc += xxh3_mix16B(input + 32, secret + 64, seed);
            acc += xxh3_mix16B(input + len - 48, secret + 80, seed);
        }
        acc += xxh3_mix16B(input + 16, secret + 32, seed);
        acc += xxh3_mix16B(input + len - 32, secret + 48, seed);
    }
    acc += xxh3_mix16B(input + 0, secret + 0, seed);
    acc += xxh3_mix16B(input + len - 16, secret + 16, seed);

    return xxh3_avalanche(acc);
}

enum XXH3_MIDSIZE_MAX = 240;
enum XXH3_MIDSIZE_STARTOFFSET = 3;
enum XXH3_MIDSIZE_LASTOFFSET = 17;

private XXH64_hash_t xxh3_len_129to240_64b(
    const(ubyte)* input, size_t len, const(ubyte)* secret, size_t secretSize, XXH64_hash_t seed)
    @trusted pure nothrow @nogc
in(secretSize >= XXH3_SECRET_SIZE_MIN, "secretSize < XXH3_SECRET_SIZE_MIN")
in { const int nbRounds = cast(int) len / 16; assert(nbRounds >= 8, "nbRounds < 8"); }
in(128 < len && len <= XXH3_MIDSIZE_MAX, "128 >= len || len > XXH3_MIDSIZE_MAX")
{
    ulong acc = len * XXH_PRIME64_1;
    const int nbRounds = cast(int) len / 16;
    int i;
    for (i = 0; i < 8; i++)
    {
        acc += xxh3_mix16B(input + (16 * i), secret + (16 * i), seed);
    }
    acc = xxh3_avalanche(acc);
    for (i = 8; i < nbRounds; i++)
    {
        acc += xxh3_mix16B(input + (16 * i),
                secret + (16 * (i - 8)) + XXH3_MIDSIZE_STARTOFFSET, seed);
    }
    /* last bytes */
    acc += xxh3_mix16B(input + len - 16,
            secret + XXH3_SECRET_SIZE_MIN - XXH3_MIDSIZE_LASTOFFSET, seed);
    return xxh3_avalanche(acc);
}

/* =======     Long Keys     ======= */

enum XXH_STRIPE_LEN = 64;
enum XXH_SECRET_CONSUME_RATE = 8; /* nb of secret bytes consumed at each accumulation */
enum XXH_ACC_NB = (XXH_STRIPE_LEN / (ulong).sizeof);

private void xxh_writeLE64(void* dst, ulong v64)
    @trusted pure nothrow @nogc
{
    version (LittleEndian) {}
    else
        v64 = bswap(v64);
    (cast(ubyte*) dst) [0 .. v64.sizeof] = (cast(ubyte*) &v64) [0 .. v64.sizeof];
}

/* scalar variants - universal */

enum XXH_ACC_ALIGN = 8;

/* Scalar round for xxh3_accumulate_512_scalar(). */
private void xxh3_scalarRound(void* acc, const(void)* input, const(void)* secret, size_t lane)
    @trusted pure nothrow @nogc
in(lane < XXH_ACC_NB, "lane >= XXH_ACC_NB")
{
    version (CheckACCAlignment)
        assert((cast(size_t) acc & (XXH_ACC_ALIGN - 1)) == 0, "(cast(size_t) acc & (XXH_ACC_ALIGN - 1)) != 0");
    ulong* xacc = cast(ulong*) acc;
    ubyte* xinput = cast(ubyte*) input;
    ubyte* xsecret = cast(ubyte*) secret;
    {
        const ulong data_val = xxh_readLE64(xinput + lane * 8);
        const ulong data_key = data_val ^ xxh_readLE64(xsecret + lane * 8);
        xacc[lane ^ 1] += data_val; /* swap adjacent lanes */
        xacc[lane] += xxh_mult32to64(data_key & 0xFFFFFFFF, data_key >> 32);
    }
}

/* Processes a 64 byte block of data using the scalar path. */
private void xxh3_accumulate_512_scalar(void* acc, const(void)* input, const(void)* secret)
    @safe pure nothrow @nogc
{
    size_t i;
    for (i = 0; i < XXH_ACC_NB; i++)
    {
        xxh3_scalarRound(acc, input, secret, i);
    }
}

/* Scalar scramble step for xxh3_scrambleAcc_scalar().
 *
 * This is extracted to its own function because the NEON path uses a combination
 * of NEON and scalar.
 */
private void xxh3_scalarScrambleRound(void* acc, const(void)* secret, size_t lane)
    @trusted pure nothrow @nogc
in(lane < XXH_ACC_NB, "lane >= XXH_ACC_NB")
{
    version (CheckACCAlignment)
        assert(((cast(size_t) acc) & (XXH_ACC_ALIGN - 1)) == 0, "((cast(size_t) acc) & (XXH_ACC_ALIGN - 1)) != 0");
    ulong* xacc = cast(ulong*) acc; /* presumed aligned */
    const ubyte* xsecret = cast(const ubyte*) secret; /* no alignment restriction */
    {
        const ulong key64 = xxh_readLE64(xsecret + lane * 8);
        ulong acc64 = xacc[lane];
        acc64 = xxh_xorshift64(acc64, 47);
        acc64 ^= key64;
        acc64 *= XXH_PRIME32_1;
        xacc[lane] = acc64;
    }
}

/* Scrambles the accumulators after a large chunk has been read */
private void xxh3_scrambleAcc_scalar(void* acc, const(void)* secret)
    @safe pure nothrow @nogc
{
    size_t i;
    for (i = 0; i < XXH_ACC_NB; i++)
    {
        xxh3_scalarScrambleRound(acc, secret, i);
    }
}

private void xxh3_initCustomSecret_scalar(void* customSecret, ulong seed64)
    @trusted pure nothrow @nogc
{
    /*
     * We need a separate pointer for the hack below,
     * which requires a non-const pointer.
     * Any decent compiler will optimize this out otherwise.
     */
    const ubyte* kSecretPtr = cast(ubyte*) xxh3_kSecret;
    static assert((XXH_SECRET_DEFAULT_SIZE & 15) == 0, "(XXH_SECRET_DEFAULT_SIZE & 15) != 0");

    /*
     * Note: in debug mode, this overrides the asm optimization
     * and Clang will emit MOVK chains again.
     */
    //assert(kSecretPtr == xxh3_kSecret);

    {
        const int nbRounds = XXH_SECRET_DEFAULT_SIZE / 16;
        int i;
        for (i = 0; i < nbRounds; i++)
        {
            /*
             * The asm hack causes Clang to assume that kSecretPtr aliases with
             * customSecret, and on aarch64, this prevented LDP from merging two
             * loads together for free. Putting the loads together before the stores
             * properly generates LDP.
             */
            const ulong lo = xxh_readLE64(kSecretPtr + 16 * i) + seed64;
            const ulong hi = xxh_readLE64(kSecretPtr + 16 * i + 8) - seed64;
            xxh_writeLE64(cast(ubyte*) customSecret + 16 * i, lo);
            xxh_writeLE64(cast(ubyte*) customSecret + 16 * i + 8, hi);
        }
    }
}

alias XXH3_f_accumulate_512 = void function(void*, const(void)*, const(void)*) @safe pure nothrow @nogc;
alias XXH3_f_scrambleAcc = void function(void*, const void*) @safe pure nothrow @nogc;
alias XXH3_f_initCustomSecret = void function(void*, ulong) @safe pure nothrow @nogc;

immutable XXH3_f_accumulate_512 xxh3_accumulate_512 = &xxh3_accumulate_512_scalar;
immutable XXH3_f_scrambleAcc xxh3_scrambleAcc = &xxh3_scrambleAcc_scalar;
immutable XXH3_f_initCustomSecret xxh3_initCustomSecret = &xxh3_initCustomSecret_scalar;

enum XXH_PREFETCH_DIST = 384;
/* TODO: Determine how to implement prefetching in D! Disabled for now */
private void XXH_PREFETCH(const ubyte* ptr) @safe pure nothrow @nogc
{
//    cast(void)(ptr); /* DISABLED prefetch and do nothing here */

// In C it is done with the following code lines:
//  if XXH_SIZE_OPT >= 1
//    define XXH_PREFETCH(ptr) (void)(ptr)
//  elif defined(_MSC_VER) && (defined(_M_X64) || defined(_M_IX86))  /* _mm_prefetch() not defined outside of x86/x64 */
//    include <mmintrin.h>   /* https://msdn.microsoft.com/fr-fr/library/84szxsww(v=vs.90).aspx */
//    define XXH_PREFETCH(ptr)  _mm_prefetch((const char*)(ptr), _MM_HINT_T0)
//  elif defined(__GNUC__) && ( (__GNUC__ >= 4) || ( (__GNUC__ == 3) && (__GNUC_MINOR__ >= 1) ) )
//    define XXH_PREFETCH(ptr)  __builtin_prefetch((ptr), 0 /* rw == read */, 3 /* locality */)
//  else
//    define XXH_PREFETCH(ptr) (void)(ptr)  /* disabled */
//  endif
}

/*
 * xxh3_accumulate()
 * Loops over xxh3_accumulate_512().
 * Assumption: nbStripes will not overflow the secret size
 */
private void xxh3_accumulate(
    ulong* acc, const ubyte* input,
    const ubyte* secret, size_t nbStripes, XXH3_f_accumulate_512 f_acc512)
    @trusted pure nothrow @nogc
{
    size_t n;
    for (n = 0; n < nbStripes; n++)
    {
        const ubyte* in_ = input + n * XXH_STRIPE_LEN;
        XXH_PREFETCH(in_ + XXH_PREFETCH_DIST);
        f_acc512(acc, in_, secret + n * XXH_SECRET_CONSUME_RATE);
    }
}

private void xxh3_hashLong_internal_loop(
    ulong* acc, const ubyte* input, size_t len, const ubyte* secret,
    size_t secretSize, XXH3_f_accumulate_512 f_acc512, XXH3_f_scrambleAcc f_scramble)
    @trusted pure nothrow @nogc
in(secretSize >= XXH3_SECRET_SIZE_MIN, "secretSize < XXH3_SECRET_SIZE_MIN")
in(len > XXH_STRIPE_LEN, "len <= XXH_STRIPE_LEN")
{
    const size_t nbStripesPerBlock = (secretSize - XXH_STRIPE_LEN) / XXH_SECRET_CONSUME_RATE;
    const size_t block_len = XXH_STRIPE_LEN * nbStripesPerBlock;
    const size_t nb_blocks = (len - 1) / block_len;

    size_t n;

    for (n = 0; n < nb_blocks; n++)
    {
        xxh3_accumulate(acc, input + n * block_len, secret, nbStripesPerBlock, f_acc512);
        f_scramble(acc, secret + secretSize - XXH_STRIPE_LEN);
    }

    /* last partial block */
    {
        const size_t nbStripes = ((len - 1) - (block_len * nb_blocks)) / XXH_STRIPE_LEN;
        assert(nbStripes <= (secretSize / XXH_SECRET_CONSUME_RATE),
                "nbStripes > (secretSize / XXH_SECRET_CONSUME_RATE)");
        xxh3_accumulate(acc, input + nb_blocks * block_len, secret, nbStripes, f_acc512);

        /* last stripe */
        {
            const ubyte* p = input + len - XXH_STRIPE_LEN;
            f_acc512(acc, p, secret + secretSize - XXH_STRIPE_LEN - XXH_SECRET_LASTACC_START);
        }
    }
}

enum XXH_SECRET_LASTACC_START = 7; /* not aligned on 8, last secret is different from acc & scrambler */

private ulong xxh3_mix2Accs(const(ulong)* acc, const(ubyte)* secret)
    @trusted pure nothrow @nogc
{
    return xxh3_mul128_fold64(acc[0] ^ xxh_readLE64(secret), acc[1] ^ xxh_readLE64(secret + 8));
}

private XXH64_hash_t xxh3_mergeAccs(const(ulong)* acc, const(ubyte)* secret, ulong start)
    @trusted pure nothrow @nogc
{
    ulong result64 = start;
    size_t i = 0;

    for (i = 0; i < 4; i++)
    {
        result64 += xxh3_mix2Accs(acc + 2 * i, secret + 16 * i);
    }

    return xxh3_avalanche(result64);
}

static immutable XXH3_INIT_ACC = [
        XXH_PRIME32_3, XXH_PRIME64_1, XXH_PRIME64_2, XXH_PRIME64_3,
        XXH_PRIME64_4, XXH_PRIME32_2, XXH_PRIME64_5, XXH_PRIME32_1
    ];

private XXH64_hash_t xxh3_hashLong_64b_internal(
    const(void)* input, size_t len, const(void)* secret, size_t secretSize,
    XXH3_f_accumulate_512 f_acc512, XXH3_f_scrambleAcc f_scramble)
    @trusted pure nothrow @nogc
{
    align(XXH_ACC_ALIGN) ulong[XXH_ACC_NB] acc = XXH3_INIT_ACC; /* NOTE: This doesn't work in D, fails on 32bit NetBSD */

    xxh3_hashLong_internal_loop(&acc[0], cast(const(ubyte)*) input, len,
            cast(const(ubyte)*) secret, secretSize, f_acc512, f_scramble);

    /* converge into final hash */
    static assert(acc.sizeof == 64, "acc.sizeof != 64");
    /* do not align on 8, so that the secret is different from the accumulator */
    assert(secretSize >= acc.sizeof + XXH_SECRET_MERGEACCS_START,
            "secretSize < acc.sizeof + XXH_SECRET_MERGEACCS_START");
    return xxh3_mergeAccs(&acc[0], cast(const(ubyte)*) secret + XXH_SECRET_MERGEACCS_START,
            cast(ulong) len * XXH_PRIME64_1);
}

enum XXH_SECRET_MERGEACCS_START = 11;

/*
 * It's important for performance to transmit secret's size (when it's static)
 * so that the compiler can properly optimize the vectorized loop.
 * This makes a big performance difference for "medium" keys (<1 KB) when using AVX instruction set.
 */
private XXH64_hash_t xxh3_hashLong_64b_withSecret(
    const(void)* input, size_t len, XXH64_hash_t seed64, const(ubyte)* secret, size_t secretLen)
    @safe pure nothrow @nogc
{
    return xxh3_hashLong_64b_internal(input, len, secret, secretLen,
            xxh3_accumulate_512, xxh3_scrambleAcc);
}

/*
 * It's preferable for performance that XXH3_hashLong is not inlined,
 * as it results in a smaller function for small data, easier to the instruction cache.
 * Note that inside this no_inline function, we do inline the internal loop,
 * and provide a statically defined secret size to allow optimization of vector loop.
 */
private XXH64_hash_t xxh3_hashLong_64b_default(
    const(void)* input, size_t len, XXH64_hash_t seed64, const(ubyte)* secret, size_t secretLen)
    @safe pure nothrow @nogc
{
    return xxh3_hashLong_64b_internal(input, len, &xxh3_kSecret[0],
            (xxh3_kSecret).sizeof, xxh3_accumulate_512, xxh3_scrambleAcc);
}

enum XXH_SEC_ALIGN = 8;

/*
 * xxh3_hashLong_64b_withSeed():
 * Generate a custom key based on alteration of default xxh3_kSecret with the seed,
 * and then use this key for long mode hashing.
 *
 * This operation is decently fast but nonetheless costs a little bit of time.
 * Try to avoid it whenever possible (typically when seed == 0).
 *
 * It's important for performance that XXH3_hashLong is not inlined. Not sure
 * why (uop cache maybe?), but the difference is large and easily measurable.
 */
private XXH64_hash_t xxh3_hashLong_64b_withSeed_internal(
    const(void)* input, size_t len, XXH64_hash_t seed,
    XXH3_f_accumulate_512 f_acc512,
    XXH3_f_scrambleAcc f_scramble,
    XXH3_f_initCustomSecret f_initSec)
    @trusted pure nothrow @nogc
{
    //#if XXH_SIZE_OPT <= 0
    if (seed == 0)
        return xxh3_hashLong_64b_internal(input, len, &xxh3_kSecret[0],
                (xxh3_kSecret).sizeof, f_acc512, f_scramble);
    //#endif
    else
    {
        align(XXH_SEC_ALIGN) ubyte[XXH_SECRET_DEFAULT_SIZE] secret;
        f_initSec(&secret[0], seed);
        return xxh3_hashLong_64b_internal(input, len, &secret[0],
            (secret).sizeof, f_acc512, f_scramble);
    }
}

/*
 * It's important for performance that XXH3_hashLong is not inlined.
 */
private XXH64_hash_t xxh3_hashLong_64b_withSeed(const(void)* input, size_t len,
    XXH64_hash_t seed, const(ubyte)* secret, size_t secretLen)
    @safe pure nothrow @nogc
{
    return xxh3_hashLong_64b_withSeed_internal(input, len, seed,
            xxh3_accumulate_512, xxh3_scrambleAcc, xxh3_initCustomSecret);
}

alias XXH3_hashLong64_f = XXH64_hash_t function(
    const(void)*, size_t, XXH64_hash_t, const(ubyte)*, size_t)
    @safe pure nothrow @nogc;

private XXH64_hash_t xxh3_64bits_internal(const(void)* input, size_t len,
        XXH64_hash_t seed64, const(void)* secret, size_t secretLen, XXH3_hashLong64_f f_hashLong)
        @safe pure nothrow @nogc
in(secretLen >= XXH3_SECRET_SIZE_MIN, "secretLen < XXH3_SECRET_SIZE_MIN")
{
    /*
     * If an action is to be taken if `secretLen` condition is not respected,
     * it should be done here.
     * For now, it's a contract pre-condition.
     * Adding a check and a branch here would cost performance at every hash.
     * Also, note that function signature doesn't offer room to return an error.
     */
    if (len <= 16)
        return xxh3_len_0to16_64b(cast(const(ubyte)*) input, len,
                cast(const(ubyte)*) secret, seed64);
    if (len <= 128)
        return xxh3_len_17to128_64b(cast(const(ubyte)*) input, len,
                cast(const(ubyte)*) secret, secretLen, seed64);
    if (len <= XXH3_MIDSIZE_MAX)
        return xxh3_len_129to240_64b(cast(const(ubyte)*) input, len,
                cast(const(ubyte)*) secret, secretLen, seed64);
    return f_hashLong(input, len, seed64, cast(const(ubyte)*) secret, secretLen);
}

/* ===   Public entry point   === */

/* XXH PUBLIC API - hidden in D module */
private XXH64_hash_t xxh3_64bits(const(void)* input, size_t length)
    @safe pure nothrow @nogc
{
    return xxh3_64bits_internal(input, length, 0, &xxh3_kSecret[0],
            (xxh3_kSecret).sizeof, &xxh3_hashLong_64b_default);
}

/* XXH PUBLIC API - hidden in D module */
private XXH64_hash_t xxh3_64bits_withSecret(
    const(void)* input, size_t length, const(void)* secret, size_t secretSize)
    @safe pure nothrow @nogc
{
    return xxh3_64bits_internal(input, length, 0, secret, secretSize,
            &xxh3_hashLong_64b_withSecret);
}

/* XXH PUBLIC API - hidden in D module */ private
XXH64_hash_t xxh3_64bits_withSeed(const(void)* input, size_t length, XXH64_hash_t seed)
    @safe pure nothrow @nogc
{
    return xxh3_64bits_internal(input, length, seed, &xxh3_kSecret[0],
            (xxh3_kSecret).sizeof, &xxh3_hashLong_64b_withSeed);
}

/* XXH PUBLIC API - hidden in D module */ private
XXH64_hash_t xxh3_64bits_withSecretandSeed(
    const(void)* input, size_t length, const(void)* secret, size_t secretSize, XXH64_hash_t seed)
    @safe pure nothrow @nogc
{
    if (length <= XXH3_MIDSIZE_MAX)
        return xxh3_64bits_internal(input, length, seed, &xxh3_kSecret[0],
                (xxh3_kSecret).sizeof, null);
    return xxh3_hashLong_64b_withSecret(input, length, seed,
            cast(const(ubyte)*) secret, secretSize);
}

/* ===   XXH3 streaming   === */

private void XXH3_INITSTATE(XXH3_state_t* XXH3_state_ptr)
    @safe nothrow @nogc
{
    (XXH3_state_ptr).seed = 0;
}

private void xxh3_reset_internal(
    scope XXH3_state_t* statePtr, XXH64_hash_t seed, const void* secret, size_t secretSize)
    @trusted pure nothrow @nogc
in
{
    const size_t initStart = XXH3_state_t.bufferedSize.offsetof;
    assert(XXH3_state_t.nbStripesPerBlock.offsetof > initStart,
            "(XXH3_state_t.nbStripesPerBlock.offsetof <= initStart");
}
in(statePtr != null, "statePtr == null")
in(secretSize >= XXH3_SECRET_SIZE_MIN, "secretSize < XXH3_SECRET_SIZE_MIN")
{
    /* set members from bufferedSize to nbStripesPerBlock (excluded) to 0 */
    *statePtr = XXH3_state_t.init;
    statePtr.acc[0] = XXH_PRIME32_3;
    statePtr.acc[1] = XXH_PRIME64_1;
    statePtr.acc[2] = XXH_PRIME64_2;
    statePtr.acc[3] = XXH_PRIME64_3;
    statePtr.acc[4] = XXH_PRIME64_4;
    statePtr.acc[5] = XXH_PRIME32_2;
    statePtr.acc[6] = XXH_PRIME64_5;
    statePtr.acc[7] = XXH_PRIME32_1;
    statePtr.seed = seed;
    statePtr.useSeed = (seed != 0);
    statePtr.extSecret = cast(const(ubyte)*) secret;
    statePtr.secretLimit = secretSize - XXH_STRIPE_LEN;
    statePtr.nbStripesPerBlock = statePtr.secretLimit / XXH_SECRET_CONSUME_RATE;
}

/* XXH PUBLIC API - hidden in D module */ private
XXH_errorcode xxh3_64bits_reset(scope XXH3_state_t* statePtr)
    @safe pure nothrow @nogc
{
    if (statePtr == null)
        return XXH_errorcode.XXH_ERROR;
    xxh3_reset_internal(statePtr, 0, &xxh3_kSecret[0], XXH_SECRET_DEFAULT_SIZE);
    return XXH_errorcode.XXH_OK;
}

/* XXH PUBLIC API - hidden in D module */
private XXH_errorcode xxh3_64bits_reset_withSecret(
    XXH3_state_t* statePtr, const void* secret, size_t secretSize)
    @safe pure nothrow @nogc
{
    if (statePtr == null)
        return XXH_errorcode.XXH_ERROR;
    xxh3_reset_internal(statePtr, 0, secret, secretSize);
    if (secret == null)
        return XXH_errorcode.XXH_ERROR;
    if (secretSize < XXH3_SECRET_SIZE_MIN)
        return XXH_errorcode.XXH_ERROR;
    return XXH_errorcode.XXH_OK;
}

/* XXH PUBLIC API - hidden in D module */
private XXH_errorcode xxh3_64bits_reset_withSeed(XXH3_state_t* statePtr, XXH64_hash_t seed)
    @safe pure nothrow @nogc
{
    if (statePtr == null)
        return XXH_errorcode.XXH_ERROR;
    if (seed == 0)
        return xxh3_64bits_reset(statePtr);
    if ((seed != statePtr.seed) || (statePtr.extSecret != null))
        xxh3_initCustomSecret(&statePtr.customSecret[0], seed);
    xxh3_reset_internal(statePtr, seed, null, XXH_SECRET_DEFAULT_SIZE);
    return XXH_errorcode.XXH_OK;
}

/* XXH PUBLIC API - hidden in D module */
private XXH_errorcode xxh3_64bits_reset_withSecretandSeed(
    XXH3_state_t* statePtr, const(void)* secret, size_t secretSize, XXH64_hash_t seed64)
    @safe pure nothrow @nogc
{
    if (statePtr == null)
        return XXH_errorcode.XXH_ERROR;
    if (secret == null)
        return XXH_errorcode.XXH_ERROR;
    if (secretSize < XXH3_SECRET_SIZE_MIN)
        return XXH_errorcode.XXH_ERROR;
    xxh3_reset_internal(statePtr, seed64, secret, secretSize);
    statePtr.useSeed = 1; /* always, even if seed64 == 0 */
    return XXH_errorcode.XXH_OK;
}

/* Note : when xxh3_consumeStripes() is invoked,
 * there must be a guarantee that at least one more byte must be consumed from input
 * so that the function can blindly consume all stripes using the "normal" secret segment */
private void xxh3_consumeStripes(
    ulong* acc, size_t* nbStripesSoFarPtr, size_t nbStripesPerBlock, const ubyte* input, size_t nbStripes,
    const ubyte* secret, size_t secretLimit,
    XXH3_f_accumulate_512 f_acc512, XXH3_f_scrambleAcc f_scramble)
    @trusted pure nothrow @nogc
in(nbStripes <= nbStripesPerBlock, "nbStripes > nbStripesPerBlock") /* can handle max 1 scramble per invocation */
in(*nbStripesSoFarPtr < nbStripesPerBlock, "*nbStripesSoFarPtr >= nbStripesPerBlock")
{
    if (nbStripesPerBlock - *nbStripesSoFarPtr <= nbStripes)
    {
        /* need a scrambling operation */
        const size_t nbStripesToEndofBlock = nbStripesPerBlock - *nbStripesSoFarPtr;
        const size_t nbStripesAfterBlock = nbStripes - nbStripesToEndofBlock;
        xxh3_accumulate(acc, input, secret + nbStripesSoFarPtr[0] * XXH_SECRET_CONSUME_RATE,
                nbStripesToEndofBlock, f_acc512);
        f_scramble(acc, secret + secretLimit);
        xxh3_accumulate(acc, input + nbStripesToEndofBlock * XXH_STRIPE_LEN,
                secret, nbStripesAfterBlock, f_acc512);
        *nbStripesSoFarPtr = nbStripesAfterBlock;
    }
    else
    {
        xxh3_accumulate(acc, input,
                secret + nbStripesSoFarPtr[0] * XXH_SECRET_CONSUME_RATE, nbStripes, f_acc512);
        *nbStripesSoFarPtr += nbStripes;
    }
}

enum XXH3_STREAM_USE_STACK = 1;
/*
 * Both xxh3_64bits_update and xxh3_128bits_update use this routine.
 */
private XXH_errorcode xxh3_update(
    scope XXH3_state_t* state, scope const(ubyte)* input, size_t len,
    XXH3_f_accumulate_512 f_acc512, XXH3_f_scrambleAcc f_scramble)
    @trusted pure nothrow @nogc
in(state != null, "state == null")
in
{
    if (input == null) assert(len == 0, "input null ptr only allowed with len == 0");
}
do
{
    if (input == null && len == 0)
        return XXH_errorcode.XXH_OK;
    else if (input == null && len != 0)
        return XXH_errorcode.XXH_ERROR;
    else
    {
        const ubyte* bEnd = input + len;
        const(ubyte)* secret = (state.extSecret == null) ? &state.customSecret[0] : &state.extSecret[0];
        static if (XXH3_STREAM_USE_STACK >= 1)
        {
            /* For some reason, gcc and MSVC seem to suffer greatly
            * when operating accumulators directly into state.
            * Operating into stack space seems to enable proper optimization.
            * clang, on the other hand, doesn't seem to need this trick */
            align(XXH_ACC_ALIGN) ulong[8] acc;
            (cast(ubyte*) &acc[0]) [0 .. acc.sizeof] = (cast(ubyte*) &state.acc[0]) [0 .. acc.sizeof];
        }
        else
        {
            ulong* acc = state.acc;
        }
        state.totalLen += len;
        assert(state.bufferedSize <= XXH3_INTERNALBUFFER_SIZE, "state.bufferedSize > XXH3_INTERNALBUFFER_SIZE");

        /* small input : just fill in tmp buffer */
        if (state.bufferedSize + len <= XXH3_INTERNALBUFFER_SIZE)
        {
            (cast(ubyte*) &state.buffer[0]) [state.bufferedSize .. state.bufferedSize + len] =
                (cast(ubyte*) input) [0 .. len];
            state.bufferedSize += cast(XXH32_hash_t) len;
            return XXH_errorcode.XXH_OK;
        }

        /* total input is now > XXH3_INTERNALBUFFER_SIZE */
        enum XXH3_INTERNALBUFFER_STRIPES = (XXH3_INTERNALBUFFER_SIZE / XXH_STRIPE_LEN);
        static assert(XXH3_INTERNALBUFFER_SIZE % XXH_STRIPE_LEN == 0, "XXH3_INTERNALBUFFER_SIZE % XXH_STRIPE_LEN != 0"); /* clean multiple */

        /*
         * Internal buffer is partially filled (always, except at beginning)
         * Complete it, then consume it.
         */
        if (state.bufferedSize)
        {
            const size_t loadSize = XXH3_INTERNALBUFFER_SIZE - state.bufferedSize;
            (cast(ubyte*)&state.buffer[0]) [state.bufferedSize .. state.bufferedSize + loadSize] =
                (cast(ubyte*) input) [0 .. loadSize];
            input += loadSize;
            xxh3_consumeStripes(&acc[0], &state.nbStripesSoFar, state.nbStripesPerBlock,
                    &state.buffer[0], XXH3_INTERNALBUFFER_STRIPES, secret,
                    state.secretLimit, f_acc512, f_scramble);
            state.bufferedSize = 0;
        }
        assert(input < bEnd, "input >= bEnd");

        /* large input to consume : ingest per full block */
        if (cast(size_t)(bEnd - input) > state.nbStripesPerBlock * XXH_STRIPE_LEN)
        {
            size_t nbStripes = cast(size_t)(bEnd - 1 - input) / XXH_STRIPE_LEN;
            assert(state.nbStripesPerBlock >= state.nbStripesSoFar, "state.nbStripesPerBlock < state.nbStripesSoFar");
            /* join to current block's end */
            {
                const size_t nbStripesToEnd = state.nbStripesPerBlock - state.nbStripesSoFar;
                assert(nbStripesToEnd <= nbStripes, "nbStripesToEnd > nbStripes");
                xxh3_accumulate(&acc[0], input,
                        secret + state.nbStripesSoFar * XXH_SECRET_CONSUME_RATE,
                        nbStripesToEnd, f_acc512);
                f_scramble(&acc[0], secret + state.secretLimit);
                state.nbStripesSoFar = 0;
                input += nbStripesToEnd * XXH_STRIPE_LEN;
                nbStripes -= nbStripesToEnd;
            }
            /* consume per entire blocks */
            while (nbStripes >= state.nbStripesPerBlock)
            {
                xxh3_accumulate(&acc[0], input, secret, state.nbStripesPerBlock, f_acc512);
                f_scramble(&acc[0], secret + state.secretLimit);
                input += state.nbStripesPerBlock * XXH_STRIPE_LEN;
                nbStripes -= state.nbStripesPerBlock;
            }
            /* consume last partial block */
            xxh3_accumulate(&acc[0], input, secret, nbStripes, f_acc512);
            input += nbStripes * XXH_STRIPE_LEN;
            assert(input < bEnd, "input exceeds buffer, no bytes left"); /* at least some bytes left */
            state.nbStripesSoFar = nbStripes;
            /* buffer predecessor of last partial stripe */
            (cast(ubyte*) &state.buffer[0])
                [state.buffer.sizeof - XXH_STRIPE_LEN .. state.buffer.sizeof - XXH_STRIPE_LEN + XXH_STRIPE_LEN] =
                (cast(ubyte*) input - XXH_STRIPE_LEN) [0 .. XXH_STRIPE_LEN];
            assert(bEnd - input <= XXH_STRIPE_LEN, "input exceed strip length");
        }
        else
        {
            /* content to consume <= block size */
            /* Consume input by a multiple of internal buffer size */
            if (bEnd - input > XXH3_INTERNALBUFFER_SIZE)
            {
                const ubyte* limit = bEnd - XXH3_INTERNALBUFFER_SIZE;
                do
                {
                    xxh3_consumeStripes(&acc[0], &state.nbStripesSoFar, state.nbStripesPerBlock, input,
                            XXH3_INTERNALBUFFER_STRIPES, secret,
                            state.secretLimit, f_acc512, f_scramble);
                    input += XXH3_INTERNALBUFFER_SIZE;
                }
                while (input < limit);
                /* buffer predecessor of last partial stripe */
                (cast(ubyte*) &state.buffer[0])
                    [state.buffer.sizeof - XXH_STRIPE_LEN .. state.buffer.sizeof - XXH_STRIPE_LEN + XXH_STRIPE_LEN] =
                    (cast(ubyte*) input - XXH_STRIPE_LEN) [0 .. XXH_STRIPE_LEN];
            }
        }

        /* Some remaining input (always) : buffer it */
        assert(input < bEnd, "input exceeds buffer");
        assert(bEnd - input <= XXH3_INTERNALBUFFER_SIZE, "input outside buffer");
        assert(state.bufferedSize == 0, "bufferedSize != 0");
        (cast(ubyte*) &state.buffer[0]) [0 .. cast(size_t)(bEnd - input)] =
            (cast(ubyte*) input) [0 .. cast(size_t)(bEnd - input)];
        state.bufferedSize = cast(XXH32_hash_t)(bEnd - input);
        static if (XXH3_STREAM_USE_STACK >= 1)
        {
            /* save stack accumulators into state */
            (cast(ubyte*) &state.acc[0]) [0 .. acc.sizeof] = (cast(ubyte*) &acc[0]) [0 .. acc.sizeof];
        }
    }

    return XXH_errorcode.XXH_OK;
}

/* XXH PUBLIC API - hidden in D module */
private XXH_errorcode xxh3_64bits_update(scope XXH3_state_t* state, scope const(void)* input, size_t len)
    @safe pure nothrow @nogc
{
    return xxh3_update(state, cast(const(ubyte)*) input, len,
            xxh3_accumulate_512, xxh3_scrambleAcc);
}

private void xxh3_digest_long(XXH64_hash_t* acc, const XXH3_state_t* state, const ubyte* secret)
    @trusted pure nothrow @nogc
{
    /*
     * Digest on a local copy. This way, the state remains unaltered, and it can
     * continue ingesting more input afterwards.
     */
    (cast(ubyte*) &acc[0]) [0 .. state.acc.sizeof] = (cast(ubyte*) &state.acc[0]) [0 .. state.acc.sizeof];
    if (state.bufferedSize >= XXH_STRIPE_LEN)
    {
        const size_t nbStripes = (state.bufferedSize - 1) / XXH_STRIPE_LEN;
        size_t nbStripesSoFar = state.nbStripesSoFar;
        xxh3_consumeStripes(acc, &nbStripesSoFar, state.nbStripesPerBlock, &state.buffer[0],
                nbStripes, secret, state.secretLimit, xxh3_accumulate_512, xxh3_scrambleAcc);
        /* last stripe */
        xxh3_accumulate_512(acc, &state.buffer[0] + state.bufferedSize - XXH_STRIPE_LEN,
                secret + state.secretLimit - XXH_SECRET_LASTACC_START);
    }
    else
    { /* bufferedSize < XXH_STRIPE_LEN */
        ubyte[XXH_STRIPE_LEN] lastStripe;
        const size_t catchupSize = XXH_STRIPE_LEN - state.bufferedSize;
        assert(state.bufferedSize > 0, "bufferedSize <= 0"); /* there is always some input buffered */
        (cast(ubyte*) &lastStripe[0]) [0 .. catchupSize] =
            (cast(ubyte*) &state.buffer[0]) [state.buffer.sizeof - catchupSize .. state.buffer.sizeof];
        (cast(ubyte*) &lastStripe[0]) [catchupSize .. catchupSize + state.bufferedSize] =
            (cast(ubyte*) &state.buffer[0]) [0 .. state.bufferedSize];
        xxh3_accumulate_512(&acc[0], &lastStripe[0], &secret[0] + state.secretLimit - XXH_SECRET_LASTACC_START);
    }
}

/* XXH PUBLIC API - hidden in D module */
private XXH64_hash_t xxh3_64bits_digest(const XXH3_state_t* state)
    @trusted pure nothrow @nogc
{
    const ubyte* secret = (state.extSecret == null) ? &state.customSecret[0] : &state.extSecret[0];
    if (state.totalLen > XXH3_MIDSIZE_MAX)
    {
        align(XXH_ACC_ALIGN) XXH64_hash_t[XXH_ACC_NB] acc;
        xxh3_digest_long(&acc[0], state, secret);
        return xxh3_mergeAccs(&acc[0], secret + XXH_SECRET_MERGEACCS_START,
                cast(ulong) state.totalLen * XXH_PRIME64_1);
    }
    /* totalLen <= XXH3_MIDSIZE_MAX: digesting a short input */
    if (state.useSeed)
        return xxh3_64bits_withSeed(&state.buffer[0], cast(size_t) state.totalLen, state.seed);
    return xxh3_64bits_withSecret(&state.buffer[0],
            cast(size_t)(state.totalLen), secret, state.secretLimit + XXH_STRIPE_LEN);
}

/* ==========================================
 * XXH3 128 bits (a.k.a XXH128)
 * ==========================================
 * XXH3's 128-bit variant has better mixing and strength than the 64-bit variant,
 * even without counting the significantly larger output size.
 *
 * For example, extra steps are taken to avoid the seed-dependent collisions
 * in 17-240 byte inputs (See xxh3_mix16B and xxh128_mix32B).
 *
 * This strength naturally comes at the cost of some speed, especially on short
 * lengths. Note that longer hashes are about as fast as the 64-bit version
 * due to it using only a slight modification of the 64-bit loop.
 *
 * XXH128 is also more oriented towards 64-bit machines. It is still extremely
 * fast for a _128-bit_ hash on 32-bit (it usually clears XXH64).
 */
private XXH128_hash_t xxh3_len_1to3_128b(
    const ubyte* input, size_t len, const ubyte* secret, XXH64_hash_t seed)
    @trusted pure nothrow @nogc
{
    /* A doubled version of 1to3_64b with different constants. */
    assert(input != null, "input is null");
    assert(1 <= len && len <= 3, "len is out of range");
    assert(secret != null, "secret is null");
    /*
     * len = 1: combinedl = { input[0], 0x01, input[0], input[0] }
     * len = 2: combinedl = { input[1], 0x02, input[0], input[1] }
     * len = 3: combinedl = { input[2], 0x03, input[0], input[1] }
     */
    {
        const ubyte c1 = input[0];
        const ubyte c2 = input[len >> 1];
        const ubyte c3 = input[len - 1];
        const uint combinedl = (cast(uint) c1 << 16) | (
                cast(uint) c2 << 24) | (cast(uint) c3 << 0) | (cast(uint) len << 8);
        const uint combinedh = rol(bswap(combinedl), 13);
        const ulong bitflipl = (xxh_readLE32(secret) ^ xxh_readLE32(secret + 4)) + seed;
        const ulong bitfliph = (xxh_readLE32(secret + 8) ^ xxh_readLE32(secret + 12)) - seed;
        const ulong keyed_lo = cast(ulong) combinedl ^ bitflipl;
        const ulong keyed_hi = cast(ulong) combinedh ^ bitfliph;
        XXH128_hash_t h128;
        h128.low64 = xxh64_avalanche(keyed_lo);
        h128.high64 = xxh64_avalanche(keyed_hi);
        return h128;
    }
}

private XXH128_hash_t xxh3_len_4to8_128b(
    const ubyte* input, size_t len, const ubyte* secret, XXH64_hash_t seed)
    @trusted pure nothrow @nogc
{
    assert(input != null, "input is null");
    assert(secret != null, "secret is null");
    assert(4 <= len && len <= 8, "len is out of range");
    seed ^= cast(ulong) bswap(cast(uint) seed) << 32;
    {
        const uint input_lo = xxh_readLE32(input);
        const uint input_hi = xxh_readLE32(input + len - 4);
        const ulong input_64 = input_lo + (cast(ulong) input_hi << 32);
        const ulong bitflip = (xxh_readLE64(secret + 16) ^ xxh_readLE64(secret + 24)) + seed;
        const ulong keyed = input_64 ^ bitflip;

        /* Shift len to the left to ensure it is even, this avoids even multiplies. */
        XXH128_hash_t m128 = xxh_mult64to128(keyed, XXH_PRIME64_1 + (len << 2));

        m128.high64 += (m128.low64 << 1);
        m128.low64 ^= (m128.high64 >> 3);

        m128.low64 = xxh_xorshift64(m128.low64, 35);
        m128.low64 *= 0x9FB21C651E98DF25;
        m128.low64 = xxh_xorshift64(m128.low64, 28);
        m128.high64 = xxh3_avalanche(m128.high64);
        return m128;
    }
}

private XXH128_hash_t xxh3_len_9to16_128b(
    const ubyte* input, size_t len, const ubyte* secret, XXH64_hash_t seed)
    @trusted pure nothrow @nogc
{
    assert(input != null, "input is null");
    assert(secret != null, "secret is null");
    assert(9 <= len && len <= 16, "len out of range");
    {
        const ulong bitflipl = (xxh_readLE64(secret + 32) ^ xxh_readLE64(secret + 40)) - seed;
        const ulong bitfliph = (xxh_readLE64(secret + 48) ^ xxh_readLE64(secret + 56)) + seed;
        const ulong input_lo = xxh_readLE64(input);
        ulong input_hi = xxh_readLE64(input + len - 8);
        XXH128_hash_t m128 = xxh_mult64to128(input_lo ^ input_hi ^ bitflipl, XXH_PRIME64_1);
        /*
         * Put len in the middle of m128 to ensure that the length gets mixed to
         * both the low and high bits in the 128x64 multiply below.
         */
        m128.low64 += cast(ulong)(len - 1) << 54;
        input_hi ^= bitfliph;
        /*
         * Add the high 32 bits of input_hi to the high 32 bits of m128, then
         * add the long product of the low 32 bits of input_hi and XXH_PRIME32_2 to
         * the high 64 bits of m128.
         *
         * The best approach to this operation is different on 32-bit and 64-bit.
         */
        if ((void*).sizeof < (ulong).sizeof)
        { /* 32-bit */
            /*
             * 32-bit optimized version, which is more readable.
             *
             * On 32-bit, it removes an ADC and delays a dependency between the two
             * halves of m128.high64, but it generates an extra mask on 64-bit.
             */
            m128.high64 += (input_hi & 0xFFFFFFFF00000000) + xxh_mult32to64(cast(uint) input_hi,
                    XXH_PRIME32_2);
        }
        else
        {
            /*
             * 64-bit optimized (albeit more confusing) version.
             *
             * Uses some properties of addition and multiplication to remove the mask:
             *
             * Let:
             *    a = input_hi.lo = (input_hi & 0x00000000FFFFFFFF)
             *    b = input_hi.hi = (input_hi & 0xFFFFFFFF00000000)
             *    c = XXH_PRIME32_2
             *
             *    a + (b * c)
             * Inverse Property: x + y - x == y
             *    a + (b * (1 + c - 1))
             * Distributive Property: x * (y + z) == (x * y) + (x * z)
             *    a + (b * 1) + (b * (c - 1))
             * Identity Property: x * 1 == x
             *    a + b + (b * (c - 1))
             *
             * Substitute a, b, and c:
             *    input_hi.hi + input_hi.lo + ((ulong)input_hi.lo * (XXH_PRIME32_2 - 1))
             *
             * Since input_hi.hi + input_hi.lo == input_hi, we get this:
             *    input_hi + ((ulong)input_hi.lo * (XXH_PRIME32_2 - 1))
             */
            m128.high64 += input_hi + xxh_mult32to64(cast(uint) input_hi, XXH_PRIME32_2 - 1);
        }
        /* m128 ^= bswap(m128 >> 64); */
        m128.low64 ^= bswap(m128.high64);

        { /* 128x64 multiply: h128 = m128 * XXH_PRIME64_2; */
            XXH128_hash_t h128 = xxh_mult64to128(m128.low64, XXH_PRIME64_2);
            h128.high64 += m128.high64 * XXH_PRIME64_2;

            h128.low64 = xxh3_avalanche(h128.low64);
            h128.high64 = xxh3_avalanche(h128.high64);
            return h128;
        }
    }
}

private XXH128_hash_t xxh3_len_0to16_128b(
    const ubyte* input, size_t len, const ubyte* secret, XXH64_hash_t seed)
    @trusted pure nothrow @nogc
{
    assert(len <= 16, "len > 16");
    {
        if (len > 8)
            return xxh3_len_9to16_128b(input, len, secret, seed);
        if (len >= 4)
            return xxh3_len_4to8_128b(input, len, secret, seed);
        if (len)
            return xxh3_len_1to3_128b(input, len, secret, seed);
        {
            XXH128_hash_t h128;
            const ulong bitflipl = xxh_readLE64(secret + 64) ^ xxh_readLE64(secret + 72);
            const ulong bitfliph = xxh_readLE64(secret + 80) ^ xxh_readLE64(secret + 88);
            h128.low64 = xxh64_avalanche(seed ^ bitflipl);
            h128.high64 = xxh64_avalanche(seed ^ bitfliph);
            return h128;
        }
    }
}

private XXH128_hash_t xxh128_mix32B(
    XXH128_hash_t acc, const ubyte* input_1, const ubyte* input_2, const ubyte* secret, XXH64_hash_t seed)
    @trusted pure nothrow @nogc
{
    acc.low64 += xxh3_mix16B(input_1, secret + 0, seed);
    acc.low64 ^= xxh_readLE64(input_2) + xxh_readLE64(input_2 + 8);
    acc.high64 += xxh3_mix16B(input_2, secret + 16, seed);
    acc.high64 ^= xxh_readLE64(input_1) + xxh_readLE64(input_1 + 8);
    return acc;
}

private XXH128_hash_t xxh3_len_17to128_128b(
    const ubyte* input, size_t len, const ubyte* secret, size_t secretSize, XXH64_hash_t seed)
    @trusted pure nothrow @nogc
in(secretSize >= XXH3_SECRET_SIZE_MIN, "secretSie < XXH3_SECRET_SIZE_MIN")
in(16 < len && len <= 128, "len out of range")
{
    XXH128_hash_t acc;
    acc.low64 = len * XXH_PRIME64_1;
    acc.high64 = 0;

    static if (XXH_SIZE_OPT >= 1)
    {
        /* Smaller, but slightly slower. */
        size_t i = (len - 1) / 32;
        do
        {
            acc = xxh128_mix32B(acc, input + 16 * i,
                    input + len - 16 * (i + 1), secret + 32 * i, seed);
        }
        while (i-- != 0);
    }
    else
    {
        if (len > 32)
        {
            if (len > 64)
            {
                if (len > 96)
                {
                    acc = xxh128_mix32B(acc, input + 48, input + len - 64, secret + 96, seed);
                }
                acc = xxh128_mix32B(acc, input + 32, input + len - 48, secret + 64, seed);
            }
            acc = xxh128_mix32B(acc, input + 16, input + len - 32, secret + 32, seed);
        }
        acc = xxh128_mix32B(acc, input, input + len - 16, secret, seed);
    }
    {
        XXH128_hash_t h128;
        h128.low64 = acc.low64 + acc.high64;
        h128.high64 = (acc.low64 * XXH_PRIME64_1) + (
                acc.high64 * XXH_PRIME64_4) + ((len - seed) * XXH_PRIME64_2);
        h128.low64 = xxh3_avalanche(h128.low64);
        h128.high64 = cast(XXH64_hash_t) 0 - xxh3_avalanche(h128.high64);
        return h128;
    }
}

private XXH128_hash_t xxh3_len_129to240_128b(
    const ubyte* input, size_t len, const ubyte* secret, size_t secretSize, XXH64_hash_t seed)
    @trusted pure nothrow @nogc
in(secretSize >= XXH3_SECRET_SIZE_MIN, "secretSize < XXH3_SECRET_SIZE_MIN")
in(128 < len && len <= XXH3_MIDSIZE_MAX, "len > 128 or len > XXH3_MIDSIZE_MAX")
{
    XXH128_hash_t acc;
    const int nbRounds = cast(int) len / 32;
    int i;
    acc.low64 = len * XXH_PRIME64_1;
    acc.high64 = 0;
    for (i = 0; i < 4; i++)
    {
        acc = xxh128_mix32B(acc, input + (32 * i), input + (32 * i) + 16, secret + (32 * i),
                seed);
    }
    acc.low64 = xxh3_avalanche(acc.low64);
    acc.high64 = xxh3_avalanche(acc.high64);
    assert(nbRounds >= 4, "nbRounds < 4");
    for (i = 4; i < nbRounds; i++)
    {
        acc = xxh128_mix32B(acc, input + (32 * i), input + (32 * i) + 16,
                secret + XXH3_MIDSIZE_STARTOFFSET + (32 * (i - 4)), seed);
    }
    /* last bytes */
    acc = xxh128_mix32B(acc, input + len - 16, input + len - 32,
            secret + XXH3_SECRET_SIZE_MIN - XXH3_MIDSIZE_LASTOFFSET - 16, 0 - seed);

    {
        XXH128_hash_t h128;
        h128.low64 = acc.low64 + acc.high64;
        h128.high64 = (acc.low64 * XXH_PRIME64_1) + (
                acc.high64 * XXH_PRIME64_4) + ((len - seed) * XXH_PRIME64_2);
        h128.low64 = xxh3_avalanche(h128.low64);
        h128.high64 = cast(XXH64_hash_t) 0 - xxh3_avalanche(h128.high64);
        return h128;
    }
}

private XXH128_hash_t xxh3_hashLong_128b_internal(
    const void* input, size_t len, const ubyte* secret, size_t secretSize,
    XXH3_f_accumulate_512 f_acc512, XXH3_f_scrambleAcc f_scramble)
    @trusted pure nothrow @nogc
{
    align(XXH_ACC_ALIGN) ulong[XXH_ACC_NB] acc = XXH3_INIT_ACC;

    xxh3_hashLong_internal_loop(&acc[0], cast(const ubyte*) input, len,
            secret, secretSize, f_acc512, f_scramble);

    /* converge into final hash */
    static assert(acc.sizeof == 64, "acc isn't 64 bytes long");
    assert(secretSize >= acc.sizeof + XXH_SECRET_MERGEACCS_START, "secretSze < allowed limit.");
    {
        XXH128_hash_t h128;
        h128.low64 = xxh3_mergeAccs(&acc[0],
                secret + XXH_SECRET_MERGEACCS_START, cast(ulong) len * XXH_PRIME64_1);
        h128.high64 = xxh3_mergeAccs(&acc[0], secret + secretSize - (acc)
                .sizeof - XXH_SECRET_MERGEACCS_START, ~(cast(ulong) len * XXH_PRIME64_2));
        return h128;
    }
}

private XXH128_hash_t xxh3_hashLong_128b_default(
    const void* input, size_t len, XXH64_hash_t seed64, const void* secret, size_t secretLen)
    @safe pure nothrow @nogc
{
    return xxh3_hashLong_128b_internal(input, len, &xxh3_kSecret[0],
            (xxh3_kSecret).sizeof, xxh3_accumulate_512, xxh3_scrambleAcc);
}

/*
 * It's important for performance to pass @p secretLen (when it's static)
 * to the compiler, so that it can properly optimize the vectorized loop.
 */
private XXH128_hash_t xxh3_hashLong_128b_withSecret(
    const void* input, size_t len, XXH64_hash_t seed64, const void* secret, size_t secretLen)
    @safe pure nothrow @nogc
{
    return xxh3_hashLong_128b_internal(input, len, cast(const ubyte*) secret,
            secretLen, xxh3_accumulate_512, xxh3_scrambleAcc);
}

private XXH128_hash_t xxh3_hashLong_128b_withSeed_internal(
    const void* input, size_t len, XXH64_hash_t seed64,
    XXH3_f_accumulate_512 f_acc512, XXH3_f_scrambleAcc f_scramble,
    XXH3_f_initCustomSecret f_initSec)
    @trusted pure nothrow @nogc
{
    if (seed64 == 0)
        return xxh3_hashLong_128b_internal(input, len, &xxh3_kSecret[0],
                (xxh3_kSecret).sizeof, f_acc512, f_scramble);
    {
        align(XXH_SEC_ALIGN) ubyte[XXH_SECRET_DEFAULT_SIZE] secret;
        f_initSec(&secret[0], seed64);
        return xxh3_hashLong_128b_internal(input, len,
                cast(const ubyte*)&secret[0], (secret).sizeof, f_acc512, f_scramble);
    }
}
/*
 * It's important for performance that XXH3_hashLong is not inlined.
 */
private XXH128_hash_t xxh3_hashLong_128b_withSeed(
    const void* input, size_t len, XXH64_hash_t seed64, const void* secret, size_t secretLen)
    @safe pure nothrow @nogc
{
    return xxh3_hashLong_128b_withSeed_internal(input, len, seed64,
            xxh3_accumulate_512, xxh3_scrambleAcc, xxh3_initCustomSecret);
}

alias XXH3_hashLong128_f = XXH128_hash_t function(const void*, size_t,
        XXH64_hash_t, const void*, size_t) @safe pure nothrow @nogc;

private XXH128_hash_t xxh3_128bits_internal(
    const void* input, size_t len, XXH64_hash_t seed64, const void* secret, size_t secretLen,
    XXH3_hashLong128_f f_hl128)
    @safe pure nothrow @nogc
in(secretLen >= XXH3_SECRET_SIZE_MIN, "Secret length is < XXH3_SECRET_SIZE_MIN")
{
    /*
     * If an action is to be taken if `secret` conditions are not respected,
     * it should be done here.
     * For now, it's a contract pre-condition.
     * Adding a check and a branch here would cost performance at every hash.
     */
    if (len <= 16)
        return xxh3_len_0to16_128b(cast(const ubyte*) input, len,
                cast(const ubyte*) secret, seed64);
    if (len <= 128)
        return xxh3_len_17to128_128b(cast(const ubyte*) input, len,
                cast(const ubyte*) secret, secretLen, seed64);
    if (len <= XXH3_MIDSIZE_MAX)
        return xxh3_len_129to240_128b(cast(const ubyte*) input, len,
                cast(const ubyte*) secret, secretLen, seed64);
    return f_hl128(input, len, seed64, secret, secretLen);
}

/* ===   Public XXH128 API   === */

/* XXH PUBLIC API - hidden in D module */
private XXH128_hash_t xxh3_128bits(const void* input, size_t len)
    @safe pure nothrow @nogc
{
    return xxh3_128bits_internal(input, len, 0, &xxh3_kSecret[0],
            (xxh3_kSecret).sizeof, &xxh3_hashLong_128b_default);
}

/* XXH PUBLIC API - hidden in D module */
private XXH128_hash_t xxh3_128bits_withSecret(
    const void* input, size_t len, const void* secret, size_t secretSize)
    @safe pure nothrow @nogc
{
    return xxh3_128bits_internal(input, len, 0, cast(const ubyte*) secret,
            secretSize, &xxh3_hashLong_128b_withSecret);
}

/* XXH PUBLIC API - hidden in D module */
private XXH128_hash_t xxh3_128bits_withSeed(const void* input, size_t len, XXH64_hash_t seed)
    @safe pure nothrow @nogc
{
    return xxh3_128bits_internal(input, len, seed, &xxh3_kSecret[0],
            (xxh3_kSecret).sizeof, &xxh3_hashLong_128b_withSeed);
}

/* XXH PUBLIC API - hidden in D module */
private XXH128_hash_t xxh3_128bits_withSecretandSeed(
    const void* input, size_t len, const void* secret, size_t secretSize, XXH64_hash_t seed)
    @safe pure nothrow @nogc
{
    if (len <= XXH3_MIDSIZE_MAX)
        return xxh3_128bits_internal(input, len, seed, &xxh3_kSecret[0],
                (xxh3_kSecret).sizeof, null);
    return xxh3_hashLong_128b_withSecret(input, len, seed, secret, secretSize);
}

/* XXH PUBLIC API - hidden in D module */
private XXH128_hash_t XXH128(const void* input, size_t len, XXH64_hash_t seed)
    @safe pure nothrow @nogc
{
    return xxh3_128bits_withSeed(input, len, seed);
}

/* XXH PUBLIC API - hidden in D module */
private XXH_errorcode xxh3_128bits_reset(scope XXH3_state_t* statePtr)
    @safe pure nothrow @nogc
{
    return xxh3_64bits_reset(statePtr);
}

/* XXH PUBLIC API - hidden in D module */
private XXH_errorcode xxh3_128bits_reset_withSecret(
    XXH3_state_t* statePtr, const void* secret, size_t secretSize)
    @safe pure nothrow @nogc
{
    return xxh3_64bits_reset_withSecret(statePtr, secret, secretSize);
}

/* XXH PUBLIC API - hidden in D module */ private
XXH_errorcode xxh3_128bits_reset_withSeed(
    XXH3_state_t* statePtr, XXH64_hash_t seed)
    @safe pure nothrow @nogc
{
    return xxh3_64bits_reset_withSeed(statePtr, seed);
}

/* XXH PUBLIC API - hidden in D module */ private
XXH_errorcode xxh3_128bits_reset_withSecretandSeed(
    XXH3_state_t* statePtr, const void* secret, size_t secretSize, XXH64_hash_t seed)
    @safe pure nothrow @nogc
{
    return xxh3_64bits_reset_withSecretandSeed(statePtr, secret, secretSize, seed);
}

/* XXH PUBLIC API - hidden in D module */ private
XXH_errorcode xxh3_128bits_update(
    scope XXH3_state_t* state, scope const void* input, size_t len)
    @safe pure nothrow @nogc
{
    return xxh3_update(state, cast(const ubyte*) input, len,
            xxh3_accumulate_512, xxh3_scrambleAcc);
}

/* XXH PUBLIC API - hidden in D module */ private
XXH128_hash_t xxh3_128bits_digest(const XXH3_state_t* state)
    @trusted pure nothrow @nogc
{
    const ubyte* secret = (state.extSecret == null) ? &state.customSecret[0] : &state.extSecret[0];
    if (state.totalLen > XXH3_MIDSIZE_MAX)
    {
        align(XXH_ACC_ALIGN) XXH64_hash_t[XXH_ACC_NB] acc;
        xxh3_digest_long(&acc[0], state, secret);
        assert(state.secretLimit + XXH_STRIPE_LEN >= acc.sizeof + XXH_SECRET_MERGEACCS_START, "Internal error");
        {
            XXH128_hash_t h128;
            h128.low64 = xxh3_mergeAccs(&acc[0], secret + XXH_SECRET_MERGEACCS_START,
                    cast(ulong) state.totalLen * XXH_PRIME64_1);
            h128.high64 = xxh3_mergeAccs(&acc[0], secret + state.secretLimit + XXH_STRIPE_LEN - (acc)
                    .sizeof - XXH_SECRET_MERGEACCS_START,
                    ~(cast(ulong) state.totalLen * XXH_PRIME64_2));
            return h128;
        }
    }
    /* len <= XXH3_MIDSIZE_MAX : short code */
    if (state.seed)
        return xxh3_128bits_withSeed(&state.buffer[0], cast(size_t) state.totalLen, state.seed);
    return xxh3_128bits_withSecret(&state.buffer[0],
            cast(size_t)(state.totalLen), secret, state.secretLimit + XXH_STRIPE_LEN);
}

/* ----------------------------------------------------------------------------------------*/

import core.bitop;

public import std.digest;

/*
 * Helper methods for encoding the buffer.
 * Can be removed if the optimizer can inline the methods from std.bitmanip.
 */
version (LittleEndian)
{
    private alias nativeToBigEndian = bswap;
    private alias bigEndianToNative = bswap;
}
else
pragma(inline, true) private pure @nogc nothrow @safe
{
    uint nativeToBigEndian(uint val)
    {
        return val;
    }

    ulong nativeToBigEndian(ulong val)
    {
        return val;
    }

    alias bigEndianToNative = nativeToBigEndian;
}

/**
 * Template API XXHTemplate implementation. Uses parameters to configure for number of bits and XXH variant (classic or XXH3)
 * See `std.digest` for differences between template and OOP API.
 */
struct XXHTemplate(HASH, STATE, bool useXXH3)
{
private:
    HASH hash;
    STATE state;
    HASH seed = HASH.init;

public:
    enum digestSize = HASH.sizeof * 8;

    /**
         * Use this to feed the digest with data.
         * Also implements the $(REF isOutputRange, std,range,primitives)
         * interface for `ubyte` and `const(ubyte)[]`.
         *
         * Example:
         * ----
         * XXHTemplate!(hashtype,statetype,useXXH3) dig;
         * dig.put(cast(ubyte) 0); //single ubyte
         * dig.put(cast(ubyte) 0, cast(ubyte) 0); //variadic
         * ubyte[10] buf;
         * dig.put(buf); //buffer
         * ----
         */
    void put(scope const(ubyte)[] data...) @safe nothrow @nogc
    {
        XXH_errorcode ec = XXH_errorcode.XXH_OK;
        if (data.length > 0) // digest will only change, when there is data!
        {
            static if (digestSize == 32)
                ec = xxh32_update(&state, &data[0], data.length);
            else static if (digestSize == 64 && !useXXH3)
                ec = xxh64_update(&state, &data[0], data.length);
            else static if (digestSize == 64 && useXXH3)
                ec = xxh3_64bits_update(&state, &data[0], data.length);
            else static if (digestSize == 128)
                ec = xxh3_128bits_update(&state, &data[0], data.length);
            else
                assert(false, "Unknown XXH bitdeep or variant");
        }
        assert(ec == XXH_errorcode.XXH_OK, "Update failed");
    }

    /**
         * Used to (re)initialize the XXHTemplate digest.
         *
         * Example:
         * --------
         * XXHTemplate!(hashtype,statetype,useXXH3) digest;
         * digest.start();
         * digest.put(0);
         * --------
         */
    void start() @safe nothrow @nogc
    {
        this = typeof(this).init;
        XXH_errorcode ec;
        static if (digestSize == 32)
        {
            assert(state.alignof == uint.alignof, "Wrong alignment for state structure");
            ec = xxh32_reset(&state, seed);
        }
        else static if (digestSize == 64 && !useXXH3)
        {
            assert(state.alignof == ulong.alignof, "Wrong alignment for state structure");
            ec = xxh64_reset(&state, seed);
        }
        else static if (digestSize == 64 && useXXH3)
        {
            assert(state.alignof == 64, "Wrong alignment for state structure");
            ec = xxh3_64bits_reset(&state);
        }
        else static if (digestSize == 128)
        {
            assert(state.alignof == 64, "Wrong alignment for state structure");
            ec = xxh3_128bits_reset(&state);
        }
        else
            assert(false, "Unknown XXH bitdeep or variant");
        //assert(ec == XXH_errorcode.XXH_OK, "reset failed");
    }

    /**
         * Returns the finished XXH hash. This also calls $(LREF start) to
         * reset the internal state.
          */
    ubyte[digestSize / 8] finish() @trusted nothrow @nogc
    {
        static if (digestSize == 32)
        {
            hash = xxh32_digest(&state);
            const auto rc = nativeToBigEndian(hash);
        }
        else static if (digestSize == 64 && !useXXH3)
        {
            hash = xxh64_digest(&state);
            const auto rc = nativeToBigEndian(hash);
        }
        else static if (digestSize == 64 && useXXH3)
        {
            hash = xxh3_64bits_digest(&state);
            const auto rc = nativeToBigEndian(hash);
        }
        else static if (digestSize == 128)
        {
            hash = xxh3_128bits_digest(&state);
            HASH rc;
            // Note: low64 and high64 are intentionally exchanged!
            rc.low64 = nativeToBigEndian(hash.high64);
            rc.high64 = nativeToBigEndian(hash.low64);
        }

        return (cast(ubyte*)&rc)[0 .. rc.sizeof];
    }
}
///
@safe unittest
{
    // Simple example using the XXH_64 digest
    XXHTemplate!(XXH64_hash_t, XXH64_state_t, false) hash1;
    hash1.start();
    hash1.put(cast(ubyte) 0);
    auto result = hash1.finish();
}

alias XXH_32 = XXHTemplate!(XXH32_hash_t, XXH32_state_t, false); /// XXH_32 for XXH, 32bit, hash is ubyte[4]
alias XXH_64 = XXHTemplate!(XXH64_hash_t, XXH64_state_t, false); /// XXH_64 for XXH, 64bit, hash is ubyte[8]
alias XXH3_64 = XXHTemplate!(XXH64_hash_t, XXH3_state_t, true); /// XXH3_64 for XXH3, 64bits, hash is ubyte[8]
alias XXH3_128 = XXHTemplate!(XXH128_hash_t, XXH3_state_t, true); /// XXH3_128 for XXH3, 128bits, hash is ubyte[16]

///
@safe unittest
{
    //Simple example
    XXH_32 hash1;
    hash1.start();
    hash1.put(cast(ubyte) 0);
    auto result = hash1.finish();
}
///
@safe unittest
{
    //Simple example
    XXH_64 hash1;
    hash1.start();
    hash1.put(cast(ubyte) 0);
    auto result = hash1.finish();
}
///
@safe unittest
{
    //Simple example
    XXH3_64 hash1;
    hash1.start();
    hash1.put(cast(ubyte) 0);
    auto result = hash1.finish();
}
///
@safe unittest
{
    //Simple example
    XXH3_128 hash1;
    hash1.start();
    hash1.put(cast(ubyte) 0);
    auto result = hash1.finish();
}

///
@safe unittest
{
    //Simple example, hashing a string using xxh32Of helper function
    auto hash = xxh32Of("abc");
    //Let's get a hash string
    assert(toHexString(hash) == "32D153FF");
}
///
@safe unittest
{
    //Simple example, hashing a string using xxh32Of helper function
    auto hash = xxh64Of("abc");
    //Let's get a hash string
    assert(toHexString(hash) == "44BC2CF5AD770999"); // XXH64
}
///
@safe unittest
{
    //Simple example, hashing a string using xxh32Of helper function
    auto hash = xxh3_64Of("abc");
    //Let's get a hash string
    assert(toHexString(hash) == "78AF5F94892F3950"); // XXH3/64
}
///
@safe unittest
{
    //Simple example, hashing a string using xxh32Of helper function
    auto hash = xxh128Of("abc");
    //Let's get a hash string
    assert(toHexString(hash) == "06B05AB6733A618578AF5F94892F3950");

}

///
@safe unittest
{
    //Using the basic API
    XXH_32 hash;
    hash.start();
    ubyte[1024] data;
    //Initialize data here...
    hash.put(data);
    ubyte[4] result = hash.finish();
}
///
@safe unittest
{
    //Using the basic API
    XXH_64 hash;
    hash.start();
    ubyte[1024] data;
    //Initialize data here...
    hash.put(data);
    ubyte[8] result = hash.finish();
}
///
@safe unittest
{
    //Using the basic API
    XXH3_64 hash;
    hash.start();
    ubyte[1024] data;
    //Initialize data here...
    hash.put(data);
    ubyte[8] result = hash.finish();
}
///
@safe unittest
{
    //Using the basic API
    XXH3_128 hash;
    hash.start();
    ubyte[1024] data;
    //Initialize data here...
    hash.put(data);
    ubyte[16] result = hash.finish();
}

///
@safe unittest
{
    //Let's use the template features:
    void doSomething(T)(ref T hash)
    if (isDigest!T)
    {
        hash.put(cast(ubyte) 0);
    }

    XXH_32 xxh;
    xxh.start();
    doSomething(xxh);
    auto hash = xxh.finish;
    assert(toHexString(hash) == "CF65B03E", "Got " ~ toHexString(hash));
}
///
@safe unittest
{
    //Let's use the template features:
    void doSomething(T)(ref T hash)
    if (isDigest!T)
    {
        hash.put(cast(ubyte) 0);
    }

    XXH_64 xxh;
    xxh.start();
    doSomething(xxh);
    auto hash = xxh.finish;
    assert(toHexString(hash) == "E934A84ADB052768", "Got " ~ toHexString(hash));
}
///
@safe unittest
{
    //Let's use the template features:
    void doSomething(T)(ref T hash)
    if (isDigest!T)
    {
        hash.put(cast(ubyte) 0);
    }

    XXH3_64 xxh;
    xxh.start();
    doSomething(xxh);
    auto hash = xxh.finish;
    assert(toHexString(hash) == "C44BDFF4074EECDB", "Got " ~ toHexString(hash));
}
///
@safe unittest
{
    //Let's use the template features:
    void doSomething(T)(ref T hash)
    if (isDigest!T)
    {
        hash.put(cast(ubyte) 0);
    }

    XXH3_128 xxh;
    xxh.start();
    doSomething(xxh);
    auto hash = xxh.finish;
    assert(toHexString(hash) == "A6CD5E9392000F6AC44BDFF4074EECDB", "Got " ~ toHexString(hash));
}

///
@safe unittest
{
    assert(isDigest!XXH_32);
    assert(isDigest!XXH_64);
    assert(isDigest!XXH3_64);
    assert(isDigest!XXH3_128);
}

@system unittest
{
    import std.range;
    import std.conv : hexString;

    ubyte[4] digest32;
    ubyte[8] digest64;
    ubyte[16] digest128;

    XXH_32 xxh;
    xxh.put(cast(ubyte[]) "abcdef");
    xxh.start();
    xxh.put(cast(ubyte[]) "");
    assert(xxh.finish() == cast(ubyte[]) hexString!"02cc5d05");

    digest32 = xxh32Of("");
    assert(digest32 == cast(ubyte[]) hexString!"02cc5d05");
    digest64 = xxh64Of("");
    assert(digest64 == cast(ubyte[]) hexString!"EF46DB3751D8E999", "Got " ~ toHexString(digest64));
    digest64 = xxh3_64Of("");
    assert(digest64 == cast(ubyte[]) hexString!"2D06800538D394C2", "Got " ~ toHexString(digest64));
    digest128 = xxh128Of("");
    assert(digest128 == cast(ubyte[]) hexString!"99AA06D3014798D86001C324468D497F",
            "Got " ~ toHexString(digest128));

    digest32 = xxh32Of("a");
    assert(digest32 == cast(ubyte[]) hexString!"550d7456");
    digest64 = xxh64Of("a");
    assert(digest64 == cast(ubyte[]) hexString!"D24EC4F1A98C6E5B", "Got " ~ toHexString(digest64));
    digest64 = xxh3_64Of("a");
    assert(digest64 == cast(ubyte[]) hexString!"E6C632B61E964E1F", "Got " ~ toHexString(digest64));
    digest128 = xxh128Of("a");
    assert(digest128 == cast(ubyte[]) hexString!"A96FAF705AF16834E6C632B61E964E1F",
            "Got " ~ toHexString(digest128));

    digest32 = xxh32Of("abc");
    assert(digest32 == cast(ubyte[]) hexString!"32D153FF");
    digest64 = xxh64Of("abc");
    assert(digest64 == cast(ubyte[]) hexString!"44BC2CF5AD770999");
    digest64 = xxh3_64Of("abc");
    assert(digest64 == cast(ubyte[]) hexString!"78AF5F94892F3950");
    digest128 = xxh128Of("abc");
    assert(digest128 == cast(ubyte[]) hexString!"06B05AB6733A618578AF5F94892F3950");

    digest32 = xxh32Of("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq");
    assert(digest32 == cast(ubyte[]) hexString!"89ea60c3");
    digest64 = xxh64Of("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq");
    assert(digest64 == cast(ubyte[]) hexString!"F06103773E8585DF", "Got " ~ toHexString(digest64));
    digest64 = xxh3_64Of("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq");
    assert(digest64 == cast(ubyte[]) hexString!"5BBCBBABCDCC3D3F", "Got " ~ toHexString(digest64));
    digest128 = xxh128Of("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq");
    assert(digest128 == cast(ubyte[]) hexString!"3D62D22A5169B016C0D894FD4828A1A7",
            "Got " ~ toHexString(digest128));

    digest32 = xxh32Of("message digest");
    assert(digest32 == cast(ubyte[]) hexString!"7c948494");
    digest64 = xxh64Of("message digest");
    assert(digest64 == cast(ubyte[]) hexString!"066ED728FCEEB3BE", "Got " ~ toHexString(digest64));
    digest64 = xxh3_64Of("message digest");
    assert(digest64 == cast(ubyte[]) hexString!"160D8E9329BE94F9", "Got " ~ toHexString(digest64));
    digest128 = xxh128Of("message digest");
    assert(digest128 == cast(ubyte[]) hexString!"34AB715D95E3B6490ABFABECB8E3A424",
            "Got " ~ toHexString(digest128));

    digest32 = xxh32Of("abcdefghijklmnopqrstuvwxyz");
    assert(digest32 == cast(ubyte[]) hexString!"63a14d5f");
    digest64 = xxh64Of("abcdefghijklmnopqrstuvwxyz");
    assert(digest64 == cast(ubyte[]) hexString!"CFE1F278FA89835C", "Got " ~ toHexString(digest64));
    digest64 = xxh3_64Of("abcdefghijklmnopqrstuvwxyz");
    assert(digest64 == cast(ubyte[]) hexString!"810F9CA067FBB90C", "Got " ~ toHexString(digest64));
    digest128 = xxh128Of("abcdefghijklmnopqrstuvwxyz");
    assert(digest128 == cast(ubyte[]) hexString!"DB7CA44E84843D67EBE162220154E1E6",
            "Got " ~ toHexString(digest128));

    digest32 = xxh32Of("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789");
    assert(digest32 == cast(ubyte[]) hexString!"9c285e64");
    digest64 = xxh64Of("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789");
    assert(digest64 == cast(ubyte[]) hexString!"AAA46907D3047814", "Got " ~ toHexString(digest64));
    digest64 = xxh3_64Of("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789");
    assert(digest64 == cast(ubyte[]) hexString!"643542BB51639CB2", "Got " ~ toHexString(digest64));
    digest128 = xxh128Of("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789");
    assert(digest128 == cast(ubyte[]) hexString!"5BCB80B619500686A3C0560BD47A4FFB",
            "Got " ~ toHexString(digest128));

    digest32 = xxh32Of(
            "1234567890123456789012345678901234567890" ~ "1234567890123456789012345678901234567890");
    assert(digest32 == cast(ubyte[]) hexString!"9c05f475");
    digest64 = xxh64Of(
            "1234567890123456789012345678901234567890" ~ "1234567890123456789012345678901234567890");
    assert(digest64 == cast(ubyte[]) hexString!"E04A477F19EE145D", "Got " ~ toHexString(digest64));
    digest64 = xxh3_64Of(
            "1234567890123456789012345678901234567890" ~ "1234567890123456789012345678901234567890");
    assert(digest64 == cast(ubyte[]) hexString!"7F58AA2520C681F9", "Got " ~ toHexString(digest64));
    digest128 = xxh128Of(
            "1234567890123456789012345678901234567890" ~ "1234567890123456789012345678901234567890");
    assert(digest128 == cast(ubyte[]) hexString!"08DD22C3DDC34CE640CB8D6AC672DCB8",
            "Got " ~ toHexString(digest128));

    enum ubyte[16] input = cast(ubyte[16]) hexString!"c3fcd3d76192e4007dfb496cca67e13b";
    assert(toHexString(input) == "C3FCD3D76192E4007DFB496CCA67E13B");

    ubyte[] onemilliona = new ubyte[1_000_000];
    onemilliona[] = 'a';
    digest32 = xxh32Of(onemilliona);
    assert(digest32 == cast(ubyte[]) hexString!"E1155920", "Got " ~ toHexString(digest32));
    digest64 = xxh64Of(onemilliona);
    assert(digest64 == cast(ubyte[]) hexString!"DC483AAA9B4FDC40", "Got " ~ toHexString(digest64));
    digest64 = xxh3_64Of(onemilliona);
    assert(digest64 == cast(ubyte[]) hexString!"B1FD6FAE5285C4EB", "Got " ~ toHexString(digest64));
    digest128 = xxh128Of(onemilliona);
    assert(digest128 == cast(ubyte[]) hexString!"A545DF8E384A9579B1FD6FAE5285C4EB",
            "Got " ~ toHexString(digest128));

    auto oneMillionRange = repeat!ubyte(cast(ubyte) 'a', 1_000_000);
    digest32 = xxh32Of(oneMillionRange);
    assert(digest32 == cast(ubyte[]) hexString!"E1155920", "Got " ~ toHexString(digest32));
    digest64 = xxh64Of(oneMillionRange);
    assert(digest64 == cast(ubyte[]) hexString!"DC483AAA9B4FDC40", "Got " ~ toHexString(digest64));
    digest64 = xxh3_64Of(oneMillionRange);
    assert(digest64 == cast(ubyte[]) hexString!"B1FD6FAE5285C4EB", "Got " ~ toHexString(digest64));
    digest128 = xxh128Of(oneMillionRange);
    assert(digest128 == cast(ubyte[]) hexString!"A545DF8E384A9579B1FD6FAE5285C4EB",
            "Got " ~ toHexString(digest128));
}

/**
 * This is a convenience alias for $(REF digest, std,digest) using the
 * XXH implementation.
 */
//simple alias doesn't work here, hope this gets inlined...
auto xxh32Of(T...)(T data)
{
    return digest!(XXH_32, T)(data);
}
/// Ditto
auto xxh64Of(T...)(T data)
{
    return digest!(XXH_64, T)(data);
}
/// Ditto
auto xxh3_64Of(T...)(T data)
{
    return digest!(XXH3_64, T)(data);
}
/// Ditto
auto xxh128Of(T...)(T data)
{
    return digest!(XXH3_128, T)(data);
}

///
@safe unittest
{
    auto hash = xxh32Of("abc");
    assert(hash == digest!XXH_32("abc"));
    auto hash1 = xxh64Of("abc");
    assert(hash1 == digest!XXH_64("abc"));
    auto hash2 = xxh3_64Of("abc");
    assert(hash2 == digest!XXH3_64("abc"));
    auto hash3 = xxh128Of("abc");
    assert(hash3 == digest!XXH3_128("abc"));
}

/**
 * OOP API XXH implementation.
 * See `std.digest` for differences between template and OOP API.
 *
 * This is an alias for $(D $(REF WrapperDigest, std,digest)!XXH_32), see
 * there for more information.
 */
alias XXH32Digest = WrapperDigest!XXH_32;
alias XXH64Digest = WrapperDigest!XXH_64; ///ditto
alias XXH3_64Digest = WrapperDigest!XXH3_64; ///ditto
alias XXH3_128Digest = WrapperDigest!XXH3_128; ///ditto

///
@safe unittest
{
    //Simple example, hashing a string using Digest.digest helper function
    auto xxh = new XXH32Digest();
    ubyte[] hash = xxh.digest("abc");
    //Let's get a hash string
    assert(toHexString(hash) == "32D153FF");
}
///
@safe unittest
{
    //Simple example, hashing a string using Digest.digest helper function
    auto xxh = new XXH64Digest();
    ubyte[] hash = xxh.digest("abc");
    //Let's get a hash string
    assert(toHexString(hash) == "44BC2CF5AD770999");
}
///
@safe unittest
{
    //Simple example, hashing a string using Digest.digest helper function
    auto xxh = new XXH3_64Digest();
    ubyte[] hash = xxh.digest("abc");
    //Let's get a hash string
    assert(toHexString(hash) == "78AF5F94892F3950");
}
///
@safe unittest
{
    //Simple example, hashing a string using Digest.digest helper function
    auto xxh = new XXH3_128Digest();
    ubyte[] hash = xxh.digest("abc");
    //Let's get a hash string
    assert(toHexString(hash) == "06B05AB6733A618578AF5F94892F3950");
}

///
@system unittest
{
    //Let's use the OOP features:
    void test(Digest dig)
    {
        dig.put(cast(ubyte) 0);
    }

    auto xxh = new XXH32Digest();
    test(xxh);

    //Let's use a custom buffer:
    ubyte[16] buf;
    ubyte[] result = xxh.finish(buf[]);
    assert(toHexString(result) == "CF65B03E", "Got " ~ toHexString(result));
}
///
@system unittest
{
    //Let's use the OOP features:
    void test(Digest dig)
    {
        dig.put(cast(ubyte) 0);
    }

    auto xxh = new XXH64Digest();
    test(xxh);

    //Let's use a custom buffer:
    ubyte[16] buf;
    ubyte[] result = xxh.finish(buf[]);
    assert(toHexString(result) == "E934A84ADB052768", "Got " ~ toHexString(result));
}
///
@system unittest
{
    //Let's use the OOP features:
    void test(Digest dig)
    {
        dig.put(cast(ubyte) 0);
    }

    auto xxh = new XXH3_64Digest();
    test(xxh);

    //Let's use a custom buffer:
    ubyte[16] buf;
    ubyte[] result = xxh.finish(buf[]);
    assert(toHexString(result) == "C44BDFF4074EECDB", "Got " ~ toHexString(result));
}
///
@system unittest
{
    //Let's use the OOP features:
    void test(Digest dig)
    {
        dig.put(cast(ubyte) 0);
    }

    auto xxh = new XXH3_128Digest();
    test(xxh);

    //Let's use a custom buffer:
    ubyte[16] buf;
    ubyte[] result = xxh.finish(buf[]);
    assert(toHexString(result) == "A6CD5E9392000F6AC44BDFF4074EECDB", "Got " ~ toHexString(result));
}

@system unittest
{
    import std.conv : hexString;

    auto xxh = new XXH32Digest();
    auto xxh64 = new XXH64Digest();
    auto xxh3_64 = new XXH3_64Digest();
    auto xxh128 = new XXH3_128Digest();

    xxh.put(cast(ubyte[]) "abcdef");
    xxh.reset();
    xxh.put(cast(ubyte[]) "");
    assert(xxh.finish() == cast(ubyte[]) hexString!"02cc5d05");

    xxh.put(cast(ubyte[]) "abcdefghijklmnopqrstuvwxyz");
    ubyte[20] result;
    auto result2 = xxh.finish(result[]);
    assert(result[0 .. 4] == result2
            && result2 == cast(ubyte[]) hexString!"63a14d5f", "Got " ~ toHexString(result));

    debug
    {
        import std.exception;

        assertThrown!Error(xxh.finish(result[0 .. 3]));
    }

    assert(xxh.length == 4);
    assert(xxh64.length == 8);
    assert(xxh3_64.length == 8);
    assert(xxh128.length == 16);

    assert(xxh.digest("") == cast(ubyte[]) hexString!"02cc5d05");
    assert(xxh64.digest("") == cast(ubyte[]) hexString!"EF46DB3751D8E999");
    assert(xxh3_64.digest("") == cast(ubyte[]) hexString!"2D06800538D394C2");
    assert(xxh128.digest("") == cast(ubyte[]) hexString!"99AA06D3014798D86001C324468D497F");

    assert(xxh.digest("a") == cast(ubyte[]) hexString!"550d7456");
    assert(xxh64.digest("a") == cast(ubyte[]) hexString!"D24EC4F1A98C6E5B");
    assert(xxh3_64.digest("a") == cast(ubyte[]) hexString!"E6C632B61E964E1F");
    assert(xxh128.digest("a") == cast(ubyte[]) hexString!"A96FAF705AF16834E6C632B61E964E1F");

    assert(xxh.digest("abc") == cast(ubyte[]) hexString!"32D153FF");
    assert(xxh64.digest("abc") == cast(ubyte[]) hexString!"44BC2CF5AD770999");
    assert(xxh3_64.digest("abc") == cast(ubyte[]) hexString!"78AF5F94892F3950");
    assert(xxh128.digest("abc") == cast(ubyte[]) hexString!"06B05AB6733A618578AF5F94892F3950");

    assert(xxh.digest("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq") == cast(
            ubyte[]) hexString!"89ea60c3");
    assert(xxh64.digest("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq") == cast(
            ubyte[]) hexString!"F06103773E8585DF");
    assert(xxh3_64.digest("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq") == cast(
            ubyte[]) hexString!"5BBCBBABCDCC3D3F");
    assert(xxh128.digest("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq") == cast(
            ubyte[]) hexString!"3D62D22A5169B016C0D894FD4828A1A7");

    assert(xxh.digest("message digest") == cast(ubyte[]) hexString!"7c948494");
    assert(xxh64.digest("message digest") == cast(ubyte[]) hexString!"066ED728FCEEB3BE");
    assert(xxh3_64.digest("message digest") == cast(ubyte[]) hexString!"160D8E9329BE94F9");
    assert(xxh128.digest("message digest") == cast(
            ubyte[]) hexString!"34AB715D95E3B6490ABFABECB8E3A424");

    assert(xxh.digest("abcdefghijklmnopqrstuvwxyz") == cast(ubyte[]) hexString!"63a14d5f");
    assert(xxh64.digest("abcdefghijklmnopqrstuvwxyz") == cast(ubyte[]) hexString!"CFE1F278FA89835C");
    assert(xxh3_64.digest("abcdefghijklmnopqrstuvwxyz") == cast(
            ubyte[]) hexString!"810F9CA067FBB90C");
    assert(xxh128.digest("abcdefghijklmnopqrstuvwxyz") == cast(
            ubyte[]) hexString!"DB7CA44E84843D67EBE162220154E1E6");

    assert(xxh.digest("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789") == cast(
            ubyte[]) hexString!"9c285e64");
    assert(xxh64.digest("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789") == cast(
            ubyte[]) hexString!"AAA46907D3047814");
    assert(xxh3_64.digest("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789") == cast(
            ubyte[]) hexString!"643542BB51639CB2");
    assert(xxh128.digest("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789") == cast(
            ubyte[]) hexString!"5BCB80B619500686A3C0560BD47A4FFB");

    assert(xxh.digest("1234567890123456789012345678901234567890",
            "1234567890123456789012345678901234567890") == cast(ubyte[]) hexString!"9c05f475");
    assert(xxh64.digest("1234567890123456789012345678901234567890",
            "1234567890123456789012345678901234567890") == cast(ubyte[]) hexString!"E04A477F19EE145D");
    assert(xxh3_64.digest("1234567890123456789012345678901234567890",
            "1234567890123456789012345678901234567890") == cast(ubyte[]) hexString!"7F58AA2520C681F9");
    assert(xxh128.digest("1234567890123456789012345678901234567890",
            "1234567890123456789012345678901234567890") == cast(ubyte[]) hexString!"08DD22C3DDC34CE640CB8D6AC672DCB8");
}

// Some left-over buffer in xxh3_digest_long was throwing a RangeViolation
unittest
{
    import std.conv : hexString;

    auto xxh = new XXH32Digest();
    auto xxh64 = new XXH64Digest();
    auto xxh3_64 = new XXH3_64Digest();
    auto xxh3_128 = new XXH3_128Digest();
    
    ubyte[] license = new ubyte[7047]; // Length of LICENSE (example file)
    license[] = 'a';
    
    xxh.put(license);
    xxh64.put(license);
    xxh3_64.put(license);
    xxh3_128.put(license);

    assert(xxh.finish() ==
        cast(ubyte[]) hexString!"40BD93E5");
    assert(xxh64.finish() ==
        cast(ubyte[]) hexString!"4E463476AA3FA339");
    assert(xxh3_64.finish() ==
        cast(ubyte[]) hexString!"6FE65AA1263B5039");
    assert(xxh3_128.finish() ==
        cast(ubyte[]) hexString!"35232F8919961F9B6FE65AA1263B5039");
}
