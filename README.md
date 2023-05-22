# xxhdd

Implementation of the XXHash non-cryptographic hashing algorithm in D.

Includes xxh32, xxh64, xxh3-64, and xxh3-128.

Originally forked from [carsten.schlote/xxhash3](https://gitlab.com/carsten.schlote/xxhash3/).

## Changes from xxhash3

- Fix range violations with XXH3_64Digest and XXH3_128Digest
- Name change to avoid package conflict
- Update README
- Clean demo and make it a subpackage
- Removed XXHException for being unused
- Add own lib version

## TODOs

- Bring all sub functions into the same structure template
- Add seeding support

# Usage

## Template API
```d
XXH_32 xxh32;
xxh32.put("abc");
assert(xxh32.finish() == cast(ubyte[])hexString!"32d153ff");
```

## OOP API
```d
XXH32Digest xxh32 = new XXH32Digest();
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