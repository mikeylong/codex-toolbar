import Foundation

enum RateLimitFormatter {
    private static let normalizationToleranceMinutes = 1

    static func remainingPercent(fromUsedPercent usedPercent: Int) -> Int {
        max(0, 100 - usedPercent)
    }

    static func compactWindowLabel(for minutes: Int?) -> String {
        guard let minutes else {
            return "Limit"
        }

        let normalizedMinutes = normalizedWindowMinutes(minutes)

        switch normalizedMinutes {
        case 300:
            return "5h"
        case 10080:
            return "Weekly"
        case let value where value % 10080 == 0:
            return "\(value / 10080) Week"
        case let value where value % 1440 == 0:
            return "\(value / 1440) Day"
        case let value where value % 60 == 0:
            return "\(value / 60)h"
        default:
            return "\(normalizedMinutes)m"
        }
    }

    static func windowTitle(for minutes: Int?) -> String {
        guard let minutes else {
            return "Rate limit window"
        }

        return compactWindowLabel(for: minutes)
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

    static func updatedFooterText(
        for date: Date,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mm:ss a"
        return "Updated \(formatter.string(from: date))"
    }

    static func normalizedWindowMinutes(_ minutes: Int) -> Int {
        if let normalizedWeeks = snapped(minutes: minutes, unitMinutes: 10080) {
            return normalizedWeeks
        }

        if let normalizedDays = snapped(minutes: minutes, unitMinutes: 1440) {
            return normalizedDays
        }

        if let normalizedHours = snapped(minutes: minutes, unitMinutes: 60) {
            return normalizedHours
        }

        return minutes
    }

    private static func snapped(minutes: Int, unitMinutes: Int) -> Int? {
        guard unitMinutes > 0 else { return nil }

        let quotient = Double(minutes) / Double(unitMinutes)
        let roundedQuotient = Int(quotient.rounded())
        guard roundedQuotient > 0 else { return nil }

        let snappedMinutes = roundedQuotient * unitMinutes
        let drift = abs(snappedMinutes - minutes)
        guard drift <= normalizationToleranceMinutes else {
            return nil
        }

        return snappedMinutes
    }
}
