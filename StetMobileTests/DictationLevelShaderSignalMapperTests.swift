import Testing

@testable import StetMobile

@Suite("Dictation Level Shader Signal Mapper")
struct DictationLevelShaderSignalMapperTests {
    @Test func zeroLevelProducesZeroEnergy() {
        let signals = DictationLevelShaderSignalMapper.signals(level: 0)

        #expect(signals.estimatedSummary.level == 0)
        #expect(signals.estimatedSummary.groupedBands == .zero)
        #expect(signals.bands.allSatisfy { $0.weight == 0 })
    }

    @Test func levelIsClampedToUnitRange() {
        let belowRange = DictationLevelShaderSignalMapper.signals(level: -0.5)
        let aboveRange = DictationLevelShaderSignalMapper.signals(level: 1.5)

        #expect(belowRange.estimatedSummary.level == 0)
        #expect(aboveRange.estimatedSummary.level == 1)
        #expect(isNear(aboveRange.estimatedSummary.groupedBands[0], 1))
        #expect(isNear(aboveRange.estimatedSummary.groupedBands[1], 0.85))
        #expect(isNear(aboveRange.estimatedSummary.groupedBands[2], 0.70))
        #expect(isNear(aboveRange.estimatedSummary.groupedBands[3], 0.55))
    }

    @Test func scalarMappingProducesTwelveBandsAndExpectedGroups() {
        let signals = DictationLevelShaderSignalMapper.signals(level: 0.8)

        #expect(signals.bands.count == 12)
        #expect(isNear(signals.estimatedSummary.groupedBands[0], 0.8))
        #expect(isNear(signals.estimatedSummary.groupedBands[1], 0.68))
        #expect(isNear(signals.estimatedSummary.groupedBands[2], 0.56))
        #expect(isNear(signals.estimatedSummary.groupedBands[3], 0.44))
    }

    @Test func higherLevelProducesMonotonicallyHigherEnergy() {
        let low = DictationLevelShaderSignalMapper.signals(level: 0.2)
        let high = DictationLevelShaderSignalMapper.signals(level: 0.8)
        let lowEnergy = low.bands.reduce(0) { $0 + $1.weight }
        let highEnergy = high.bands.reduce(0) { $0 + $1.weight }

        #expect(high.estimatedSummary.level > low.estimatedSummary.level)
        #expect(highEnergy > lowEnergy)
        #expect(zip(low.bands, high.bands).allSatisfy { $0.weight <= $1.weight })
    }

    private func isNear(_ lhs: Float, _ rhs: Float, tolerance: Float = 0.000_001) -> Bool {
        abs(lhs - rhs) <= tolerance
    }
}
