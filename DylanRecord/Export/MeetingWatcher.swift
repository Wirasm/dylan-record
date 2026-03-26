import EventKit
import Foundation
import UserNotifications

@MainActor
final class MeetingWatcher {
    private var checkTimer: Timer?
    private var notifiedEventIDs: Set<String> = []
    private let calendarService = CalendarService()

    func start() {
        // Check every 30 seconds for upcoming meetings
        checkTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForMeetingStart()
            }
        }
        // Also check immediately
        checkForMeetingStart()
    }

    func stop() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    private func checkForMeetingStart() {
        let now = Date()
        let store = EKEventStore()

        // Look for events starting in the next 1 minute
        let windowEnd = Calendar.current.date(byAdding: .minute, value: 1, to: now) ?? now

        let predicate = store.predicateForEvents(
            withStart: now,
            end: windowEnd,
            calendars: nil
        )

        let upcomingEvents = store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .filter { event in
                // Event starts within the next 60 seconds (or just started within last 30 seconds)
                let timeUntilStart = event.startDate.timeIntervalSince(now)
                return timeUntilStart >= -30 && timeUntilStart <= 60
            }

        for event in upcomingEvents {
            let eventID = event.eventIdentifier ?? event.title ?? UUID().uuidString
            guard !notifiedEventIDs.contains(eventID) else { continue }

            notifiedEventIDs.insert(eventID)
            sendMeetingNotification(title: event.title ?? "Meeting")

            // Clean up old IDs after 2 hours
            let idToClean = eventID
            DispatchQueue.main.asyncAfter(deadline: .now() + 7200) { [weak self] in
                self?.notifiedEventIDs.remove(idToClean)
            }
        }
    }

    private func sendMeetingNotification(title: String) {
        let content = UNMutableNotificationContent()
        content.title = "Meeting Starting"
        content.body = "\(title) — Start recording?"
        content.sound = .default
        content.categoryIdentifier = "MEETING_START"

        let request = UNNotificationRequest(
            identifier: "meeting-start-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[MeetingWatcher] Notification error: \(error)")
            }
        }
    }
}
