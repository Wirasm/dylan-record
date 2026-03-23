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

            Section("Hotkey") {
                Text("⌘⇧R to start/stop recording")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 280)
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
