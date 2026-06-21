import SwiftUI

struct CleanPreviewView: View {
    @ObservedObject var viewModel: WalkthroughViewModel
    let onBeginGuidance: () -> Void

    @State private var didAnnounce = false

    var body: some View {
        let data = CleanFlowBriefing.resolved(from: viewModel)

        CleanStickyBottomContainer {
            CleanScreenHeader(
                title: "Arrival Preview",
                subtitle: data.destinationName,
                eyebrow: data.visitType,
                systemImage: data.visitType == "First visit" ? "sparkle.magnifyingglass" : "checkmark.seal"
            )

            CleanCard(title: "Preview only", systemImage: "info.circle.fill") {
                Text("You have not arrived yet. This screen previews what HearSight will tell you when you reach your destination. Say start or begin to start guidance.")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if data.isPreparing {
                CleanCard(title: "Preparing arrival preview", systemImage: "hourglass") {
                    Text("HearSight is gathering entrance and landmark cues. Basic guidance is available while details load.")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                if let fallbackMessage = data.fallbackMessage {
                    CleanCard(title: "Limited preview", systemImage: "exclamationmark.triangle.fill") {
                        Text(fallbackMessage)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                CleanCard(title: "When you arrive, you'll hear", systemImage: "list.bullet") {
                    VStack(alignment: .leading, spacing: HearSightTheme.Spacing.sm) {
                        summaryRow(label: "Entrance", value: summaryText(data.entranceCue))
                        summaryRow(label: "Key landmark", value: data.arrivalKeyLandmark ?? "Use near-arrival landmarks.")
                        summaryRow(label: "Watch for", value: summaryText(data.whatToExpect.first ?? data.arrivalFocus))
                    }
                }

                CleanCueCard(
                    title: "Arrival cue you'll hear",
                    cue: data.entranceCue,
                    systemImage: "door.left.hand.open",
                    onHear: { viewModel.speakImmediate("When you arrive, you will hear: \(data.entranceCue)") }
                )

                CleanCard(title: "What to expect", systemImage: "ear") {
                    VStack(alignment: .leading, spacing: HearSightTheme.Spacing.sm) {
                        ForEach(data.whatToExpect.prefix(3), id: \.self) { line in
                            HStack(alignment: .firstTextBaseline, spacing: HearSightTheme.Spacing.sm) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.teal)
                                    .imageScale(.medium)

                                Text(line)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                CleanLandmarkChainCard(landmarks: data.landmarkChain)

                if let trustedNote = data.trustedNote, !trustedNote.isEmpty {
                    CleanCard(title: "Trusted note", systemImage: "checkmark.seal") {
                        Text(trustedNote)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } bottomAction: {
            CleanPrimaryButton(
                title: viewModel.isCleanFlowDestinationRecognized ? "Start Guidance" : "Resolving Destination",
                systemImage: "figure.walk",
                accessibilityLabel: "Start Guidance",
                accessibilityHint: viewModel.isCleanFlowDestinationRecognized
                    ? "Start Guidance. Starts the simple guidance controls."
                    : "Wait until HearSight recognizes the destination."
            ) {
                onBeginGuidance()
            }
            .disabled(!viewModel.isCleanFlowDestinationRecognized)
        }
        .onAppear {
            // Make sure the microphone is actually listening on this screen (orange dot appears).
            viewModel.startGuidanceVoiceCommands()
            guard !didAnnounce else { return }
            didAnnounce = true
            viewModel.speakImmediate("This is a preview of your arrival at \(data.destinationName). You have not arrived yet. When you arrive, you will hear the entrance cue. Say start or begin to start guidance, or say repeat to hear what you'll be told on arrival.")
        }
        .onChange(of: viewModel.isCleanFlowDestinationRecognized) { _, recognized in
            // Keep the recognizer alive once the destination is ready, so "start"/"begin" register.
            if recognized {
                viewModel.startGuidanceVoiceCommands()
            }
        }
        .onChange(of: viewModel.pendingGuidanceCommand) { _, command in
            guard let command else { return }
            viewModel.pendingGuidanceCommand = nil
            switch command {
            case .next, .resume:
                if viewModel.isCleanFlowDestinationRecognized {
                    onBeginGuidance()
                } else {
                    viewModel.speakImmediate("Still resolving the destination. Please wait a moment.")
                }
            case .repeatCue:
                viewModel.speakImmediate("When you arrive, you will hear: \(data.entranceCue)")
            case .back, .pause:
                break
            }
        }
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: HearSightTheme.Spacing.sm) {
            Text(label)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)

            Text(value)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func summaryText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 82 else { return trimmed }
        return "\(String(trimmed.prefix(79)).trimmingCharacters(in: .whitespacesAndNewlines))..."
    }
}

#Preview {
    CleanPreviewView(viewModel: WalkthroughViewModel()) {}
}
