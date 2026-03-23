import SwiftUI

struct SavePopover: View {
    @Environment(AppState.self) private var appState
    @State private var meetingName: String
    let suggestedName: String?
    let onSave: (String) -> Void
    let onDiscard: () -> Void

    init(
        suggestedName: String?,
        onSave: @escaping (String) -> Void,
        onDiscard: @escaping () -> Void
    ) {
        self.suggestedName = suggestedName
        self.onSave = onSave
        self.onDiscard = onDiscard
        self._meetingName = State(initialValue: suggestedName ?? "Untitled Meeting")
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Save Transcript")
                .font(.headline)

            TextField("Meeting name", text: $meetingName)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    save()
                }

            HStack {
                Button("Discard") {
                    onDiscard()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(meetingName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
    }

    private func save() {
        let name = meetingName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        onSave(name)
    }
}
