import CoreLocation
import Foundation

enum TripPhase: String, CaseIterable {
    case home
    case preview
    case guidance
    case arrival
    case completed
}

enum CueDensity: String, CaseIterable, Identifiable {
    case quiet
    case standard
    case detailed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quiet:
            return "Quiet"
        case .standard:
            return "Standard"
        case .detailed:
            return "Detailed"
        }
    }
}

enum ConfidenceLevel: String, CaseIterable, Identifiable {
    case veryUnsure
    case unsure
    case okay
    case confident
    case veryConfident

    var id: String { rawValue }

    var title: String {
        switch self {
        case .veryUnsure:
            return "Very unsure"
        case .unsure:
            return "Unsure"
        case .okay:
            return "Okay"
        case .confident:
            return "Confident"
        case .veryConfident:
            return "Very confident"
        }
    }
}

enum VoiceInputState: Equatable {
    case idle
    case listening
    case processing
    case success
    case failure(String)
    case unavailable(String)

    var title: String {
        switch self {
        case .idle:
            return "Idle"
        case .listening:
            return "Listening"
        case .processing:
            return "Processing"
        case .success:
            return "Success"
        case .failure:
            return "Failure"
        case .unavailable:
            return "Microphone unavailable"
        }
    }

    var message: String {
        switch self {
        case .idle:
            return "Tap the microphone or type a destination."
        case .listening:
            return "Listening for your destination."
        case .processing:
            return "Processing destination."
        case .success:
            return "Destination captured."
        case .failure(let reason):
            return reason
        case .unavailable(let reason):
            return reason
        }
    }

    var isListening: Bool {
        if case .listening = self { return true }
        return false
    }
}

struct ArrivalPreview {
    let destinationName: String
    let entranceNote: String
    let whatToExpect: String
    let landmarkChain: [String]
    let trustedNote: String?
    let isFirstVisit: Bool
}

struct ArrivalMemory {
    var lastConfidence: ConfidenceLevel?
    var futureNote: String
    var isFamiliarPlace: Bool
}

struct CoordinatePayload: Codable, Hashable {
    let latitude: Double
    let longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }

    var locationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}

struct WalkthroughRequest: Codable {
    let origin: CoordinatePayload
    let destination: CoordinatePayload?
    let destinationText: String?
    let language: String
}

struct WalkthroughResponse: Codable, Identifiable {
    let id: String
    let language: String
    let generatedAt: String
    var destination: WalkthroughDestination? = nil
    let routeSummary: RouteSummary
    let stages: [RouteStage]
}

struct WalkthroughDestination: Codable {
    let name: String?
    let formattedAddress: String?
    let coordinate: CoordinatePayload?
    let confidence: String?
}

struct RouteSummary: Codable {
    let distanceMeters: Int
    let duration: String?
    let encodedPolyline: String?
    let stageCount: Int
    let safetyNotice: String
}

struct RouteStage: Codable, Identifiable {
    let id: String
    let index: Int
    let coordinate: CoordinatePayload
    let routeDistanceMeters: Int
    let headingDegrees: Int
    let routeInstruction: String
    let kind: StageKind
    let snapshotUrl: URL?
    let streetView: StreetViewMetadata?
    let description: StageDescription
    let context: StageContext?

    var location: CLLocation {
        coordinate.location
    }
}

struct StageContext: Codable {
    let streetName: String?
    let nearestIntersection: String?
    let nearbyLandmarks: [String]
    let streetViewAvailable: Bool
    let streetViewDate: String?
    let fallbackReason: String?
}

enum StageKind: String, Codable {
    case maneuver
    case checkpoint
    case destination
}

struct StreetViewMetadata: Codable {
    let status: String
    let panoId: String?
    let date: String?
    let coordinate: CoordinatePayload?
    let copyright: String?
}

struct StageDescription: Codable {
    let spokenCue: String
    let landmarks: [String]
    let crossingOrIntersectionNotes: [String]
    let uncertainties: [String]
    let confidence: Double
}

struct DestinationCandidate {
    let name: String
    let coordinate: CLLocationCoordinate2D
}

struct BackendHealth: Codable {
    let ok: Bool
    let mockMode: Bool
    let missingConfig: [String]
}
