import SwiftUI

struct CleanPreviewView: View {
    @ObservedObject var viewModel: WalkthroughViewModel
    let onBeginGuidance: () -> Void

    var body: some View {
        let data = CleanFlowBriefing.resolved(from: viewModel)

        CleanStickyBottomContainer {
            CleanScreenHeader(
                title: "Arrival Preview",
                subtitle: data.destinationName,
                eyebrow: data.visitType,
                systemImage: data.visitType == "First visit" ? "sparkle.magnifyingglass" : "checkmark.seal"
            )

            CleanVoiceHint(text: "Use Begin Guidance when ready.")

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

                CleanCard(title: "Arrival summary", systemImage: "list.bullet") {
                    VStack(alignment: .leading, spacing: HearSightTheme.Spacing.sm) {
                        summaryRow(label: "Entrance", value: summaryText(data.entranceCue))
                        summaryRow(label: "Key landmark", value: data.arrivalKeyLandmark ?? "Use near-arrival landmarks.")
                        summaryRow(label: "Watch for", value: summaryText(data.whatToExpect.first ?? data.arrivalFocus))
                    }
                }

                CleanCueCard(
                    title: "Entrance cue",
                    cue: data.entranceCue,
                    systemImage: "door.left.hand.open"
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
                title: viewModel.isCleanFlowDestinationRecognized ? "Begin Guidance" : "Resolving Destination",
                systemImage: "figure.walk",
                accessibilityHint: viewModel.isCleanFlowDestinationRecognized
                    ? "Begin Guidance. Starts the simple guidance controls."
                    : "Wait until HearSight recognizes the destination."
            ) {
                onBeginGuidance()
            }
            .disabled(!viewModel.isCleanFlowDestinationRecognized)
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
