# xxhdd

D implementation of the xxhash library 0.81 including xxh32, xxh64, xxh3_64 and xxh3_128 hashes.

## Changes from xxhash3

- Fix range violations with XXH3_64Digest and XXH3_128Digest
- Name change to avoid package conflict
- Update README

## TODOs

- Bring all sub functions into the same structure template
- Add seeding support

# Usage

- Include this package as a dub dependancy
- Use
```
import xxhash3;      /* Import the D module into scope */
```
**Template API:**
```d
ubyte[1024] data;
XXH_32 xxh;  // OR XXH_64, xxh3_64, xxh3_128
xxh.start();
xxh.put(data[]);
xxh.start(); //Start again
xxh.put(data[]);
auto hash = xxh.finish();
```
**OOP API:**
```d
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

# Benchmarks

- Operating system: Windows 11 (10.0.22621.1555)
- Processor: AMD Ryzen 9 5950X 16-Core Processor

DMD64-win64 v2.103.1
```
xxhash3 demo, compiled on May 12 2023
The xxhash3 package implements version 801 of upstream C library
    xxh-32:   4194304 bytes took  0.0006402 s at  6248.0478516 MB/s
    xxh-64:   4194304 bytes took  0.0004573 s at  8746.9931641 MB/s
   xxh3-64:   4194304 bytes took  0.0008786 s at  4552.6972656 MB/s
  xxh3-128:   4194304 bytes took  0.0008729 s at  4582.4262695 MB/s
```

LDC2-win64 v1.32.2
```
xxhash3 demo, compiled on May 12 2023
The xxhash3 package implements version 801 of upstream C library
    xxh-32:   4194304 bytes took  0.0006365 s at  6284.3676758 MB/s
    xxh-64:   4194304 bytes took  0.0003382 s at 11827.3203125 MB/s
   xxh3-64:   4194304 bytes took  0.0004166 s at  9601.5361328 MB/s
  xxh3-128:   4194304 bytes took  0.0004103 s at  9748.9638672 MB/s
```
