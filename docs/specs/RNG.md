# RNG: Random number generation

> Format (PRD §7): `- **ID** {Mn} [M][W][P] statement (source)`. Ruleset tags: [M] Modern, [W] Windows 2.01, [P] Original Palm 1.2.2.
> - A bullet with several ruleset tags carries the milestone of its earliest ruleset. Palm and Modern must satisfy it by M5.
> - Sources:
>   - C#: `/Users/megatih/Downloads/SpaceTraderSource201` (cited as `File.cs:line`).
>   - Palm: `docs/reference/palm-src/Src` (cited as `Src/File.c:Function`).
>   - .NET: the reference source <https://referencesource.microsoft.com/#mscorlib/system/random.cs> and, for modern .NET, `src/libraries/System.Private.CoreLib/src/System/Random.Net5CompatImpl.cs` in <https://github.com/dotnet/runtime>.
> - `[verify]` marks a value that can't be confirmed from the available sources. Each one must be closed, or logged as an accepted assumption, by the end of M5 (PRD §9).
> - The values in Appendix A were computed with an independent transliteration of the algorithms below. Seeds 0 and 1 reproduce the widely published .NET values (`new Random(0).Next() == 1559595546`, `new Random(1).Next() == 534011718`). The M1 harness is still the authority for DotNetRandom.

## 1. Generators and where each one is used

| Generator | Purpose | Rulesets | Persisted |
|---|---|---|---|
| `DotNetRandom` | All game logic | [W] | yes |
| `PalmLCG` | All game logic (a stand-in for the ROM `SysRandom`) | [P] | yes |
| `Xoshiro256StarStar` | All game logic | [M] | yes |
| `PieterRand.csharp` | Newspaper only (`GetRandom2`) | [M][W] | no (reseeded before every use) |
| `PieterRand.palm` | Newspaper only (`GetRandom2`) | [P] | no (reseeded before every use) |

- **RNG-001** {M1} [M][W][P] Every random decision in `ParsecEngine` draws from the game's `RNGState`, or from `PieterRand` where §5 allows it. The engine never uses `SystemRandomNumberGenerator`, `Int.random`/`Double.random` without an explicit generator, `Date`, `UUID`, `hashValue`, or any other non-deterministic source. A source scan test fails on any of these symbols under `Sources/ParsecEngine`. (source: PRD §4.2, §6.2)
- **RNG-002** {M1} [M][W][P] Each ruleset declares its `rngKind`: Windows 2.01 → `.dotNet`, Palm 1.2.2 → `.palmLCG`, Modern → `.xoshiro`. Its newspaper generator is `PieterRand.csharp` for Windows 2.01 and Modern, and `PieterRand.palm` for Palm. `Ruleset.makeRNG(seed:)` returns the matching `RNGState` case. (source: PRD §4.1, §4.2)

## 2. The `RandomSource` protocol

```swift
public protocol RandomSource: Sendable {
    /// ≡ C# Functions.GetRandom(max) ≡ .NET Random.Next(0, max)
    mutating func next(below n: Int) -> Int
    /// ≡ C# Functions.GetRandom(min, max) ≡ .NET Random.Next(min, max); upper bound exclusive
    mutating func next(in range: Range<Int>) -> Int
}
```

- **RNG-003** {M1} [M][W][P] `next(below: n)` requires `n >= 0` (a negative `n` is a programmer error: a `precondition`, matching .NET's `ArgumentOutOfRangeException`). For `n > 0` it returns a value in `0..<n`. (source: Functions.cs:148-156; .NET random.cs `Next(int,int)`)
- **RNG-004** {M1} [M][W][P] `next(below: 0)` returns `0` and **consumes exactly one draw** of the underlying generator. This matches .NET `Next(0,0)`, which calls `Sample()` and returns `(int)(Sample()*0)+0 == 0`. The other generators copy this so call counts stay aligned. (source: .NET random.cs `Next(int minValue, int maxValue)`)
- **RNG-005** {M1} [M][W][P] `next(in: a..<b)` returns a value in `a..<b`, so the upper bound is exclusive, exactly like C# `GetRandom(min, max)`. An empty range (`a == b`) returns `a` and consumes exactly one draw. Negative bounds are allowed: `next(in: -12..<13)` yields −12…12. (source: Functions.cs:153-156; Game.cs:2209-2210)
- **RNG-006** {M1} [W] For `DotNetRandom`, `next(below: n)` is `Next(0, n)` and `next(in: a..<b)` is `Next(a, b)`, both exactly as in §3.4. C# `GetRandom(max)` calls `rand.Next(0, max)`, not `rand.Next(max)`. For `max ≥ 0` the two give identical results and consume the same draw. (source: Functions.cs:148-156)
- **RNG-007** {M1} [M][P] For `PalmLCG` and `Xoshiro256StarStar`, `next(in: a..<b)` is defined as `a + next(below: b - a)`. (Palm has no two-argument `GetRandom`; Modern defines its own.) (source: Src/spacetrader.h:444 `#define GetRandom(a)`)
- **RNG-008** {M1} [M][W][P] Every call site evaluates its RNG draws in source order. Arguments and operands are evaluated left to right, as C# guarantees. For Palm C code, where the order of evaluation is unspecified (for example `1 + GetRandom(5) + GetRandom(6)`, or `Qty - GetRandom(10) + GetRandom(10)`), the port also evaluates left to right. That choice is documented here because Palm is not sequence-faithful anyway (§6). (source: Src/Skill.c:RandomSkill; Src/Traveler.c:InitializeTradeitems)

## 3. `DotNetRandom` (Windows 2.01)

An exact port of the seeded legacy `System.Random`: Knuth's subtractive generator from *Numerical Recipes* `ran3`. The C# project targets the .NET 2.0+ toolchain (`Fryz.Apps.SpaceTrader.csproj`: ToolsVersion 3.5, VS 2008), so the reference source below is the matching implementation. Modern .NET (Core 3.0, 5, 6 and later) keeps the same algorithm for **every seeded constructor**: `new Random(seed)` creates `Net5CompatSeedImpl`, which wraps `CompatPrng`, so the M1 harness on a current .NET SDK reproduces it. Only the unseeded `new Random()` switched to xoshiro in .NET 6.

### 3.1 Constants and state
```
MBIG  = 2147483647   // Int32.MaxValue
MSEED = 161803398
MZ    = 0
SeedArray: [Int32] of length 56 (index 0 unused)
inext, inextp: Int32
```

### 3.2 Constructor `Random(Seed: Int32)` (verbatim logic, Int32 arithmetic that wraps on overflow)
```
subtraction = (Seed == Int32.MinValue) ? Int32.MaxValue : abs(Seed)
mj = MSEED - subtraction            // may be negative when |Seed| > MSEED
SeedArray[55] = mj
mk = 1
for i in 1...54:
    ii = (21 * i) % 55
    SeedArray[ii] = mk
    mk = mj - mk
    if mk < 0: mk += MBIG
    mj = SeedArray[ii]
for k in 1...4:
    for i in 1...55:
        SeedArray[i] = SeedArray[i] &- SeedArray[1 + (i + 30) % 55]   // C# unchecked: WRAPS
        if SeedArray[i] < 0: SeedArray[i] += MBIG
inext  = 0
inextp = 21
```

### 3.3 Core sampling
```
InternalSample() -> Int32:
    locINext  = inext  + 1; if locINext  >= 56: locINext  = 1
    locINextp = inextp + 1; if locINextp >= 56: locINextp = 1
    retVal = SeedArray[locINext] - SeedArray[locINextp]
    if retVal == MBIG: retVal -= 1
    if retVal < 0:     retVal += MBIG
    SeedArray[locINext] = retVal
    inext = locINext; inextp = locINextp
    return retVal

Sample() -> Double:
    return Double(InternalSample()) * (1.0 / Double(MBIG))   // multiply by reciprocal, not divide

GetSampleForLargeRange() -> Double:
    result = InternalSample()
    negative = (InternalSample() % 2 == 0)
    if negative: result = -result
    d = Double(result)
    d += Double(Int32.MaxValue - 1)
    d /= Double(2 * UInt32(Int32.MaxValue) - 1)
    return d
```

### 3.4 Public API
```
Next() -> Int32:            return InternalSample()
Next(maxValue) -> Int32:    precondition(maxValue >= 0); return Int32(Sample() * Double(maxValue))   // truncation
Next(minValue, maxValue):   precondition(minValue <= maxValue)
    range = Int64(maxValue) - Int64(minValue)
    if range <= Int64(Int32.MaxValue):
        return Int32(Sample() * Double(range)) + minValue
    else:
        return Int32(Int64(GetSampleForLargeRange() * Double(range)) + Int64(minValue))
NextDouble() -> Double:     return Sample()
```

- **RNG-009** {M1} [W] The `DotNetRandom(seed: Int32)` constructor implements §3.2 exactly. That includes the `Int32.MinValue → Int32.MaxValue` substitution, `abs` for negative seeds (so seeds `-s` and `s` give identical sequences), and **wrapping** Int32 subtraction (`&-`) in the four mixing passes. Wrapping happens when `|Seed| > 161803398` makes `SeedArray[55]` negative. (source: .NET random.cs `Random(int Seed)`)
- **RNG-010** {M1} [W] `InternalSample()` implements §3.3 exactly. Both indices advance before use and wrap from 56 back to 1, `retVal == MBIG` is decremented, and negative results get `MBIG` added. After construction `inext == 0` and `inextp == 21`. (source: .NET random.cs `InternalSample`)
- **RNG-011** {M1} [W] `Sample()` returns `Double(InternalSample()) * (1.0 / 2147483647.0)`, computed in IEEE-754 binary64 by multiplying with the precomputed reciprocal. (source: .NET random.cs `Sample`)
- **RNG-012** {M1} [W] `Next(min, max)` with `max - min <= Int32.MaxValue` returns `Int32(Sample() * Double(max - min)) + min`, truncating toward zero, and consumes exactly one `InternalSample`. `Next(max)` returns `Int32(Sample() * Double(max))`. (source: .NET random.cs `Next(int)`, `Next(int,int)`)
- **RNG-013** {M1} [W] When `max - min > Int32.MaxValue`, `Next(min, max)` uses `GetSampleForLargeRange()`, which consumes **two** `InternalSample`s (value, then sign parity), as in §3.3–§3.4. This path is unreachable from game code, since every game range is ≤ 128 wide. It is implemented anyway for completeness and tested with `Next(Int32.MinValue, Int32.MaxValue)`. (.NET Framework 1.x used a different single-sample overflow branch here. The difference is immaterial because the C# build targets .NET 2.0+ and the path is never reached.) (source: .NET random.cs `GetSampleForLargeRange`)
- **RNG-014** {M1} [W] For every `range` in 1…1024, `Int32(Sample() * Double(range))` equals the integer expression `(Int64(k) * Int64(range)) / 2147483647`, where `k` is the `InternalSample` consumed. A property test covers 10⁶ random `k` plus every `k` adjacent to an integer boundary. Because MBIG is prime, `k*range/MBIG` is never within ~4.7×10⁻¹⁰ of an integer. Results therefore can't depend on x87 extended precision in the original .NET 2.0 x86 JIT, or on reciprocal-versus-division rounding. (source: .NET random.cs `Sample`; analysis)
- **RNG-015** {M1} [W] The Windows 2.01 game seed is bound as `DotNetRandom(seed: Int32(truncatingIfNeeded: gameSeed))`: the low 32 bits of the UInt64 game seed, read as a signed Int32. The C# harness seeds `Functions.rand = new Random(thatInt32)` immediately before `new Game(...)`, so the first draw is the size roll of system 0 (GAL). (source: Functions.cs:41; PRD §8.4)

## 4. Derived helper

- **RNG-016** {M1} [M][W][P] `randomSkill()` returns `1 + next(below: 5) + next(below: 6)`, drawing the `below: 5` value first. The result is 1…10 (non-uniform, triangular-trapezoid) and uses exactly two draws. (source: Functions.cs:263-266; Palm: Src/Skill.c:RandomSkill)

## 5. `PieterRand` (newspaper `GetRandom2`)

Pieter Spronck's two-seed multiply-with-carry generator, "tweaked a bit by SjG". Both sources use it **only** for the newspaper, so a given system and day always produces the same paper.

### 5.1 C# variant (Windows 2.01, Modern), verbatim
```csharp
private const long DEFSEEDX = 521288629;      // Functions.cs:43
private const long DEFSEEDY = 362436069;      // Functions.cs:44
private const int  MAX_WORD = 65535;          // Functions.cs:45
private static long SeedX = DEFSEEDX;
private static long SeedY = DEFSEEDY;

public static int GetRandom2(int max) { return (int)(Rand() % max); }   // Functions.cs:161-164

private static long Rand()                                              // Functions.cs:252-261
{
    const int a = 18000;
    const int b = 30903;
    SeedX = a*(SeedX&MAX_WORD) + (SeedX>>16);
    SeedY = b*(SeedY&MAX_WORD) + (SeedY>>16);
    return ((SeedX<<16) + (SeedY&MAX_WORD));
}

public static void RandSeed(int seed1, int seed2)                       // Functions.cs:268-279
{
    if (seed1 > 0) SeedX = seed1; else SeedX = DEFSEEDX;
    if (seed2 > 0) SeedY = seed2; else SeedY = DEFSEEDY;
}
```

- **RNG-017** {M1} [M][W] `PieterRand.csharp` keeps `seedX` and `seedY` as `Int64` and implements `Rand()` exactly as in §5.1. The output `(seedX << 16) + (seedY & 0xFFFF)` is an `Int64`. (source: Functions.cs:252-261)
- **RNG-018** {M1} [M][W] `PieterRand.csharp` never overflows Int64 and never returns a negative value. After the first step `seedX <= 18000·65535 + 32767 < 2³¹` and `seedY <= 30903·65535 + 32767 < 2³¹`, so the output is below 2⁴⁸. A test runs 10⁵ steps from the seed pairs {0, 1, 65535, 2147483647} × {0, 1, 5000, 2147483647} and checks every output is ≥ 0. This overrides the research-01 §2 claim that it "can go negative". (source: Functions.cs:252-261; research 01 errata #3)
- **RNG-019** {M1} [M][W] `randSeed(seed1, seed2)` sets `seedX = seed1` if `seed1 > 0`, otherwise 521288629, and `seedY = seed2` if `seed2 > 0`, otherwise 362436069. **Negative** seeds therefore also select the defaults. (source: Functions.cs:268-279)
- **RNG-020** {M1} [M][W] `getRandom2(max)` returns `Int(rand() % Int64(max))` for `max > 0`. (source: Functions.cs:161-164)

### 5.2 Palm variant (Palm 1.2.2), verbatim
```c
#define DEFSEEDX 521288629                        // Src/Math.c:79
#define DEFSEEDY 362436069                        // Src/Math.c:80
static UInt16 SeedX = DEFSEEDX;                   // Src/Math.c:82 (truncated to 15285)
static UInt16 SeedY = DEFSEEDY;                   // Src/Math.c:83 (truncated to 21989)

int GetRandom2(int maxVal) { return (int)(Rand() % maxVal); }      // Src/Math.c:85-88

UInt16 Rand()                                                      // Src/Math.c:90-99
{
   static UInt16 a = 18000;
   static UInt16 b = 30903;
   SeedX = a*(SeedX&MAX_WORD) + (SeedX>>16);
   SeedY = b*(SeedY&MAX_WORD) + (SeedY>>16);
   return ((SeedX<<16) + (SeedY&MAX_WORD));
}

void RandSeed( UInt16 seed1, UInt16 seed2 )                       // Src/Math.c:101-112
{
   if (seed1) SeedX = seed1; else SeedX = DEFSEEDX;
   if (seed2) SeedY = seed2; else SeedY = DEFSEEDY;
}
```
(`MAX_WORD` is 65535, from Src/spacetrader.h:437.) Because the seeds are `UInt16`, `SeedX>>16` and `SeedY>>16` are 0, every assignment truncates modulo 2¹⁶, and the `UInt16` return value drops the `SeedX<<16` term. So the **effective** generator is `SeedY = (30903 * SeedY) & 0xFFFF; return SeedY`. `SeedX` is updated but never affects the output.

- **RNG-021** {M1} [P] `PieterRand.palm` keeps `seedY: UInt16` and implements `rand()` as `seedY = UInt16(truncatingIfNeeded: 30903 * UInt32(seedY)); return seedY`. Its outputs are bit-identical to Src/Math.c `Rand()`. Keeping `seedX` is optional, because it never influences the output. (source: Src/Math.c:90-99)
- **RNG-022** {M1} [P] The default seeds are the truncated constants `seedX = 521288629 & 0xFFFF = 15285` and `seedY = 362436069 & 0xFFFF = 21989`. (source: Src/Math.c:79-83)
- **RNG-023** {M1} [P] `randSeed(seed1, seed2)` first truncates each argument to UInt16 (`seed & 0xFFFF`) and **then** applies the zero test: a truncated value of 0 selects the default. For example, `randSeed(5, 65536)` sets `seedY = 21989`. (source: Src/Math.c:101-112; research 04 errata #7)
- **RNG-024** {M1} [P] `getRandom2(max)` returns `Int(rand()) % max` for `max > 0`. (source: Src/Math.c:85-88)
- **RNG-025** {M3} [M][W][P] The newspaper reseeds `PieterRand` with `randSeed(systemId, days)` at the start of every newspaper composition: C# uses the current system and `Commander.Days`, Palm uses `WarpSystem` and `Days`. `PieterRand` is never used outside the newspaper. Its draws never advance the game `RNGState`, and game draws never advance it. Because it is always reseeded before use, its state is **not** persisted. (source: Game.cs:3919-3921; Palm: Src/SystemInfoEvent.c:465)

## 6. `PalmLCG` (Palm 1.2.2 game-logic stand-in)

Palm game logic calls `#define GetRandom(a) (SysRandom(0)%(a))` (Src/spacetrader.h:444). That is the ROM's `SysRandom`, and the game never seeds it, so the original sequence can't be reproduced. The Palm ruleset is therefore **rule-faithful, not sequence-faithful** (PRD §4.2). The stand-in uses the LCG commonly documented for PalmOS `SysRandom`: `seed = 0x015A4E35 * seed + 1; return (Int16)((seed >> 16) & 0x7FFF)`. Its constants are **unverified** against a ROM disassembly. The choice is recorded here and in RUL.md.

- **RNG-026** {M1} [P] `PalmLCG` keeps `state: UInt32`. One step is `state = 0x015A4E35 &* state &+ 1` (wrapping modulo 2³²) and then outputs `Int((state >> 16) & 0x7FFF)`, a value in 0…32767. Whether these constants match the PalmOS ROM is `[verify]` (accepted assumption: rule-faithful, not sequence-faithful). (source: Src/spacetrader.h:444; PalmOS SDK `SysRandom` documentation)
- **RNG-027** {M1} [P] `PalmLCG.next(below: n)` for `n > 0` returns `output % n`, keeping the modulo bias of `SysRandom(0) % a`. For `n == 0` it returns 0 and consumes one step (RNG-004). Palm C would divide by zero there, and no game path reaches it. (source: Src/spacetrader.h:444)
- **RNG-028** {M1} [P] The Palm game seed is bound as `PalmLCG(state: UInt32(truncatingIfNeeded: gameSeed))`, with no further mixing. Seed 0 is legal, and its first output is 0. (source: this spec, accepted assumption)

## 7. `Xoshiro256StarStar` (Modern)

Reference algorithm: Blackman and Vigna, <https://prng.di.unimi.it/xoshiro256starstar.c>, seeded with SplitMix64 from <https://prng.di.unimi.it/splitmix64.c>.

```
rotl(x, k) = (x << k) | (x >> (64 - k))          // UInt64

next() -> UInt64:
    result = rotl(s[1] &* 5, 7) &* 9
    t = s[1] << 17
    s[2] ^= s[0]
    s[3] ^= s[1]
    s[1] ^= s[2]
    s[0] ^= s[3]
    s[2] ^= t
    s[3] = rotl(s[3], 45)
    return result

splitmix64(state) -> (newState, out):
    state = state &+ 0x9E3779B97F4A7C15
    z = state
    z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
    z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
    return (state, z ^ (z >> 31))

seed(gameSeed: UInt64): sm = gameSeed; for i in 0..<4 { (sm, s[i]) = splitmix64(sm) }

next(below n: Int) -> Int:          // Lemire multiply-shift with rejection (exact, unbiased)
    if n == 0 { _ = next(); return 0 }
    N = UInt64(n)
    (hi, lo) = next().multipliedFullWidth(by: N)
    if lo < N:
        t = (0 &- N) % N
        while lo < t: (hi, lo) = next().multipliedFullWidth(by: N)
    return Int(hi)
```

- **RNG-029** {M1} [M] `Xoshiro256StarStar.next()` implements the reference xoshiro256** step above bit for bit, with wrapping UInt64 arithmetic. (source: prng.di.unimi.it/xoshiro256starstar.c)
- **RNG-030** {M1} [M] The state is seeded as `s[0…3]`, the first four outputs of SplitMix64 started at `gameSeed`. For seed 0 that gives `s = E220A8397B1DCDAF, 6E789E6AA1B965F4, 06C45D188009454F, F88BB8A8724C81EC`. SplitMix64's output function is a bijection and its successive states differ, so an all-zero state is impossible. (source: prng.di.unimi.it/splitmix64.c)
- **RNG-031** {M1} [M] `next(below:)` uses the Lemire multiply-shift with rejection exactly as written above, implemented inside ParsecEngine. It must **not** delegate to the Swift standard library's `next(upperBound:)` or `Int.random(in:using:)`, whose algorithm may change between Swift versions. Each accepted or rejected candidate consumes one `next()`. (source: this spec)

## 8. Serialization, state and determinism

- **RNG-032** {M1} [M][W][P] `RNGState` is a `Codable, Sendable, Equatable` enum with one case per kind, stored in `GameState` and in the save: `.dotNet(seedArray: [Int32] /*56 elements, index 0 included*/, inext: Int32, inextp: Int32)`; `.palmLCG(state: UInt32)`; `.xoshiro(s: [String] /*4 × 16 upper-case hex digits*/)`. UInt64 words are encoded as hex strings so JSON round-trips stay exact and independent of platform number handling. (source: PRD §6.2; research 06 §RNG)
- **RNG-033** {M1} [M][W][P] Round-trip: for every generator, take 0, 1, 57 and 1000 draws, encode the state to JSON, decode it, and draw 100 more. The output matches 100 draws from an uninterrupted generator, and the decoded state is `==` the original. (source: PRD §6.2, §8.2)
- **RNG-034** {M1} [M][W][P] The canonical state hash (SHA-256 of sorted-key JSON) includes `RNGState`. Two games with the same ruleset, seed and command sequence produce identical RNG states and hashes after every command. (source: PRD §6.2 Determinism)
- **RNG-035** {M6} [M][W][P] Loading a save whose `RNGState` case doesn't match the ruleset's `rngKind` is rejected with a typed persistence error. The engine never silently reseeds. (source: PRD §6.4; SAV.md)
- **RNG-036** {M1} [M][W][P] The following never consume a game RNG draw: `preview` queries, a risky command returned as `.confirm` without acknowledgement, a rejected command (`rejection != nil`), and app-side randomness (flavor text, audio, art, tips, Foundation Models). An app-side need for randomness uses its own generator. Tests: the RNG state is unchanged after each of these. (source: PRD §6.2)
- **RNG-037** {M1} [M][W][P] Code that consumes RNG draws never iterates a `Set` or `Dictionary`, whose order is randomized per process in Swift. It iterates arrays or index ranges in source order (for example system index 0…N−1). (source: PRD §6.2 Determinism)
- **RNG-038** {M1} [M][W][P] Within each ruleset the number and order of RNG draws mirror the source for the operation being ported: galaxy construction (GAL), price variance (ECO), opponent generation (ENC), and so on. Each area spec states its draw order, and harness fixtures check it for Windows 2.01. (source: PRD §4.2 "Call order"; research 01 errata #4)

## 9. Test vectors

- **RNG-039** {M1} [M][W][P] Unit tests assert the **first 20 outputs** for seeds 0, 1, 42 and 12345 of every generator. The expected values are those listed in Appendix A: `DotNetRandom`: `Next()`, `next(below: 100)` and `next(in: -12..<13)`; `PieterRand.csharp` and `PieterRand.palm`: raw `rand()` after `randSeed(s, s)`; `PalmLCG`: raw output and `next(below: 100)`; `Xoshiro256StarStar`: the initial state, raw `next()` and `next(below: 100)`. Each vector starts from a freshly seeded generator. (source: PRD §8.2 "RNG vectors")
- **RNG-040** {M1} [W] The M1 harness emits `Fixtures/harness/rng-dotnet.json`, which is .NET's own `new Random(seed)` output for seeds 0, 1, 42, 12345, 2147483647, −2147483648 and −42 (`Next()` ×20, `Next(0,100)` ×20, `Next(-12,13)` ×20). The Swift test compares `DotNetRandom` against it. If a fixture disagrees with Appendix A, the harness wins: fix this spec first, then the code (PRD §7.6). If the harness can't be built, Appendix A stands as the hand-worked fallback (PRD §8.4). (source: PRD §4.2, §8.4)
- **RNG-041** {M1} [W] Edge seeds: `DotNetRandom` with seeds 2147483647 and −2147483648 produces identical sequences, as Appendix A lists. Those sequences differ from seed 0 at outputs 3, 6, 10, 13, 17 and 20, which proves the wrapping subtraction in RNG-009. Seed −42 matches seed 42. (source: .NET random.cs `Random(int)`)

## Appendix A: reference vectors (first 20 outputs from a fresh generator)

```
dotnet.next() seed=0: 1559595546, 1755192844, 1649316166, 1198642031, 442452829, 1200195957, 1945678308, 949569752, 2099272109, 587775847, 626863973, 1003550677, 1358625013, 1008269081, 2109153755, 65212616, 1851925803, 2137491580, 1454235444, 675580731
dotnet.next() seed=1: 534011718, 237820880, 1002897798, 1657007234, 1412011072, 929393559, 760389092, 2026928803, 217468053, 1379662799, 61497087, 532638534, 687431273, 2125508764, 1464848243, 1406361028, 607156385, 1321446349, 1512368656, 1507096884
dotnet.next() seed=42: 1434747710, 302596119, 269548474, 1122627734, 361709742, 563913476, 1555655117, 1101493307, 372913049, 1634773126, 503774878, 552593494, 1085775344, 687695533, 818126015, 558871098, 1111217775, 75846583, 1748346701, 1239520805
dotnet.next() seed=12345: 143337951, 150666398, 1663795458, 1097663221, 1712597933, 1776631026, 356393799, 1580828476, 558810388, 1086637143, 494509053, 831377771, 463814839, 44691035, 289552956, 1590924033, 418954878, 1904902962, 1849199486, 770656856
dotnet.next(below:100) seed=0: 72, 81, 76, 55, 20, 55, 90, 44, 97, 27, 29, 46, 63, 46, 98, 3, 86, 99, 67, 31
dotnet.next(below:100) seed=1: 24, 11, 46, 77, 65, 43, 35, 94, 10, 64, 2, 24, 32, 98, 68, 65, 28, 61, 70, 70
dotnet.next(below:100) seed=42: 66, 14, 12, 52, 16, 26, 72, 51, 17, 76, 23, 25, 50, 32, 38, 26, 51, 3, 81, 57
dotnet.next(below:100) seed=12345: 6, 7, 77, 51, 79, 82, 16, 73, 26, 50, 23, 38, 21, 2, 13, 74, 19, 88, 86, 35
dotnet.next(in:-12..<13) seed=0: 6, 8, 7, 1, -7, 1, 10, -1, 12, -6, -5, -1, 3, -1, 12, -12, 9, 12, 4, -5
dotnet.next(in:-12..<13) seed=1: -6, -10, -1, 7, 4, -2, -4, 11, -10, 4, -12, -6, -4, 12, 5, 4, -5, 3, 5, 5
dotnet.next(in:-12..<13) seed=42: 4, -9, -9, 1, -8, -6, 6, 0, -8, 7, -7, -6, 0, -4, -3, -6, 0, -12, 8, 2
dotnet.next(in:-12..<13) seed=12345: -11, -11, 7, 0, 7, 8, -8, 6, -6, 0, -7, -3, -7, -12, -9, 6, -8, 10, 9, -4
dotnet.next() seed=2147483647: 1559595546, 1755192844, 1649316172, 1198642031, 442452829, 1200195955, 1945678308, 949569752, 2099272109, 587775835, 626863973, 1003550677, 1358624999, 1008269081, 2109153755, 65212616, 1851925783, 2137491580, 1454235444, 675580701
dotnet.next() seed=-2147483648: 1559595546, 1755192844, 1649316172, 1198642031, 442452829, 1200195955, 1945678308, 949569752, 2099272109, 587775835, 626863973, 1003550677, 1358624999, 1008269081, 2109153755, 65212616, 1851925783, 2137491580, 1454235444, 675580701
dotnet.next() seed=-42: 1434747710, 302596119, 269548474, 1122627734, 361709742, 563913476, 1555655117, 1101493307, 372913049, 1634773126, 503774878, 552593494, 1085775344, 687695533, 818126015, 558871098, 1111217775, 75846583, 1748346701, 1239520805
pieterCS.rand() randSeed(0,0): 18031441007693, 21028680369035, 9369085285497, 31709081197611, 65387192783972, 10992957824754, 38456692512923, 69306086427072, 44894921458650, 70619132899786, 23051399464338, 5580086820660, 16636660879564, 40545935293437, 25991803093446, 53207240002396, 21332386699811, 64423262074601, 54856974294891, 29736224207805
pieterCS.rand() randSeed(1,1): 1179678903, 21233664004817, 65532129682515, 68645896677428, 67128916847272, 51714433314619, 54487550541642, 28718182310489, 36557729719159, 58735231758915, 27971529983179, 48652649252697, 63984849851755, 48997656008994, 12043774095719, 12344020476118, 5119860702835, 4673843533836, 16543454891060, 63644621332702
pieterCS.rand() randSeed(42,42): 49545268742, 41410364118621, 46520050775457, 22679442626722, 36275701743521, 7342682685364, 46504195482166, 46522487775908, 66545833169291, 70287982182158, 15163088259445, 33366575068346, 58843710653337, 47856857915287, 41982043265791, 54592390718254, 60415325683448, 41682604323340, 76349813817504, 44554110690435
pieterCS.rand() randSeed(12345,12345): 14562754572479, 50677900277574, 28460960918022, 45137305670280, 26899022418697, 70870123338796, 56933253123181, 62309876064701, 50139529706487, 1467067569063, 44706322255573, 138701027299, 22716483691075, 7229229595802, 14392995589319, 10082671068418, 42890975499751, 25777142903421, 54795042886712, 74612392446935
pieterPalm.rand() randSeed(0,0): 48819, 14837, 17955, 35589, 47251, 55573, 1539, 46117, 7795, 44085, 61923, 20805, 28755, 13141, 35267, 57957, 11827, 61045, 19875, 59269
pieterPalm.rand() randSeed(1,1): 30903, 4817, 27495, 3745, 60695, 17265, 11719, 321, 23927, 38929, 44071, 22497, 18903, 37041, 26247, 37505, 12855, 44369, 56551, 12577
pieterPalm.rand() randSeed(42,42): 52742, 5706, 40678, 26218, 58822, 4234, 33446, 13482, 21894, 62154, 15974, 27370, 7494, 48394, 53798, 2346, 15622, 28490, 15846, 3946
pieterPalm.rand() randSeed(12345,12345): 12479, 24713, 14831, 29145, 6687, 13353, 33103, 30585, 8063, 3017, 42159, 49433, 49375, 26473, 9231, 52921, 32319, 50953, 32623, 8281
palmLCG.output seed=0: 0, 346, 130, 10982, 1090, 11656, 7117, 17595, 6415, 22948, 31126, 9004, 14558, 3571, 22879, 18492, 1360, 5412, 26721, 22463
palmLCG.output seed=1: 346, 130, 10982, 1090, 11656, 7117, 17595, 6415, 22948, 31126, 9004, 14558, 3571, 22879, 18492, 1360, 5412, 26721, 22463, 25047
palmLCG.output seed=42: 14544, 24056, 29925, 21512, 18870, 17624, 21206, 6777, 12690, 5958, 19514, 12907, 11839, 28091, 2449, 19862, 7693, 15636, 11730, 32684
palmLCG.output seed=12345: 15301, 24996, 10921, 23577, 19316, 10386, 21959, 16484, 32360, 16814, 26124, 25833, 1636, 11030, 26232, 13965, 16051, 30867, 23092, 5184
palmLCG.next(below:100) seed=0: 0, 46, 30, 82, 90, 56, 17, 95, 15, 48, 26, 4, 58, 71, 79, 92, 60, 12, 21, 63
palmLCG.next(below:100) seed=1: 46, 30, 82, 90, 56, 17, 95, 15, 48, 26, 4, 58, 71, 79, 92, 60, 12, 21, 63, 47
palmLCG.next(below:100) seed=42: 44, 56, 25, 12, 70, 24, 6, 77, 90, 58, 14, 7, 39, 91, 49, 62, 93, 36, 30, 84
palmLCG.next(below:100) seed=12345: 1, 96, 21, 77, 16, 86, 59, 84, 60, 14, 24, 33, 36, 30, 32, 65, 51, 67, 92, 84
xoshiro.initialState seed=0: E220A8397B1DCDAF, 6E789E6AA1B965F4, 06C45D188009454F, F88BB8A8724C81EC
xoshiro.initialState seed=1: 910A2DEC89025CC1, BEEB8DA1658EEC67, F893A2EEFB32555E, 71C18690EE42C90B
xoshiro.initialState seed=42: BDD732262FEB6E95, 28EFE333B266F103, 47526757130F9F52, 581CE1FF0E4AE394
xoshiro.initialState seed=12345: 22118258A9D111A0, 346EDCE5F713F8ED, 1E9A57BC80E6721D, 2D160E7E5C3F42CA
xoshiro.next() seed=0: 99EC5F36CB75F2B4, BF6E1F784956452A, 1A5F849D4933E6E0, 6AA594F1262D2D2C, BBA5AD4A1F842E59, FFEF8375D9EBCACA, 6C160DEED2F54C98, 8920AD648FC30A3F, DB032C0BA7539731, EB3A475A3E749A3D, 1D42993FA43F2A54, 11361BF526A14BB5, 1B4F07A5AB3D8E9C, A7A3257F6986DB7F, 7EFDAA95605DFC9C, 4BDE97C0A78EAAB8, B455EAC43518666C, 304DBF6C06730690, 8CBE7776598A798C, 0ECBDF7FFCD727E5
xoshiro.next() seed=1: B3F2AF6D0FC710C5, 853B559647364CEA, 92F89756082A4514, 642E1C7BC266A3A7, B27A48E29A233673, 24C123126FFDA722, 123004EF8DF510E6, 61954DCC47B1E89D, DDFDB48AB9ED4A21, 8D3CDB8C3AA5B1D0, EEBD114BD87226D1, F50C3FF1E7D7E8A6, EECA3115E23BC8F1, AB49ED3DB4C66435, 99953C6C57808DD7, E3FA941B05219325, 1498C2C122087C87, 7DC9C3C6CD31382F, 0BBADEDEC37361C0, 10538449E2D4F5AF
xoshiro.next() seed=42: 15780B2E0C2EC716, 6104D9866D113A7E, AE17533239E499A1, ECB8AD4703B360A1, FDE6DC7FE2EC5E64, C50DA53101795238, B82154855A65DDB2, D99A2743EBE60087, C2E96E726E97647E, 9556615F775FBC3D, AEB53B340C103971, 4A69DB9873AF8965, CD0FEDA93006C6B6, 52480865A4B42742, B60DEC3BF2D887CD, E0B55A68B96677FA, 9DE4159EDA9CEF95, D9F4B354EC3844D4, B5215F43ED431A77, B5344CBE421F4F3A
xoshiro.next() seed=12345: BE6A36374160D49B, 214AAA0637A688C6, F69D16DE9954D388, 0C60048C4E96E033, 8E2076AEED51C648, 02BBCC1C1FC50F84, 28E72A4FEC84F699, 4BB9D7CBB8DDDEBE, 62CEA6A22CF0BD36, E91DF042CCDE955D, C826F11010F4A3D2, 8985B3ADCD266FDC, D6EC21EEC05E255B, F10BFD24E5EDB1F1, 22CDD55F17CA33A1, DD4773F85B29AE79, 753EC48AE8869A10, DBCA067FFB2B6F34, 8A52B7321740E05F, 6E9D4A85FE9632DB
xoshiro.next(below:100) seed=0: 60, 74, 10, 41, 73, 99, 42, 53, 85, 91, 11, 6, 10, 65, 49, 29, 70, 18, 54, 5
xoshiro.next(below:100) seed=1: 70, 52, 57, 39, 69, 14, 7, 38, 86, 55, 93, 95, 93, 66, 59, 89, 8, 49, 4, 6
xoshiro.next(below:100) seed=42: 8, 37, 68, 92, 99, 76, 71, 85, 76, 58, 68, 29, 80, 32, 71, 87, 61, 85, 70, 70
xoshiro.next(below:100) seed=12345: 74, 13, 96, 4, 55, 1, 15, 29, 38, 91, 78, 53, 83, 94, 13, 86, 45, 85, 54, 43
```
