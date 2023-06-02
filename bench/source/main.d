/* xxhash3 test executable */
module bench;

import std.stdio;
import std.datetime.stopwatch;
import xxhdd;

void main(const string[] args)
{
	writeln("xxhash3 demo, compiled on " ~ __DATE__);
	writefln("xxhash3 v%d upstream C library", xxh_versionNumber);

	/* Run some demo code */
	test_xxhash!(XXH_32, XXH32Digest, XXH32_canonical_t)("xxh-32");
	test_xxhash!(XXH_64, XXH64Digest, XXH64_canonical_t)("xxh-64");
	test_xxhash!(XXH3_64, XXH3_64Digest, XXH64_canonical_t)("xxh3-64");
	test_xxhash!(XXH3_128, XXH3_128Digest, XXH128_canonical_t)("xxh3-128");
}

/// Short for representing one megabyte (MiB).
// Was named `mega`. There was another definition shadowing this one in
// getMegaBytePerSeconds, so it's streamlined here.
enum MiB = 1024 * 1024;

/** Get duration as a float in seconds
 * Param: duration
 * Returns: duration as float, unit seconds
 */
float getFloatSecond(Duration duration) pure
{
	return (cast(float)duration.total!"nsecs") / (10 ^^ 9);
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
float getMegaBytePerSeconds(size_t byteSize, Duration duration) pure
{
	return (cast(float)(byteSize / MiB)) / getFloatSecond(duration);
}

unittest
{
	import std.math.operations : isClose;

	auto mbs = getMegaBytePerSeconds(150 * MiB, dur!"seconds"(1));
	assert(isClose(mbs, 150.0));
	mbs = getMegaBytePerSeconds(10 * MiB, dur!"msecs"(500));
	assert(isClose(mbs, 20.0));
	mbs = getMegaBytePerSeconds(10 * MiB, dur!"usecs"(500));
	assert(isClose(mbs, 20_000.0));
}

/** Test XXH32 code */
void test_xxhash(TT, OOT, HASH)(string name)
{
	immutable static string LINE = "%10s: %9d bytes took %10.7s s at %13.7f MiB/s";
	scope test = new ubyte[4 * MiB];
	StopWatch sw; // .init doesn't autostart

	// Hash the file in chunks
	HASH hash1;
	{
		TT xxh;
		sw.start;
		xxh.start(); //TODO: temp: fixes a bug for xxh3
		for (size_t j; j < test.length; j += test.length / 8)
		{
			xxh.put(test[j .. j + test.length / 8]);
		}
		hash1 = xxh.finish(); // Finalize the hash
		sw.stop;
	}
	auto time1 = sw.peek;
	writefln(LINE,
		name, test.length,
		getFloatSecond(time1),
		getMegaBytePerSeconds(test.length, time1));
}
