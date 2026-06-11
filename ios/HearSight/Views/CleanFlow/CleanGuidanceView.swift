import SwiftUI

struct CleanGuidanceView: View {
    @ObservedObject var viewModel: WalkthroughViewModel
    let onArrival: () -> Void

    @State private var cleanCueIndex = 0
    @State private var feedbackMessage: String?
    @State private var didSpeakInitialCue = false

    var body: some View {
        let data = CleanFlowBriefing.resolved(from: viewModel)
        let approaching = viewModel.guidancePhaseLabel != "En route"
        let cues = cleanCues(for: data)
        let cue = currentCue(in: cues, fallback: data.currentCue)
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
                systemImage: "speaker.wave.2.fill"
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
                compact: true
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
                    title: "Pause",
                    systemImage: "pause.fill",
                    accessibilityLabel: "Pause guidance",
                    accessibilityHint: "Pauses spoken guidance."
                ) {
                    pauseCue()
                }

                CleanIconButton(
                    title: "Next",
                    systemImage: "forward.fill",
                    isProminent: true,
                    accessibilityLabel: "Next cue",
                    accessibilityHint: "Moves to the next cue."
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
        if !data.guidanceCues.isEmpty {
            return data.guidanceCues
        }

        return [
            data.currentCue,
            data.entranceCue,
            data.arrivalFocus
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
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
        viewModel.speakImmediate(currentCue(in: cues, fallback: data.currentCue))
    }

    private func repeatCue(data: CleanFlowBriefing) {
        let cues = cleanCues(for: data)
        feedbackMessage = nil
        viewModel.speakImmediate(currentCue(in: cues, fallback: data.currentCue))
    }

    private func pauseCue() {
        viewModel.stopSpeakingImmediately()
        feedbackMessage = "Guidance paused."
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
            viewModel.speakImmediate(currentCue(in: cues, fallback: data.currentCue))
            return
        }

        feedbackMessage = nil
        onArrival()
    }

    private func resetCueState() {
        cleanCueIndex = 0
        feedbackMessage = nil
        didSpeakInitialCue = false
    }
}

#Preview {
    CleanGuidanceView(viewModel: WalkthroughViewModel()) {}
}
