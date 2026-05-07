import AVFoundation
import CoreLocation
import Foundation
import UIKit

final class WalkthroughViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var serverBaseURL = "http://127.0.0.1:8787"
    @Published var destinationQuery = ""
    @Published var resolvedDestinationName: String?
    @Published var walkthrough: WalkthroughResponse?
    @Published var backendHealth: BackendHealth?
    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var statusMessage = "Location access is needed to generate and follow a walkthrough."
    @Published var errorMessage: String?
    @Published var isGenerating = false
    @Published var isGuiding = false
    @Published var isCheckingBackend = false
    @Published var nextStageIndex = 0
    @Published var pausedForOffRoute = false

    private let locationManager = CLLocationManager()
    private let synthesizer = AVSpeechSynthesizer()
    private var routeCoordinates: [CLLocationCoordinate2D] = []
    private var poorAccuracyWarningDate: Date?
    private var offRouteObservationCount = 0

    private let triggerRadiusMeters: CLLocationDistance = 22
    private let acceptableAccuracyMeters: CLLocationAccuracy = 35
    private let offRouteRadiusMeters: CLLocationDistance = 90

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.activityType = .fitness
    }

    var currentStage: RouteStage? {
        guard let stages = walkthrough?.stages, stages.indices.contains(nextStageIndex) else {
            return walkthrough?.stages.last
        }
        return stages[nextStageIndex]
    }

    var progressLabel: String {
        guard let stages = walkthrough?.stages, !stages.isEmpty else {
            return "No walkthrough loaded"
        }
        let spokenCount = min(nextStageIndex, stages.count)
        return "\(spokenCount) of \(stages.count) stages spoken"
    }

    var backendStatusLabel: String {
        guard let backendHealth else {
            return "Backend not checked"
        }
        if !backendHealth.missingConfig.isEmpty {
            return "Backend needs \(backendHealth.missingConfig.joined(separator: ", "))"
        }
        return backendHealth.mockMode ? "Backend mock mode" : "Backend ready"
    }

    var currentStageTitle: String {
        guard let currentStage else {
            return "No active stage"
        }
        return "Stage \(currentStage.index + 1): \(currentStage.routeInstruction)"
    }

    var isRouteReady: Bool {
        walkthrough != nil
    }

    var currentCueText: String {
        guard let stage = stageForRepeat() ?? currentStage else {
            return "Enter a destination to begin."
        }
        return stage.description.spokenCue
    }

    func requestLocationAccess() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
    }

    func generateWalkthrough() {
        guard let origin = currentLocation?.coordinate else {
            errorMessage = "Current location is not ready yet."
            requestLocationAccess()
            return
        }

        let query = destinationQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            errorMessage = "Type a destination first."
            return
        }

        let baseURL = serverBaseURL
        let language = Locale.current.identifier

        isGenerating = true
        errorMessage = nil
        statusMessage = "Checking backend and preparing route stages."

        Task {
            do {
                let client = WalkthroughAPIClient(serverBaseURL: baseURL)
                let health = try await client.health()
                if !health.missingConfig.isEmpty {
                    throw WalkthroughAPIError.serverError("Backend is running, but missing: \(health.missingConfig.joined(separator: ", ")).")
                }

                let response = try await client.createWalkthrough(
                    origin: origin,
                    destinationText: query,
                    language: language
                )

                await MainActor.run {
                    self.backendHealth = health
                    self.resolvedDestinationName = query
                    self.installWalkthrough(response)
                    self.statusMessage = "Walkthrough ready with \(response.stages.count) stages."
                    self.isGenerating = false
                    self.speak("Walkthrough ready with \(response.stages.count) stages.")
                }
            } catch {
                await MainActor.run {
                    self.isGenerating = false
                    self.errorMessage = self.friendlyGenerationError(error)
                    self.statusMessage = "Walkthrough generation failed."
                    self.speak("Walkthrough generation failed.")
                }
            }
        }
    }

    func checkBackend() {
        let baseURL = serverBaseURL
        isCheckingBackend = true
        errorMessage = nil
        statusMessage = "Checking backend."

        Task {
            do {
                let health = try await WalkthroughAPIClient(serverBaseURL: baseURL).health()
                await MainActor.run {
                    self.backendHealth = health
                    self.isCheckingBackend = false
                    self.statusMessage = self.backendStatusLabel
                }
            } catch {
                await MainActor.run {
                    self.backendHealth = nil
                    self.isCheckingBackend = false
                    self.statusMessage = "Backend offline."
                    self.errorMessage = self.friendlyGenerationError(error)
                }
            }
        }
    }

    func startGuidance() {
        guard walkthrough != nil else {
            speak("Generate a walkthrough first.")
            return
        }

        requestLocationAccess()
        pausedForOffRoute = false
        isGuiding = true
        statusMessage = "Guidance started."
        speak("Guidance started.")
    }

    func pauseGuidance() {
        isGuiding = false
        synthesizer.stopSpeaking(at: .immediate)
        statusMessage = "Guidance paused."
    }

    func repeatCurrentStage() {
        guard let stage = stageForRepeat() else {
            speak("No stage is available to repeat.")
            return
        }
        speak(stage.description.spokenCue)
    }

    func speakPreviousStage() {
        guard let stages = walkthrough?.stages, !stages.isEmpty else { return }
        nextStageIndex = max(0, nextStageIndex - 1)
        let stage = stages[nextStageIndex]
        speak(stage.description.spokenCue)
    }

    func speakNextStage() {
        guard let stages = walkthrough?.stages, stages.indices.contains(nextStageIndex) else {
            speak("There are no more stages.")
            return
        }

        let stage = stages[nextStageIndex]
        nextStageIndex += 1
        speak(stage.description.spokenCue)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
                self.statusMessage = "Location is active."
                manager.startUpdatingLocation()
                manager.startUpdatingHeading()
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        DispatchQueue.main.async {
            self.currentLocation = location
            self.evaluateProgress(location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.errorMessage = error.localizedDescription
        }
    }

    private func evaluateProgress(_ location: CLLocation) {
        guard isGuiding, !pausedForOffRoute, let walkthrough else { return }

        guard location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= acceptableAccuracyMeters else {
            speakPoorAccuracyWarningIfNeeded(location.horizontalAccuracy)
            return
        }

        if !routeCoordinates.isEmpty {
            let distanceFromRoute = GeoMath.distanceFromRoute(location, route: routeCoordinates)
            if distanceFromRoute > offRouteRadiusMeters {
                offRouteObservationCount += 1
                if offRouteObservationCount >= 3 {
                    pausedForOffRoute = true
                    isGuiding = false
                    statusMessage = "Guidance paused because you appear to be off route."
                    speak("Guidance paused. You appear to be away from the planned route. Regenerate the walkthrough if your route changed.")
                    return
                }
            } else {
                offRouteObservationCount = 0
            }
        }

        guard walkthrough.stages.indices.contains(nextStageIndex) else {
            isGuiding = false
            statusMessage = "All stages have been spoken."
            speak("All stages have been spoken. Confirm the destination using live surroundings.")
            return
        }

        let nextStage = walkthrough.stages[nextStageIndex]
        let distanceToStage = location.distance(from: nextStage.location)
        if distanceToStage <= triggerRadiusMeters {
            speakNextStage()
        }
    }

    private func installWalkthrough(_ response: WalkthroughResponse) {
        walkthrough = response
        routeCoordinates = PolylineDecoder.decode(response.routeSummary.encodedPolyline)
        if routeCoordinates.isEmpty {
            routeCoordinates = response.stages.map(\.coordinate.locationCoordinate)
        }
        nextStageIndex = 0
        pausedForOffRoute = false
        offRouteObservationCount = 0
    }

    private func speakPoorAccuracyWarningIfNeeded(_ accuracy: CLLocationAccuracy) {
        let now = Date()
        if let last = poorAccuracyWarningDate, now.timeIntervalSince(last) < 60 {
            return
        }

        poorAccuracyWarningDate = now
        statusMessage = "Waiting for better GPS accuracy."
        speak("Location accuracy is weak. Waiting for a more precise location before speaking the next cue.")
    }

    private func stageForRepeat() -> RouteStage? {
        guard let stages = walkthrough?.stages, !stages.isEmpty else { return nil }
        let index = min(max(nextStageIndex - 1, 0), stages.count - 1)
        return stages[index]
    }

    private func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        synthesizer.speak(utterance)
    }

    private func friendlyGenerationError(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCannotConnectToHost {
            return "Could not connect to the backend at \(serverBaseURL). Start the backend first."
        }
        if nsError.domain == NSURLErrorDomain {
            return "Network error: \(error.localizedDescription). Check the backend URL."
        }
        return error.localizedDescription
    }
}
