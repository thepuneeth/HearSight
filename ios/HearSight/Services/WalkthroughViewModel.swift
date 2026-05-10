import AVFoundation
import CoreLocation
import Foundation
import Speech
import UIKit

enum RouteFlowState: String {
    case destinationEntry
    case previewing
    case readyToStart
    case activeGuidance
    case paused
    case routeComplete

    var label: String {
        switch self {
        case .destinationEntry:
            return "Destination entry"
        case .previewing:
            return "Previewing route"
        case .readyToStart:
            return "Ready to start"
        case .activeGuidance:
            return "Active guidance"
        case .paused:
            return "Paused"
        case .routeComplete:
            return "Route complete"
        }
    }
}

enum HapticGuidancePulse {
    case straight
    case turn
    case warning
}

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
    @Published var previewStageIndex = 0
    @Published var pausedForOffRoute = false
    @Published var flowState: RouteFlowState = .destinationEntry
    @Published var isListeningForDestination = false
    @Published var speechRecognitionStatus = "Tap the microphone and speak a destination."

    private let locationManager = CLLocationManager()
    private let synthesizer = AVSpeechSynthesizer()
    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var isAudioTapInstalled = false
    private var recognizedDestinationText: String?
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
        return "\(spokenCount) of \(stages.count) cues heard"
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

    var destinationDisplayName: String {
        resolvedDestinationName ?? destinationQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var currentCueText: String {
        guard let stage = stageForRepeat() ?? currentStage else {
            return "Enter a destination to begin."
        }
        return stage.description.spokenCue
    }

    var previewStage: RouteStage? {
        guard let stages = walkthrough?.stages, stages.indices.contains(previewStageIndex) else {
            return walkthrough?.stages.first
        }
        return stages[previewStageIndex]
    }

    var primaryActionTitle: String {
        switch flowState {
        case .previewing:
            return "Ready to Start"
        case .readyToStart, .paused:
            return "Start Guidance"
        case .activeGuidance:
            return "Pause Guidance"
        case .routeComplete:
            return "New Destination"
        case .destinationEntry:
            return "Get Route"
        }
    }

    func requestLocationAccess() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
    }

    func startDestinationListening() {
        guard !isListeningForDestination else {
            stopDestinationListening(confirm: true)
            return
        }

        guard speechRecognizer?.isAvailable == true else {
            showMicrophoneUnavailableMessage()
            return
        }

        SFSpeechRecognizer.requestAuthorization { [weak self] authorizationStatus in
            DispatchQueue.main.async {
                guard let self else { return }
                guard authorizationStatus == .authorized else {
                    self.speechRecognitionStatus = "Speech recognition is not available. Type the destination instead."
                    self.errorMessage = "Speech recognition permission is needed for spoken destination entry."
                    return
                }
                self.beginDestinationRecognition()
            }
        }
    }

    func stopDestinationListening(confirm: Bool = false) {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if isAudioTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isAudioTapInstalled = false
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListeningForDestination = false

        if confirm {
            let destination = recognizedDestinationText ?? ""
            if destination.isEmpty {
                speechRecognitionStatus = "No destination heard. Try again or type it."
            } else {
                destinationQuery = destination
                speechRecognitionStatus = "Destination captured. Confirm or edit below."
            }
        }
        recognizedDestinationText = nil
    }

    func generateWalkthrough() {
        stopDestinationListening()

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
        flowState = .destinationEntry

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
                    self.flowState = .previewing
                    self.statusMessage = "Previewing route. Swipe through cues before starting."
                    self.isGenerating = false
                    self.speak("Navigating to \(query). Preview the route before starting.")
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
        guard let walkthrough else {
            speak("Generate a walkthrough first.")
            return
        }

        requestLocationAccess()
        pausedForOffRoute = false
        isGuiding = true
        flowState = .activeGuidance
        statusMessage = "Active guidance."
        speak("\(walkthrough.routeSummary.safetyNotice) Guidance started.")
        performHaptic(.straight)
    }

    func pauseGuidance() {
        isGuiding = false
        synthesizer.stopSpeaking(at: .immediate)
        flowState = .paused
        statusMessage = "Paused."
        performHaptic(.warning)
    }

    func markReadyToStart() {
        guard walkthrough != nil else { return }
        flowState = .readyToStart
        statusMessage = "Ready to start guidance."
        speak("Ready to start.")
    }

    func handlePrimaryAction() {
        switch flowState {
        case .destinationEntry:
            generateWalkthrough()
        case .previewing:
            markReadyToStart()
        case .readyToStart, .paused:
            startGuidance()
        case .activeGuidance:
            pauseGuidance()
        case .routeComplete:
            resetRoute()
        }
    }

    func resetRoute() {
        stopDestinationListening()
        walkthrough = nil
        resolvedDestinationName = nil
        destinationQuery = ""
        routeCoordinates = []
        nextStageIndex = 0
        previewStageIndex = 0
        pausedForOffRoute = false
        isGuiding = false
        flowState = .destinationEntry
        statusMessage = "Tap the microphone and speak a destination."
    }

    func repeatCurrentStage() {
        guard let stage = stageForRepeat() else {
            speak("No stage is available to repeat.")
            return
        }
        speak(stage.description.spokenCue)
        performHaptic(hapticPulse(for: stage))
    }

    func hearPreviewCue(for stage: RouteStage) {
        previewStageIndex = stage.index
        speak(stage.description.spokenCue)
        performHaptic(hapticPulse(for: stage))
    }

    func speakPreviousStage() {
        guard let stages = walkthrough?.stages, !stages.isEmpty else { return }
        nextStageIndex = max(0, nextStageIndex - 1)
        let stage = stages[nextStageIndex]
        speak(stage.description.spokenCue)
        performHaptic(hapticPulse(for: stage))
    }

    func speakNextStage() {
        guard let stages = walkthrough?.stages, stages.indices.contains(nextStageIndex) else {
            speak("There are no more stages.")
            return
        }

        let stage = stages[nextStageIndex]
        nextStageIndex += 1
        speak(stage.description.spokenCue)
        performHaptic(hapticPulse(for: stage))
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
                    flowState = .paused
                    statusMessage = "Paused. You appear to be off route."
                    speak("Guidance paused. You appear to be away from the planned route. Regenerate the walkthrough if your route changed.")
                    performHaptic(.warning)
                    return
                }
            } else {
                offRouteObservationCount = 0
            }
        }

        guard walkthrough.stages.indices.contains(nextStageIndex) else {
            isGuiding = false
            flowState = .routeComplete
            statusMessage = "Route complete."
            speak("Route complete. Confirm the destination with your normal mobility tools.")
            performHaptic(.straight)
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
        previewStageIndex = 0
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
        performHaptic(.warning)
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

    private func beginDestinationRecognition() {
        stopDestinationListening()

        do {
            try configureAudioSessionForSpeech()
        } catch {
            showMicrophoneUnavailableMessage()
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        recognizedDestinationText = nil

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard isValidInputFormat(recordingFormat) else {
            showMicrophoneUnavailableMessage()
            return
        }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        isAudioTapInstalled = true

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let result {
                    if let cleanedText = self.cleanRecognizedDestination(result.bestTranscription.formattedString) {
                        self.recognizedDestinationText = cleanedText
                        self.destinationQuery = cleanedText
                    }
                    self.speechRecognitionStatus = result.isFinal ? "Destination captured. Confirm or edit below." : "Listening…"
                    if result.isFinal {
                        self.stopDestinationListening(confirm: true)
                    }
                    return
                }

                if error != nil {
                    self.stopDestinationListening()
                    self.showMicrophoneUnavailableMessage()
                }
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isListeningForDestination = true
            speechRecognitionStatus = "Listening…"
            statusMessage = "Listening…"
        } catch {
            showMicrophoneUnavailableMessage()
        }
    }

    private func configureAudioSessionForSpeech() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func isValidInputFormat(_ format: AVAudioFormat) -> Bool {
        format.sampleRate > 0 && format.channelCount > 0
    }

    private func showMicrophoneUnavailableMessage() {
        stopDestinationListening()
        speechRecognitionStatus = "Microphone unavailable. Type your destination instead."
        statusMessage = "Microphone unavailable. Type your destination instead."
    }

    private func cleanRecognizedDestination(_ text: String) -> String? {
        var cleaned = text
            .replacingOccurrences(of: "listening for destination", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "listening", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "destination", with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        while cleaned.contains("  ") {
            cleaned = cleaned.replacingOccurrences(of: "  ", with: " ")
        }

        let trimmed = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: " .,!?\n\t"))
        guard trimmed.count >= 3 else { return nil }
        return trimmed
    }

    private func performHaptic(_ pulse: HapticGuidancePulse) {
        switch pulse {
        case .straight:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .turn:
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    private func hapticPulse(for stage: RouteStage) -> HapticGuidancePulse {
        switch stage.kind {
        case .maneuver:
            return .turn
        case .checkpoint:
            return .straight
        case .destination:
            return .warning
        }
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
