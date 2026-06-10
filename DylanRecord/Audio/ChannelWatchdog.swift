import Foundation

/// Detects one-sided recordings: if the other side keeps transcribing but our
/// mic channel produces nothing for `threshold`, something is wrong with mic
/// capture (wrong input device, muted hardware, a bug) — tell the user now
/// instead of after the meeting.
@MainActor
final class ChannelWatchdog {
    private var lastMe = Date()
    private var lastThem = Date()
    private var timer: Timer?
    private var notified = false

    let threshold: TimeInterval = 5 * 60

    func start(recordingStart: Date) {
        lastMe = recordingStart
        lastThem = recordingStart
        notified = false
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
            if notified {
                notified = false
                Notifier.send(title: "Mic Is Back", body: "Your side is being transcribed again.")
            }
        case .them:
            lastThem = Date()
        }
    }

    private func check() {
        let now = Date()
        // Only alarm when the other side is alive but our mic is silent —
        // mutual silence is just a quiet meeting.
        guard now.timeIntervalSince(lastThem) < 60,
              now.timeIntervalSince(lastMe) >= threshold,
              !notified else { return }

        notified = true
        Notifier.send(
            title: "One-Sided Recording?",
            body: "The other side is transcribing, but your mic hasn't produced anything for \(Int(threshold / 60)) minutes."
        )
    }
}
