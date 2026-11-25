import Foundation

enum Formatters {
    static let full: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .medium
        return f
    }()

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("HHmm")
        return f
    }()

    private static let dayMonthYear: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("dMMMyyyy")
        return f
    }()

    /// "Today 09:54", "Yesterday 09:54" or "7 Sep 2026 14:50".
    static func historyDate(_ d: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(d) { return "Today " + time.string(from: d) }
        if calendar.isDateInYesterday(d) { return "Yesterday " + time.string(from: d) }
        return dayMonthYear.string(from: d) + " " + time.string(from: d)
    }
}
