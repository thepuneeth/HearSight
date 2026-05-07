import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = WalkthroughViewModel()
    @FocusState private var isDestinationFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 18) {
                    titleArea

                    ZStack {
                        destinationCard
                            .opacity(viewModel.isRouteReady ? 0 : 1)
                            .allowsHitTesting(!viewModel.isRouteReady)

                        guidanceCard
                            .opacity(viewModel.isRouteReady ? 1 : 0)
                            .allowsHitTesting(viewModel.isRouteReady)
                    }
                    .frame(maxHeight: .infinity)

                    footerStatus
                }
                .padding(20)
            }
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

    private var titleArea: some View {
        VStack(spacing: 8) {
            Text("HearSight")
                .font(.largeTitle.weight(.bold))
                .minimumScaleFactor(0.8)

            Text(viewModel.isRouteReady ? (viewModel.resolvedDestinationName ?? "Route ready") : "Where are you going?")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var destinationCard: some View {
        VStack(spacing: 18) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(.blue)

            TextField("Type destination", text: $viewModel.destinationQuery)
                .font(.title3)
                .textFieldStyle(.roundedBorder)
                .textContentType(.fullStreetAddress)
                .submitLabel(.go)
                .focused($isDestinationFocused)
                .onSubmit {
                    isDestinationFocused = false
                    viewModel.generateWalkthrough()
                }
                .accessibilityLabel("Destination")

            Button {
                isDestinationFocused = false
                viewModel.generateWalkthrough()
            } label: {
                Text(viewModel.isGenerating ? "Getting Route..." : "Get Route")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isGenerating)

            Button {
                viewModel.checkBackend()
            } label: {
                Text("Check Connection")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isCheckingBackend)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 8)
    }

    private var guidanceCard: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Text("Next Cue")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text(viewModel.currentCueText)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(5)
                    .minimumScaleFactor(0.78)
                    .frame(maxWidth: .infinity)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Text(viewModel.progressLabel)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                SquareButton(title: "Start", systemImage: "play.fill", prominent: true) {
                    viewModel.startGuidance()
                }

                SquareButton(title: "Pause", systemImage: "pause.fill") {
                    viewModel.pauseGuidance()
                }
            }

            HStack(spacing: 12) {
                SquareButton(title: "Back", systemImage: "backward.fill") {
                    viewModel.speakPreviousStage()
                }

                SquareButton(title: "Repeat", systemImage: "repeat") {
                    viewModel.repeatCurrentStage()
                }

                SquareButton(title: "Next", systemImage: "forward.fill", prominent: true) {
                    viewModel.speakNextStage()
                }
            }

            Button {
                viewModel.walkthrough = nil
                viewModel.resolvedDestinationName = nil
                viewModel.destinationQuery = ""
            } label: {
                Text("New Destination")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 8)
    }

    private var footerStatus: some View {
        Text(viewModel.statusMessage)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(viewModel.statusMessage)
    }
}

private struct SquareButton: View {
    let title: String
    let systemImage: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Group {
            if prominent {
                Button(action: action) {
                    label
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button(action: action) {
                    label
                }
                .buttonStyle(.bordered)
            }
        }
        .accessibilityLabel(title)
    }

    private var label: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 62)
    }
}

#Preview {
    ContentView()
}
