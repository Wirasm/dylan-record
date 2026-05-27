import EventKit
import Foundation

struct CalendarService {
    nonisolated(unsafe) static let shared = EKEventStore()
    private let store = CalendarService.shared

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

    struct UpcomingMeeting {
        let title: String
        let startDate: Date
        let endDate: Date
    }

    func nextMeeting(after date: Date = Date()) -> UpcomingMeeting? {
        let status = EKEventStore.authorizationStatus(for: .event)
        let calendar = Calendar.current
        let windowEnd = calendar.date(byAdding: .hour, value: 12, to: date) ?? date

        let predicate = store.predicateForEvents(
            withStart: date,
            end: windowEnd,
            calendars: nil
        )

        let allEvents = store.events(matching: predicate)
        let nonAllDay = allEvents.filter { !$0.isAllDay }
        let future = nonAllDay.filter { $0.startDate > date }

        print("[Calendar] nextMeeting — status: \(status.rawValue), all: \(allEvents.count), nonAllDay: \(nonAllDay.count), future: \(future.count)")

        let event = future
            .sorted { $0.startDate < $1.startDate }
            .first

        guard let event else { return nil }
        let title = event.title ?? "?"
        let when: Date = event.startDate
        print("[Calendar] Next: \(title) at \(when)")
        return UpcomingMeeting(title: event.title ?? "Untitled", startDate: event.startDate, endDate: event.endDate)
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
