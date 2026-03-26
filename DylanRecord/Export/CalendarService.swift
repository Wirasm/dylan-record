import EventKit
import Foundation

struct CalendarService {
    private let store = EKEventStore()

    func requestAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToEvents()
        } catch {
            print("[Calendar] Access request failed: \(error)")
            return false
        }
    }

    func currentMeetingTitle(at date: Date = Date()) -> String? {
        let calendar = Calendar.current
        let windowStart = calendar.date(byAdding: .minute, value: -5, to: date) ?? date
        let windowEnd = calendar.date(byAdding: .minute, value: 5, to: date) ?? date

        let predicate = store.predicateForEvents(
            withStart: windowStart,
            end: windowEnd,
            calendars: nil
        )

        let events = store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .filter { $0.startDate <= date && $0.endDate >= date }
            .sorted { $0.startDate < $1.startDate }

        return events.first?.title
    }

    func currentMeetingEndDate(at date: Date = Date()) -> Date? {
        let calendar = Calendar.current
        let windowStart = calendar.date(byAdding: .minute, value: -5, to: date) ?? date
        let windowEnd = calendar.date(byAdding: .minute, value: 5, to: date) ?? date

        let predicate = store.predicateForEvents(
            withStart: windowStart,
            end: windowEnd,
            calendars: nil
        )

        let event = store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .filter { $0.startDate <= date && $0.endDate >= date }
            .sorted { $0.startDate < $1.startDate }
            .first

        return event?.endDate
    }

    func meetingTitleOverlapping(start: Date, end: Date) -> String? {
        let predicate = store.predicateForEvents(
            withStart: start,
            end: end,
            calendars: nil
        )

        let events = store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }

        return events.first?.title
    }
}
