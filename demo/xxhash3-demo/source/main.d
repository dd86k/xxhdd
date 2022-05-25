/* xxhash3 test executable */
import core.stdc.string;

import std.stdio;
import std.datetime.stopwatch;

/* Import the binding modules into scope */
import xxhash3;

/** Minimalistic demo code for lmdb
 * Param: args = Commandline args as a dynamic array of strings
 */
void main(const string[] args)
{
	writefln("xxhash3 demo, compiled on %s", __DATE__);

	/* Extract the lmdb version */
	auto xxhashVersion = xxh_versionNumber();
	writefln("The xxhash3 package implements version %d of upstream C library", xxhashVersion);

	/* Run some demo code */
	test_xxhash!(XXH_32, XXH32Digest, XXH32_canonical_t)();
	test_xxhash!(XXH_64, XXH64Digest, XXH64_canonical_t)();
	test_xxhash!(XXH3_64, XXH3_64Digest, XXH64_canonical_t)();
	test_xxhash!(XXH3_128, XXH3_128Digest, XXH128_canonical_t)();
}

/** Shorthand for 2^^20 bytes */
enum mega = 1024 * 1024;

/** Get duration as a float in seconds
 * Param: duration
 * Returns: duration as float, unit seconds
 */
float getFloatSecond(Duration duration)
{
	const auto ns_duration = duration.total!"nsecs";
	const float second_duration = float(ns_duration) / 10 ^^ 9;
	return second_duration;
}

unittest
{
	import std.math.operations;

	auto s = getFloatSecond(dur!"seconds"(1));
	assert(isClose(s, 1.0));
	s = getFloatSecond(dur!"msecs"(500));
	assert(isClose(s, 0.5));
	s = getFloatSecond(dur!"usecs"(500));
	assert(isClose(s, 0.0005));
}

/** Calculate MB/s from bytesize and a Duration value
 * Param: byteSize - size_t Size of Data processed
 * Param: duration - Duration of processing
 * Returns:
 *   float Megabyte per second
 */
float getMegaBytePerSeconds(size_t byteSize, Duration duration)
{
	enum mega = 2 ^^ 20;
	const float second_duration = getFloatSecond(duration);
	const float megaBytesPerSec = (byteSize != 0) ?
		(float(byteSize) / mega) / float(second_duration) : float.nan;
	return megaBytesPerSec;
}

unittest
{
	import std.math.operations;

	auto mbs = getMegaBytePerSeconds(150 * 2 ^^ 20, dur!"seconds"(1));
	assert(isClose(mbs, 150.0));
	mbs = getMegaBytePerSeconds(10 * 2 ^^ 20, dur!"msecs"(500));
	assert(isClose(mbs, 20.0));
	mbs = getMegaBytePerSeconds(10 * 2 ^^ 20, dur!"usecs"(500));
	assert(isClose(mbs, 20_000.0));
}

/** Test XXH32 code */
void test_xxhash(TT, OOT, HASH)()
{
	auto test = new ubyte[4 * 1024 * 1024];
	auto sw = StopWatch(AutoStart.no);

	// Hash the file in chunks
	HASH hash1;
	{
		TT xxh;
		sw.reset;
		sw.start;
		xxh.start();
		for (int j = 0; j < test.length; j += test.length / 8)
		{
			xxh.put(test[j .. j + test.length / 8]);
		}
		hash1 = xxh.finish(); // Finalize the hash
		sw.stop;
	}
	auto time1 = sw.peek;
	writefln("%58.55s: Testsize %10d bytes, took %10.6s. %14.7f MB/s",
		TT.stringof, test.length,
		getFloatSecond(time1),
		getMegaBytePerSeconds(test.length, time1));

	HASH hash3;
	{
		auto xxh = new OOT();
		sw.reset;
		sw.start;
		hash3 = xxh.digest(test); //&test[0], test.length, 0xbaad5eed);
		sw.stop;
	}
	auto time2 = sw.peek;
	writefln("%58.55s: Testsize %10d bytes, took %10.6s. %14.7f MB/s",
		OOT.stringof, test.length,
		getFloatSecond(time1),
		getMegaBytePerSeconds(test.length, time1));
}
