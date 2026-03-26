import Foundation
import UserNotifications

@MainActor
final class SilenceDetector {
    private var lastSpeechDate: Date = Date()
    private var checkTimer: Timer?
    private var hasNudged = false
    private var calendarEndDate: Date?

    // Config
    let nudgeAfter: TimeInterval = 3 * 60       // 3 min silence → notification
    let autoStopAfter: TimeInterval = 10 * 60   // 10 min silence → auto-stop
    let maxDuration: TimeInterval = 3 * 60 * 60 // 3 hour hard cap
    let calendarGrace: TimeInterval = 5 * 60    // 5 min after calendar end + silence → auto-stop

    var onShouldAutoStop: ((String) -> Void)?

    private var recordingStartDate: Date?

    func start(recordingStart: Date, calendarEndDate: Date?) {
        self.recordingStartDate = recordingStart
        self.calendarEndDate = calendarEndDate
        self.lastSpeechDate = recordingStart
        self.hasNudged = false

        requestNotificationPermission()

        checkTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.check()
            }
        }
    }

    func stop() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    func speechDetected() {
        lastSpeechDate = Date()
        hasNudged = false
    }

    private func check() {
        let now = Date()
        let silenceDuration = now.timeIntervalSince(lastSpeechDate)
        let totalDuration = now.timeIntervalSince(recordingStartDate ?? now)

        // Hard cap on duration
        if totalDuration >= maxDuration {
            let reason = "Recording auto-stopped: reached \(Int(maxDuration / 3600)) hour limit."
            sendNotification(title: "Recording Stopped", body: reason)
            onShouldAutoStop?(reason)
            return
        }

        // Calendar-aware: if past meeting end time + grace period and silent
        if let calEnd = calendarEndDate,
           now > calEnd.addingTimeInterval(calendarGrace),
           silenceDuration > 60 {
            let reason = "Recording auto-stopped: calendar event ended and no speech detected."
            sendNotification(title: "Recording Stopped", body: reason)
            onShouldAutoStop?(reason)
            return
        }

        // Auto-stop after 10 min silence
        if silenceDuration >= autoStopAfter {
            let mins = Int(autoStopAfter / 60)
            let reason = "Recording auto-stopped: \(mins) minutes of silence."
            sendNotification(title: "Recording Stopped", body: reason)
            onShouldAutoStop?(reason)
            return
        }

        // Nudge notification after 3 min silence
        if silenceDuration >= nudgeAfter && !hasNudged {
            hasNudged = true
            let mins = Int(silenceDuration / 60)
            sendNotification(
                title: "Still Recording",
                body: "No speech detected for \(mins) minutes. Forgot to stop?"
            )
        }
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "dylanrecord-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[SilenceDetector] Notification error: \(error)")
            }
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error {
                print("[SilenceDetector] Notification permission error: \(error)")
            }
        }
    }
}
