import SwiftUI

struct CleanHomeView: View {
    @ObservedObject var viewModel: WalkthroughViewModel
    let onPreview: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isDestinationFocused: Bool
    @State private var validationMessage: String?
    @State private var isManualLocationEditorPresented = false
    @State private var manualLocationMessage: String?

    var body: some View {
        CleanStickyBottomContainer(contentBottomPadding: 132) {
            VStack(spacing: HearSightTheme.Spacing.lg) {
                CleanScreenHeader(
                    title: "HearSight",
                    subtitle: "Preview the final approach before you leave.",
                    alignment: .center
                )

                currentLocationCard

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

                if let manualLocationMessage {
                    Text(manualLocationMessage)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(HearSightTheme.current(for: colorScheme).warning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(manualLocationMessage)
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
        .sheet(isPresented: $isManualLocationEditorPresented) {
            ManualCurrentLocationSheet(
                viewModel: viewModel,
                manualLocationMessage: $manualLocationMessage,
                onDone: {
                    isManualLocationEditorPresented = false
                }
            )
        }
    }

    private var currentLocationCard: some View {
        CleanCard(title: "Current location", systemImage: viewModel.currentLocationSystemImage) {
            VStack(alignment: .leading, spacing: HearSightTheme.Spacing.xs) {
                Text(viewModel.currentLocationTitle)
                    .font(.body.weight(.bold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(viewModel.currentLocationDetail)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .highPriorityGesture(
            TapGesture(count: 3)
                .onEnded {
                    prepareManualLocationEditor()
                }
        )
        .accessibilityLabel("Current location. \(viewModel.currentLocationTitle). \(viewModel.currentLocationDetail)")
        .accessibilityHint("Triple tap to change the current location.")
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

    private func prepareManualLocationEditor() {
        if viewModel.manualCurrentLocationQuery.isEmpty {
            viewModel.manualCurrentLocationQuery = viewModel.isUsingManualCurrentLocation ? viewModel.currentLocationTitle : ""
        }
        manualLocationMessage = nil
        isManualLocationEditorPresented = true
    }
}

private struct ManualCurrentLocationSheet: View {
    @ObservedObject var viewModel: WalkthroughViewModel
    @Binding var manualLocationMessage: String?
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isLocationFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: HearSightTheme.Spacing.lg) {
                CleanScreenHeader(
                    title: "Current Location",
                    subtitle: "Type or speak where you want the route to start.",
                    alignment: .leading
                )

                Button {
                    viewModel.toggleCurrentLocationVoiceInput()
                } label: {
                    Label(
                        viewModel.isListeningForCurrentLocation ? "Listening" : "Speak current location",
                        systemImage: viewModel.isListeningForCurrentLocation ? "waveform" : "mic.fill"
                    )
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 58)
                    .background(HearSightTheme.primary(colorScheme))
                    .clipShape(RoundedRectangle(cornerRadius: HearSightTheme.Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityHint(viewModel.isListeningForCurrentLocation ? "Stops listening." : "Starts listening for your current location.")

                CleanCard {
                    VStack(alignment: .leading, spacing: HearSightTheme.Spacing.sm) {
                        Text("Current location")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        TextField("Type current location", text: $viewModel.manualCurrentLocationQuery)
                            .font(.system(.title2, design: .rounded).weight(.semibold))
                            .textFieldStyle(.plain)
                            .textContentType(.fullStreetAddress)
                            .submitLabel(.done)
                            .focused($isLocationFocused)
                            .padding(.horizontal, HearSightTheme.Spacing.md)
                            .frame(minHeight: 60)
                            .background(HearSightTheme.insetPanel(colorScheme))
                            .clipShape(RoundedRectangle(cornerRadius: HearSightTheme.Radius.md, style: .continuous))
                            .onSubmit {
                                setLocation()
                            }
                            .accessibilityLabel("Current location")
                    }
                }

                if let manualLocationMessage {
                    Text(manualLocationMessage)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(HearSightTheme.current(for: colorScheme).warning)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                CleanPrimaryButton(
                    title: "Set Location",
                    systemImage: "location.fill",
                    accessibilityHint: "Uses this typed or spoken place as the current location."
                ) {
                    setLocation()
                }

                CleanSecondaryButton(
                    title: "Use Live GPS",
                    systemImage: "location.north.line.fill",
                    accessibilityHint: "Returns to the device current location."
                ) {
                    manualLocationMessage = nil
                    viewModel.stopCurrentLocationListening()
                    viewModel.resumeLiveCurrentLocation()
                    dismiss()
                    onDone()
                }
            }
            .padding(HearSightTheme.Spacing.lg)
            .navigationTitle("Change Current Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        viewModel.stopCurrentLocationListening()
                        dismiss()
                        onDone()
                    }
                }
            }
            .onAppear {
                isLocationFocused = true
            }
            .onDisappear {
                viewModel.stopCurrentLocationListening()
            }
        }
    }

    private func setLocation() {
        let query = viewModel.manualCurrentLocationQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            manualLocationMessage = "Type or speak a current location first."
            viewModel.statusMessage = "Type or speak a current location first."
            return
        }

        manualLocationMessage = nil
        viewModel.stopCurrentLocationListening(confirm: true)
        viewModel.setManualCurrentLocation(from: query)
        dismiss()
        onDone()
    }
}

#Preview {
    CleanHomeView(viewModel: WalkthroughViewModel()) {}
}
