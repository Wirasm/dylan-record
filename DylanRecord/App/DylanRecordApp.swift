import SwiftUI

@main
struct DylanRecordApp: App {
    @State private var appState = AppState()

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
        // Delay hotkey setup to after app is fully initialized
        DispatchQueue.main.async { [appState] in
            appState.setupHotkey()
        }
    }
}
