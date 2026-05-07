import CoreLocation
import Foundation

enum GeoMath {
    static func distanceFromRoute(_ location: CLLocation, route: [CLLocationCoordinate2D]) -> CLLocationDistance {
        guard !route.isEmpty else { return .greatestFiniteMagnitude }
        guard route.count > 1 else {
            return location.distance(from: CLLocation(latitude: route[0].latitude, longitude: route[0].longitude))
        }

        var best = CLLocationDistance.greatestFiniteMagnitude
        for index in 1..<route.count {
            best = min(best, distanceFromSegment(location.coordinate, route[index - 1], route[index]))
        }
        return best
    }

    private static func distanceFromSegment(
        _ point: CLLocationCoordinate2D,
        _ start: CLLocationCoordinate2D,
        _ end: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        let meanLatitude = (point.latitude + start.latitude + end.latitude) / 3 * .pi / 180
        let metersPerDegreeLatitude = 111_320.0
        let metersPerDegreeLongitude = 111_320.0 * cos(meanLatitude)

        let pointX = (point.longitude - start.longitude) * metersPerDegreeLongitude
        let pointY = (point.latitude - start.latitude) * metersPerDegreeLatitude
        let vectorX = (end.longitude - start.longitude) * metersPerDegreeLongitude
        let vectorY = (end.latitude - start.latitude) * metersPerDegreeLatitude
        let lengthSquared = vectorX * vectorX + vectorY * vectorY

        guard lengthSquared > 0 else {
            return CLLocation(latitude: point.latitude, longitude: point.longitude)
                .distance(from: CLLocation(latitude: start.latitude, longitude: start.longitude))
        }

        let projection = max(0, min(1, (pointX * vectorX + pointY * vectorY) / lengthSquared))
        let projected = CLLocationCoordinate2D(
            latitude: start.latitude + (end.latitude - start.latitude) * projection,
            longitude: start.longitude + (end.longitude - start.longitude) * projection
        )

        return CLLocation(latitude: point.latitude, longitude: point.longitude)
            .distance(from: CLLocation(latitude: projected.latitude, longitude: projected.longitude))
    }
}
