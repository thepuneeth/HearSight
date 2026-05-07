import CoreLocation
import Foundation

enum PolylineDecoder {
    static func decode(_ encoded: String?) -> [CLLocationCoordinate2D] {
        guard let encoded, !encoded.isEmpty else { return [] }

        var coordinates: [CLLocationCoordinate2D] = []
        var index = encoded.startIndex
        var latitude = 0
        var longitude = 0

        while index < encoded.endIndex {
            latitude += decodeValue(encoded, index: &index)
            longitude += decodeValue(encoded, index: &index)
            coordinates.append(CLLocationCoordinate2D(
                latitude: Double(latitude) / 100_000,
                longitude: Double(longitude) / 100_000
            ))
        }

        return coordinates
    }

    private static func decodeValue(_ encoded: String, index: inout String.Index) -> Int {
        var result = 0
        var shift = 0
        var byte = 0

        repeat {
            byte = Int(encoded[index].asciiValue ?? 63) - 63
            index = encoded.index(after: index)
            result |= (byte & 0x1f) << shift
            shift += 5
        } while byte >= 0x20 && index < encoded.endIndex

        return (result & 1) == 1 ? ~(result >> 1) : (result >> 1)
    }
}
