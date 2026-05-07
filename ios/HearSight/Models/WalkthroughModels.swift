import CoreLocation
import Foundation

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
    let routeSummary: RouteSummary
    let stages: [RouteStage]
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
