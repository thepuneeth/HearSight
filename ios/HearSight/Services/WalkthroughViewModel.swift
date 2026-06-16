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
    @Published var currentLocationName: String?
    @Published var manualCurrentLocationQuery = ""
    @Published var isUsingManualCurrentLocation = false
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var statusMessage = "Enter a destination to prepare a route."
    @Published var errorMessage: String?
    @Published var isGenerating = false
    @Published var routeGenerationProgress = 0.0
    @Published var routeGenerationTitle = "Preparing walking route"
    @Published var routeGenerationDetail = "Using your current location."
    @Published var isGuiding = false
    @Published var isCheckingBackend = false
    @Published var nextStageIndex = 0
    @Published var previewStageIndex = 0
    @Published var pausedForOffRoute = false
    @Published var flowState: RouteFlowState = .destinationEntry
    @Published var isListeningForDestination = false
    @Published var isListeningForCurrentLocation = false
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

    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private let synthesizer = AVSpeechSynthesizer()
    private var ttsAudioPlayer: AVAudioPlayer?
    private var ttsPlaybackTask: Task<Void, Never>?
    private var ttsAudioCache: [String: Data] = [:]
    private var hasUsedRemoteTts = false
    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var isAudioTapInstalled = false
    private var recognizedDestinationText: String?
    private var recognizedCurrentLocationText: String?
    private var routeCoordinates: [CLLocationCoordinate2D] = []
    private var poorAccuracyWarningDate: Date?
    private var offRouteObservationCount = 0
    private var previewTask: Task<Void, Never>?
    private var fallbackPreviewTask: Task<Void, Never>?
    private var locationWaitTask: Task<Void, Never>?
    private var previewStillWorkingSpeechTask: Task<Void, Never>?
    private var activePreviewKey: String?
    private var isWaitingForLocationToGenerate = false
    private var isResolvingCurrentLocationName = false
    private var isResolvingManualCurrentLocation = false
    private var lastGeocodedLocation: CLLocation?
    private var hasSpokenHomeIntro = false
    private var lastSpokenDestinationEntry: String?
    private var lastSpokenPreviewReadyID: String?

    private static var walkthroughCache: [String: WalkthroughResponse] = [:]

    private let triggerRadiusMeters: CLLocationDistance = 22
    private let acceptableAccuracyMeters: CLLocationAccuracy = 35
    private let offRouteRadiusMeters: CLLocationDistance = 90
    private let routeOriginMaxAge: TimeInterval = 45
    private let routeOriginAcceptableAccuracyMeters: CLLocationAccuracy = 120
    private let fallbackPreviewDelayNanos: UInt64 = 7_000_000_000
    private let maxTtsCacheEntries = 40

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
        return "Backend ready"
    }

    var currentLocationTitle: String {
        if isUsingManualCurrentLocation {
            return currentLocationName ?? "Manual current location"
        }

        switch authorizationStatus {
        case .denied, .restricted:
            return "Location access is off"
        case .notDetermined:
            return "Waiting for location permission"
        case .authorizedAlways, .authorizedWhenInUse:
            guard currentLocation != nil else { return "Finding current location" }
            return currentLocationName ?? "Current location found"
        @unknown default:
            return "Finding current location"
        }
    }

    var currentLocationDetail: String {
        if isUsingManualCurrentLocation, let location = currentLocation {
            let accuracyText = location.horizontalAccuracy >= 0
                ? "Accuracy about \(Int(location.horizontalAccuracy.rounded())) meters."
                : "Accuracy unavailable."
            return "\(coordinateSummary(for: location)) \(accuracyText)"
        }

        switch authorizationStatus {
        case .denied, .restricted:
            return "Enable Location Services for HearSight to build walking routes."
        case .notDetermined:
            return "Allow location access when prompted."
        case .authorizedAlways, .authorizedWhenInUse:
            guard let location = currentLocation else {
                return "Waiting for GPS."
            }

            let accuracyText = location.horizontalAccuracy >= 0
                ? "Accuracy about \(Int(location.horizontalAccuracy.rounded())) meters."
                : "Accuracy unavailable."
            return "\(coordinateSummary(for: location)) \(accuracyText)"
        @unknown default:
            return "Waiting for GPS."
        }
    }

    var currentLocationSystemImage: String {
        if isUsingManualCurrentLocation {
            return "mappin.and.ellipse"
        }

        switch authorizationStatus {
        case .denied, .restricted:
            return "location.slash.fill"
        case .authorizedAlways, .authorizedWhenInUse:
            return currentLocation == nil ? "location.magnifyingglass" : "location.fill"
        default:
            return "location"
        }
    }

    func setManualCurrentLocation(latitude: Double, longitude: Double) {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        guard CLLocationCoordinate2DIsValid(coordinate) else {
            statusMessage = "Manual location is not valid."
            performHaptic(.warning)
            return
        }

        let location = CLLocation(
            coordinate: coordinate,
            altitude: 0,
            horizontalAccuracy: 8,
            verticalAccuracy: 8,
            timestamp: Date()
        )
        isUsingManualCurrentLocation = true
        currentLocation = location
        currentLocationName = "Manual current location"
        lastGeocodedLocation = nil
        updateCurrentLocationName(for: location)
        statusMessage = "Manual current location set."
        performHaptic(.straight)
    }

    func setManualCurrentLocation(from query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusMessage = "Type or speak a current location first."
            performHaptic(.warning)
            return
        }

        isResolvingManualCurrentLocation = true
        manualCurrentLocationQuery = trimmed
        statusMessage = "Finding current location."
        geocoder.geocodeAddressString(trimmed) { [weak self] placemarks, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isResolvingManualCurrentLocation = false

                guard error == nil,
                      let location = placemarks?.first?.location else {
                    self.statusMessage = "Could not find that current location."
                    self.performHaptic(.warning)
                    return
                }

                self.isUsingManualCurrentLocation = true
                self.currentLocation = location
                self.currentLocationName = trimmed
                self.lastGeocodedLocation = location
                self.statusMessage = "Manual current location set."
                self.performHaptic(.straight)
            }
        }
    }

    func resumeLiveCurrentLocation() {
        isUsingManualCurrentLocation = false
        currentLocationName = nil
        manualCurrentLocationQuery = ""
        lastGeocodedLocation = nil
        statusMessage = "Using live current location."
        requestLocationAccess()
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
        authorizationStatus = locationManager.authorizationStatus

        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.startUpdatingLocation()
            locationManager.startUpdatingHeading()
        case .denied, .restricted:
            statusMessage = "Location access is off. Enable Location Services for HearSight, then try again."
        @unknown default:
            locationManager.requestWhenInUseAuthorization()
        }
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
        speakAccessibilityPrompt("Destination entered. Press Preview Arrival to continue.")
    }

    private func speakPreviewReadyIfNeeded(for walkthrough: WalkthroughResponse) {
        guard walkthrough.id != lastSpokenPreviewReadyID else { return }
        lastSpokenPreviewReadyID = walkthrough.id
        speakAccessibilityPrompt("Arrival preview ready. Review the cues, then press Start Guidance when ready.")
    }

    func toggleDestinationVoiceInput() {
        if isListeningForDestination {
            stopDestinationListening(confirm: true)
        } else {
            startDestinationListening()
        }
    }

    func toggleCurrentLocationVoiceInput() {
        if isListeningForCurrentLocation {
            stopCurrentLocationListening(confirm: true)
        } else {
            startCurrentLocationListening()
        }
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
                    self.voiceInputState = .unavailable("Speech recognition unavailable. Type destination.")
                    self.speechRecognitionStatus = "Speech recognition is not available. Type the destination instead."
                    self.statusMessage = self.speechRecognitionStatus
                    return
                }
                self.beginDestinationRecognition()
            }
        }
    }

    func startCurrentLocationListening() {
        guard !isListeningForCurrentLocation else {
            stopCurrentLocationListening(confirm: true)
            return
        }

        guard speechRecognizer?.isAvailable == true else {
            showMicrophoneUnavailableMessage(context: "current location")
            return
        }

        SFSpeechRecognizer.requestAuthorization { [weak self] authorizationStatus in
            DispatchQueue.main.async {
                guard let self else { return }
                guard authorizationStatus == .authorized else {
                    self.voiceInputState = .unavailable("Speech recognition unavailable. Type current location.")
                    self.speechRecognitionStatus = "Speech recognition is not available. Type the current location instead."
                    self.statusMessage = self.speechRecognitionStatus
                    return
                }
                self.beginCurrentLocationRecognition()
            }
        }
    }

    func stopDestinationListening(confirm: Bool = false) {
        stopRecognitionSession()
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

    func stopCurrentLocationListening(confirm: Bool = false) {
        stopRecognitionSession()
        isListeningForCurrentLocation = false

        if confirm {
            let location = recognizedCurrentLocationText ?? ""
            if location.isEmpty {
                speechRecognitionStatus = "No current location heard. Try again or type it."
                voiceInputState = .failure(speechRecognitionStatus)
            } else {
                manualCurrentLocationQuery = location
                speechRecognitionStatus = "Current location captured."
                voiceInputState = .success
            }
        } else if manualCurrentLocationQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            voiceInputState = .idle
        }
        recognizedCurrentLocationText = nil
    }

    private func stopRecognitionSession() {
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
    }

    func generateWalkthrough(forceRefresh: Bool = false) {
        stopDestinationListening()
        stopCurrentLocationListening()

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
        routeGenerationProgress = 0.12
        routeGenerationTitle = "Preparing walking route"
        routeGenerationDetail = "Using your current location."
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

        guard let origin = usableCurrentLocation?.coordinate else {
            isWaitingForLocationToGenerate = true
            if currentLocation == nil {
                statusMessage = "Waiting for current location before resolving \(query)."
                debugDestinationLog("Waiting for current location before requesting \(query).")
            } else {
                statusMessage = "Waiting for a more accurate current location before resolving \(query)."
                debugDestinationLog("Waiting for a fresher or more accurate location before requesting \(query).")
            }
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
                await MainActor.run {
                    self.routeGenerationProgress = 0.28
                    self.routeGenerationTitle = "Connecting to route service"
                    self.routeGenerationDetail = "Confirming the route engine is available."
                }

                let health = try await client.health()
                if !health.missingConfig.isEmpty {
                    throw WalkthroughAPIError.serverError("Preview service is not fully configured.")
                }

                await MainActor.run {
                    self.routeGenerationProgress = 0.52
                    self.routeGenerationTitle = "Building walking route"
                    self.routeGenerationDetail = "Finding a walking path and route checkpoints."
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
                    self.routeGenerationProgress = 1
                    self.routeGenerationTitle = "Route preview ready"
                    self.routeGenerationDetail = "Opening the cue preview."
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
                    self.routeGenerationProgress = 0
                    self.routeGenerationTitle = "Preparing walking route"
                    self.routeGenerationDetail = "Using your current location."
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

    func resetRoute(announcePause: Bool = true) {
        stopDestinationListening()
        if announcePause {
            stopSpeakingImmediately()
        } else {
            stopSpeechPlayback()
        }
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
        routeGenerationProgress = 0
        routeGenerationTitle = "Preparing walking route"
        routeGenerationDetail = "Using your current location."
        isPreviewLoading = false
        isRefreshingPreview = false
        previewUnavailable = false
        isUsingBasicGuidanceFallback = false
        flowState = .destinationEntry
        statusMessage = "Enter a destination to prepare a route."
    }

    func endRoute() {
        resetRoute(announcePause: false)
        statusMessage = "Route ended."
        speechRecognitionStatus = "Route ended. Speak or type a new destination."
        speakAccessibilityPrompt("Route ended. Speak or type a new destination.", interrupt: true)
        performHaptic(.warning)
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
        stopSpeechPlayback()
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
            } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
                self.isWaitingForLocationToGenerate = false
                self.locationWaitTask?.cancel()
                self.isGenerating = false
                self.isPreviewLoading = false
                self.statusMessage = "Location access is off. Enable Location Services for HearSight, then try again."
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !isUsingManualCurrentLocation else { return }
        guard let location = locations.reversed().first(where: isFreshLocation) ?? locations.last else { return }
        DispatchQueue.main.async {
            self.currentLocation = location
            self.updateCurrentLocationName(for: location)
            if self.isWaitingForLocationToGenerate {
                guard self.isUsableRouteOrigin(location) else {
                    self.statusMessage = "Waiting for a more accurate current location."
                    self.debugDestinationLog("Received location, but accuracy or age is not route-ready.")
                    return
                }

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
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isSpeaking = false
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        isSpeaking = false
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
                      self.usableCurrentLocation == nil else {
                    return
                }

                self.isWaitingForLocationToGenerate = false
                self.isGenerating = false
                self.isPreviewLoading = false
                self.isRefreshingPreview = false
                self.previewUnavailable = true
                self.statusMessage = "Current location is not ready. Turn on Location Services or set a manual current location, then try \(destination) again."
                self.debugDestinationLog("Location wait timed out for \(destination).")
            }
        }
    }

    private var usableCurrentLocation: CLLocation? {
        guard let currentLocation, isUsableRouteOrigin(currentLocation) else { return nil }
        return currentLocation
    }

    private func updateCurrentLocationName(for location: CLLocation) {
        guard location.horizontalAccuracy >= 0 else { return }
        if let lastGeocodedLocation,
           lastGeocodedLocation.distance(from: location) < 50,
           currentLocationName != nil {
            return
        }
        guard !isResolvingCurrentLocationName else { return }

        isResolvingCurrentLocationName = true
        lastGeocodedLocation = location
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isResolvingCurrentLocationName = false
                guard self.currentLocation?.distance(from: location) ?? .greatestFiniteMagnitude < 100 else { return }
                self.currentLocationName = placemarks?.compactMap(self.locationName(from:)).first
            }
        }
    }

    private func locationName(from placemark: CLPlacemark) -> String? {
        let street = [placemark.subThoroughfare, placemark.thoroughfare]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !street.isEmpty {
            return street
        }

        var seenAreas = Set<String>()
        let area = [placemark.name, placemark.locality, placemark.administrativeArea]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seenAreas.insert($0).inserted }
            .prefix(2)
            .joined(separator: ", ")
        return area.isEmpty ? nil : area
    }

    private func coordinateSummary(for location: CLLocation) -> String {
        let latitude = String(format: "%.5f", location.coordinate.latitude)
        let longitude = String(format: "%.5f", location.coordinate.longitude)
        return "Lat \(latitude), Long \(longitude)."
    }

    private func isFreshLocation(_ location: CLLocation) -> Bool {
        abs(location.timestamp.timeIntervalSinceNow) <= routeOriginMaxAge
    }

    private func isUsableRouteOrigin(_ location: CLLocation) -> Bool {
        isFreshLocation(location)
            && location.horizontalAccuracy >= 0
            && location.horizontalAccuracy <= routeOriginAcceptableAccuracyMeters
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

    private func speak(_ text: String, immediate: Bool = false) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        stopSpeechPlayback()

        let language = Locale.current.identifier
        let cacheKey = ttsCacheKey(text: trimmed, language: language)
        isSpeaking = true

        ttsPlaybackTask = Task { [weak self] in
            guard let self else { return }

            do {
                let audioData = try await self.ttsAudioData(text: trimmed, language: language, cacheKey: cacheKey)
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.playTtsAudio(audioData, fallbackText: trimmed)
                }
            } catch {
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    if self.hasUsedRemoteTts {
                        self.isSpeaking = false
                        self.debugDestinationLog("Google TTS failed after remote voice was active; skipping Apple fallback to keep voice consistent.")
                    } else {
                        self.speakWithApple(text: trimmed)
                    }
                }
            }
        }
    }

    private func ttsAudioData(text: String, language: String, cacheKey: String) async throws -> Data {
        if let cached = await MainActor.run(body: { ttsAudioCache[cacheKey] }) {
            return cached
        }

        let audioData = try await WalkthroughAPIClient(serverBaseURL: serverBaseURL)
            .synthesizeSpeech(text: text, language: language)

        await MainActor.run {
            if self.ttsAudioCache.count >= self.maxTtsCacheEntries {
                self.ttsAudioCache.removeAll(keepingCapacity: true)
            }
            self.ttsAudioCache[cacheKey] = audioData
        }

        return audioData
    }

    private func playTtsAudio(_ audioData: Data, fallbackText: String) {
        do {
            stopActiveSpeech(cancelPendingTts: false)
            let player = try AVAudioPlayer(data: audioData)
            player.delegate = self
            player.prepareToPlay()
            ttsAudioPlayer = player
            hasUsedRemoteTts = true
            isSpeaking = true
            if !player.play() {
                handleRemoteTtsPlaybackFailure(fallbackText: fallbackText)
            }
        } catch {
            handleRemoteTtsPlaybackFailure(fallbackText: fallbackText)
        }
    }

    private func speakWithApple(text: String) {
        stopActiveSpeech(cancelPendingTts: false)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    private func handleRemoteTtsPlaybackFailure(fallbackText: String) {
        if hasUsedRemoteTts {
            isSpeaking = false
            debugDestinationLog("Google TTS audio could not be played; skipping Apple fallback to keep voice consistent.")
        } else {
            speakWithApple(text: fallbackText)
        }
    }

    private func stopSpeechPlayback() {
        stopActiveSpeech(cancelPendingTts: true)
    }

    private func stopActiveSpeech(cancelPendingTts: Bool) {
        if cancelPendingTts {
            ttsPlaybackTask?.cancel()
            ttsPlaybackTask = nil
        }
        ttsAudioPlayer?.stop()
        ttsAudioPlayer = nil
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    private func ttsCacheKey(text: String, language: String) -> String {
        "\(language)|\(text)"
    }

    private func beginDestinationRecognition() {
        stopDestinationListening()
        stopCurrentLocationListening()

        do {
            try configureAudioSessionForSpeech()
        } catch {
            showMicrophoneUnavailableMessage(context: "destination")
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        recognizedDestinationText = nil

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard isValidInputFormat(recordingFormat) else {
            showMicrophoneUnavailableMessage(context: "destination")
            return
        }

        stopSpeechPlayback()

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
                    self.speechRecognitionStatus = result.isFinal ? "Destination captured." : "Listening..."
                    self.voiceInputState = result.isFinal ? .success : .listening
                    if result.isFinal {
                        self.stopDestinationListening(confirm: true)
                    }
                    return
                }

                if error != nil {
                    self.stopDestinationListening()
                    self.showMicrophoneUnavailableMessage(context: "destination")
                }
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isListeningForDestination = true
            speechRecognitionStatus = "Listening..."
            voiceInputState = .listening
            statusMessage = "Listening for your destination."
            speakAccessibilityPrompt("Listening. Say your destination now.", interrupt: true)
        } catch {
            showMicrophoneUnavailableMessage(context: "destination")
        }
    }

    private func beginCurrentLocationRecognition() {
        stopDestinationListening()
        stopCurrentLocationListening()

        do {
            try configureAudioSessionForSpeech()
        } catch {
            showMicrophoneUnavailableMessage(context: "current location")
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        recognizedCurrentLocationText = nil

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard isValidInputFormat(recordingFormat) else {
            showMicrophoneUnavailableMessage(context: "current location")
            return
        }

        stopSpeechPlayback()

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        isAudioTapInstalled = true

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let result {
                    if let cleanedText = self.cleanRecognizedCurrentLocation(result.bestTranscription.formattedString) {
                        self.recognizedCurrentLocationText = cleanedText
                        self.manualCurrentLocationQuery = cleanedText
                    }
                    self.speechRecognitionStatus = result.isFinal ? "Current location captured." : "Listening..."
                    self.voiceInputState = result.isFinal ? .success : .listening
                    if result.isFinal {
                        self.stopCurrentLocationListening(confirm: true)
                    }
                    return
                }

                if error != nil {
                    self.stopCurrentLocationListening()
                    self.showMicrophoneUnavailableMessage(context: "current location")
                }
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isListeningForCurrentLocation = true
            speechRecognitionStatus = "Listening..."
            voiceInputState = .listening
            statusMessage = "Listening for your current location."
            speakAccessibilityPrompt("Listening. Say your current location now.", interrupt: true)
        } catch {
            showMicrophoneUnavailableMessage(context: "current location")
        }
    }

    private func configureAudioSessionForSpeech() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func isValidInputFormat(_ format: AVAudioFormat) -> Bool {
        format.sampleRate > 0 && format.channelCount > 0
    }

    private func showMicrophoneUnavailableMessage(context: String = "destination") {
        stopDestinationListening()
        stopCurrentLocationListening()
        let target = context == "current location" ? "current location" : "destination"
        speechRecognitionStatus = "Microphone unavailable. Type \(target)."
        statusMessage = "Microphone unavailable. Type \(target)."
        voiceInputState = .unavailable("Microphone unavailable. Type \(target).")
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

    private func cleanRecognizedCurrentLocation(_ text: String) -> String? {
        var cleaned = text
            .replacingOccurrences(of: "say your current location now", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "current location", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "location", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "listening", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "now", with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        while cleaned.contains("  ") {
            cleaned = cleaned.replacingOccurrences(of: "  ", with: " ")
        }

        let trimmed = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: " .,!?\n\t"))
        guard trimmed.count >= 3 else { return nil }
        return trimmed
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
