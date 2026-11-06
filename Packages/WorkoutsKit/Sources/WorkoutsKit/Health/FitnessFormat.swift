import Foundation

extension HealthEffort {
    /// Apple's words for the 1-10 scale: 1-3 Easy, 4-6 Moderate, 7-8 Hard, 9-10 All Out. The score is rounded to the
    /// nearest whole number first and clamped into 1...10.
    public var word: String {
        switch FitnessFormat.wholeScore(score) {
        case ...3: "Easy"
        case 4...6: "Moderate"
        case 7...8: "Hard"
        default: "All Out"
        }
    }

    /// `8 Hard`; the estimated flavour adds ` · Estimated`.
    public var text: String {
        let base = "\(FitnessFormat.wholeScore(score)) \(word)"
        return isEstimated ? base + " · Estimated" : base
    }
}

/// The pure text and proportions of the Fitness card, the History row and the dashboard (PLAN 7.1b f).
public nonisolated enum FitnessFormat {
    /// The score as a whole number in 1...10.
    public static func wholeScore(_ score: Double) -> Int {
        min(10, max(1, clampedInt(score)))
    }

    /// `value` rounded to an `Int`, never trapping: NaN is 0 and anything beyond +-10^9 is clamped there.
    static func clampedInt(_ value: Double) -> Int {
        guard value.isFinite else { return value.isNaN ? 0 : (value < 0 ? -1_000_000_000 : 1_000_000_000) }
        return Int(min(1e9, max(-1e9, value.rounded())))
    }

    /// `266 kcal`, `1,240 kcal`: whole calories with thousands separators.
    public static func kcalText(_ kcal: Double) -> String {
        "\(wholeNumber(kcal)) kcal"
    }

    /// `1,240`: a rounded whole number with thousands separators.
    public static func wholeNumber(_ value: Double) -> String {
        value.rounded().formatted(
            .number.precision(.fractionLength(0)).locale(Locale(identifier: "en_US"))
        )
    }

    /// `39 minutes, 53 seconds`, for VoiceOver.
    public static func spokenDuration(seconds: TimeInterval) -> String {
        Duration.seconds(max(0, clampedInt(seconds)))
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide).locale(Locale(identifier: "en_US")))
    }

    /// `Zone 1, 39 minutes, 53 seconds, up to 138 bpm`: one zone as VoiceOver reads it.
    public static func zoneSentence(_ zone: HeartRateZoneTime) -> String {
        var parts = ["Zone \(zone.index)", spokenDuration(seconds: zone.seconds)]
        if let range = zoneRangeText(zone) { parts.append(range) }
        return parts.joined(separator: ", ")
    }

    /// Each zone's share of the time spent in all the zones together (0...1), in the order given; all zeros when no time
    /// was spent in any.
    public static func zoneShares(_ zones: [HeartRateZoneTime]) -> [Double] {
        let total = zones.reduce(0) { $0 + max(0, $1.seconds) }
        guard total > 0 else { return zones.map { _ in 0 } }
        return zones.map { max(0, $0.seconds) / total }
    }

    /// `up to 138 bpm`, `139–150 bpm`, `175+ bpm`; nil when Health reported neither bound.
    public static func zoneRangeText(_ zone: HeartRateZoneTime) -> String? {
        switch (zone.lowerBPM, zone.upperBPM) {
        case (nil, nil): nil
        case (nil, let upper?): "up to \(wholeNumber(upper)) bpm"
        case (let lower?, nil): "\(wholeNumber(lower))+ bpm"
        case (let lower?, let upper?): "\(wholeNumber(lower))\u{2013}\(wholeNumber(upper)) bpm"
        }
    }

    /// `66°F` or `19°C` in the unit the locale uses for weather. The reading is stored in degrees Celsius.
    public static func temperatureText(celsius: Double, locale: Locale = .current) -> String {
        Measurement(value: celsius, unit: UnitTemperature.celsius)
            .formatted(
                .measurement(
                    width: .abbreviated,
                    usage: .weather,
                    numberFormatStyle: .number.precision(.fractionLength(0))
                )
                .locale(locale)
            )
    }

    /// Normalises `HKMetadataKeyWeatherHumidity` read in `HKUnit.percent()` to a 0-100 percentage. Health's own docs say
    /// the quantity is a fraction, but real Watch workouts store 83 for 83 %. A value of 1 or less is a fraction (x100);
    /// anything above is already a percentage.
    public static func humidityPercent(fromHealthPercent value: Double) -> Double {
        value <= 1 ? value * 100 : value
    }

    /// `65%`. `percent` is a 0-100 percentage. Rule for already-stored data: an earlier build multiplied Watch values
    /// that were already percentages by 100 (83 became 8300), so a stored value above 100 can only be that mistake and is
    /// divided by 100 here.
    public static func humidityText(percent: Double, locale: Locale = .current) -> String {
        let percent = percent > 100 ? percent / 100 : percent
        return (percent / 100).formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    /// `66°F, 65% humidity`, as the weather row reads to VoiceOver; nil when Health had neither.
    public static func weatherText(
        celsius: Double?,
        humidityPercent: Double?,
        locale: Locale = .current
    ) -> String? {
        var parts: [String] = []
        if let celsius { parts.append(temperatureText(celsius: celsius, locale: locale)) }
        if let humidityPercent { parts.append("\(humidityText(percent: humidityPercent, locale: locale)) humidity") }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
