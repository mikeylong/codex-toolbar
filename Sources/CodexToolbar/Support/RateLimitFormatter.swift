import Foundation

enum RateLimitFormatter {
    static func remainingPercent(fromUsedPercent usedPercent: Int) -> Int {
        max(0, 100 - usedPercent)
    }

    static func windowLabel(for minutes: Int?) -> String {
        guard let minutes else {
            return "Limit"
        }

        switch minutes {
        case 300:
            return "5h"
        case 10080:
            return "Weekly"
        case let value where value % 1440 == 0:
            let days = value / 1440
            return days == 1 ? "1d" : "\(days)d"
        case let value where value % 60 == 0:
            return "\(value / 60)h"
        default:
            return "\(minutes)m"
        }
    }

    static func resetText(
        for date: Date?,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        guard let date else {
            return "--"
        }

        if calendar.isDate(date, inSameDayAs: now) {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = timeZone
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: date)
        }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}
