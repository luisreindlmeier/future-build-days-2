import Foundation

/// Numbers and dates as the app writes them: British English, euro, no decimals unless they matter.
enum Format {
    private static let locale = Locale(identifier: "en_GB")

    static func euro(_ value: Double, decimals: Int = 0) -> String {
        value.formatted(.currency(code: "EUR").precision(.fractionLength(decimals)).locale(locale))
    }

    /// "€585k", "€1.2m": for chart axes and tight places.
    static func short(_ value: Double) -> String {
        if abs(value) >= 1_000_000 { return "€" + (value / 1_000_000).formatted(.number.precision(.fractionLength(0...2)).locale(locale)) + "m" }
        if abs(value) >= 1000 { return "€" + (value / 1000).formatted(.number.precision(.fractionLength(0)).locale(locale)) + "k" }
        return euro(value)
    }

    static func percent(_ value: Double, decimals: Int = 0) -> String {
        value.formatted(.percent.precision(.fractionLength(decimals)).locale(locale))
    }

    static func number(_ value: Double, decimals: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(decimals)).locale(locale))
    }

    static func count(_ value: Int, _ noun: String) -> String {
        value == 1 ? "1 \(noun)" : "\(value) \(noun)s"
    }

    /// "2026-11" as "November 2026", "2028-06-01" as "June 2028".
    static func month(_ text: String) -> String {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count >= 2, let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: parts[0], month: parts[1], day: 1)) else { return text }
        return date.formatted(Date.FormatStyle(locale: locale).month(.wide).year())
    }
}
