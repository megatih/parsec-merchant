// SPDX-License-Identifier: GPL-2.0-or-later

/// Exact port of the .NET Framework `System.Random` algorithm for a supplied seed
/// (Knuth's subtractive generator; reference source `mscorlib/system/random.cs`).
/// Modern .NET keeps this algorithm for seeded constructors (`Net5CompatSeedImpl`), so a C# harness can confirm vectors.
public struct DotNetRandom: Codable, Sendable, Equatable, RandomSource {
    private static let mbig: Int32 = Int32.max
    private static let mseed: Int32 = 161_803_398

    private var seedArray: [Int32]
    private var inext: Int
    private var inextp: Int

    public init(seed: Int32) {
        var seeds = [Int32](repeating: 0, count: 56)
        let subtraction: Int32 = (seed == Int32.min) ? Int32.max : abs(seed)
        var mj: Int32 = Self.mseed &- subtraction
        seeds[55] = mj
        var mk: Int32 = 1
        for i in 1..<55 {
            let ii = (21 * i) % 55
            seeds[ii] = mk
            mk = mj &- mk
            if mk < 0 { mk &+= Self.mbig }
            mj = seeds[ii]
        }
        for _ in 1..<5 {
            for i in 1..<56 {
                seeds[i] &-= seeds[1 + (i + 30) % 55]
                if seeds[i] < 0 { seeds[i] &+= Self.mbig }
            }
        }
        seedArray = seeds
        inext = 0
        inextp = 21
    }

    /// `InternalSample()`: next value in `0..<Int32.max`.
    public mutating func internalSample() -> Int32 {
        var locINext = inext + 1
        var locINextp = inextp + 1
        if locINext >= 56 { locINext = 1 }
        if locINextp >= 56 { locINextp = 1 }
        var retVal = seedArray[locINext] &- seedArray[locINextp]
        if retVal == Self.mbig { retVal -= 1 }
        if retVal < 0 { retVal &+= Self.mbig }
        seedArray[locINext] = retVal
        inext = locINext
        inextp = locINextp
        return retVal
    }

    /// `Sample()`: a double in `[0, 1)`.
    public mutating func sample() -> Double {
        Double(internalSample()) * (1.0 / Double(Self.mbig))
    }

    /// `Next()`: non-negative Int32.
    public mutating func nextInt() -> Int {
        Int(internalSample())
    }

    private mutating func sampleForLargeRange() -> Double {
        var result = Int(internalSample())
        let negative = Int(internalSample()) % 2 == 0
        if negative { result = -result }
        var d = Double(result)
        d += Double(Int32.max - 1)
        d /= 2.0 * Double(UInt32(Int32.max)) - 1.0
        return d
    }

    /// `Next(maxValue)`: `(int)(Sample() * maxValue)`. Returns 0 for `max <= 0` (the original never passes negatives).
    public mutating func next(below max: Int) -> Int {
        next(in: 0, max)
    }

    /// `Next(minValue, maxValue)`.
    public mutating func next(in min: Int, _ max: Int) -> Int {
        precondition(max >= min, "next(in:) requires max >= min (RNG-003)")
        if max <= min {
            // .NET: Next(x, x) returns x after consuming one sample; min > max throws (never happens in the game).
            _ = internalSample()
            return min
        }
        let range = Int64(max) - Int64(min)
        if range <= Int64(Int32.max) {
            return Int(sample() * Double(range)) + min
        }
        return Int(Int64(sampleForLargeRange() * Double(range)) + Int64(min))
    }
}
