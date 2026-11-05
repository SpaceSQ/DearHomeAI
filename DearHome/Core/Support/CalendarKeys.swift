import Foundation

enum Shichen: String, Codable, Sendable, Equatable {
    case morning
    case midday
    case evening

    static func of(_ date: Date, calendar: Calendar = .current) -> Shichen {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<11: return .morning
        case 11..<18: return .midday
        default: return .evening
        }
    }
}

enum DayKey {
    static func string(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func date(from key: String, calendar: Calendar = .current) -> Date? {
        let pieces = key.split(separator: "-")
        guard pieces.count == 3,
              let year = Int(pieces[0]),
              let month = Int(pieces[1]),
              let day = Int(pieces[2]) else { return nil }
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        return calendar.date(from: parts)
    }

    static func ageInDays(of key: String, current currentKey: String, calendar: Calendar = .current) -> Int? {
        guard let older = date(from: key, calendar: calendar),
              let current = date(from: currentKey, calendar: calendar) else { return nil }
        return calendar.dateComponents([.day], from: older, to: current).day
    }
}

/// ISO week id (`2026-W44`), used by weekly consolidation.
enum ISOWeek {
    static func key(for date: Date, timeZone: TimeZone? = nil, calendar base: Calendar = .current) -> String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = timeZone ?? base.timeZone
        let year = calendar.component(.yearForWeekOfYear, from: date)
        let week = calendar.component(.weekOfYear, from: date)
        return String(format: "%04d-W%02d", year, week)
    }

    static func key(forDateKey dateKey: String, calendar: Calendar = .current) -> String {
        guard let date = DayKey.date(from: dateKey, calendar: calendar) else { return dateKey }
        return key(for: date, calendar: calendar)
    }

    static func previousWeekKey(before date: Date, calendar base: Calendar = .current) -> String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = base.timeZone
        let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: date) ?? date
        return key(for: previous, calendar: base)
    }

    static func monday(of weekKey: String, calendar base: Calendar = .current) -> Date? {
        let parts = weekKey.split(separator: "-W")
        guard parts.count == 2, let year = Int(parts[0]), let week = Int(parts[1]) else { return nil }
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = base.timeZone
        return calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            weekday: 2,
            weekOfYear: week,
            yearForWeekOfYear: year
        ))
    }

    static func dateKeys(in weekKey: String, calendar base: Calendar = .current) -> [String] {
        guard let monday = monday(of: weekKey, calendar: base) else { return [] }
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = base.timeZone
        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: monday).map { DayKey.string(for: $0, calendar: calendar) }
        }
    }
}
