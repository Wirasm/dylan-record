import Foundation

/// Posts user notifications via osascript — UNUserNotificationCenter crashes
/// in this app (see git history).
enum Notifier {
    static func send(title: String, body: String) {
        let script = "display notification \"\(escape(body))\" with title \"\(escape(title))\" sound name \"default\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        do {
            try process.run()
        } catch {
            print("[Notifier] Failed to post notification: \(error)")
        }
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
