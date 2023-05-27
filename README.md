# xxhdd

Implementation of the XXHash non-cryptographic hashing algorithm in D.

Includes xxh32, xxh64, xxh3-64, and xxh3-128.

Originally forked from [carsten.schlote/xxhash3](https://gitlab.com/carsten.schlote/xxhash3/).

## Changes from xxhash3

- Fix range violations with XXH3_64Digest and XXH3_128Digest
- Change package name to xxhdd to avoid package conflict
- Rework README
- Clean demo and make it a subpackage named bench
- Removed XXHException for being unused
- Add own lib version
- Make primes private
- (WIP) Reworked whole structure template as XXHash
  - (WIP) Definition is now pure and free of pointers
  - Removed XXHTemplate, XXH_errorcode, and accessories

## TODOs

- Bring all sub functions into the same structure template
- Add support for seeding in Template and OOP APIs

# Usage

## Template API
```d
XXHash32 xxh32;
xxh32.put("abc");
assert(xxh32.finish() == cast(ubyte[])hexString!"32d153ff");
```

## OOP API
```d
XXHash32Digest xxh32 = new XXHash32Digest();
xxh32.put("abc");
assert(xxh32.finish() == cast(ubyte[])hexString!"32d153ff");
```

# Benchmarks

To run the bench subpackage: `dub :bench`

To choose another compiler, add `--compiler=COMPILER` where `COMPILER` is
either `dmd`, `gdc`, or `ldc2`.

# Unittesting

- Library: `dub test`
- Bench: `dub test :bench`