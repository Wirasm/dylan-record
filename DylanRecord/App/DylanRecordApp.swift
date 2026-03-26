import SwiftUI

@main
struct DylanRecordApp: App {
    @State private var appState = AppState()
    @State private var meetingWatcher = MeetingWatcher()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appState)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: appState.isRecording ? "record.circle.fill" : "record.circle")
                    .symbolRenderingMode(.multicolor)
                if appState.isRecording {
                    Text(appState.formatElapsedTime())
                        .monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(appState)
        }
    }

    init() {
        DispatchQueue.main.async { [appState, meetingWatcher] in
            appState.setupHotkey()
            Task {
                let service = CalendarService()
                let granted = await service.requestAccess()
                if granted {
                    meetingWatcher.start()
                }
            }
        }
    }
}
