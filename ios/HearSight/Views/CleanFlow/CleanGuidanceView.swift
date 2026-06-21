import SwiftUI

struct CleanGuidanceView: View {
    @ObservedObject var viewModel: WalkthroughViewModel
    let onArrival: () -> Void

    @State private var cleanCueIndex = 0
    @State private var feedbackMessage: String?
    @State private var didSpeakInitialCue = false
    @State private var isPaused = false
    @State private var showingSettings = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let data = CleanFlowBriefing.resolved(from: viewModel)
        let approaching = viewModel.guidancePhaseLabel != "En route"
        let cues = cleanCues(for: data)
        let cue = currentCue(in: cues, fallback: data.currentCue)
        let isLastCue = cleanCueIndex >= max(0, cues.count - 1)
        let cueIdentity = "\(data.destinationName)|\(viewModel.walkthrough?.id ?? "fallback")|\(viewModel.isUsingBasicGuidanceFallback)"

        CleanStickyBottomContainer(contentBottomPadding: 132) {
            CleanScreenHeader(
                title: "Guidance",
                subtitle: data.destinationName,
                eyebrow: approaching ? "Approaching" : "En route",
                systemImage: approaching ? "location.north.circle.fill" : "figure.walk"
            )

            CleanVoiceHint(text: "Say \"next\", \"repeat\", or \"back\" — or use the buttons.")

            CleanCueCard(
                title: "Current cue",
                cue: cue,
                systemImage: "speaker.wave.2.fill",
                onHear: { viewModel.speakImmediate(cue) }
            )

            if let feedbackMessage {
                CleanCard(title: "Status", systemImage: "pause.circle") {
                    Text(feedbackMessage)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                }
            }

            CleanCueCard(
                title: "What to expect",
                cue: data.arrivalFocus,
                systemImage: "scope",
                compact: true,
                onHear: { viewModel.speakImmediate(data.arrivalFocus) }
            )
        } bottomAction: {
            HStack(spacing: HearSightTheme.Spacing.md) {
                CleanIconButton(
                    title: "Repeat",
                    systemImage: "repeat",
                    accessibilityLabel: "Repeat cue",
                    accessibilityHint: "Speaks the current cue again."
                ) {
                    repeatCue(data: data)
                }

                CleanIconButton(
                    title: isPaused ? "Resume" : "Pause",
                    systemImage: isPaused ? "play.fill" : "pause.fill",
                    accessibilityLabel: isPaused ? "Resume guidance" : "Pause guidance",
                    accessibilityHint: isPaused ? "Resumes guidance." : "Pauses spoken guidance."
                ) {
                    togglePause()
                }

                CleanIconButton(
                    title: isLastCue ? "Arrival" : "Next",
                    systemImage: isLastCue ? "mappin.circle.fill" : "forward.fill",
                    isProminent: true,
                    accessibilityLabel: isLastCue ? "Arrival Assistance" : "Next cue",
                    accessibilityHint: isLastCue ? "Opens arrival assistance." : "Moves to the next cue."
                ) {
                    advanceCue(data: data)
                }
            }
        }
        .onAppear {
            speakInitialCueIfNeeded(data: data)
        }
        .onChange(of: cueIdentity) { _, _ in
            resetCueState()
        }
        .onChange(of: viewModel.pendingGuidanceCommand) { _, command in
            guard let command else { return }
            viewModel.pendingGuidanceCommand = nil
            let latestData = CleanFlowBriefing.resolved(from: viewModel)
            switch command {
            case .next:      advanceCue(data: latestData)
            case .repeatCue: repeatCue(data: latestData)
            case .back:      goBackCue(data: latestData)
            case .pause:     if !isPaused { togglePause() }
            case .resume:    if isPaused  { togglePause() }
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(HearSightTheme.primary(colorScheme))
                    .frame(width: 40, height: 40)
                    .background(HearSightTheme.primary(colorScheme).opacity(0.10))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.top, HearSightTheme.Spacing.sm)
            .padding(.trailing, HearSightTheme.Spacing.lg)
            .accessibilityLabel("Settings")
            .accessibilityHint("Opens settings including ElevenLabs voice status.")
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(viewModel: viewModel)
        }
    }

    private func cleanCues(for data: CleanFlowBriefing) -> [String] {
        // Read directly from walkthrough stages so CleanFlowBriefing's Street View
        // filtering doesn't silently drop valid route cues.
        let stageCues: [String]
        if let stages = viewModel.walkthrough?.stages, !stages.isEmpty {
            stageCues = stages.compactMap { stage -> String? in
                let spoken = stage.description.spokenCue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !spoken.isEmpty { return spoken }
                let instruction = stage.routeInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
                return instruction.isEmpty ? nil : instruction
            }
        } else {
            stageCues = data.guidanceCues
        }

        var seen = Set<String>()
        var cues: [String] = []

        for rawCue in stageCues + [data.entranceCue, data.arrivalFocus] {
            let cue = rawCue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cue.isEmpty else { continue }

            let key = cue
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .lowercased()
            guard !seen.contains(key) else { continue }

            seen.insert(key)
            cues.append(cue)
        }

        return cues
    }

    private func currentCue(in cues: [String], fallback: String) -> String {
        guard !cues.isEmpty else { return fallback }
        let index = min(max(cleanCueIndex, 0), cues.count - 1)
        return cues[index]
    }

    private func progressPrefix(in cues: [String]) -> String {
        guard !cues.isEmpty else { return "" }
        let position = min(cleanCueIndex, cues.count - 1) + 1
        return "Cue \(position) of \(cues.count). "
    }

    private func speakInitialCueIfNeeded(data: CleanFlowBriefing) {
        guard !didSpeakInitialCue else { return }
        didSpeakInitialCue = true
        let cues = cleanCues(for: data)
        let cue = currentCue(in: cues, fallback: data.currentCue)
        // Speak the destination and first cue as one uninterrupted utterance. No auto-tips.
        viewModel.speakImmediate("Going to \(data.destinationName). \(progressPrefix(in: cues))\(cue)")
    }

    private func repeatCue(data: CleanFlowBriefing) {
        let cues = cleanCues(for: data)
        let cue = currentCue(in: cues, fallback: data.currentCue)
        feedbackMessage = nil
        viewModel.speakImmediate("\(progressPrefix(in: cues))\(cue)")
    }

    private func togglePause() {
        if isPaused {
            isPaused = false
            viewModel.startGuidance()
            feedbackMessage = "Guidance resumed."
            viewModel.speakImmediate("Guidance resumed.")
        } else {
            isPaused = true
            viewModel.pauseGuidance()
            feedbackMessage = "Guidance paused. Say resume to continue."
            viewModel.speakImmediate("Guidance paused. Say resume to continue.")
        }
    }

    private func advanceCue(data: CleanFlowBriefing) {
        let cues = cleanCues(for: data)
        guard !cues.isEmpty else {
            onArrival()
            return
        }

        if cleanCueIndex < cues.count - 1 {
            cleanCueIndex += 1
            feedbackMessage = nil
            viewModel.speakImmediate("\(progressPrefix(in: cues))\(currentCue(in: cues, fallback: data.currentCue))")
            return
        }

        feedbackMessage = nil
        onArrival()
    }

    private func goBackCue(data: CleanFlowBriefing) {
        guard cleanCueIndex > 0 else { return }
        cleanCueIndex -= 1
        feedbackMessage = nil
        let cues = cleanCues(for: data)
        viewModel.speakImmediate("Going back. \(progressPrefix(in: cues))\(currentCue(in: cues, fallback: data.currentCue))")
    }

    private func resetCueState() {
        cleanCueIndex = 0
        feedbackMessage = nil
        didSpeakInitialCue = false
        isPaused = false
    }
}

#Preview {
    CleanGuidanceView(viewModel: WalkthroughViewModel()) {}
}
