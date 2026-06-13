import SwiftUI

struct CleanHomeView: View {
    @ObservedObject var viewModel: WalkthroughViewModel
    let onPreview: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                            .scaleEffect((!reduceMotion && viewModel.voiceInputState.isListening) ? 1.06 : 1)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: viewModel.voiceInputState.isListening)

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
                .accessibilityLabel("Microphone")
                .accessibilityValue(viewModel.voiceInputState.title)
                .accessibilityHint(viewModel.voiceInputState.isListening ? "Double tap to stop listening." : "Double tap to start listening and speak your destination.")

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
                                viewModel.speakDestinationEnteredIfNeeded()
                                previewArrival()
                            }
                            .accessibilityLabel("Destination")
                            .accessibilityHint("Enter the place you are visiting.")
                    }
                }

                visitTypeSelector

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
                accessibilityLabel: "Preview Arrival",
                accessibilityHint: "Creates a short pre-trip arrival briefing."
            ) {
                previewArrival()
            }
            .disabled(viewModel.isGenerating)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            viewModel.toggleDestinationVoiceInput()
        }
        .onAppear {
            viewModel.speakHomeIntroIfNeeded()
        }
        .onChange(of: isDestinationFocused) { oldValue, newValue in
            if oldValue && !newValue {
                viewModel.speakDestinationEnteredIfNeeded()
            }
        }
    }

    private var visitTypeSelector: some View {
        HStack(spacing: HearSightTheme.Spacing.sm) {
            visitTypeButton(
                title: "First Visit",
                isSelected: viewModel.isFirstVisit,
                accessibilityHint: "Selects first visit mode."
            ) {
                selectFirstVisit(true)
            }

            visitTypeButton(
                title: "Familiar Route",
                isSelected: !viewModel.isFirstVisit,
                accessibilityHint: "Selects familiar route mode."
            ) {
                selectFirstVisit(false)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func visitTypeButton(
        title: String,
        isSelected: Bool,
        accessibilityHint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.bold))
                .foregroundStyle(isSelected ? .white : HearSightTheme.primary(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 54)
                .background(isSelected ? HearSightTheme.primary(colorScheme) : HearSightTheme.insetPanel(colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: HearSightTheme.Radius.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: HearSightTheme.Radius.md, style: .continuous)
                        .stroke(HearSightTheme.cardStroke(colorScheme), lineWidth: isSelected ? 0 : 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(accessibilityHint)
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
        viewModel.speakDestinationEnteredIfNeeded()
        onPreview()
    }

    private func selectFirstVisit(_ isFirstVisit: Bool) {
        viewModel.isFirstVisit = isFirstVisit
        if isFirstVisit {
            viewModel.speakAccessibilityPrompt("First Visit selected. HearSight will generate an arrival preview for this destination.")
        } else {
            viewModel.speakAccessibilityPrompt("Familiar Route selected. HearSight will use saved arrival notes if available.")
        }
    }
}

#Preview {
    CleanHomeView(viewModel: WalkthroughViewModel()) {}
}
