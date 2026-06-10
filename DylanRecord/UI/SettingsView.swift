import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        Form {
            Section("Deepgram") {
                SecureField("API Key", text: $state.deepgramApiKey)
                    .textFieldStyle(.roundedBorder)
            }

            Section("AI Summary") {
                SecureField("Anthropic API Key", text: $state.anthropicApiKey)
                    .textFieldStyle(.roundedBorder)
                Text("Adds a summary, decisions, and action items to saved transcripts. Leave empty to disable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $state.launchAtLogin)
            }

            Section("Obsidian") {
                HStack {
                    TextField("Vault Path", text: $state.obsidianVaultPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse...") {
                        pickFolder()
                    }
                }
                if !appState.obsidianVaultPath.isEmpty {
                    let exists = FileManager.default.fileExists(atPath: appState.obsidianVaultPath)
                    Label(
                        exists ? "Vault found" : "Path not found",
                        systemImage: exists ? "checkmark.circle" : "xmark.circle"
                    )
                    .foregroundStyle(exists ? .green : .red)
                    .font(.caption)
                }
            }

            Section("Keywords") {
                Text("One per line. Boosts recognition of these terms.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $state.keywordsText)
                    .font(.body.monospaced())
                    .frame(height: 150)
                    .border(Color.secondary.opacity(0.3))
            }

            Section("Hotkeys") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("⌘⇧R — Start / stop recording")
                    Text("⌘⇧1 — Set language to Svenska")
                    Text("⌘⇧2 — Set language to English")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 500)
        .navigationTitle("Dylan Record Settings")
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select your Obsidian vault folder"

        if panel.runModal() == .OK, let url = panel.url {
            appState.obsidianVaultPath = url.path(percentEncoded: false)
        }
    }
}
