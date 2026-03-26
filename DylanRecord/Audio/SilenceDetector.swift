import Foundation
import UserNotifications

@MainActor
final class SilenceDetector {
    private var lastSpeechDate: Date = Date()
    private var checkTimer: Timer?
    private var hasNotified = false
    private var calendarEndDate: Date?

    // Config
    let nudgeAfter: TimeInterval = 5 * 60       // 5 min silence → notification
    let autoStopAfter: TimeInterval = 10 * 60   // 10 min silence → auto-stop
    let maxDuration: TimeInterval = 3 * 60 * 60 // 3 hour hard cap
    let calendarGrace: TimeInterval = 5 * 60    // 5 min after calendar end + silence → auto-stop

    var onShouldAutoStop: (() -> Void)?

    private var recordingStartDate: Date?

    func start(recordingStart: Date, calendarEndDate: Date?) {
        self.recordingStartDate = recordingStart
        self.calendarEndDate = calendarEndDate
        self.lastSpeechDate = recordingStart
        self.hasNotified = false

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

    /// Call this whenever speech is detected (a non-empty transcript arrives)
    func speechDetected() {
        lastSpeechDate = Date()
        hasNotified = false
    }

    private func check() {
        let now = Date()
        let silenceDuration = now.timeIntervalSince(lastSpeechDate)
        let totalDuration = now.timeIntervalSince(recordingStartDate ?? now)

        // Hard cap on duration
        if totalDuration >= maxDuration {
            print("[SilenceDetector] Max duration reached (\(Int(maxDuration / 60)) min), auto-stopping")
            onShouldAutoStop?()
            return
        }

        // Calendar-aware: if past meeting end time + grace period and silent
        if let calEnd = calendarEndDate,
           now > calEnd.addingTimeInterval(calendarGrace),
           silenceDuration > 60 {
            print("[SilenceDetector] Past calendar end + grace + silent, auto-stopping")
            onShouldAutoStop?()
            return
        }

        // Auto-stop after extended silence
        if silenceDuration >= autoStopAfter {
            print("[SilenceDetector] \(Int(autoStopAfter / 60)) min silence, auto-stopping")
            onShouldAutoStop?()
            return
        }

        // Nudge notification after shorter silence
        if silenceDuration >= nudgeAfter && !hasNotified {
            hasNotified = true
            sendNudgeNotification()
        }
    }

    private func sendNudgeNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Dylan Record"
        content.body = "Still recording — no speech detected for 5 minutes. Forgot to stop?"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "silence-nudge",
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
