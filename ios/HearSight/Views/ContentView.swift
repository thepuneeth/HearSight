import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = WalkthroughViewModel()
    @FocusState private var isDestinationFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var theme: HearSightTheme {
        HearSightTheme.current(for: colorScheme)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if viewModel.walkthrough == nil {
                    warmDestinationEntry
                } else {
                    HearSightAmbientBackground()

                    VStack(spacing: 0) {
                        header

                        Group {
                            if viewModel.flowState == .previewing {
                                routePreview
                            } else {
                                guidanceSurface
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 22)
                    .padding(.bottom, 18)
                }
            }
            .tint(theme.accent)
            .navigationBarHidden(true)
            .onAppear {
                viewModel.requestLocationAccess()
                viewModel.checkBackend()
            }
            .alert("HearSight", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private var warmDestinationEntry: some View {
        ZStack {
            WarmDestinationBackground()

            VStack(spacing: 0) {
                warmTopAppBar

                VStack(spacing: 34) {
                    Spacer(minLength: 24)

                    warmInputPanel

                    Text(viewModel.speechRecognitionStatus)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(hex: 0x6E3900).opacity(0.82))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.84)
                        .accessibilityLabel(viewModel.speechRecognitionStatus)

                    Spacer(minLength: 150)
                }
                .padding(.horizontal, 24)
            }

            VStack {
                Spacer()
                warmBottomControls
            }
        }
    }

    private var warmTopAppBar: some View {
        HStack {
            Button {
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 21, weight: .semibold))
                    .frame(width: 64, height: 64)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(hex: 0x904D00))
            .accessibilityLabel("Menu")
            .accessibilityHint("Navigation menu placeholder.")

            Spacer()

            Text("HearSight")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: 0x904D00))
                .accessibilityAddTraits(.isHeader)

            Spacer()

            Button {
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 21, weight: .semibold))
                    .frame(width: 64, height: 64)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(hex: 0x904D00))
            .accessibilityLabel("Settings")
            .accessibilityHint("Settings placeholder.")
        }
        .frame(height: 72)
        .padding(.horizontal, 12)
        .background(.ultraThinMaterial)
        .background(Color(hex: 0xFBF9F8).opacity(0.78))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(hex: 0xDDC1AE).opacity(0.26))
                .frame(height: 1)
        }
        .shadow(color: Color(hex: 0x904D00).opacity(0.08), radius: 20, x: 0, y: 4)
    }

    private var warmInputPanel: some View {
        VStack(spacing: 18) {
            HStack(spacing: 14) {
                TextField("Where to?", text: $viewModel.destinationQuery)
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                    .textFieldStyle(.plain)
                    .textContentType(.fullStreetAddress)
                    .submitLabel(.go)
                    .focused($isDestinationFocused)
                    .foregroundStyle(Color(hex: 0x1B1C1C))
                    .onSubmit {
                        isDestinationFocused = false
                        viewModel.generateWalkthrough()
                    }
                    .accessibilityLabel("Destination")
                    .accessibilityHint("Type or edit your destination.")

                Image(systemName: "location.north.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color(hex: 0x904D00))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 28)
            .background(Color(hex: 0xF6F3F2).opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.72),
                                Color(hex: 0xDDC1AE).opacity(0.28)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color(hex: 0x904D00).opacity(0.08), radius: 32, x: 0, y: 16)

            HearSightPrimaryButton(
                title: viewModel.isGenerating ? "Getting Route" : "Confirm Destination",
                systemImage: "checkmark",
                accessibilityHint: "Creates a route preview for this destination."
            ) {
                isDestinationFocused = false
                viewModel.generateWalkthrough()
            }
            .disabled(viewModel.isGenerating)

            if viewModel.isListeningForDestination {
                QuietButton(
                    title: "Stop Listening",
                    systemImage: "stop.fill",
                    accessibilityHint: "Stops microphone input and keeps recognized destination text."
                ) {
                    viewModel.stopDestinationListening(confirm: true)
                }
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: 0xFF8C00).opacity(0.16),
                            Color(hex: 0xD6A21A).opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blur(radius: 1)
        )
        .accessibilityElement(children: .contain)
    }

    private var warmBottomControls: some View {
        ZStack(alignment: .bottom) {
            HStack {
                Button {
                } label: {
                    Image(systemName: "map.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .frame(width: 64, height: 64)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(hex: 0x623200))
                .background(Color(hex: 0xFF8C00))
                .clipShape(Circle())
                .scaleEffect(1.08)
                .accessibilityLabel("Map")
                .accessibilityHint("Current destination entry tab.")

                Spacer()
                    .frame(width: 84)

                Button {
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 22, weight: .semibold))
                        .frame(width: 64, height: 64)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(hex: 0x564334))
                .accessibilityLabel("Settings")
                .accessibilityHint("Settings placeholder.")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: 360)
            .background(.ultraThinMaterial)
            .background(Color(hex: 0xFFFFFF).opacity(0.86))
            .clipShape(Capsule())
            .shadow(color: Color(hex: 0x904D00).opacity(0.16), radius: 24, x: 0, y: 10)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)

            Button {
                viewModel.startDestinationListening()
            } label: {
                WarmFloatingMic(isListening: viewModel.isListeningForDestination)
            }
            .buttonStyle(.plain)
            .offset(y: -66)
            .accessibilityLabel(viewModel.isListeningForDestination ? "Listening" : "Speak destination")
            .accessibilityHint("Double tap to start spoken destination entry.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("HearSight")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(theme.primaryText)
                .accessibilityAddTraits(.isHeader)

            if !viewModel.destinationDisplayName.isEmpty {
                Text(viewModel.destinationDisplayName)
                    .font(.headline.weight(.medium))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .accessibilityLabel("Destination: \(viewModel.destinationDisplayName)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var destinationEntry: some View {
        VStack(spacing: 30) {
            Spacer(minLength: 24)

            Text("Speak a destination, or type it below.")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.primaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.82)

            VStack(spacing: 18) {
                Button {
                    viewModel.startDestinationListening()
                } label: {
                    HearSightOrbMicrophone(isListening: viewModel.isListeningForDestination)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(viewModel.isListeningForDestination ? "Listening" : "Speak destination")
                .accessibilityHint("Double tap to start spoken destination entry.")

                Text(viewModel.speechRecognitionStatus)
                    .font(.headline.weight(.medium))
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .accessibilityLabel(viewModel.speechRecognitionStatus)

                if viewModel.isListeningForDestination {
                    QuietButton(
                        title: "Stop Listening",
                        systemImage: "stop.fill",
                        accessibilityHint: "Stops microphone input and keeps recognized destination text."
                    ) {
                        viewModel.stopDestinationListening(confirm: true)
                    }
                }
            }

            TextField("Type destination", text: $viewModel.destinationQuery)
                .font(.title2.weight(.semibold))
                .textFieldStyle(.plain)
                .textContentType(.fullStreetAddress)
                .submitLabel(.go)
                .focused($isDestinationFocused)
                .padding(.horizontal, 18)
                .frame(height: 60)
                .background(theme.field)
                .foregroundStyle(theme.primaryText)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(theme.stroke, lineWidth: 1)
                )
                .onSubmit {
                    isDestinationFocused = false
                    viewModel.generateWalkthrough()
                }
                .accessibilityLabel("Destination text")
                .accessibilityHint("Type or edit the destination.")

            Spacer(minLength: 10)

            HearSightPrimaryButton(
                title: viewModel.isGenerating ? "Getting Route" : "Confirm",
                systemImage: "checkmark",
                accessibilityHint: "Creates a route preview for this destination."
            ) {
                isDestinationFocused = false
                viewModel.generateWalkthrough()
            }
            .disabled(viewModel.isGenerating)
        }
    }

    private var routePreview: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 10)

            if let stages = viewModel.walkthrough?.stages, !stages.isEmpty {
                TabView(selection: $viewModel.previewStageIndex) {
                    ForEach(stages) { stage in
                        PreviewStageCard(
                            stage: stage,
                            totalStages: stages.count,
                            hearCue: {
                                viewModel.hearPreviewCue(for: stage)
                            }
                        )
                        .tag(stage.index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .accessibilityLabel("Route preview")
                .accessibilityHint("Swipe left or right to preview each cue.")

                HearSightPrimaryButton(
                    title: "Start",
                    systemImage: "figure.walk",
                    accessibilityHint: "Prepares active guidance."
                ) {
                    viewModel.markReadyToStart()
                }
            }
        }
    }

    private var guidanceSurface: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 20)

            VStack(spacing: 18) {
                Image(systemName: guidanceIcon)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                    .accessibilityHidden(true)

                Text(viewModel.currentCueText)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.primaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(5)
                    .minimumScaleFactor(0.68)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Current cue: \(viewModel.currentCueText)")

                Text(guidanceStateText)
                    .font(.headline.weight(.medium))
                    .foregroundStyle(theme.secondaryText)
                    .accessibilityLabel(guidanceStateText)
            }
            .padding(.horizontal, 8)

            Spacer(minLength: 14)

            HearSightPrimaryButton(
                title: viewModel.primaryActionTitle,
                systemImage: primaryActionIcon,
                accessibilityHint: primaryActionHint
            ) {
                viewModel.handlePrimaryAction()
            }

            HStack(spacing: 12) {
                GuidanceButton(title: "Back", systemImage: "backward.fill", hint: "Hear the previous cue.") {
                    viewModel.speakPreviousStage()
                }

                GuidanceButton(title: "Hear", systemImage: "speaker.wave.2.fill", hint: "Repeat the current cue.") {
                    viewModel.repeatCurrentStage()
                }

                GuidanceButton(title: "Next", systemImage: "forward.fill", hint: "Hear the next cue.") {
                    viewModel.speakNextStage()
                }
            }

            if viewModel.flowState != .activeGuidance {
                QuietButton(
                    title: "New Destination",
                    systemImage: "plus",
                    accessibilityHint: "Clears this route and returns to destination entry."
                ) {
                    viewModel.resetRoute()
                }
            }
        }
    }

    private var guidanceStateText: String {
        switch viewModel.flowState {
        case .readyToStart:
            return "Ready"
        case .activeGuidance:
            return "Guidance active"
        case .paused:
            return "Paused"
        case .routeComplete:
            return "Complete"
        case .previewing:
            return "Preview"
        case .destinationEntry:
            return ""
        }
    }

    private var guidanceIcon: String {
        switch viewModel.flowState {
        case .paused:
            return "pause.circle"
        case .routeComplete:
            return "checkmark.circle"
        default:
            return "ear.and.waveform"
        }
    }

    private var primaryActionIcon: String {
        switch viewModel.flowState {
        case .activeGuidance:
            return "pause.fill"
        case .routeComplete:
            return "plus"
        default:
            return "play.fill"
        }
    }

    private var primaryActionHint: String {
        switch viewModel.flowState {
        case .activeGuidance:
            return "Pauses location-triggered cue playback."
        case .routeComplete:
            return "Starts a new destination."
        default:
            return "Starts guidance."
        }
    }
}

private struct QuietButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let systemImage: String
    let accessibilityHint: String
    let action: () -> Void

    var body: some View {
        let theme = HearSightTheme.current(for: colorScheme)

        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(theme.primaryText)
                .frame(minHeight: 48)
        }
        .buttonStyle(HearSightHapticButtonStyle())
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHint)
    }
}

private struct WarmDestinationBackground: View {
    var body: some View {
        ZStack {
            Color(hex: 0xFBF9F8)

            RadialGradient(
                colors: [
                    Color(hex: 0xFF8C00).opacity(0.18),
                    Color.clear
                ],
                center: .bottom,
                startRadius: 40,
                endRadius: 520
            )

            RadialGradient(
                colors: [
                    Color(hex: 0xF6BE39).opacity(0.16),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 360
            )
        }
        .ignoresSafeArea()
    }
}

private struct WarmFloatingMic: View {
    let isListening: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: 0xFF8C00).opacity(isListening ? 0.24 : 0.14))
                .frame(width: 118, height: 118)
                .scaleEffect(isListening ? 1.08 : 1)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: isListening)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: 0xFFD166),
                            Color(hex: 0xE76F51)
                        ],
                        center: .topLeading,
                        startRadius: 10,
                        endRadius: 92
                    )
                )
                .frame(width: 88, height: 88)
                .shadow(color: Color(hex: 0x904D00).opacity(0.34), radius: 28, x: 0, y: 12)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.42), lineWidth: 1)
                )

            Image(systemName: isListening ? "waveform" : "mic.fill")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
        }
        .accessibilityElement(children: .ignore)
    }
}

private struct PreviewStageCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let stage: RouteStage
    let totalStages: Int
    let hearCue: () -> Void

    var body: some View {
        let theme = HearSightTheme.current(for: colorScheme)

        VStack(spacing: 22) {
            Spacer(minLength: 10)

            Text(stageTitle)
                .font(.headline.weight(.medium))
                .foregroundStyle(theme.secondaryText)

           Text(stage.description.spokenCue)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.primaryText)
                .multilineTextAlignment(.center)
                .lineLimit(5)
                .minimumScaleFactor(0.68)
                .accessibilityLabel(stage.description.spokenCue)

            if !landmarkText.isEmpty {
                Label(landmarkText, systemImage: "mappin.and.ellipse")
                    .font(.headline.weight(.medium))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .accessibilityLabel("Nearby landmark: \(landmarkText)")
            }

            QuietButton(
                title: "Hear Cue",
                systemImage: "speaker.wave.2.fill",
                accessibilityHint: "Speaks this preview cue.",
                action: hearCue
            )

            Spacer(minLength: 10)
        }
        .padding(.horizontal, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(stageTitle). \(stage.description.spokenCue). \(landmarkText)")
    }

    private var stageTitle: String {
        if stage.kind == .destination {
            return "Destination"
        }
        return "Cue \(stage.index + 1) of \(totalStages)"
    }

    private var landmarkText: String {
        if let landmark = stage.description.landmarks.first, !landmark.isEmpty {
            return landmark
        }
        if let landmark = stage.context?.nearbyLandmarks.first, !landmark.isEmpty {
            return landmark
        }
        if let intersection = stage.context?.nearestIntersection, !intersection.isEmpty {
            return intersection
        }
        if let street = stage.context?.streetName, !street.isEmpty {
            return street
        }
        return ""
    }
}

private struct GuidanceButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let systemImage: String
    let hint: String
    let action: () -> Void

    var body: some View {
        let theme = HearSightTheme.current(for: colorScheme)

        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.bold))
                Text(title)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
            }
            .foregroundStyle(theme.primaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 68)
            .background(.ultraThinMaterial)
            .background(theme.surfaceGlass)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(HearSightHapticButtonStyle())
        .accessibilityLabel(title)
        .accessibilityHint(hint)
    }
}

#Preview {
    ContentView()
}
