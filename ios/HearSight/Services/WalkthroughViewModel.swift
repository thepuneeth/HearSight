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

final class WalkthroughViewModel: NSObject, ObservableObject, CLLocationManagerDelegate, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    @Published var serverBaseURL = "http://127.0.0.1:8787"
    @Published var destinationQuery = ""
    @Published var resolvedDestinationName: String?
    @Published var walkthrough: WalkthroughResponse?
    @Published var backendHealth: BackendHealth?
    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var statusMessage = "Enter a destination to prepare a route."
    @Published var errorMessage: String?
    @Published var isGenerating = false
    @Published var isGuiding = false
    @Published var isCheckingBackend = false
    @Published var nextStageIndex = 0
    @Published var previewStageIndex = 0
    @Published var pausedForOffRoute = false
    @Published var flowState: RouteFlowState = .destinationEntry
    @Published var isListeningForDestination = false
    @Published var speechRecognitionStatus = "Double tap the screen to activate the microphone."
    @Published var voiceInputState: VoiceInputState = .idle
    @Published var isFirstVisit = true
    @Published var cueDensity: CueDensity = .standard
    @Published var confidenceLevel: ConfidenceLevel?
    @Published var futureSelfNote = ""
    @Published var arrivalMemory = ArrivalMemory(lastConfidence: nil, futureNote: "", isFamiliarPlace: false)
    @Published var hasArrived = false
    @Published var hasStartedGuidance = false
    @Published var isSpeaking = false
    @Published var previewUnavailable = false
    @Published var isUsingBasicGuidanceFallback = false
    @Published var isPreviewLoading = false
    @Published var isRefreshingPreview = false

    @Published var pendingGuidanceCommand: GuidanceVoiceCommand? = nil

    enum ArrivalVoiceMode { case off, confidence, note, nextTrip }
    var arrivalVoiceMode: ArrivalVoiceMode = .off
    @Published var pendingConfidenceLevel: ConfidenceLevel? = nil
    @Published var capturedArrivalNote: String? = nil
    @Published var pendingNextTripAnswer: Bool? = nil
    @Published var lastHeardText: String = ""
    private var noteSilenceTimer: Timer?
    private var pendingNoteText: String = ""

    private let locationManager = CLLocationManager()
    private let synthesizer = AVSpeechSynthesizer()
    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var micAcceptingInput = false
    private var isAudioTapInstalled = false
    private var isListeningForGuidanceCommands = false
    private var guidanceCommandRequest: SFSpeechAudioBufferRecognitionRequest?
    private var guidanceCommandTask: SFSpeechRecognitionTask?
    private var guidanceCommandLastDetected: Date = .distantPast
    private var recognizedDestinationText: String?
    private var routeCoordinates: [CLLocationCoordinate2D] = []
    private var poorAccuracyWarningDate: Date?
    private var offRouteObservationCount = 0
    private var previewTask: Task<Void, Never>?
    private var fallbackPreviewTask: Task<Void, Never>?
    private var locationWaitTask: Task<Void, Never>?
    private var previewStillWorkingSpeechTask: Task<Void, Never>?
    private var activePreviewKey: String?
    private var isWaitingForLocationToGenerate = false
    private var hasSpokenHomeIntro = false
    private var lastSpokenDestinationEntry: String?
    private var lastSpokenPreviewReadyID: String?
    private var elevenLabsPlayer: AVAudioPlayer?
    private var elevenLabsSpeechTask: Task<Void, Never>?
    @Published var elevenLabsStatus: String = ""
    private var commandsMutedUntil: Date = .distantPast
    private var lastSpokenLowercased: String = ""
    private var hasConfiguredAudioSession = false

    private static var walkthroughCache: [String: WalkthroughResponse] = [:]

    private let triggerRadiusMeters: CLLocationDistance = 22
    private let acceptableAccuracyMeters: CLLocationAccuracy = 35
    private let offRouteRadiusMeters: CLLocationDistance = 90
    private let fallbackPreviewDelayNanos: UInt64 = 7_000_000_000

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.activityType = .fitness
        synthesizer.delegate = self
    }

    var tripPhase: TripPhase {
        if hasArrived { return .arrival }
        if isGuiding || flowState == .activeGuidance || flowState == .paused { return .guidance }
        if walkthrough != nil { return .preview }
        return .home
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

    var isCleanFlowDestinationRecognized: Bool {
        guard currentLocation != nil, walkthrough != nil, !isUsingBasicGuidanceFallback else { return false }
        let destination = walkthrough?.destination?.name
            ?? walkthrough?.destination?.formattedAddress
            ?? resolvedDestinationName
        let trimmed = destination?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !trimmed.isEmpty && trimmed != "Destination"
    }

    var destinationDisplayName: String {
        resolvedDestinationName ?? destinationQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var guidancePhaseLabel: String {
        guard let stages = walkthrough?.stages, !stages.isEmpty else { return "En route" }
        return nextStageIndex >= max(0, stages.count - 2) ? "Approaching" : "En route"
    }

    var currentCueText: String {
        guard let stage = stageForRepeat() ?? currentStage else {
            return "Enter a destination to begin."
        }
        return stage.description.spokenCue
    }

    var arrivalSearchCue: String {
        let destinationCue = walkthrough?.stages.last(where: { $0.kind == .destination })?.description.spokenCue
        return destinationCue ?? arrivalPreview.entranceNote
    }

    var previewStage: RouteStage? {
        guard let stages = walkthrough?.stages, stages.indices.contains(previewStageIndex) else {
            return walkthrough?.stages.first
        }
        return stages[previewStageIndex]
    }

    var arrivalPreview: ArrivalPreview {
        let destination = resolvedDestinationName
            ?? walkthrough?.destination?.name
            ?? walkthrough?.destination?.formattedAddress
            ?? destinationQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let stages = walkthrough?.stages ?? []
        let destinationStage = stages.last { $0.kind == .destination } ?? stages.last
        let landmarkChain = Array(stages.flatMap { stage in
            stage.description.landmarks.isEmpty ? stage.context?.nearbyLandmarks ?? [] : stage.description.landmarks
        }.prefix(4))
        let note = arrivalMemory.futureNote.trimmingCharacters(in: .whitespacesAndNewlines)

        return ArrivalPreview(
            destinationName: destination.isEmpty ? "Destination" : destination,
            entranceNote: destinationStage?.description.spokenCue ?? "Arrival details are limited. Use nearby signage, entrances, and your normal mobility tools to confirm the correct entrance.",
            whatToExpect: expectationText(from: destinationStage),
            landmarkChain: landmarkChain.isEmpty ? ["Main entrance area", "Building front", "Pickup or parking area"] : landmarkChain,
            trustedNote: note.isEmpty ? nil : note,
            isFirstVisit: isFirstVisit
        )
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

    func speakHomeIntroIfNeeded() {
        guard !hasSpokenHomeIntro else { return }
        hasSpokenHomeIntro = true
        speakAccessibilityPrompt(
            "Welcome to HearSight. Double tap the screen to activate the microphone, or type your destination below.",
            interrupt: true
        )
    }

    func speakAccessibilityPrompt(_ text: String, interrupt: Bool = false) {
        speak(text, immediate: interrupt)
        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: text)
        }
    }

    func speakDestinationEnteredIfNeeded() {
        let destination = destinationQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !destination.isEmpty, destination != lastSpokenDestinationEntry else { return }
        lastSpokenDestinationEntry = destination
        speakAccessibilityPrompt("Destination entered. \(destination). To continue, press Preview Arrival, or say preview, or say next.")
    }

    private func speakPreviewReadyIfNeeded(for walkthrough: WalkthroughResponse) {
        guard walkthrough.id != lastSpokenPreviewReadyID else { return }
        lastSpokenPreviewReadyID = walkthrough.id
        let name = walkthrough.destination?.name
            ?? walkthrough.destination?.formattedAddress
            ?? resolvedDestinationName
            ?? "your destination"
        speakAccessibilityPrompt("Destination confirmed: \(name). Say next or proceed to continue, or say edit to change it.")
    }

    func toggleDestinationVoiceInput() {
        if isListeningForDestination {
            stopDestinationListening(confirm: true)
        } else {
            startDestinationListening()
        }
    }

    func startDestinationListening() {
        guard !isListeningForDestination else {
            stopDestinationListening(confirm: true)
            return
        }

        // Hand the microphone over from command recognition to destination capture.
        stopGuidanceVoiceCommands()

        guard speechRecognizer?.isAvailable == true else {
            showMicrophoneUnavailableMessage()
            return
        }

        SFSpeechRecognizer.requestAuthorization { [weak self] authorizationStatus in
            DispatchQueue.main.async {
                guard let self else { return }
                guard authorizationStatus == .authorized else {
                    self.voiceInputState = .unavailable("Speech recognition unavailable. Type destination.")
                    self.speechRecognitionStatus = "Speech recognition is not available. Type the destination instead."
                    self.statusMessage = self.speechRecognitionStatus
                    return
                }
                self.beginDestinationRecognition()
            }
        }
    }

    func stopDestinationListening(confirm: Bool = false) {
        silenceTimer?.invalidate()
        silenceTimer = nil
        micAcceptingInput = false
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
                voiceInputState = .failure(speechRecognitionStatus)
            } else {
                destinationQuery = destination
                speechRecognitionStatus = "Destination captured."
                voiceInputState = .success
                speakDestinationEnteredIfNeeded()
            }
        } else if destinationQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            voiceInputState = .idle
        }
        recognizedDestinationText = nil
    }

    // MARK: - Guidance voice commands

    func startGuidanceVoiceCommands() {
        guard !isListeningForDestination else { return }

        // Heal a stale "running" flag: the recognizer can be marked as listening while its audio
        // engine was stopped (e.g. destination capture) or its recognition task ended — either case
        // leaves a dead recognizer that silently ignores everything. Restart cleanly if so.
        if isListeningForGuidanceCommands && (!audioEngine.isRunning || guidanceCommandTask == nil) {
            stopGuidanceVoiceCommands()
        }
        guard !isListeningForGuidanceCommands else { return }

        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            beginGuidanceCommandsIfReady()
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                DispatchQueue.main.async {
                    guard let self, status == .authorized else { return }
                    self.beginGuidanceCommandsIfReady()
                }
            }
        default:
            break
        }
    }

    private func beginGuidanceCommandsIfReady() {
        guard !isListeningForGuidanceCommands, !isListeningForDestination else { return }
        guard speechRecognizer?.isAvailable == true else { return }
        isListeningForGuidanceCommands = true
        runGuidanceCommandCycle()
    }

    func stopGuidanceVoiceCommands() {
        isListeningForGuidanceCommands = false
        guidanceCommandTask?.cancel()
        guidanceCommandRequest?.endAudio()
        guidanceCommandTask = nil
        guidanceCommandRequest = nil
        if !isListeningForDestination {
            if audioEngine.isRunning { audioEngine.stop() }
            if isAudioTapInstalled {
                audioEngine.inputNode.removeTap(onBus: 0)
                isAudioTapInstalled = false
            }
        }
    }

    private func runGuidanceCommandCycle() {
        guard isListeningForGuidanceCommands, !isListeningForDestination else { return }

        guidanceCommandTask?.cancel()
        guidanceCommandRequest?.endAudio()
        guidanceCommandTask = nil
        guidanceCommandRequest = nil

        if isAudioTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isAudioTapInstalled = false
        }
        if audioEngine.isRunning { audioEngine.stop() }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        guidanceCommandRequest = request

        do { try configureAudioSessionForSpeech() } catch { return }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard isValidInputFormat(format) else {
            // Mic input isn't ready yet (common right after a long spoken prompt). Retry shortly;
            // the next cycle reconfigures the session and the input becomes valid.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                self?.runGuidanceCommandCycle()
            }
            return
        }

        // Remove any existing tap first so we never install two on the same bus (which crashes).
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.guidanceCommandRequest?.append(buffer)
        }
        isAudioTapInstalled = true

        guidanceCommandTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, self.isListeningForGuidanceCommands else { return }
                if let result {
                    self.processRecognition(result)
                    if result.isFinal {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                            self?.runGuidanceCommandCycle()
                        }
                    }
                }
                if error != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        self?.runGuidanceCommandCycle()
                    }
                }
            }
        }

        audioEngine.prepare()
        try? audioEngine.start()
    }

    private func processRecognition(_ result: SFSpeechRecognitionResult) {
        let heard = result.bestTranscription.formattedString.lowercased()
        let recent = heard.components(separatedBy: .whitespaces).suffix(5).joined(separator: " ")
        let now = Date()
        // Surface what the mic is hearing so the user can see recognition is alive.
        if arrivalVoiceMode != .off { lastHeardText = recent }
        guard now > commandsMutedUntil else { return }

        switch arrivalVoiceMode {
        case .confidence:
            // Capture a spoken confidence answer after the question finishes.
            guard !isSpeaking, now.timeIntervalSince(guidanceCommandLastDetected) > 1.0 else { return }
            // Ignore the question's own echo (no echo cancellation on Simulator): the question says
            // "how was your trip" and lists both "unsure" and "confident" — a real answer does neither.
            if recent.contains("trip") || recent.contains("how was") { return }
            if recent.contains("unsure") && recent.contains("confident") { return }
            if let level = confidenceLevelIn(recent) {
                guidanceCommandLastDetected = now
                haltSpeech()
                pendingConfidenceLevel = level
            }

        case .note:
            // Capture the spoken note by silence: SFSpeech doesn't reliably send a "final" result in
            // continuous mode, so we take the latest transcription once the user stops talking.
            guard !isSpeaking else { return }
            // Ignore the note prompt's own echo.
            if recent.contains("would you like") || recent.contains("add a note") { return }
            let note = heard.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !note.isEmpty else { return }
            pendingNoteText = note
            noteSilenceTimer?.invalidate()
            noteSilenceTimer = Timer.scheduledTimer(withTimeInterval: 1.6, repeats: false) { [weak self] _ in
                guard let self, self.arrivalVoiceMode == .note else { return }
                let final = self.pendingNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
                self.pendingNoteText = ""
                if !final.isEmpty {
                    self.guidanceCommandLastDetected = Date()
                    self.capturedArrivalNote = final
                }
            }

        case .nextTrip:
            // Listen for a yes/no answer to "ready for your next trip?"
            guard !isSpeaking, now.timeIntervalSince(guidanceCommandLastDetected) > 1.0 else { return }
            // Ignore the question's own echo (it literally says "yes or no").
            if recent.contains("ready for") || recent.contains("next trip") || (recent.contains("yes") && recent.contains("no")) { return }
            if let yes = yesNoIn(recent) {
                guidanceCommandLastDetected = now
                haltSpeech()
                pendingNextTripAnswer = yes
            }

        case .off:
            guard now.timeIntervalSince(guidanceCommandLastDetected) > 2.0 else { return }
            if let match = commandMatch(in: recent) {
                // While the app is talking, ignore a command only if the exact word that
                // triggered it is part of what we are currently saying (echo on devices
                // without echo cancellation).
                if isSpeaking, lastSpokenLowercased.contains(match.keyword) { return }
                guidanceCommandLastDetected = now
                haltSpeech()
                pendingGuidanceCommand = match.command
            }
        }
    }

    private func confidenceLevelIn(_ text: String) -> ConfidenceLevel? {
        if text.contains("very unsure") { return .veryUnsure }
        if text.contains("very confident") { return .veryConfident }
        if text.contains("unsure") { return .unsure }
        if text.contains("confident") { return .confident }
        if text.contains("okay") || text.contains("ok") || text.contains("fine") || text.contains("alright") || text.contains("good") { return .okay }
        return nil
    }

    // Whole-word yes/no so "no" doesn't match inside "now" or "know".
    private func yesNoIn(_ text: String) -> Bool? {
        let words = text.split(whereSeparator: { $0 == " " }).map(String.init)
        for word in words.reversed() {
            if ["yes", "yeah", "yep", "yup", "sure", "ready", "ya"].contains(word) { return true }
            if ["no", "nope", "nah", "later"].contains(word) { return false }
        }
        return nil
    }

    // Trigger words per command. Resume is listed first because "unpause" also contains "pause".
    private static let commandKeywordGroups: [(GuidanceVoiceCommand, [String])] = [
        (.resume, ["unpause", "resume", "continue"]),
        (.next, ["next", "proceed", "forward", "start", "begin", "preview"]),
        (.repeatCue, ["repeat", "again", "hear"]),
        (.back, ["back", "previous", "edit"]),
        (.pause, ["pause", "stop", "wait"])
    ]

    private func guidanceCommandIn(_ text: String) -> GuidanceVoiceCommand? {
        commandMatch(in: text)?.command
    }

    private func commandMatch(in text: String) -> (command: GuidanceVoiceCommand, keyword: String)? {
        // Scan words newest-first so the most recently spoken command wins. This prevents an
        // older word still in the recognition buffer (e.g. "next") from overriding the latest
        // word the user actually said (e.g. "back").
        let words = text.split(whereSeparator: { $0 == " " }).map(String.init)
        for word in words.reversed() {
            for (command, keywords) in Self.commandKeywordGroups {
                if let keyword = keywords.first(where: { word.contains($0) }) {
                    return (command, keyword)
                }
            }
        }
        return nil
    }

    func generateWalkthrough(forceRefresh: Bool = false) {
        stopDestinationListening()

        // Offline demo mode: no backend, network, or API needed. Loads a polished pre-baked route.
        if UserDefaults.standard.bool(forKey: "offlineDemoMode") {
            installOfflineDemoWalkthrough()
            return
        }

        let query = destinationQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            statusMessage = "Type a destination first."
            return
        }

        debugDestinationLog("Typed destination: \(query)")
        let cacheKey = normalizedCacheKey(for: query)
        activePreviewKey = cacheKey
        previewTask?.cancel()
        fallbackPreviewTask?.cancel()
        locationWaitTask?.cancel()
        previewStillWorkingSpeechTask?.cancel()
        resolvedDestinationName = query
        hasArrived = false
        hasStartedGuidance = false
        isGuiding = false
        pausedForOffRoute = false
        previewUnavailable = false
        isUsingBasicGuidanceFallback = false
        isWaitingForLocationToGenerate = false
        errorMessage = nil
        isGenerating = true
        isPreviewLoading = true
        isRefreshingPreview = false
        flowState = .destinationEntry

        let hadPreviousWalkthrough = walkthrough != nil
        walkthrough = nil
        routeCoordinates = []
        nextStageIndex = 0
        previewStageIndex = 0
        debugDestinationLog("Previous walkthrough cleared: \(hadPreviousWalkthrough)")

        if let cached = Self.walkthroughCache[cacheKey], !forceRefresh {
            installWalkthrough(cached)
            isPreviewLoading = false
            isRefreshingPreview = true
            statusMessage = "Cached preview ready. Refreshing arrival details."
            speakPreviewReadyIfNeeded(for: cached)
            debugDestinationLog("Using cached walkthrough for \(query)")
        } else {
            statusMessage = "Preparing arrival preview."
        }

        guard let origin = currentLocation?.coordinate else {
            isWaitingForLocationToGenerate = true
            statusMessage = "Waiting for current location before resolving \(query)."
            debugDestinationLog("Waiting for current location before requesting \(query).")
            scheduleLocationWaitTimeout(for: query, cacheKey: cacheKey)
            requestLocationAccess()
            return
        }

        let baseURL = serverBaseURL
        let language = Locale.current.identifier

        scheduleFallbackPreview(for: query, cacheKey: cacheKey)
        schedulePreviewStillWorkingPrompt(cacheKey: cacheKey)
        debugDestinationLog("Request destination: \(query)")

        previewTask = Task {
            do {
                let client = WalkthroughAPIClient(serverBaseURL: baseURL)
                let health = try await client.health()
                if !health.missingConfig.isEmpty {
                    throw WalkthroughAPIError.serverError("Preview service is not fully configured.")
                }

                let response = try await client.createWalkthrough(
                    origin: origin,
                    destinationText: query,
                    language: language
                )

                await MainActor.run {
                    guard self.activePreviewKey == cacheKey, !Task.isCancelled else { return }
                    self.fallbackPreviewTask?.cancel()
                    self.previewStillWorkingSpeechTask?.cancel()
                    Self.walkthroughCache[cacheKey] = response
                    self.backendHealth = health
                    self.resolvedDestinationName = response.destination?.name ?? response.destination?.formattedAddress ?? query
                    if !self.hasStartedGuidance && !self.hasArrived {
                        self.installWalkthrough(response)
                    }
                    self.previewUnavailable = false
                    self.isGenerating = false
                    self.isPreviewLoading = false
                    self.isRefreshingPreview = false
                    self.statusMessage = "Arrival preview ready with \(response.stages.count) cues."
                    self.speakPreviewReadyIfNeeded(for: response)
                    self.debugDestinationLog("Real walkthrough installed for \(query) with \(response.stages.count) cues.")
                }
            } catch {
                await MainActor.run {
                    guard self.activePreviewKey == cacheKey, !Task.isCancelled else { return }
                    self.fallbackPreviewTask?.cancel()
                    self.previewStillWorkingSpeechTask?.cancel()
                    self.previewUnavailable = true
                    self.isGenerating = false
                    self.isPreviewLoading = false
                    self.isRefreshingPreview = false
                    self.statusMessage = self.friendlyGenerationMessage(for: error, destination: query)
                    self.debugDestinationLog("Backend generation failed for \(query): \(error.localizedDescription)")
                }
            }
        }
    }

    func retryPreview() {
        generateWalkthrough(forceRefresh: true)
    }

    func cancelPreviewForEditing() {
        previewTask?.cancel()
        fallbackPreviewTask?.cancel()
        locationWaitTask?.cancel()
        previewStillWorkingSpeechTask?.cancel()
        activePreviewKey = nil
        isWaitingForLocationToGenerate = false
        isGenerating = false
        isPreviewLoading = false
        isRefreshingPreview = false
        previewUnavailable = false
        isUsingBasicGuidanceFallback = false
        walkthrough = nil
        routeCoordinates = []
        nextStageIndex = 0
        previewStageIndex = 0
        flowState = .destinationEntry
        statusMessage = "Edit the destination, then preview arrival."
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
                }
            }
        }
    }

    func startGuidance() {
        guard walkthrough != nil else {
            requestLocationAccess()
            return
        }

        requestLocationAccess()
        pausedForOffRoute = false
        isGuiding = true
        hasStartedGuidance = true
        flowState = .activeGuidance
        statusMessage = "Active guidance."
        performHaptic(.straight)
    }

    func pauseGuidance() {
        isGuiding = false
        stopSpeakingImmediately()
        flowState = .paused
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
        previewTask?.cancel()
        fallbackPreviewTask?.cancel()
        locationWaitTask?.cancel()
        previewStillWorkingSpeechTask?.cancel()
        isWaitingForLocationToGenerate = false
        walkthrough = nil
        resolvedDestinationName = nil
        destinationQuery = ""
        routeCoordinates = []
        nextStageIndex = 0
        previewStageIndex = 0
        pausedForOffRoute = false
        isGuiding = false
        hasArrived = false
        hasStartedGuidance = false
        isGenerating = false
        isPreviewLoading = false
        isRefreshingPreview = false
        previewUnavailable = false
        isUsingBasicGuidanceFallback = false
        flowState = .destinationEntry
        statusMessage = "Enter a destination to prepare a route."
    }

    func repeatCurrentStage() {
        guard let stage = stageForRepeat() else {
            speak("No stage is available to repeat.")
            return
        }
        speakImmediate(stage.description.spokenCue)
        performHaptic(hapticPulse(for: stage))
    }

    func hearPreviewCue(for stage: RouteStage) {
        previewStageIndex = stage.index
        speakImmediate(stage.description.spokenCue)
        performHaptic(hapticPulse(for: stage))
    }

    func speakPreviousStage() {
        guard let stages = walkthrough?.stages, !stages.isEmpty else { return }
        nextStageIndex = max(0, nextStageIndex - 1)
        let stage = stages[nextStageIndex]
        speakImmediate(stage.description.spokenCue)
        performHaptic(hapticPulse(for: stage))
    }

    func speakNextStage() {
        guard let stages = walkthrough?.stages, stages.indices.contains(nextStageIndex) else {
            speak("There are no more stages.")
            return
        }

        let stage = stages[nextStageIndex]
        nextStageIndex += 1
        speakImmediate(stage.description.spokenCue)
        performHaptic(hapticPulse(for: stage))
    }

    func speakImmediate(_ text: String) {
        speak(text, immediate: true)
    }

    func stopSpeakingImmediately() {
        synthesizer.stopSpeaking(at: .immediate)
        elevenLabsSpeechTask?.cancel()
        elevenLabsPlayer?.stop()
        elevenLabsPlayer = nil
        isSpeaking = false
        statusMessage = "Guidance paused."
        speakAccessibilityPrompt("Guidance paused.")
    }

    func playArrivalPreview() {
        let preview = arrivalPreview
        let trusted = preview.trustedNote.map { "Trusted note: \($0)" } ?? ""
        speakImmediate("\(preview.destinationName). \(preview.entranceNote) \(preview.whatToExpect) Landmark chain: \(preview.landmarkChain.joined(separator: ", ")). \(trusted)")
    }

    func saveArrivalMemory() {
        arrivalMemory = ArrivalMemory(
            lastConfidence: confidenceLevel ?? .okay,
            futureNote: futureSelfNote,
            isFamiliarPlace: !isFirstVisit
        )
        statusMessage = "Arrival confidence saved."
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
            if self.isWaitingForLocationToGenerate {
                self.isWaitingForLocationToGenerate = false
                self.locationWaitTask?.cancel()
                self.debugDestinationLog("Current location ready. Retrying destination request.")
                self.generateWalkthrough(forceRefresh: true)
                return
            }
            self.evaluateProgress(location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.errorMessage = error.localizedDescription
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        isSpeaking = true
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
        commandsMutedUntil = Date().addingTimeInterval(0.8)
        reviveGuidanceCommandsAfterSpeech()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false
        commandsMutedUntil = Date().addingTimeInterval(0.5)
        reviveGuidanceCommandsAfterSpeech()
    }

    // Speaking (especially the system synthesizer) can stop the shared mic engine the recognizer
    // uses. After speech ends, bring the recognizer back so voice commands keep working.
    private func reviveGuidanceCommandsAfterSpeech() {
        guard isListeningForGuidanceCommands, !isListeningForDestination else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.isListeningForGuidanceCommands, !self.isListeningForDestination else { return }
            // In the arrival question modes, force a fresh recognition cycle so the prompt's own
            // echo is cleared from the buffer and the user's spoken answer is heard cleanly.
            if self.arrivalVoiceMode != .off || !self.audioEngine.isRunning {
                self.runGuidanceCommandCycle()
            }
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
            speakAccessibilityPrompt(
                "You have reached the arrival area. Please use your normal mobility tools and surroundings to confirm the exact entrance.",
                interrupt: true
            )
            performHaptic(.straight)
            return
        }

        let nextStage = walkthrough.stages[nextStageIndex]
        let distanceToStage = location.distance(from: nextStage.location)
        if distanceToStage <= triggerRadiusMeters {
            speakNextStage()
        }
    }

    private func installWalkthrough(_ response: WalkthroughResponse, isBasicFallback: Bool = false) {
        walkthrough = response
        isUsingBasicGuidanceFallback = isBasicFallback
        debugDestinationLog("Installed \(isBasicFallback ? "basic fallback" : "real") walkthrough id \(response.id).")
        routeCoordinates = PolylineDecoder.decode(response.routeSummary.encodedPolyline)
        if routeCoordinates.isEmpty {
            routeCoordinates = response.stages.map(\.coordinate.locationCoordinate)
        }
        nextStageIndex = 0
        previewStageIndex = 0
        pausedForOffRoute = false
        hasArrived = false
        hasStartedGuidance = false
        offRouteObservationCount = 0
        flowState = .previewing
    }

    private func installBasicGuidance(destination: String, reason: String) {
        fallbackPreviewTask?.cancel()
        if walkthrough == nil {
            installMockWalkthrough(destination: destination)
        }
        isGenerating = false
        isPreviewLoading = false
        isRefreshingPreview = false
        previewUnavailable = true
        statusMessage = limitedDetailsMessage(for: destination)
        debugDestinationLog("Basic fallback installed for \(destination): \(reason)")
    }

    private func scheduleFallbackPreview(for destination: String, cacheKey: String) {
        let delay = fallbackPreviewDelayNanos
        fallbackPreviewTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            await MainActor.run { [weak self] in
                guard let self = self, self.activePreviewKey == cacheKey, self.isGenerating, self.walkthrough == nil else { return }
                self.installMockWalkthrough(destination: destination)
                self.isPreviewLoading = false
                self.previewUnavailable = true
                self.statusMessage = "Preparing arrival preview."
                self.debugDestinationLog("Delayed basic fallback is available for \(destination) while backend continues.")
            }
        }
    }

    private func schedulePreviewStillWorkingPrompt(cacheKey: String) {
        previewStillWorkingSpeechTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            await MainActor.run { [weak self] in
                guard let self,
                      self.activePreviewKey == cacheKey,
                      self.isGenerating else {
                    return
                }

                self.speakAccessibilityPrompt("Still working. HearSight is gathering route and arrival details.")
            }
        }
    }

    private func scheduleLocationWaitTimeout(for destination: String, cacheKey: String) {
        locationWaitTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            await MainActor.run { [weak self] in
                guard let self,
                      self.activePreviewKey == cacheKey,
                      self.isWaitingForLocationToGenerate,
                      self.currentLocation == nil else {
                    return
                }

                self.isWaitingForLocationToGenerate = false
                self.isGenerating = false
                self.isPreviewLoading = false
                self.isRefreshingPreview = false
                self.previewUnavailable = true
                self.statusMessage = "Current location is not available. Turn on Location Services or set a simulator location, then try \(destination) again."
                self.debugDestinationLog("Location wait timed out for \(destination).")
            }
        }
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

    private func haltSpeech() {
        synthesizer.stopSpeaking(at: .immediate)
        elevenLabsSpeechTask?.cancel()
        elevenLabsPlayer?.stop()
        elevenLabsPlayer = nil
        isSpeaking = false
    }

    private func speak(_ text: String, immediate: Bool = false, systemOnly: Bool = false) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        lastSpokenLowercased = trimmed.lowercased()

        if immediate {
            synthesizer.stopSpeaking(at: .immediate)
            elevenLabsSpeechTask?.cancel()
            elevenLabsPlayer?.stop()
            elevenLabsPlayer = nil
        }

        let apiKey = UserDefaults.standard.string(forKey: "elevenLabsAPIKey") ?? ""
        if !systemOnly && !apiKey.isEmpty {
            speakWithElevenLabs(trimmed, apiKey: apiKey)
        } else {
            let utterance = AVSpeechUtterance(string: trimmed)
            utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85
            isSpeaking = true
            synthesizer.speak(utterance)
        }
    }

    private func speakWithElevenLabs(_ text: String, apiKey: String) {
        elevenLabsSpeechTask?.cancel()
        elevenLabsSpeechTask = Task { [weak self] in
            guard let self else { return }
            await MainActor.run { self.isSpeaking = true }
            do {
                let data = try await self.fetchElevenLabsAudio(text, apiKey: apiKey)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    do {
                        let player = try AVAudioPlayer(data: data, fileTypeHint: "mp3")
                        player.delegate = self
                        self.elevenLabsPlayer = player
                        player.play()
                    } catch {
                        self.isSpeaking = false
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    let utterance = AVSpeechUtterance(string: text)
                    utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85
                    self.isSpeaking = true
                    self.synthesizer.speak(utterance)
                }
            }
        }
    }

    private func fetchElevenLabsAudio(_ text: String, apiKey: String) async throws -> Data {
        let stored = UserDefaults.standard.string(forKey: "elevenLabsVoiceID") ?? ""
        let voiceID = stored.isEmpty ? "21m00Tcm4TlvDq8ikWAM" : stored
        guard let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_multilingual_v2",
            "voice_settings": ["stability": 0.5, "similarity_boost": 0.75, "style": 0.0, "use_speaker_boost": true, "speed": 0.85]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 401 {
            await MainActor.run { self.elevenLabsStatus = "ElevenLabs: invalid API key (401)" }
            throw URLError(.userAuthenticationRequired)
        }
        if http.statusCode == 402 {
            await MainActor.run { self.elevenLabsStatus = "ElevenLabs: out of credits (402)" }
            throw URLError(.badServerResponse)
        }
        guard http.statusCode == 200 else {
            await MainActor.run { self.elevenLabsStatus = "ElevenLabs: error \(http.statusCode)" }
            throw URLError(.badServerResponse)
        }
        await MainActor.run { self.elevenLabsStatus = "ElevenLabs: OK" }
        return data
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.elevenLabsPlayer = nil
            self.isSpeaking = false
            self.commandsMutedUntil = Date().addingTimeInterval(0.8)
            self.reviveGuidanceCommandsAfterSpeech()
        }
    }

    private func beginDestinationRecognition() {
        stopDestinationListening()
        recognizedDestinationText = nil

        // Speak prompt first. The mic doesn't start until the prompt is fully done
        // so VoiceOver audio never enters the recognition buffer.
        speakAccessibilityPrompt("Listening. Say your destination now.", interrupt: true)
        speechRecognitionStatus = "Listening..."
        voiceInputState = .listening
        statusMessage = "Listening for your destination."

        // 3 seconds covers the ~2s TTS prompt plus a buffer for VoiceOver UI reads
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self, self.voiceInputState == .listening else { return }
            self.startFreshRecognitionSession()
        }
    }

    private func startFreshRecognitionSession() {
        do {
            try configureAudioSessionForSpeech()
        } catch {
            showMicrophoneUnavailableMessage()
            return
        }

        // Create request NOW (after delay) so no warmup audio enters the buffer
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard isValidInputFormat(recordingFormat) else {
            showMicrophoneUnavailableMessage()
            return
        }

        // Remove any existing tap first. Installing a second tap on the same bus crashes with
        // "required condition is false: nullptr == Tap()". This can happen when the voice-command
        // recognizer still has a tap on the shared input node.
        inputNode.removeTap(onBus: 0)
        isAudioTapInstalled = false

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }
        isAudioTapInstalled = true

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let result {
                    if let cleanedText = self.cleanRecognizedDestination(result.bestTranscription.formattedString) {
                        self.recognizedDestinationText = cleanedText
                        self.destinationQuery = cleanedText
                        self.resetSilenceTimer()
                    }
                    self.speechRecognitionStatus = result.isFinal ? "Destination captured." : "Listening..."
                    self.voiceInputState = result.isFinal ? .success : .listening
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
            micAcceptingInput = true
            resetSilenceTimer()
        } catch {
            showMicrophoneUnavailableMessage()
        }
    }

    private func configureAudioSessionForSpeech() throws {
        let audioSession = AVAudioSession.sharedInstance()
        // Reconfigure every cycle so the microphone input is reliably ready after the speaker played
        // audio (a small stutter is an acceptable trade for the mic actually capturing).
        try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.duckOthers, .defaultToSpeaker])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func isValidInputFormat(_ format: AVAudioFormat) -> Bool {
        format.sampleRate > 0 && format.channelCount > 0
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                let wordCount = self.recognizedDestinationText?
                    .split(separator: " ").count ?? 0
                if wordCount >= 2 {
                    self.stopDestinationListening(confirm: true)
                } else {
                    // Single word — likely noise or VoiceOver pickup. Keep listening.
                    self.recognizedDestinationText = nil
                    self.destinationQuery = ""
                    self.resetSilenceTimer()
                }
            }
        }
    }

    private func showMicrophoneUnavailableMessage() {
        stopDestinationListening()
        speechRecognitionStatus = "Microphone unavailable. Type destination."
        statusMessage = "Microphone unavailable. Type destination."
        voiceInputState = .unavailable("Microphone unavailable. Type destination.")
    }

    private func cleanRecognizedDestination(_ text: String) -> String? {
        var cleaned = text
            .replacingOccurrences(of: "say your destination now", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "say your", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "listening for destination", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "listening", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "destination", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "now", with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        while cleaned.contains("  ") {
            cleaned = cleaned.replacingOccurrences(of: "  ", with: " ")
        }

        let trimmed = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: " .,!?\n\t"))
        guard trimmed.count >= 3 else { return nil }
        return trimmed
    }

    // MARK: - Offline demo route (TSA demo, no backend required)

    func installOfflineDemoWalkthrough() {
        let gaylord = CLLocationCoordinate2D(latitude: 38.7807, longitude: -77.0162)
        let destinationName = "Rosa Mexicano"
        let destinationAddress = "153 Waterfront St, National Harbor, MD 20745"
        let destinationCoordinate = CLLocationCoordinate2D(latitude: 38.7820, longitude: -77.0168)

        // Simulate standing at the Gaylord National so the flow enables without real GPS.
        currentLocation = CLLocation(latitude: gaylord.latitude, longitude: gaylord.longitude)

        let stages = [
            mockStage(
                index: 0,
                coordinate: gaylord,
                instruction: "Exit the Gaylord National Resort onto Waterfront Street.",
                cue: "Exit the Gaylord National Resort through the main entrance onto Waterfront Street. The Gaylord is a large hotel with a glass atrium that faces the Potomac River and the National Harbor waterfront.",
                landmarks: ["Gaylord National Resort"],
                kind: .maneuver
            ),
            mockStage(
                index: 1,
                coordinate: CLLocationCoordinate2D(latitude: 38.7812, longitude: -77.0164),
                instruction: "Head north along Waterfront Street.",
                cue: "Head north along Waterfront Street. This is the main waterfront walkway, lined with restaurants and shops, with the Potomac River on one side. You will pass near the Capital Wheel, the large Ferris wheel out on the pier.",
                landmarks: ["Waterfront Street", "The Capital Wheel"],
                kind: .maneuver
            ),
            mockStage(
                index: 2,
                coordinate: CLLocationCoordinate2D(latitude: 38.7816, longitude: -77.0166),
                instruction: "Continue toward American Way.",
                cue: "Continue along Waterfront Street toward American Way, the main street that runs up from the water. The restaurants are clustered along this stretch of the harbor.",
                landmarks: ["American Way"],
                kind: .checkpoint
            ),
            mockStage(
                index: 3,
                coordinate: destinationCoordinate,
                instruction: "Arrive at Rosa Mexicano on Waterfront Street.",
                cue: "Rosa Mexicano is at 153 Waterfront Street, on the harbor side. It is a Mexican restaurant on the ground floor, with its entrance facing the waterfront walkway.",
                landmarks: ["Rosa Mexicano"],
                kind: .destination
            )
        ]

        let response = WalkthroughResponse(
            id: "offline-demo-national-harbor",
            language: Locale.current.identifier,
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            destination: WalkthroughDestination(
                name: destinationName,
                formattedAddress: destinationAddress,
                coordinate: CoordinatePayload(destinationCoordinate),
                confidence: "high"
            ),
            routeSummary: RouteSummary(
                distanceMeters: 280,
                duration: "4 mins",
                encodedPolyline: nil,
                stageCount: stages.count,
                safetyNotice: "Use your normal mobility tools to confirm the entrance on arrival."
            ),
            stages: stages
        )

        destinationQuery = destinationName
        resolvedDestinationName = destinationName
        previewUnavailable = false
        isUsingBasicGuidanceFallback = false
        isGenerating = false
        isPreviewLoading = false
        isRefreshingPreview = false
        statusMessage = "Offline demo route ready with \(stages.count) cues."
        installWalkthrough(response, isBasicFallback: false)
        speakPreviewReadyIfNeeded(for: response)
    }

    private func installMockWalkthrough(destination: String) {
        let baseCoordinate = currentLocation?.coordinate ?? CLLocationCoordinate2D(latitude: 41.8781, longitude: -87.6298)
        let stages = [
            mockStage(
                index: 0,
                coordinate: baseCoordinate,
                instruction: "Begin heading toward \(destination).",
                cue: "Start heading toward \(destination). Stay on the sidewalk and listen for traffic to your left and right to stay oriented.",
                landmarks: ["Main entrance area"],
                kind: .maneuver
            ),
            mockStage(
                index: 1,
                coordinate: CLLocationCoordinate2D(latitude: baseCoordinate.latitude + 0.0002, longitude: baseCoordinate.longitude + 0.0002),
                instruction: "Continue toward \(destination).",
                cue: "As you get closer to \(destination), slow down. Listen for building entrances, a change in foot traffic, or any audible activity that signals you are near the right place.",
                landmarks: ["Building front", "Pickup or parking area"],
                kind: .checkpoint
            ),
            mockStage(
                index: 2,
                coordinate: CLLocationCoordinate2D(latitude: baseCoordinate.latitude + 0.0003, longitude: baseCoordinate.longitude + 0.0003),
                instruction: "You have arrived at \(destination).",
                cue: "You have arrived at \(destination). Stop and listen for building sounds, a doorway, or foot traffic entering and exiting to locate the correct entrance.",
                landmarks: ["Main entrance area"],
                kind: .destination
            )
        ]

        let response = WalkthroughResponse(
            id: UUID().uuidString,
            language: Locale.current.identifier,
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            destination: WalkthroughDestination(
                name: destination,
                formattedAddress: nil,
                coordinate: CoordinatePayload(baseCoordinate),
                confidence: "fallback"
            ),
            routeSummary: RouteSummary(
                distanceMeters: 0,
                duration: nil,
                encodedPolyline: nil,
                stageCount: stages.count,
                safetyNotice: "Confirm route details before walking."
            ),
            stages: stages
        )

        resolvedDestinationName = destination
        installWalkthrough(response, isBasicFallback: true)
    }

    private func mockStage(
        index: Int,
        coordinate: CLLocationCoordinate2D,
        instruction: String,
        cue: String,
        landmarks: [String],
        kind: StageKind
    ) -> RouteStage {
        RouteStage(
            id: UUID().uuidString,
            index: index,
            coordinate: CoordinatePayload(coordinate),
            routeDistanceMeters: index * 35,
            headingDegrees: 0,
            routeInstruction: instruction,
            kind: kind,
            snapshotUrl: nil,
            streetView: nil,
            description: StageDescription(
                spokenCue: cue,
                landmarks: landmarks,
                crossingOrIntersectionNotes: [],
                uncertainties: [],
                confidence: 0
            ),
            context: StageContext(
                streetName: nil,
                nearestIntersection: nil,
                nearbyLandmarks: landmarks,
                streetViewAvailable: false,
                streetViewDate: nil,
                fallbackReason: nil
            )
        )
    }

    private func expectationText(from stage: RouteStage?) -> String {
        guard let stage else {
            return "Use entrance cues, nearby landmarks, and normal mobility tools near arrival."
        }

        if !stage.description.crossingOrIntersectionNotes.isEmpty {
            return stage.description.crossingOrIntersectionNotes.prefix(3).joined(separator: " ")
        }

        if let street = stage.context?.streetName, !street.isEmpty {
            return "Expect the final approach near \(street)."
        }

        return "Use entrance cues, nearby landmarks, and normal mobility tools near arrival."
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

    private func limitedDetailsMessage(for destination: String) -> String {
        "Arrival details are limited for \"\(destination)\". Try a more specific name or address for a better preview."
    }

    private func friendlyGenerationMessage(for error: Error, destination: String) -> String {
        let nsError = error as NSError

        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost, NSURLErrorNotConnectedToInternet:
                return "HearSight could not reach the preview service. Start the backend, then try \(destination) again."
            case NSURLErrorTimedOut:
                return "The preview service took too long to recognize \(destination). Try a more specific name or address."
            default:
                return "HearSight could not recognize \(destination) right now. Check the backend connection and try again."
            }
        }

        if let apiError = error as? WalkthroughAPIError {
            switch apiError {
            case .serverError(let message) where message.localizedCaseInsensitiveContains("missing required API"):
                return "The preview service is missing API keys. Add the backend configuration, then try \(destination) again."
            default:
                break
            }
        }

        return limitedDetailsMessage(for: destination)
    }

    private func normalizedCacheKey(for destination: String) -> String {
        destination
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    private func debugDestinationLog(_ message: String) {
        #if DEBUG
        print("[HearSight Destination] \(message)")
        #endif
    }
}
