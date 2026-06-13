import SwiftUI

struct CleanArrivalView: View {
    @ObservedObject var viewModel: WalkthroughViewModel
    let onSave: () -> Void
    let onDone: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var didSave = false

    var body: some View {
        let data = CleanFlowBriefing.resolved(from: viewModel)

        CleanStickyBottomContainer {
            CleanScreenHeader(
                title: "Arrival Assistance",
                subtitle: "Confirm the entrance before going inside.",
                eyebrow: data.destinationName,
                systemImage: "mappin.circle.fill"
            )

            CleanVoiceHint(text: "Use Repeat cues, Need help, or Save Arrival Confidence.")

            CleanCueCard(
                title: "Correct entrance",
                cue: data.entranceCue,
                systemImage: "door.left.hand.open",
                onHear: { viewModel.speakImmediate(data.entranceCue) }
            )

            CleanLandmarkChainCard(landmarks: data.landmarkChain)

            HStack(spacing: HearSightTheme.Spacing.md) {
                CleanIconButton(
                    title: viewModel.isSpeaking ? "Speaking..." : "Repeat cues",
                    systemImage: viewModel.isSpeaking ? "speaker.wave.3.fill" : "speaker.wave.2.fill",
                    accessibilityLabel: "Repeat arrival cues",
                    accessibilityHint: "Repeats the entrance and landmark cues."
                ) {
                    speakArrivalCues(data)
                }

                CleanIconButton(
                    title: "Need help",
                    systemImage: "hand.raised.fill",
                    isProminent: true,
                    accessibilityLabel: "Need help",
                    accessibilityHint: "Repeats the entrance and landmark guidance."
                ) {
                    speakArrivalCues(data)
                }
            }

            if didSave {
                CleanCard(title: "Saved", systemImage: "checkmark.circle.fill") {
                    Text("Next time, HearSight can use this note to make the arrival easier.")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            CleanConfidencePicker(selection: $viewModel.confidenceLevel)

            CleanCard(title: "Note to future self", systemImage: "square.and.pencil") {
                TextField("Add a short note", text: $viewModel.futureSelfNote, axis: .vertical)
                    .font(.body.weight(.medium))
                    .lineLimit(3...5)
                    .padding(HearSightTheme.Spacing.md)
                    .frame(minHeight: 112, alignment: .topLeading)
                    .background(HearSightTheme.insetPanel(colorScheme))
                    .clipShape(RoundedRectangle(cornerRadius: HearSightTheme.Radius.md, style: .continuous))
                    .accessibilityLabel("Note to future self")
                    .accessibilityHint("Saves a short note for a future visit.")
            }
        } bottomAction: {
            CleanPrimaryButton(
                title: didSave ? "Done" : "Save Arrival Confidence",
                systemImage: didSave ? "house.fill" : "checkmark.circle.fill",
                accessibilityLabel: didSave ? "Done" : "Save Confidence",
                accessibilityHint: didSave ? "Returns to the start screen." : "Saves your confidence level and note."
            ) {
                if didSave {
                    onDone()
                } else {
                    saveArrivalConfidence()
                }
            }
        }
        .onAppear {
            if viewModel.confidenceLevel == nil {
                viewModel.confidenceLevel = .okay
            }
        }
    }

    private func speakArrivalCues(_ data: CleanFlowBriefing) {
        let cue = [
            data.arrivalFocus,
            data.entranceCue,
            "Landmarks: \(data.landmarkChain.joined(separator: ", "))."
        ]
        .joined(separator: " ")
        viewModel.speakImmediate("Repeating arrival cues. \(cue)")
    }

    private func saveArrivalConfidence() {
        if viewModel.confidenceLevel == nil {
            viewModel.confidenceLevel = .okay
        }
        onSave()
        didSave = true
        viewModel.speakAccessibilityPrompt("Arrival confidence saved.")
    }
}

#Preview {
    CleanArrivalView(viewModel: WalkthroughViewModel(), onSave: {}, onDone: {})
}
