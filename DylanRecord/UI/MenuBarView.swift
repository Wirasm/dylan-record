import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @State private var suggestedName: String?

    var body: some View {
        VStack(spacing: 12) {
            if appState.isSaving {
                SavePopover(
                    suggestedName: suggestedName,
                    onSave: { name in
                        saveTranscript(name: name)
                    },
                    onDiscard: {
                        appState.discardRecording()
                    }
                )
                .environment(appState)
            } else if appState.isRecording {
                recordingView
            } else {
                idleView
            }
        }
        .padding()
        .frame(width: 300)
    }

    private var idleView: some View {
        @Bindable var state = appState

        return VStack(spacing: 8) {
            Text("Dylan Record")
                .font(.headline)

            if let error = appState.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            if appState.deepgramApiKey.isEmpty {
                Label("Set API key in Settings", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }

            if appState.obsidianVaultPath.isEmpty {
                Label("Set vault path in Settings", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }

            Divider()

            // Language picker — prominent in main UI
            Picker("Language", selection: $state.language) {
                ForEach(AppState.supportedLanguages, id: \.code) { lang in
                    Text(lang.name).tag(lang.code)
                }
            }
            .pickerStyle(.menu)

            // Language hotkey hints
            Text("⌘⇧1 Svenska  ·  ⌘⇧2 English")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Divider()

            Button("Start Recording  ⌘⇧R") {
                appState.startRecording()
            }
            .disabled(appState.deepgramApiKey.isEmpty)

            Divider()

            HStack {
                SettingsLink {
                    Text("Settings...")
                }
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .font(.caption)
        }
    }

    private var recordingView: some View {
        VStack(spacing: 8) {
            HStack {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                Text("Recording")
                    .font(.headline)
                Spacer()
                Text(appState.formatElapsedTime())
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            let langName = AppState.supportedLanguages.first { $0.code == appState.language }?.name ?? appState.language
            Text(langName)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let error = appState.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }

            Text("\(appState.transcriptManager.segments.count) segments")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Stop Recording  ⌘⇧R") {
                let calendar = CalendarService()
                suggestedName = calendar.currentMeetingTitle()
                appState.stopRecording()
            }
        }
    }

    private func saveTranscript(name: String) {
        let vaultPath = appState.obsidianVaultPath
        guard !vaultPath.isEmpty else {
            appState.lastError = "Set vault path in Settings."
            appState.finishSaving()
            return
        }

        let exporter = MarkdownExporter()
        do {
            let filePath = try exporter.export(
                segments: appState.transcriptManager.segments,
                meetingName: name,
                startDate: appState.recordingStartDate ?? Date(),
                duration: appState.elapsedTime,
                vaultPath: vaultPath,
                calendarEvent: nil
            )
            print("[MenuBarView] Saved to: \(filePath)")
        } catch {
            appState.lastError = "Save failed: \(error.localizedDescription)"
        }

        appState.finishSaving()
    }
}
