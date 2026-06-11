import SwiftUI

struct CleanConfirmDestinationView: View {
    @ObservedObject var viewModel: WalkthroughViewModel
    let onConfirm: () -> Void
    let onEdit: () -> Void

    var body: some View {
        CleanStickyBottomContainer(contentBottomPadding: 176) {
            CleanScreenHeader(
                title: "Confirm Destination",
                subtitle: "Make sure this is the place you mean.",
                eyebrow: destinationName,
                systemImage: "mappin.and.ellipse"
            )

            CleanCard(title: destinationCardTitle, systemImage: destinationCardIcon) {
                VStack(alignment: .leading, spacing: HearSightTheme.Spacing.sm) {
                    Text(destinationName)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if let resolvedAddress {
                        Text(resolvedAddress)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(statusText)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if shouldShowLimitedDetails {
                CleanCard(title: "Limited details", systemImage: "exclamationmark.triangle.fill") {
                    Text(limitedDetailsText)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } bottomAction: {
            VStack(spacing: HearSightTheme.Spacing.sm) {
                CleanPrimaryButton(
                    title: canContinue ? "Continue to Arrival Preview" : "Resolving Destination",
                    systemImage: "checkmark.circle.fill",
                    accessibilityHint: canContinue
                        ? "Continues to the arrival preview for this destination."
                        : "Wait until HearSight recognizes the destination."
                ) {
                    onConfirm()
                }
                .disabled(!canContinue)

                CleanSecondaryButton(
                    title: "Edit Destination",
                    systemImage: "pencil",
                    accessibilityHint: "Returns to the start screen to change the destination."
                ) {
                    onEdit()
                }
            }
        }
    }

    private var destinationName: String {
        let candidates = [
            viewModel.walkthrough?.destination?.name,
            viewModel.walkthrough?.destination?.formattedAddress,
            viewModel.resolvedDestinationName,
            viewModel.destinationQuery
        ]

        return candidates
            .compactMap { $0?.cleanConfirmDisplayText }
            .first { !$0.isEmpty && $0 != "Destination" }
            ?? "your destination"
    }

    private var resolvedAddress: String? {
        guard let address = viewModel.walkthrough?.destination?.formattedAddress?.cleanConfirmDisplayText,
              !address.isEmpty,
              address.caseInsensitiveCompare(destinationName) != .orderedSame else {
            return nil
        }
        return address
    }

    private var isResolving: Bool {
        viewModel.isGenerating
    }

    private var canContinue: Bool {
        viewModel.isCleanFlowDestinationRecognized
    }

    private var shouldShowLimitedDetails: Bool {
        !isResolving && !canContinue && (viewModel.previewUnavailable || viewModel.isUsingBasicGuidanceFallback || viewModel.walkthrough == nil)
    }

    private var destinationCardTitle: String {
        if isResolving {
            return viewModel.currentLocation == nil ? "Finding current location" : "Resolving destination"
        }

        return canContinue ? "Resolved destination" : "Destination not confirmed"
    }

    private var destinationCardIcon: String {
        isResolving ? "hourglass" : "location.fill"
    }

    private var statusText: String {
        if isResolving {
            return viewModel.currentLocation == nil
                ? "Waiting for current location before requesting directions."
                : "Resolving destination and preparing arrival preview..."
        }

        if shouldShowLimitedDetails {
            return "HearSight has not confirmed this location yet. Edit the destination or try a more specific name or address."
        }

        return "Continue if this destination looks right."
    }

    private var limitedDetailsText: String {
        let message = viewModel.statusMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !message.isEmpty,
           message != "Backend offline.",
           message != "Checking backend." {
            return message
        }

        return "HearSight has not confirmed \"\(destinationName)\" yet. Try a more specific name or address."
    }
}

private extension String {
    var cleanConfirmDisplayText: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "Unnamed Road", with: "the final approach", options: [.caseInsensitive])
            .replacingOccurrences(of: "Unnamed route", with: "the final approach", options: [.caseInsensitive])
            .replacingOccurrences(of: "Unnamed", with: "the destination area", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview {
    CleanConfirmDestinationView(
        viewModel: {
            let viewModel = WalkthroughViewModel()
            viewModel.destinationQuery = "Walmart"
            viewModel.resolvedDestinationName = "Walmart"
            return viewModel
        }(),
        onConfirm: {},
        onEdit: {}
    )
}
