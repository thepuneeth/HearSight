import SwiftUI

struct StageRowView: View {
    let stage: RouteStage
    let isNext: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Stage \(stage.index + 1)", systemImage: iconName)
                    .font(.headline)
                Spacer()
                if isNext {
                    Text("Next")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(Capsule())
                }
            }

            Text(stage.description.spokenCue)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits {
                HStack(spacing: 12) {
                    stageMetric(progressLabel, icon: "figure.walk.motion")
                    stageMetric("\(stage.headingDegrees) deg", icon: "safari")
                    stageMetric(confidenceLabel, icon: "gauge.with.dots.needle.33percent")
                }
                VStack(alignment: .leading, spacing: 6) {
                    stageMetric(progressLabel, icon: "figure.walk.motion")
                    stageMetric("\(stage.headingDegrees) deg", icon: "safari")
                    stageMetric(confidenceLabel, icon: "gauge.with.dots.needle.33percent")
                }
            }

            if !stage.description.uncertainties.isEmpty {
                Text(stage.description.uncertainties.joined(separator: " "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isNext ? Color.accentColor.opacity(0.10) : Color(.secondarySystemGroupedBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isNext ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Double tap the Hear Cue button in route preview to speak this cue.")
    }

    private var iconName: String {
        switch stage.kind {
        case .maneuver:
            return "arrow.triangle.turn.up.right.diamond"
        case .checkpoint:
            return "smallcircle.filled.circle"
        case .destination:
            return "flag.checkered"
        }
    }

    private var confidenceLabel: String {
        "\(Int((stage.description.confidence * 100).rounded()))%"
    }

    private var progressLabel: String {
        stage.kind == .destination ? "Destination area" : "About \(stage.routeDistanceMeters) meters from start"
    }

    private func stageMetric(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private var accessibilitySummary: String {
        var parts = [
            "Stage \(stage.index + 1)",
            isNext ? "next stage" : "",
            stage.description.spokenCue,
            progressLabel,
            "Confidence \(confidenceLabel)."
        ]
        if !stage.description.uncertainties.isEmpty {
            parts.append("Uncertainties: \(stage.description.uncertainties.joined(separator: ", ")).")
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " ")
    }
}
