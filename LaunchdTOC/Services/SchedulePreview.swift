import Foundation

struct SchedulePreview: Sendable {
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    init(
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.calendar = calendar
        self.now = now
    }

    func summary(for configuration: JobConfiguration) -> String {
        var parts: [String] = []
        if configuration.runAtLoad {
            parts.append("At load")
        }
        if let interval = configuration.startInterval {
            parts.append(intervalSummary(interval))
        }
        if !configuration.calendarSchedules.isEmpty {
            if configuration.calendarSchedules.count == 1 {
                parts.append(calendarSummary(configuration.calendarSchedules[0]))
            } else {
                parts.append("\(configuration.calendarSchedules.count) calendar times")
            }
        }
        return parts.isEmpty ? "Not scheduled" : parts.joined(separator: " · ")
    }

    func nextRuns(
        for configuration: JobConfiguration,
        count: Int = 5,
        after startDate: Date? = nil
    ) -> [Date] {
        let start = startDate ?? now()
        var candidates: [Date] = []

        if let interval = configuration.startInterval, interval > 0 {
            candidates.append(contentsOf: (1...count).map {
                start.addingTimeInterval(TimeInterval(interval * $0))
            })
        }

        for schedule in configuration.calendarSchedules {
            var cursor = start
            for _ in 0..<count {
                let components = DateComponents(
                    month: schedule.month,
                    day: schedule.day,
                    hour: schedule.hour,
                    minute: schedule.minute,
                    weekday: schedule.weekday
                )
                guard let next = calendar.nextDate(
                    after: cursor,
                    matching: components,
                    matchingPolicy: .nextTime,
                    repeatedTimePolicy: .first,
                    direction: .forward
                ) else {
                    break
                }
                candidates.append(next)
                cursor = next.addingTimeInterval(1)
            }
        }

        return Array(Set(candidates).sorted().prefix(count))
    }

    private func intervalSummary(_ seconds: Int) -> String {
        if seconds.isMultiple(of: 86_400) {
            let days = seconds / 86_400
            return days == 1 ? "Every day" : "Every \(days) days"
        }
        if seconds.isMultiple(of: 3_600) {
            let hours = seconds / 3_600
            return hours == 1 ? "Every hour" : "Every \(hours) hours"
        }
        if seconds.isMultiple(of: 60) {
            let minutes = seconds / 60
            return minutes == 1 ? "Every minute" : "Every \(minutes) minutes"
        }
        return "Every \(seconds) seconds"
    }

    private func calendarSummary(_ schedule: CalendarSchedule) -> String {
        let time: String
        if let hour = schedule.hour {
            time = String(format: "%02d:%02d", hour, schedule.minute ?? 0)
        } else if let minute = schedule.minute {
            time = "minute \(minute)"
        } else {
            time = "calendar schedule"
        }

        if let weekday = schedule.weekday {
            let normalized = weekday == 0 ? 1 : weekday
            let names = calendar.weekdaySymbols
            if (1...names.count).contains(normalized) {
                return "\(names[normalized - 1]) at \(time)"
            }
        }
        if let day = schedule.day {
            return "Day \(day) at \(time)"
        }
        return "At \(time)"
    }
}
