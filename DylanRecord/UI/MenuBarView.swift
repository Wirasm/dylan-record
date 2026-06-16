import SwiftUI
import AppKit

struct MenuBarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 12) {
            if appState.isSaving {
                SavePopover(
                    suggestedName: appState.suggestedMeetingName,
                    onSave: { name in
                        appState.saveTranscript(name: name)
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

            // Next meeting
            if let meeting = appState.nextMeeting {
                Divider()
                nextMeetingView(meeting)
            }

            Divider()

            // Language picker
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

            liveTranscriptView

            Text("\(appState.transcriptManager.segments.count) segments")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Stop Recording  ⌘⇧R") {
                appState.stopRecording()
            }
        }
    }

    private var liveTranscriptView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Live transcript")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button {
                    copyTranscript()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .disabled(appState.transcriptManager.segments.isEmpty)
                .help("Copy the full transcript to the clipboard")
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        if appState.transcriptManager.segments.isEmpty {
                            Text("Waiting for speech…")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        ForEach(appState.transcriptManager.segments) { segment in
                            (Text("\(segment.speaker.rawValue): ")
                                .bold()
                                .foregroundStyle(segment.speaker == .me ? Color.accentColor : Color.secondary)
                                + Text(segment.text))
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .id(segment.id)
                        }
                    }
                    .padding(6)
                }
                .frame(height: 200)
                .background(.quaternary.opacity(0.3))
                .cornerRadius(6)
                .onChange(of: appState.transcriptManager.segments.count) {
                    if let last = appState.transcriptManager.segments.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .onAppear {
                    if let last = appState.transcriptManager.segments.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func copyTranscript() {
        let text = appState.transcriptManager.formattedTranscript()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func nextMeetingView(_ meeting: CalendarService.UpcomingMeeting) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Next meeting")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(meeting.title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(timeUntilString(meeting.startDate))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.5))
        .cornerRadius(6)
    }

    private func timeUntilString(_ date: Date) -> String {
        let now = Date()
        let interval = date.timeIntervalSince(now)

        if interval <= 0 {
            return "Now"
        } else if interval < 60 {
            return "In less than a minute"
        } else if interval < 3600 {
            let mins = Int(interval / 60)
            return "In \(mins) min"
        } else {
            let hours = Int(interval / 3600)
            let mins = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
            let df = DateFormatter()
            df.dateFormat = "HH:mm"
            return "At \(df.string(from: date)) (\(hours)h \(mins)m)"
        }
    }

}
