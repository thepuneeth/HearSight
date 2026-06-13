import SwiftUI

struct CleanGuidanceView: View {
    @ObservedObject var viewModel: WalkthroughViewModel
    let onArrival: () -> Void

    @State private var cleanCueIndex = 0
    @State private var feedbackMessage: String?
    @State private var didSpeakInitialCue = false
    @State private var isPaused = false

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

            CleanVoiceHint(text: "Use Repeat, Pause, or Next.")

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
                title: "Arrival focus",
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

    private func speakInitialCueIfNeeded(data: CleanFlowBriefing) {
        guard !didSpeakInitialCue else { return }
        didSpeakInitialCue = true
        let cues = cleanCues(for: data)
        let cue = currentCue(in: cues, fallback: data.currentCue)
        viewModel.speakImmediate("Guidance started. You can use Repeat, Pause, or Next at any time. \(cue)")
    }

    private func repeatCue(data: CleanFlowBriefing) {
        let cues = cleanCues(for: data)
        let cue = currentCue(in: cues, fallback: data.currentCue)
        feedbackMessage = nil
        viewModel.speakImmediate("Repeating current cue. \(cue)")
    }

    private func togglePause() {
        if isPaused {
            isPaused = false
            viewModel.startGuidance()
            feedbackMessage = "Guidance resumed."
            viewModel.speakAccessibilityPrompt("Guidance resumed.", interrupt: true)
        } else {
            isPaused = true
            viewModel.stopSpeakingImmediately()
            feedbackMessage = "Guidance paused."
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
            viewModel.speakImmediate("Moving to next cue. \(currentCue(in: cues, fallback: data.currentCue))")
            return
        }

        feedbackMessage = nil
        onArrival()
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
