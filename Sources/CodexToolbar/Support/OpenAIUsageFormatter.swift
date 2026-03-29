import Foundation

enum OpenAIUsageFormatter {
    static func currencyText(
        for amount: Decimal?,
        currencyCode: String?,
        locale: Locale = .current
    ) -> String? {
        guard let amount else {
            return nil
        }

        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode ?? "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2

        return formatter.string(from: amount as NSNumber)
    }

    static func countText(for value: Int?, locale: Locale = .current) -> String? {
        guard let value else {
            return nil
        }

        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = locale.groupingSeparator

        return formatter.string(from: NSNumber(value: value))
    }
}
