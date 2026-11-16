// SPDX-License-Identifier: GPL-2.0-or-later
// swiftlint:disable line_length
// Vectors from docs/specs/RNG.md Appendix A (RNG-039).
import Testing
@testable import ParsecEngine

@Suite("RNG reference vectors (RNG-039)")
struct RNGVectorTests {
    @Test("RNG-039 RNG-016 PieterRand C# and Palm, seed 0")
    func pieter0() {
        var cs = PieterRand(variant: .csharp); cs.seed(0, 0)
        #expect((0..<20).map { _ in cs.rand() } == [18031441007693, 21028680369035, 9369085285497, 31709081197611, 65387192783972, 10992957824754, 38456692512923, 69306086427072, 44894921458650, 70619132899786, 23051399464338, 5580086820660, 16636660879564, 40545935293437, 25991803093446, 53207240002396, 21332386699811, 64423262074601, 54856974294891, 29736224207805])
        var palm = PieterRand(variant: .palm); palm.seed(0, 0)
        #expect((0..<20).map { _ in palm.rand() } == [48819, 14837, 17955, 35589, 47251, 55573, 1539, 46117, 7795, 44085, 61923, 20805, 28755, 13141, 35267, 57957, 11827, 61045, 19875, 59269])
    }

    @Test("RNG-039 RNG-027 PalmLCG outputs and next(below:100), seed 0")
    func palm0() {
        var a = PalmLCG(seed: 0)
        #expect((0..<20).map { _ in a.sysRandom() } == [0, 346, 130, 10982, 1090, 11656, 7117, 17595, 6415, 22948, 31126, 9004, 14558, 3571, 22879, 18492, 1360, 5412, 26721, 22463])
        var b = PalmLCG(seed: 0)
        #expect((0..<20).map { _ in b.next(below: 100) } == [0, 46, 30, 82, 90, 56, 17, 95, 15, 48, 26, 4, 58, 71, 79, 92, 60, 12, 21, 63])
    }

    @Test("RNG-039 RNG-029 RNG-030 RNG-031 Xoshiro256** outputs and bounded draws, seed 0")
    func xoshiro0() {
        var a = Xoshiro256StarStar(seed: 0)
        #expect((0..<20).map { _ in a.nextUInt64() } == [0x99EC5F36CB75F2B4, 0xBF6E1F784956452A, 0x1A5F849D4933E6E0, 0x6AA594F1262D2D2C, 0xBBA5AD4A1F842E59, 0xFFEF8375D9EBCACA, 0x6C160DEED2F54C98, 0x8920AD648FC30A3F, 0xDB032C0BA7539731, 0xEB3A475A3E749A3D, 0x1D42993FA43F2A54, 0x11361BF526A14BB5, 0x1B4F07A5AB3D8E9C, 0xA7A3257F6986DB7F, 0x7EFDAA95605DFC9C, 0x4BDE97C0A78EAAB8, 0xB455EAC43518666C, 0x304DBF6C06730690, 0x8CBE7776598A798C, 0x0ECBDF7FFCD727E5])
        var b = Xoshiro256StarStar(seed: 0)
        #expect((0..<20).map { _ in b.next(below: 100) } == [60, 74, 10, 41, 73, 99, 42, 53, 85, 91, 11, 6, 10, 65, 49, 29, 70, 18, 54, 5])
    }

    @Test("RNG-039 DotNetRandom next(below:100) and next(in:-12..<13), seed 0")
    func dotnet0() {
        var a = DotNetRandom(seed: 0)
        #expect((0..<20).map { _ in a.next(below: 100) } == [72, 81, 76, 55, 20, 55, 90, 44, 97, 27, 29, 46, 63, 46, 98, 3, 86, 99, 67, 31])
        var b = DotNetRandom(seed: 0)
        #expect((0..<20).map { _ in b.next(in: -12, 13) } == [6, 8, 7, 1, -7, 1, 10, -1, 12, -6, -5, -1, 3, -1, 12, -12, 9, 12, 4, -5])
    }

    @Test("RNG-039 RNG-016 PieterRand C# and Palm, seed 1")
    func pieter1() {
        var cs = PieterRand(variant: .csharp); cs.seed(1, 1)
        #expect((0..<20).map { _ in cs.rand() } == [1179678903, 21233664004817, 65532129682515, 68645896677428, 67128916847272, 51714433314619, 54487550541642, 28718182310489, 36557729719159, 58735231758915, 27971529983179, 48652649252697, 63984849851755, 48997656008994, 12043774095719, 12344020476118, 5119860702835, 4673843533836, 16543454891060, 63644621332702])
        var palm = PieterRand(variant: .palm); palm.seed(1, 1)
        #expect((0..<20).map { _ in palm.rand() } == [30903, 4817, 27495, 3745, 60695, 17265, 11719, 321, 23927, 38929, 44071, 22497, 18903, 37041, 26247, 37505, 12855, 44369, 56551, 12577])
    }

    @Test("RNG-039 RNG-027 PalmLCG outputs and next(below:100), seed 1")
    func palm1() {
        var a = PalmLCG(seed: 1)
        #expect((0..<20).map { _ in a.sysRandom() } == [346, 130, 10982, 1090, 11656, 7117, 17595, 6415, 22948, 31126, 9004, 14558, 3571, 22879, 18492, 1360, 5412, 26721, 22463, 25047])
        var b = PalmLCG(seed: 1)
        #expect((0..<20).map { _ in b.next(below: 100) } == [46, 30, 82, 90, 56, 17, 95, 15, 48, 26, 4, 58, 71, 79, 92, 60, 12, 21, 63, 47])
    }

    @Test("RNG-039 RNG-029 RNG-030 RNG-031 Xoshiro256** outputs and bounded draws, seed 1")
    func xoshiro1() {
        var a = Xoshiro256StarStar(seed: 1)
        #expect((0..<20).map { _ in a.nextUInt64() } == [0xB3F2AF6D0FC710C5, 0x853B559647364CEA, 0x92F89756082A4514, 0x642E1C7BC266A3A7, 0xB27A48E29A233673, 0x24C123126FFDA722, 0x123004EF8DF510E6, 0x61954DCC47B1E89D, 0xDDFDB48AB9ED4A21, 0x8D3CDB8C3AA5B1D0, 0xEEBD114BD87226D1, 0xF50C3FF1E7D7E8A6, 0xEECA3115E23BC8F1, 0xAB49ED3DB4C66435, 0x99953C6C57808DD7, 0xE3FA941B05219325, 0x1498C2C122087C87, 0x7DC9C3C6CD31382F, 0x0BBADEDEC37361C0, 0x10538449E2D4F5AF])
        var b = Xoshiro256StarStar(seed: 1)
        #expect((0..<20).map { _ in b.next(below: 100) } == [70, 52, 57, 39, 69, 14, 7, 38, 86, 55, 93, 95, 93, 66, 59, 89, 8, 49, 4, 6])
    }

    @Test("RNG-039 DotNetRandom next(below:100) and next(in:-12..<13), seed 1")
    func dotnet1() {
        var a = DotNetRandom(seed: 1)
        #expect((0..<20).map { _ in a.next(below: 100) } == [24, 11, 46, 77, 65, 43, 35, 94, 10, 64, 2, 24, 32, 98, 68, 65, 28, 61, 70, 70])
        var b = DotNetRandom(seed: 1)
        #expect((0..<20).map { _ in b.next(in: -12, 13) } == [-6, -10, -1, 7, 4, -2, -4, 11, -10, 4, -12, -6, -4, 12, 5, 4, -5, 3, 5, 5])
    }

    @Test("RNG-039 RNG-016 PieterRand C# and Palm, seed 42")
    func pieter42() {
        var cs = PieterRand(variant: .csharp); cs.seed(42, 42)
        #expect((0..<20).map { _ in cs.rand() } == [49545268742, 41410364118621, 46520050775457, 22679442626722, 36275701743521, 7342682685364, 46504195482166, 46522487775908, 66545833169291, 70287982182158, 15163088259445, 33366575068346, 58843710653337, 47856857915287, 41982043265791, 54592390718254, 60415325683448, 41682604323340, 76349813817504, 44554110690435])
        var palm = PieterRand(variant: .palm); palm.seed(42, 42)
        #expect((0..<20).map { _ in palm.rand() } == [52742, 5706, 40678, 26218, 58822, 4234, 33446, 13482, 21894, 62154, 15974, 27370, 7494, 48394, 53798, 2346, 15622, 28490, 15846, 3946])
    }

    @Test("RNG-039 RNG-027 PalmLCG outputs and next(below:100), seed 42")
    func palm42() {
        var a = PalmLCG(seed: 42)
        #expect((0..<20).map { _ in a.sysRandom() } == [14544, 24056, 29925, 21512, 18870, 17624, 21206, 6777, 12690, 5958, 19514, 12907, 11839, 28091, 2449, 19862, 7693, 15636, 11730, 32684])
        var b = PalmLCG(seed: 42)
        #expect((0..<20).map { _ in b.next(below: 100) } == [44, 56, 25, 12, 70, 24, 6, 77, 90, 58, 14, 7, 39, 91, 49, 62, 93, 36, 30, 84])
    }

    @Test("RNG-039 RNG-029 RNG-030 RNG-031 Xoshiro256** outputs and bounded draws, seed 42")
    func xoshiro42() {
        var a = Xoshiro256StarStar(seed: 42)
        #expect((0..<20).map { _ in a.nextUInt64() } == [0x15780B2E0C2EC716, 0x6104D9866D113A7E, 0xAE17533239E499A1, 0xECB8AD4703B360A1, 0xFDE6DC7FE2EC5E64, 0xC50DA53101795238, 0xB82154855A65DDB2, 0xD99A2743EBE60087, 0xC2E96E726E97647E, 0x9556615F775FBC3D, 0xAEB53B340C103971, 0x4A69DB9873AF8965, 0xCD0FEDA93006C6B6, 0x52480865A4B42742, 0xB60DEC3BF2D887CD, 0xE0B55A68B96677FA, 0x9DE4159EDA9CEF95, 0xD9F4B354EC3844D4, 0xB5215F43ED431A77, 0xB5344CBE421F4F3A])
        var b = Xoshiro256StarStar(seed: 42)
        #expect((0..<20).map { _ in b.next(below: 100) } == [8, 37, 68, 92, 99, 76, 71, 85, 76, 58, 68, 29, 80, 32, 71, 87, 61, 85, 70, 70])
    }

    @Test("RNG-039 DotNetRandom next(below:100) and next(in:-12..<13), seed 42")
    func dotnet42() {
        var a = DotNetRandom(seed: 42)
        #expect((0..<20).map { _ in a.next(below: 100) } == [66, 14, 12, 52, 16, 26, 72, 51, 17, 76, 23, 25, 50, 32, 38, 26, 51, 3, 81, 57])
        var b = DotNetRandom(seed: 42)
        #expect((0..<20).map { _ in b.next(in: -12, 13) } == [4, -9, -9, 1, -8, -6, 6, 0, -8, 7, -7, -6, 0, -4, -3, -6, 0, -12, 8, 2])
    }

    @Test("RNG-039 RNG-016 PieterRand C# and Palm, seed 12345")
    func pieter12345() {
        var cs = PieterRand(variant: .csharp); cs.seed(12345, 12345)
        #expect((0..<20).map { _ in cs.rand() } == [14562754572479, 50677900277574, 28460960918022, 45137305670280, 26899022418697, 70870123338796, 56933253123181, 62309876064701, 50139529706487, 1467067569063, 44706322255573, 138701027299, 22716483691075, 7229229595802, 14392995589319, 10082671068418, 42890975499751, 25777142903421, 54795042886712, 74612392446935])
        var palm = PieterRand(variant: .palm); palm.seed(12345, 12345)
        #expect((0..<20).map { _ in palm.rand() } == [12479, 24713, 14831, 29145, 6687, 13353, 33103, 30585, 8063, 3017, 42159, 49433, 49375, 26473, 9231, 52921, 32319, 50953, 32623, 8281])
    }

    @Test("RNG-039 RNG-027 PalmLCG outputs and next(below:100), seed 12345")
    func palm12345() {
        var a = PalmLCG(seed: 12345)
        #expect((0..<20).map { _ in a.sysRandom() } == [15301, 24996, 10921, 23577, 19316, 10386, 21959, 16484, 32360, 16814, 26124, 25833, 1636, 11030, 26232, 13965, 16051, 30867, 23092, 5184])
        var b = PalmLCG(seed: 12345)
        #expect((0..<20).map { _ in b.next(below: 100) } == [1, 96, 21, 77, 16, 86, 59, 84, 60, 14, 24, 33, 36, 30, 32, 65, 51, 67, 92, 84])
    }

    @Test("RNG-039 RNG-029 RNG-030 RNG-031 Xoshiro256** outputs and bounded draws, seed 12345")
    func xoshiro12345() {
        var a = Xoshiro256StarStar(seed: 12345)
        #expect((0..<20).map { _ in a.nextUInt64() } == [0xBE6A36374160D49B, 0x214AAA0637A688C6, 0xF69D16DE9954D388, 0x0C60048C4E96E033, 0x8E2076AEED51C648, 0x02BBCC1C1FC50F84, 0x28E72A4FEC84F699, 0x4BB9D7CBB8DDDEBE, 0x62CEA6A22CF0BD36, 0xE91DF042CCDE955D, 0xC826F11010F4A3D2, 0x8985B3ADCD266FDC, 0xD6EC21EEC05E255B, 0xF10BFD24E5EDB1F1, 0x22CDD55F17CA33A1, 0xDD4773F85B29AE79, 0x753EC48AE8869A10, 0xDBCA067FFB2B6F34, 0x8A52B7321740E05F, 0x6E9D4A85FE9632DB])
        var b = Xoshiro256StarStar(seed: 12345)
        #expect((0..<20).map { _ in b.next(below: 100) } == [74, 13, 96, 4, 55, 1, 15, 29, 38, 91, 78, 53, 83, 94, 13, 86, 45, 85, 54, 43])
    }

    @Test("RNG-039 DotNetRandom next(below:100) and next(in:-12..<13), seed 12345")
    func dotnet12345() {
        var a = DotNetRandom(seed: 12345)
        #expect((0..<20).map { _ in a.next(below: 100) } == [6, 7, 77, 51, 79, 82, 16, 73, 26, 50, 23, 38, 21, 2, 13, 74, 19, 88, 86, 35])
        var b = DotNetRandom(seed: 12345)
        #expect((0..<20).map { _ in b.next(in: -12, 13) } == [-11, -11, 7, 0, 7, 8, -8, 6, -6, 0, -7, -3, -7, -12, -9, 6, -8, 10, 9, -4])
    }

    @Test("RNG-004 next(below: 0) returns 0 and consumes one draw on every generator")
    func zeroBoundConsumes() {
        var p1 = PalmLCG(seed: 7), p2 = PalmLCG(seed: 7)
        #expect(p1.next(below: 0) == 0)
        _ = p2.sysRandom()
        #expect(p1 == p2)
        var x1 = Xoshiro256StarStar(seed: 7), x2 = Xoshiro256StarStar(seed: 7)
        #expect(x1.next(below: 0) == 0)
        _ = x2.nextUInt64()
        #expect(x1 == x2)
        var d1 = DotNetRandom(seed: 7), d2 = DotNetRandom(seed: 7)
        #expect(d1.next(below: 0) == 0)
        _ = d2.internalSample()
        #expect(d1 == d2)
    }
}
