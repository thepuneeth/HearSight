import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: WalkthroughViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage("elevenLabsAPIKey") private var elevenLabsAPIKey = ""
    @AppStorage("elevenLabsVoiceID") private var elevenLabsVoiceID = ""
    @AppStorage("offlineDemoMode") private var offlineDemoMode = false

    @State private var showAPIKey = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: $offlineDemoMode) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Offline demo mode")
                                .font(.body.weight(.semibold))
                            Text("Loads a pre-baked route at National Harbor, MD with no backend, network, or API needed.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityHint("When on, Preview Arrival loads the offline demo route instead of contacting the server.")
                } header: {
                    Text("Demo")
                } footer: {
                    Text("Use this for a guaranteed demo: Gaylord National Resort to Rosa Mexicano. Turn off to use real destinations from the server.")
                }

                Section {
                    VStack(alignment: .leading, spacing: HearSightTheme.Spacing.xs) {
                        Text("API Key")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        HStack {
                            Group {
                                if showAPIKey {
                                    TextField("Paste ElevenLabs API key", text: $elevenLabsAPIKey)
                                } else {
                                    SecureField("Paste ElevenLabs API key", text: $elevenLabsAPIKey)
                                }
                            }
                            .font(.body)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                            Button {
                                showAPIKey.toggle()
                            } label: {
                                Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }

                        if !elevenLabsAPIKey.isEmpty {
                            if viewModel.elevenLabsStatus.isEmpty {
                                Label("Key saved — speak a cue to test", systemImage: "checkmark.circle.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.green)
                            } else {
                                Label(viewModel.elevenLabsStatus, systemImage: viewModel.elevenLabsStatus.contains("OK") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(viewModel.elevenLabsStatus.contains("OK") ? Color.green : Color.orange)
                            }
                        }
                    }
                    .padding(.vertical, HearSightTheme.Spacing.xs)

                    VStack(alignment: .leading, spacing: HearSightTheme.Spacing.xs) {
                        Text("Voice ID")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        TextField("21m00Tcm4TlvDq8ikWAM", text: $elevenLabsVoiceID)
                            .font(.body)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Text("Leave blank to use the default Rachel voice.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, HearSightTheme.Spacing.xs)
                } header: {
                    Text("ElevenLabs Voice")
                } footer: {
                    Text("When a key is set, guidance cues use ElevenLabs for higher-quality speech. Short UI prompts always use the system voice. If the key is wrong or the network fails, guidance falls back to the system voice automatically.")
                }

                if !elevenLabsAPIKey.isEmpty {
                    Section {
                        Button(role: .destructive) {
                            elevenLabsAPIKey = ""
                            elevenLabsVoiceID = ""
                        } label: {
                            Label("Remove ElevenLabs Key", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    SettingsView(viewModel: WalkthroughViewModel())
}
