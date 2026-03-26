import EventKit
import Foundation

@MainActor
final class MeetingWatcher {
    private var checkTimer: Timer?
    private var notifiedEventIDs: Set<String> = []

    func start() {
        checkTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForMeetingStart()
            }
        }
        checkForMeetingStart()
    }

    func stop() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    private func checkForMeetingStart() {
        let now = Date()
        let store = CalendarService.shared

        let windowEnd = Calendar.current.date(byAdding: .minute, value: 1, to: now) ?? now

        let predicate = store.predicateForEvents(
            withStart: now,
            end: windowEnd,
            calendars: nil
        )

        let upcomingEvents = store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .filter { event in
                let timeUntilStart = event.startDate.timeIntervalSince(now)
                return timeUntilStart >= -30 && timeUntilStart <= 60
            }

        for event in upcomingEvents {
            let eventID = event.eventIdentifier ?? event.title ?? UUID().uuidString
            guard !notifiedEventIDs.contains(eventID) else { continue }

            notifiedEventIDs.insert(eventID)
            sendNotification(title: "Meeting Starting", body: "\(event.title ?? "Meeting") — Start recording?")

            let idToClean = eventID
            DispatchQueue.main.asyncAfter(deadline: .now() + 7200) { [weak self] in
                self?.notifiedEventIDs.remove(idToClean)
            }
        }
    }

    private func sendNotification(title: String, body: String) {
        let script = "display notification \"\(body)\" with title \"\(title)\" sound name \"default\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }
}
