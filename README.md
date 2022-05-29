# xxhash3

D implementation of the xxhash library 0.81 including xxh32, xxh64, xxh3_64 and xxh3_128 hashes.

# Prerequisites

- A recent D compiler (DMD, LDC2, GDC)
- DUB

# How to use

- Include this package as a dub dependancy
- Use
```
import xxhash3;      /* Import the D module into scope */
```
**Template API:**
```
    ubyte[1024] data;
    XXH_32 xxh;  // OR XXH_64, xxh3_64, xxh3_128
    xxh.start();
    xxh.put(data[]);
    xxh.start(); //Start again
    xxh.put(data[]);
    auto hash = xxh.finish();
```
**OOP API:**
```
    auto xxh = new XXH32Digest();
    ubyte[] hash = xxh.digest("abc");
    assert(toHexString(hash) == "32D153FF", "Got " ~ toHexString(hash));

    //Feeding data
    ubyte[1024] data;
    xxh.put(data[]);
    xxh.reset(); //Start again
    xxh.put(data[]);
    hash = xxh.finish();
```

# Todos

- Optimize code, cleanups, speed imporovements
- Expose more XXH API functions
- Add support for secrets and seeds with XXH3

# Benchmarks

**LDC2 1.29.0 / Release:**
```
Running xxhash3-demo
xxhash3 demo, compiled on May 25 2022
The xxhash3 package implements version 801 of upstream C library
                  XXHTemplate!(uint, XXH32_state_t, false): Testsize    4194304 bytes, took  0.0004663.   8578.1689453 MB/s
   WrapperDigest!(XXHTemplate!(uint, XXH32_state_t, false): Testsize    4194304 bytes, took  0.0004663.   8578.1689453 MB/s
                 XXHTemplate!(ulong, XXH64_state_t, false): Testsize    4194304 bytes, took  0.0002579.  15509.8867188 MB/s
   WrapperDigest!(XXHTemplate!(ulong, XXH64_state_t, false: Testsize    4194304 bytes, took  0.0002579.  15509.8867188 MB/s
                   XXHTemplate!(ulong, XXH3_state_t, true): Testsize    4194304 bytes, took  0.0003032.  13192.6113281 MB/s
   WrapperDigest!(XXHTemplate!(ulong, XXH3_state_t, true)): Testsize    4194304 bytes, took  0.0003032.  13192.6113281 MB/s
           XXHTemplate!(XXH128_hash_t, XXH3_state_t, true): Testsize    4194304 bytes, took  0.0003109.  12865.8730469 MB/s
   WrapperDigest!(XXHTemplate!(XXH128_hash_t, XXH3_state_t: Testsize    4194304 bytes, took  0.0003109.  12865.8730469 MB/s
```
**DMD v2.100.0 / Release:**
```
xxhash3 demo, compiled on May 25 2022
The xxhash3 package implements version 801 of upstream C library
                  XXHTemplate!(uint, XXH32_state_t, false): Testsize    4194304 bytes, took  0.0004656.   8591.0654297 MB/s
   WrapperDigest!(XXHTemplate!(uint, XXH32_state_t, false): Testsize    4194304 bytes, took  0.0004656.   8591.0654297 MB/s
                 XXHTemplate!(ulong, XXH64_state_t, false): Testsize    4194304 bytes, took  0.0003344.  11961.7216797 MB/s
   WrapperDigest!(XXHTemplate!(ulong, XXH64_state_t, false: Testsize    4194304 bytes, took  0.0003344.  11961.7216797 MB/s
                   XXHTemplate!(ulong, XXH3_state_t, true): Testsize    4194304 bytes, took  0.0006295.   6354.2490234 MB/s
   WrapperDigest!(XXHTemplate!(ulong, XXH3_state_t, true)): Testsize    4194304 bytes, took  0.0006295.   6354.2490234 MB/s
           XXHTemplate!(XXH128_hash_t, XXH3_state_t, true): Testsize    4194304 bytes, took  0.0006384.   6265.6645508 MB/s
   WrapperDigest!(XXHTemplate!(XXH128_hash_t, XXH3_state_t: Testsize    4194304 bytes, took  0.0006384.   6265.6645508 MB/s
```
**GDC 11.2.0 / Release:**
```
xxhash3 demo, compiled on May 25 2022
The xxhash3 package implements version 801 of upstream C library
                  XXHTemplate!(uint, XXH32_state_t, false): Testsize    4194304 bytes, took  0.0004583.   8727.9072266 MB/s
   WrapperDigest!(XXHTemplate!(uint, XXH32_state_t, false): Testsize    4194304 bytes, took  0.0004583.   8727.9072266 MB/s
                 XXHTemplate!(ulong, XXH64_state_t, false): Testsize    4194304 bytes, took  0.0002647.  15111.4462891 MB/s
   WrapperDigest!(XXHTemplate!(ulong, XXH64_state_t, false: Testsize    4194304 bytes, took  0.0002647.  15111.4462891 MB/s
                   XXHTemplate!(ulong, XXH3_state_t, true): Testsize    4194304 bytes, took  0.0004871.   8211.8662109 MB/s
   WrapperDigest!(XXHTemplate!(ulong, XXH3_state_t, true)): Testsize    4194304 bytes, took  0.0004871.   8211.8662109 MB/s
           XXHTemplate!(XXH128_hash_t, XXH3_state_t, true): Testsize    4194304 bytes, took  0.0004647.   8607.7041016 MB/s
   WrapperDigest!(XXHTemplate!(XXH128_hash_t, XXH3_state_t: Testsize    4194304 bytes, took  0.0004647.   8607.7041016 MB/s
```
