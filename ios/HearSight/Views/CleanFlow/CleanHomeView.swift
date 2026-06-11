import SwiftUI

struct CleanHomeView: View {
    @ObservedObject var viewModel: WalkthroughViewModel
    let onPreview: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isDestinationFocused: Bool
    @State private var validationMessage: String?

    var body: some View {
        CleanStickyBottomContainer(contentBottomPadding: 132) {
            VStack(spacing: HearSightTheme.Spacing.lg) {
                CleanScreenHeader(
                    title: "HearSight",
                    subtitle: "Preview the final approach before you leave.",
                    alignment: .center
                )

                Button {
                    viewModel.toggleDestinationVoiceInput()
                } label: {
                    ZStack {
                        Circle()
                            .fill(HearSightTheme.primary(colorScheme).opacity(viewModel.voiceInputState.isListening ? 0.24 : 0.14))
                            .frame(width: 176, height: 176)
                            .scaleEffect(viewModel.voiceInputState.isListening ? 1.06 : 1)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: viewModel.voiceInputState.isListening)

                        Circle()
                            .fill(HearSightTheme.primary(colorScheme))
                            .frame(width: 132, height: 132)
                            .shadow(color: HearSightTheme.glow(colorScheme), radius: 24, x: 0, y: 10)

                        Image(systemName: viewModel.voiceInputState.isListening ? "waveform" : "mic.fill")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Speak destination")
                .accessibilityValue(viewModel.voiceInputState.title)
                .accessibilityHint(viewModel.voiceInputState.isListening ? "Stops listening for your destination." : "Starts listening so you can speak a destination.")

                CleanCard {
                    VStack(alignment: .leading, spacing: HearSightTheme.Spacing.sm) {
                        Text("Destination")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        TextField("Type destination", text: $viewModel.destinationQuery)
                            .font(.system(.title2, design: .rounded).weight(.semibold))
                            .textFieldStyle(.plain)
                            .textContentType(.fullStreetAddress)
                            .submitLabel(.go)
                            .focused($isDestinationFocused)
                            .padding(.horizontal, HearSightTheme.Spacing.md)
                            .frame(minHeight: 60)
                            .background(HearSightTheme.insetPanel(colorScheme))
                            .clipShape(RoundedRectangle(cornerRadius: HearSightTheme.Radius.md, style: .continuous))
                            .onSubmit {
                                previewArrival()
                            }
                            .accessibilityLabel("Destination")
                            .accessibilityHint("Enter the place you are visiting.")
                    }
                }

                Picker("Visit type", selection: $viewModel.isFirstVisit) {
                    Text("First Visit").tag(true)
                    Text("Familiar Route").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(minHeight: 52)
                .accessibilityLabel("Visit type")
                .accessibilityHint("Choose whether this is your first visit or a familiar route.")

                if let validationMessage {
                    Text(validationMessage)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(HearSightTheme.current(for: colorScheme).warning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(validationMessage)
                }
            }
            .frame(maxWidth: .infinity)
        } bottomAction: {
            CleanPrimaryButton(
                title: viewModel.isGenerating ? "Preparing Arrival" : "Preview Arrival",
                systemImage: "play.circle.fill",
                accessibilityHint: "Creates a short pre-trip arrival briefing."
            ) {
                previewArrival()
            }
            .disabled(viewModel.isGenerating)
        }
    }

    private func previewArrival() {
        let destination = viewModel.destinationQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !destination.isEmpty else {
            validationMessage = "Enter a destination to preview the arrival."
            viewModel.statusMessage = "Enter a destination to preview the arrival."
            return
        }

        validationMessage = nil
        isDestinationFocused = false
        viewModel.destinationQuery = destination
        onPreview()
    }
}

#Preview {
    CleanHomeView(viewModel: WalkthroughViewModel()) {}
}
