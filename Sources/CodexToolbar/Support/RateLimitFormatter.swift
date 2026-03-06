import Foundation

enum RateLimitFormatter {
    static func remainingPercent(fromUsedPercent usedPercent: Int) -> Int {
        max(0, 100 - usedPercent)
    }

    static func compactWindowLabel(for minutes: Int?) -> String {
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

    static func windowTitle(for minutes: Int?) -> String {
        guard let minutes else {
            return "Rate limit window"
        }

        switch minutes {
        case 300:
            return "Rolling 5-hour window"
        case 10080:
            return "Weekly"
        case let value where value % 1440 == 0:
            let days = value / 1440
            return days == 1 ? "Daily" : "Rolling \(days)-day window"
        case let value where value % 60 == 0:
            return "Rolling \(value / 60)-hour window"
        default:
            return "Rolling \(minutes)-minute window"
        }
    }

    static func absoluteResetText(
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

    static func relativeResetText(
        for date: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String? {
        guard let date else {
            return nil
        }

        let seconds = max(0, Int(date.timeIntervalSince(now)))
        guard seconds < 86_400 else {
            return nil
        }

        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60

        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }

        if minutes > 0 {
            return "\(minutes)m"
        }

        return "<1m"
    }

    static func combinedResetText(
        for date: Date?,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        guard let date else {
            return "Reset unavailable"
        }

        let absolute = absoluteResetText(for: date, now: now, calendar: calendar, locale: locale, timeZone: timeZone)
        if let relative = relativeResetText(for: date, now: now, calendar: calendar) {
            return "Resets in \(relative) (\(absolute))"
        }

        return "Resets \(absolute)"
    }
}
