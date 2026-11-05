import Foundation
import Testing

@testable import WorkoutsKit

@Suite struct WeightFormatTests {
    @Test func numberUsesHalfStepsWithoutTrailingZeros() {
        #expect(WeightFormat.number(27.5) == "27.5")
        #expect(WeightFormat.number(100) == "100")
        #expect(WeightFormat.number(0) == "0")
        #expect(WeightFormat.number(22.25) == "22.25")
        #expect(WeightFormat.number(12.499) == "12.5")
        #expect(WeightFormat.number(2.5) == "2.5")
        #expect(WeightFormat.number(-0.001) == "0")
    }

    @Test func numberNeverGroups() {
        #expect(WeightFormat.number(1929) == "1929")
        #expect(WeightFormat.number(1_234_567.5) == "1234567.5")
    }

    @Test func groupedNumberAddsThousandsSeparators() {
        #expect(WeightFormat.groupedNumber(1929) == "1,929")
        #expect(WeightFormat.groupedNumber(117.5) == "117.5")
        #expect(WeightFormat.groupedNumber(0) == "0")
        #expect(WeightFormat.groupedNumber(-0.001) == "0")
    }

    @Test func textAppendsTheUnit() {
        #expect(WeightFormat.text(27.5, unit: .lb) == "27.5 lb")
        #expect(WeightFormat.text(1929, unit: .kg) == "1929 kg")
        #expect(WeightFormat.groupedText(1929, unit: .kg) == "1,929 kg")
        #expect(WeightFormat.groupedText(117.5, unit: .lb) == "117.5 lb")
    }

    @Test func ordinalReadsLikeEnglish() {
        #expect(OrdinalFormat.string(1) == "1st")
        #expect(OrdinalFormat.string(2) == "2nd")
        #expect(OrdinalFormat.string(3) == "3rd")
        #expect(OrdinalFormat.string(11) == "11th")
        #expect(OrdinalFormat.string(615) == "615th")
        #expect(OrdinalFormat.string(1001) == "1,001st")
    }
}
