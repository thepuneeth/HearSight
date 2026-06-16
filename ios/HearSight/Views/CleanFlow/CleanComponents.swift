import SwiftUI

extension HearSightTheme {
    enum Spacing {
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 18
        static let lg: CGFloat = 24
    }

    enum Radius {
        static let md: CGFloat = 16
        static let card: CGFloat = 22
    }

    static func background(_ colorScheme: ColorScheme) -> Color {
        current(for: colorScheme).background
    }

    static func panel(_ colorScheme: ColorScheme) -> Color {
        current(for: colorScheme).surface
    }

    static func insetPanel(_ colorScheme: ColorScheme) -> Color {
        current(for: colorScheme).field.opacity(colorScheme == .dark ? 0.5 : 0.62)
    }

    static func primary(_ colorScheme: ColorScheme) -> Color {
        current(for: colorScheme).accent
    }

    static func secondary(_ colorScheme: ColorScheme) -> Color {
        current(for: colorScheme).secondaryAccent
    }

    static func cardStroke(_ colorScheme: ColorScheme) -> Color {
        current(for: colorScheme).stroke
    }

    static func glow(_ colorScheme: ColorScheme) -> Color {
        current(for: colorScheme).glow.opacity(0.32)
    }
}

struct CleanFlowBriefing {
    var destinationName: String
    var visitType: String
    var entranceCue: String
    var whatToExpect: [String]
    var landmarkChain: [String]
    var trustedNote: String?
    var currentCue: String
    var arrivalFocus: String
    var arrivalKeyLandmark: String?
    var guidanceCues: [String] = []
    var isUsingRealData = false
    var isPreparing = false
    var fallbackMessage: String?

    static let streetViewLimitation = "Use the landmark chain and normal mobility tools near arrival."

    private struct CleanLandmarkCandidate {
        let text: String
        let isNearArrival: Bool
        let routeDistanceMeters: Int
    }

    static let sample = CleanFlowBriefing(
        destinationName: "Nolensville high school",
        visitType: "First visit",
        entranceCue: "Use the main entrance near the front drive. Confirm with the landmark chain before entering.",
        whatToExpect: [
            "Traffic may be audible near the main road.",
            "The final approach may include a sidewalk and open front area.",
            "Use the entrance cue and landmarks to confirm the correct side."
        ],
        landmarkChain: [
            "Near arrival: Nolensville First United Methodist Church",
            "Near arrival: White house with a porch",
            "Near arrival: White church with a red roof",
            "Near arrival: Red covered shelter"
        ],
        trustedNote: "Expect a busy lobby and security desk inside.",
        currentCue: "Continue toward the destination. Listen for traffic and use the sidewalk edge as your reference.",
        arrivalFocus: "Use the landmark chain to confirm the correct entrance before going inside.",
        arrivalKeyLandmark: "Near arrival: Nolensville First United Methodist Church"
    )

    static func resolved(from viewModel: WalkthroughViewModel) -> CleanFlowBriefing {
        let destination = destinationName(from: viewModel)
        let visitType = viewModel.isFirstVisit ? "First visit" : "Familiar route"
        let isPreparing = viewModel.isGenerating && (viewModel.walkthrough == nil || viewModel.isUsingBasicGuidanceFallback)
        let fallbackMessage = (viewModel.previewUnavailable || viewModel.isUsingBasicGuidanceFallback)
            ? limitedDetailsMessage(for: destination)
            : nil

        var data = runtimeFallback(
            destinationName: destination,
            visitType: visitType,
            isPreparing: isPreparing,
            fallbackMessage: fallbackMessage
        )

        if let walkthrough = viewModel.walkthrough, !viewModel.isUsingBasicGuidanceFallback {
            data.isUsingRealData = true
            applyRealWalkthrough(walkthrough, to: &data, viewModel: viewModel)
            debugDestinationLog("CleanFlow using real walkthrough for \(data.destinationName)")
            return data
        }

        if let walkthrough = viewModel.walkthrough, viewModel.isUsingBasicGuidanceFallback {
            applyBasicFallbackWalkthrough(walkthrough, to: &data)
            debugDestinationLog("CleanFlow using basic fallback for \(data.destinationName)")
            return data
        }

        debugDestinationLog("CleanFlow using generic fallback for \(data.destinationName)")
        return data
    }

    private static func runtimeFallback(
        destinationName: String,
        visitType: String,
        isPreparing: Bool,
        fallbackMessage: String?
    ) -> CleanFlowBriefing {
        let landmarks = fallbackLandmarks(destinationName: destinationName)
        let keyLandmark = firstArrivalLandmark(in: landmarks)

        return CleanFlowBriefing(
            destinationName: destinationName,
            visitType: visitType,
            entranceCue: "Arrival details are limited for \(destinationName). Use nearby signage, building entrances, and your normal mobility tools to confirm the correct entrance.",
            whatToExpect: [
                "Route details may be limited for this destination.",
                "Use available sidewalks, crossings, and audible traffic cues near arrival.",
                "Confirm the entrance with signage, landmarks, or a nearby person if needed."
            ],
            landmarkChain: landmarks,
            trustedNote: nil,
            currentCue: "Continue toward \(destinationName). Use available route guidance and listen for nearby traffic or entrance activity.",
            arrivalFocus: "Near \(destinationName), slow down and confirm the entrance using signage, landmarks, and normal mobility tools.",
            arrivalKeyLandmark: keyLandmark,
            guidanceCues: [],
            isUsingRealData: false,
            isPreparing: isPreparing,
            fallbackMessage: fallbackMessage
        )
    }

    private static func applyRealWalkthrough(
        _ walkthrough: WalkthroughResponse,
        to data: inout CleanFlowBriefing,
        viewModel: WalkthroughViewModel
    ) {
        let stages = walkthrough.stages
        let destinationStage = stages.last { $0.kind == .destination } ?? stages.last

        if let entranceCue = realCue(from: destinationStage) {
            data.entranceCue = entranceCue
        }

        data.whatToExpect = realExpectationLines(from: destinationStage, fallback: data.whatToExpect)

        let landmarks = realLandmarkChain(from: walkthrough, destinationName: data.destinationName)
        if !landmarks.isEmpty {
            data.landmarkChain = landmarks
        }
        data.arrivalKeyLandmark = firstArrivalLandmark(in: data.landmarkChain)

        data.trustedNote = viewModel.arrivalMemory.futureNote.cleanFlowNilIfBlank.map {
            cleanText($0, fallback: "")
        }

        data.guidanceCues = realGuidanceCues(from: stages)
        data.currentCue = data.guidanceCues.first ?? cleanText(viewModel.currentCueText, fallback: data.currentCue)
        data.arrivalFocus = arrivalFocus(landmarks: arrivalLandmarkNames(from: data.landmarkChain), entranceCue: data.entranceCue)
    }

    private static func applyBasicFallbackWalkthrough(
        _ walkthrough: WalkthroughResponse,
        to data: inout CleanFlowBriefing
    ) {
        let allowNolensvilleContent = data.destinationName.lowercased().contains("nolensville")
        let stages = walkthrough.stages

        let cues = realGuidanceCues(from: stages)
            .filter { allowNolensvilleContent || !isNolensvilleSpecific($0) }
        if !cues.isEmpty {
            data.guidanceCues = cues
            data.currentCue = cues.first ?? data.currentCue
        }

        if let destinationCue = realCue(from: stages.last(where: { $0.kind == .destination }) ?? stages.last),
           allowNolensvilleContent || !isNolensvilleSpecific(destinationCue) {
            data.entranceCue = destinationCue
        }

        let landmarks = realLandmarkChain(from: walkthrough, destinationName: data.destinationName)
            .filter { allowNolensvilleContent || !isNolensvilleSpecific($0) }
        if !landmarks.isEmpty {
            data.landmarkChain = Array(landmarks.prefix(8))
        } else {
            data.landmarkChain = fallbackLandmarks(destinationName: data.destinationName)
        }
        data.arrivalKeyLandmark = firstArrivalLandmark(in: data.landmarkChain)

        data.arrivalFocus = "Near \(data.destinationName), slow down and confirm the entrance using signage, landmarks, and normal mobility tools."
    }

    private static func destinationName(from viewModel: WalkthroughViewModel) -> String {
        let candidates = [
            viewModel.walkthrough?.destination?.name,
            viewModel.walkthrough?.destination?.formattedAddress,
            viewModel.resolvedDestinationName,
            viewModel.destinationQuery
        ]

        return candidates
            .compactMap { $0?.cleanFlowTrimmed }
            .filter { !$0.isEmpty }
            .first { $0 != "Destination" }
            .map { cleanText($0, fallback: "your destination") }
            ?? "your destination"
    }

    private static func realGuidanceCues(from stages: [RouteStage]) -> [String] {
        stages.compactMap { realCue(from: $0) }
    }

    private static func realCue(from stage: RouteStage?) -> String? {
        guard let stage else { return nil }
        let spoken = cleanText(stage.description.spokenCue, fallback: "")
        let instruction = cleanText(stage.routeInstruction, fallback: "")

        if !spoken.isEmpty && spoken != streetViewLimitation {
            return spoken
        }

        if !instruction.isEmpty {
            return instruction
        }

        if !spoken.isEmpty {
            return spoken
        }

        return instruction.isEmpty ? nil : instruction
    }

    private static func realExpectationLines(from destinationStage: RouteStage?, fallback: [String]) -> [String] {
        guard let destinationStage else { return fallback }

        var lines: [String] = []
        lines.append(contentsOf: destinationStage.description.crossingOrIntersectionNotes.map {
            cleanText($0, fallback: "")
        })

        if let nearestIntersection = cleanContextName(destinationStage.context?.nearestIntersection) {
            lines.append("Near \(nearestIntersection).")
        }

        if let streetName = cleanContextName(destinationStage.context?.streetName) {
            lines.append("Expect the final approach near \(streetName).")
        }

        if let cue = realCue(from: destinationStage) {
            lines.append(cue)
        }

        let unique = uniqueCleanLines(lines).prefix(3)
        return unique.isEmpty ? fallback : Array(unique)
    }

    private static func realLandmarkChain(from walkthrough: WalkthroughResponse, destinationName: String) -> [String] {
        let budgets = landmarkBudgets(distanceMeters: walkthrough.routeSummary.distanceMeters)
        let finalApproachStart = finalApproachStart(distanceMeters: walkthrough.routeSummary.distanceMeters)
        let candidates = uniqueLandmarkCandidates(
            walkthrough.stages.flatMap { stage -> [CleanLandmarkCandidate] in
                let rawLandmarks = stage.description.landmarks.isEmpty
                    ? stage.context?.nearbyLandmarks ?? []
                    : stage.description.landmarks
                let isNearArrival = stage.kind == .destination || stage.routeDistanceMeters >= finalApproachStart

                return rawLandmarks.compactMap { raw in
                    cleanLandmarkText(raw, destinationName: destinationName).map {
                        CleanLandmarkCandidate(
                            text: $0,
                            isNearArrival: isNearArrival,
                            routeDistanceMeters: stage.routeDistanceMeters
                        )
                    }
                }
            }
        )

        let routeLandmarks = candidates
            .filter { !$0.isNearArrival }
            .sorted { $0.routeDistanceMeters < $1.routeDistanceMeters }
        let arrivalLandmarks = candidates
            .filter(\.isNearArrival)
            .sorted { $0.routeDistanceMeters < $1.routeDistanceMeters }

        var selected = Array(routeLandmarks.prefix(budgets.route))
        selected.append(contentsOf: arrivalLandmarks.prefix(budgets.arrival))

        if selected.count < budgets.target {
            let selectedKeys = Set(selected.map { normalizedLandmarkKey($0.text) })
            let remaining = (arrivalLandmarks + routeLandmarks)
                .filter { !selectedKeys.contains(normalizedLandmarkKey($0.text)) }
            selected.append(contentsOf: remaining.prefix(budgets.target - selected.count))
        }

        if selected.isEmpty {
            return fallbackLandmarks(destinationName: destinationName)
        }

        return selected
            .sorted { $0.routeDistanceMeters < $1.routeDistanceMeters }
            .prefix(8)
            .map { "\($0.isNearArrival ? "Near arrival" : "Along route"): \($0.text)" }
    }

    private static func landmarkBudgets(distanceMeters: Int) -> (target: Int, route: Int, arrival: Int) {
        let miles = Double(max(distanceMeters, 0)) / 1_609.344

        if miles < 0.5 {
            return (target: 3, route: 0, arrival: 3)
        }

        if miles < 2 {
            return (target: 5, route: 1, arrival: 4)
        }

        if miles < 5 {
            return (target: 7, route: 2, arrival: 5)
        }

        return (target: 8, route: 3, arrival: 5)
    }

    private static func finalApproachStart(distanceMeters: Int) -> Int {
        let distance = max(distanceMeters, 0)
        guard distance >= 805 else { return 0 }
        return max(0, distance - 350)
    }

    private static func uniqueLandmarkCandidates(_ candidates: [CleanLandmarkCandidate]) -> [CleanLandmarkCandidate] {
        var keyed: [String: CleanLandmarkCandidate] = [:]
        var orderedKeys: [String] = []

        for candidate in candidates {
            let key = normalizedLandmarkKey(candidate.text)
            guard !key.isEmpty else { continue }

            if let existing = keyed[key] {
                if candidate.isNearArrival && !existing.isNearArrival {
                    keyed[key] = candidate
                }
                continue
            }

            keyed[key] = candidate
            orderedKeys.append(key)
        }

        return orderedKeys.compactMap { keyed[$0] }
    }

    private static func arrivalFocus(landmarks: [String], entranceCue: String) -> String {
        let landmarkText = landmarks.isEmpty
            ? "Use near-arrival landmarks"
            : "Use near-arrival landmarks: \(landmarks.prefix(4).joined(separator: ", "))"
        return "\(landmarkText). \(entranceCue)"
    }

    private static func fallbackLandmarks(destinationName: String) -> [String] {
        let items = isStoreDestination(destinationName)
            ? ["Main storefront", "Parking lot entrance", "Storefront signage", "Main entrance area"]
            : ["Building front", "Main entrance area", "Pickup or parking area"]

        return items
            .compactMap { cleanLandmarkText($0, destinationName: destinationName) }
            .prefix(8)
            .map { "Near arrival: \($0)" }
    }

    private static func firstArrivalLandmark(in landmarks: [String]) -> String? {
        landmarks.first { $0.lowercased().hasPrefix("near arrival:") } ?? landmarks.first
    }

    private static func arrivalLandmarkNames(from landmarks: [String]) -> [String] {
        landmarks.compactMap { landmark in
            guard landmark.lowercased().hasPrefix("near arrival:") else { return nil }
            return removingLandmarkContextPrefix(from: landmark)
        }
    }

    private static func limitedDetailsMessage(for destinationName: String) -> String {
        "Arrival details are limited for \"\(destinationName)\". Try a more specific name or address for a better preview."
    }

    private static func cleanText(_ text: String, fallback: String) -> String {
        let trimmed = suppressDemoRiskWording(in: text.cleanFlowTrimmed)
        guard !trimmed.isEmpty else { return fallback }

        if mentionsUnavailableStreetView(trimmed) {
            return streetViewLimitation
        }

        let withoutDebugSentences = removingDebugSentences(from: trimmed)
            .replacingOccurrences(of: "Route instruction:", with: "")
            .cleanFlowTrimmed
        guard !withoutDebugSentences.isEmpty else { return fallback }

        if containsDebugWording(withoutDebugSentences) {
            return fallback
        }

        return conciseText(withoutDebugSentences)
    }

    private static func suppressDemoRiskWording(in text: String) -> String {
        text
            .replacingOccurrences(of: "Unnamed Road", with: "the final approach", options: [.caseInsensitive])
            .replacingOccurrences(of: "Unnamed route", with: "the final approach", options: [.caseInsensitive])
            .replacingOccurrences(of: "Unnamed", with: "the destination area", options: [.caseInsensitive])
            .replacingOccurrences(
                of: #"(?i)near the final approach near the final approach"#,
                with: "near the destination area",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?i)expect the final approach near the final approach\.?"#,
                with: "Expect the final approach near the destination area.",
                options: .regularExpression
            )
            .cleanFlowTrimmed
    }

    private static func cleanLandmarkText(_ text: String, destinationName: String) -> String? {
        let cleaned = removingLandmarkContextPrefix(from: cleanText(text, fallback: ""))
        guard !isGenericLandmark(cleaned, destinationName: destinationName) else {
            return nil
        }
        return cleaned
    }

    private static func cleanContextName(_ text: String?) -> String? {
        let cleaned = cleanText(text ?? "", fallback: "")
        let key = normalizedLandmarkKey(cleaned)
        guard !key.isEmpty,
              key != "the final approach",
              key != "the destination area",
              key != "final approach",
              key != "destination area" else {
            return nil
        }
        return cleaned
    }

    private static func isGenericLandmark(_ text: String, destinationName: String) -> Bool {
        let key = normalizedLandmarkKey(text)
        let destinationKey = normalizedLandmarkKey(destinationName)
        let blockedExact = Set([
            "",
            "traffic",
            "road",
            "unnamed road",
            "destination",
            "entrance",
            "building",
            "nearby signage",
            "final approach",
            "the final approach",
            "normal mobility tools"
        ])

        if blockedExact.contains(key) || key == destinationKey {
            return true
        }

        return key.contains("normal mobility tools")
            || key.contains("nearby signage")
            || key.contains("unnamed road")
            || key.contains("sidewalk")
            || key.contains("street view")
    }

    private static func normalizedLandmarkKey(_ text: String) -> String {
        removingLandmarkContextPrefix(from: text)
            .lowercased()
            .replacingOccurrences(of: "&", with: "and")
            .replacingOccurrences(of: #"[^a-z0-9\s]"#, with: "", options: .regularExpression)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func removingLandmarkContextPrefix(from text: String) -> String {
        text
            .replacingOccurrences(of: #"(?i)^\s*(near arrival|along route)\s*:\s*"#, with: "", options: .regularExpression)
            .cleanFlowTrimmed
    }

    private static func isStoreDestination(_ destinationName: String) -> Bool {
        let lowercased = destinationName.lowercased()
        return lowercased.contains("walmart")
            || lowercased.contains("supercenter")
            || lowercased.contains("store")
            || lowercased.contains("market")
            || lowercased.contains("pharmacy")
            || lowercased.contains("target")
            || lowercased.contains("costco")
            || lowercased.contains("kroger")
            || lowercased.contains("publix")
            || lowercased.contains("mall")
    }

    private static func mentionsUnavailableStreetView(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return lowercased.contains("street view")
            && (lowercased.contains("unavailable")
                || lowercased.contains("not available")
                || lowercased.contains("no street view")
                || lowercased.contains("limited"))
    }

    private static func removingDebugSentences(from text: String) -> String {
        text
            .split(separator: ".")
            .map { String($0).cleanFlowTrimmed }
            .filter { !$0.isEmpty }
            .filter { !containsDebugWording($0) }
            .map { $0.hasSuffix(".") ? $0 : "\($0)." }
            .joined(separator: " ")
    }

    private static func containsDebugWording(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return lowercased.contains("mock")
            || lowercased.contains("local preview only")
            || lowercased.contains("backend")
            || lowercased.contains("debug")
    }

    private static func isNolensvilleSpecific(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return lowercased.contains("nolensville")
            || lowercased.contains("first united methodist")
            || lowercased.contains("white house with a porch")
            || lowercased.contains("white church with a red roof")
            || lowercased.contains("red covered shelter")
    }

    private static func debugDestinationLog(_ message: String) {
        #if DEBUG
        print("[HearSight Destination] \(message)")
        #endif
    }

    private static func uniqueCleanLines(_ lines: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for line in lines {
            let cleaned = cleanText(line, fallback: "")
            guard !cleaned.isEmpty else { continue }

            let key = cleaned.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            guard !seen.contains(key) else { continue }

            seen.insert(key)
            result.append(cleaned)
        }

        return result
    }

    private static func conciseText(_ text: String) -> String {
        let collapsed = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        let sentences = collapsed
            .split(separator: ".")
            .map { String($0).cleanFlowTrimmed }
            .filter { !$0.isEmpty }

        let sentenceLimited = sentences.isEmpty
            ? collapsed
            : sentences.prefix(2).map { $0.hasSuffix(".") ? $0 : "\($0)." }.joined(separator: " ")

        if sentenceLimited.count <= 220 {
            return sentenceLimited
        }

        return "\(String(sentenceLimited.prefix(217)).cleanFlowTrimmed)..."
    }
}

struct CleanFlowScreen<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            HearSightTheme.background(colorScheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: HearSightTheme.Spacing.md) {
                    content
                }
                .padding(.horizontal, HearSightTheme.Spacing.lg)
                .padding(.vertical, HearSightTheme.Spacing.lg)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

struct CleanStickyBottomContainer<Content: View, BottomAction: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    private let contentBottomPadding: CGFloat
    private let content: Content
    private let bottomAction: BottomAction

    init(
        contentBottomPadding: CGFloat = 112,
        @ViewBuilder content: () -> Content,
        @ViewBuilder bottomAction: () -> BottomAction
    ) {
        self.contentBottomPadding = contentBottomPadding
        self.content = content()
        self.bottomAction = bottomAction()
    }

    var body: some View {
        ZStack {
            HearSightTheme.background(colorScheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: HearSightTheme.Spacing.md) {
                    content
                }
                .padding(.horizontal, HearSightTheme.Spacing.lg)
                .padding(.top, HearSightTheme.Spacing.lg)
                .padding(.bottom, contentBottomPadding)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                bottomAction
                    .frame(maxWidth: 680)
            }
            .padding(.horizontal, HearSightTheme.Spacing.lg)
            .padding(.top, HearSightTheme.Spacing.sm)
            .padding(.bottom, HearSightTheme.Spacing.sm)
            .frame(maxWidth: .infinity)
            .background(HearSightTheme.panel(colorScheme).opacity(0.98))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(HearSightTheme.cardStroke(colorScheme))
                    .frame(height: 1)
            }
            .shadow(color: HearSightTheme.glow(colorScheme), radius: 14, x: 0, y: -8)
        }
    }
}

enum CleanHeaderAlignment {
    case leading
    case center
}

struct CleanScreenHeader: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    var subtitle: String?
    var eyebrow: String?
    var systemImage: String?
    var alignment: CleanHeaderAlignment = .leading

    var body: some View {
        VStack(alignment: stackAlignment, spacing: HearSightTheme.Spacing.xs) {
            Text(title)
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .multilineTextAlignment(textAlignment)
                .lineLimit(2)
                .minimumScaleFactor(0.76)

            if let subtitle {
                Text(subtitle)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(textAlignment)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let eyebrow {
                Label(eyebrow, systemImage: systemImage ?? "location.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HearSightTheme.primary(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .padding(.horizontal, HearSightTheme.Spacing.sm)
                    .padding(.vertical, HearSightTheme.Spacing.xs)
                    .background(HearSightTheme.primary(colorScheme).opacity(0.10))
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var stackAlignment: HorizontalAlignment {
        alignment == .center ? .center : .leading
    }

    private var textAlignment: TextAlignment {
        alignment == .center ? .center : .leading
    }

    private var frameAlignment: Alignment {
        alignment == .center ? .center : .leading
    }
}

struct CleanCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    var title: String?
    var systemImage: String?
    var content: Content

    init(
        title: String? = nil,
        systemImage: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HearSightTheme.Spacing.sm) {
            if let title {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                } else {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
            }

            content
        }
        .padding(HearSightTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HearSightTheme.panel(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: HearSightTheme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: HearSightTheme.Radius.card, style: .continuous)
                .stroke(HearSightTheme.cardStroke(colorScheme), lineWidth: 1)
        }
        .shadow(color: HearSightTheme.glow(colorScheme), radius: 16, x: 0, y: 8)
        .accessibilityElement(children: .combine)
    }
}

struct CleanVoiceHint: View {
    @Environment(\.colorScheme) private var colorScheme

    let text: String

    var body: some View {
        Label(text, systemImage: "waveform")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(HearSightTheme.primary(colorScheme))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, HearSightTheme.Spacing.md)
            .padding(.vertical, HearSightTheme.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HearSightTheme.primary(colorScheme).opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: HearSightTheme.Radius.md, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Voice hint. \(text)")
    }
}

struct CleanPrimaryButton: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    let title: String
    var systemImage: String = "arrow.right.circle.fill"
    var accessibilityLabel: String?
    var accessibilityHint: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 60)
                .background(HearSightTheme.primary(colorScheme).opacity(isEnabled ? 1 : 0.58))
                .clipShape(RoundedRectangle(cornerRadius: HearSightTheme.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel ?? title)
        .accessibilityHint(accessibilityHint ?? "")
    }
}

struct CleanSecondaryButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    var systemImage: String
    var accessibilityHint: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(HearSightTheme.primary(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 56)
                .background(HearSightTheme.insetPanel(colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: HearSightTheme.Radius.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: HearSightTheme.Radius.md, style: .continuous)
                        .stroke(HearSightTheme.cardStroke(colorScheme), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHint ?? "")
    }
}

struct CleanIconButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    var systemImage: String
    var isProminent = false
    var accessibilityLabel: String?
    var accessibilityHint: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: HearSightTheme.Spacing.xs) {
                Image(systemName: systemImage)
                    .font(.title2.weight(.semibold))

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .foregroundStyle(isProminent ? .white : HearSightTheme.primary(colorScheme))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 72)
            .background(buttonBackground)
            .clipShape(RoundedRectangle(cornerRadius: HearSightTheme.Radius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: HearSightTheme.Radius.md, style: .continuous)
                    .stroke(isProminent ? Color.clear : HearSightTheme.cardStroke(colorScheme), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel ?? title)
        .accessibilityHint(accessibilityHint ?? "")
    }

    private var buttonBackground: Color {
        isProminent ? HearSightTheme.primary(colorScheme) : HearSightTheme.insetPanel(colorScheme)
    }
}

struct CleanCueCard: View {
    let title: String
    let cue: String
    var systemImage: String = "waveform"
    var compact = false
    var onHear: (() -> Void)? = nil

    var body: some View {
        CleanCard(title: title, systemImage: systemImage) {
            VStack(alignment: .leading, spacing: HearSightTheme.Spacing.xs) {
                Text(cue)
                    .font(.system(compact ? .body : .title2, design: .rounded).weight(compact ? .medium : .semibold))
                    .foregroundStyle(.primary)
                    .lineSpacing(compact ? 2 : 4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if onHear != nil {
                    Text("Tap to hear")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.teal)
                }
            }
        }
        .accessibilityLabel("\(title). \(cue)")
        .accessibilityHint(onHear != nil ? "Double tap to hear this cue." : "")
        .accessibilityAddTraits(onHear != nil ? .isButton : [])
        .onTapGesture { onHear?() }
    }
}

struct CleanLandmarkChainCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let landmarks: [String]

    var body: some View {
        CleanCard(title: "Landmark chain", systemImage: "point.topleft.down.curvedto.point.bottomright.up") {
            VStack(alignment: .leading, spacing: HearSightTheme.Spacing.sm) {
                ForEach(Array(landmarks.prefix(8).enumerated()), id: \.offset) { index, landmark in
                    HStack(alignment: .firstTextBaseline, spacing: HearSightTheme.Spacing.sm) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(HearSightTheme.primary(colorScheme))
                            .clipShape(Circle())

                        Text(landmark)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .accessibilityLabel("Landmark chain. \(landmarks.prefix(8).joined(separator: ", "))")
    }
}

struct CleanConfidencePicker: View {
    @Environment(\.colorScheme) private var colorScheme

    @Binding var selection: ConfidenceLevel?

    var body: some View {
        CleanCard(title: "Confidence check-in", systemImage: "gauge.with.dots.needle.bottom.50percent") {
            VStack(spacing: HearSightTheme.Spacing.xs) {
                ForEach(ConfidenceLevel.allCases) { level in
                    Button {
                        selection = level
                    } label: {
                        HStack(spacing: HearSightTheme.Spacing.sm) {
                            Text(level.title)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)

                            Spacer(minLength: HearSightTheme.Spacing.sm)

                            Image(systemName: selection == level ? "checkmark.circle.fill" : "circle")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(selection == level ? HearSightTheme.secondary(colorScheme) : .secondary)
                        }
                        .padding(.horizontal, HearSightTheme.Spacing.md)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                        .background(selection == level ? HearSightTheme.secondary(colorScheme).opacity(0.14) : HearSightTheme.insetPanel(colorScheme))
                        .clipShape(RoundedRectangle(cornerRadius: HearSightTheme.Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(level.title)
                    .accessibilityValue(selection == level ? "Selected" : "Not selected")
                    .accessibilityHint("Sets arrival confidence to \(level.title).")
                }
            }
        }
    }
}

private extension String {
    var cleanFlowTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var cleanFlowNilIfBlank: String? {
        let trimmed = cleanFlowTrimmed
        return trimmed.isEmpty ? nil : trimmed
    }
}
