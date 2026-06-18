import Foundation

/// Detects one-sided recordings in either direction: if one channel keeps
/// transcribing but the other produces nothing for `threshold`, that channel's
/// capture is broken — wrong input device, muted hardware, or (commonly) a
/// missing system-audio permission. Tell the user now instead of after the
/// meeting, when half the conversation is already lost.
@MainActor
final class ChannelWatchdog {
    private var lastMe = Date()
    private var lastThem = Date()
    private var timer: Timer?
    private var micNotified = false
    private var systemNotified = false

    let threshold: TimeInterval = 5 * 60

    func start(recordingStart: Date) {
        lastMe = recordingStart
        lastThem = recordingStart
        micNotified = false
        systemNotified = false
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.check()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func segmentArrived(speaker: TranscriptSegment.Speaker) {
        switch speaker {
        case .me:
            lastMe = Date()
            if micNotified {
                micNotified = false
                Notifier.send(title: "Mic Is Back", body: "Your side is being transcribed again.")
            }
        case .them:
            lastThem = Date()
            if systemNotified {
                systemNotified = false
                Notifier.send(title: "System Audio Is Back", body: "The other side is being transcribed again.")
            }
        }
    }

    private func check() {
        let now = Date()
        let mins = Int(threshold / 60)

        // The other side is alive but our mic is silent → mic capture is broken.
        if now.timeIntervalSince(lastThem) < 60,
           now.timeIntervalSince(lastMe) >= threshold,
           !micNotified {
            micNotified = true
            Notifier.send(
                title: "One-Sided Recording?",
                body: "The other side is transcribing, but your mic hasn't produced anything for \(mins) minutes."
            )
        }

        // Our mic is alive but the other side is silent → system-audio capture
        // is broken. Most often a missing "Screen & System Audio Recording"
        // permission (e.g. after an app update changed its signature).
        if now.timeIntervalSince(lastMe) < 60,
           now.timeIntervalSince(lastThem) >= threshold,
           !systemNotified {
            systemNotified = true
            Notifier.send(
                title: "Only Recording You?",
                body: "Your side is transcribing, but the other side hasn't been captured for \(mins) minutes. Check System Settings → Privacy & Security → Screen & System Audio Recording."
            )
        }
    }
}
