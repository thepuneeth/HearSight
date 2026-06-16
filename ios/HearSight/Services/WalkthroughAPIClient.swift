import CoreLocation
import Foundation

enum WalkthroughAPIError: LocalizedError {
    case invalidServerURL
    case invalidResponse
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "The backend server URL is not valid."
        case .invalidResponse:
            return "The backend returned an unexpected response."
        case .serverError(let message):
            return message
        }
    }
}

struct WalkthroughAPIClient {
    var serverBaseURL: String
    var urlSession: URLSession = .shared

    func health() async throws -> BackendHealth {
        guard let baseURL = URL(string: normalizedServerBaseURL) else {
            throw WalkthroughAPIError.invalidServerURL
        }

        let endpoint = baseURL.appending(path: "health")
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 4

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WalkthroughAPIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw WalkthroughAPIError.serverError("Backend health check failed with status \(httpResponse.statusCode).")
        }

        return try JSONDecoder().decode(BackendHealth.self, from: data)
    }

    func createWalkthrough(
        origin: CLLocationCoordinate2D,
        destinationText: String,
        language: String
    ) async throws -> WalkthroughResponse {
        guard let baseURL = URL(string: normalizedServerBaseURL) else {
            throw WalkthroughAPIError.invalidServerURL
        }

        let endpoint = baseURL.appending(path: "api/walkthroughs")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 45
        request.httpBody = try JSONEncoder().encode(WalkthroughRequest(
            origin: CoordinatePayload(origin),
            destination: nil,
            destinationText: destinationText,
            language: language
        ))

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WalkthroughAPIError.invalidResponse
        }

        if (200..<300).contains(httpResponse.statusCode) {
            return try JSONDecoder().decode(WalkthroughResponse.self, from: data)
        }

        if let errorPayload = try? JSONDecoder().decode(ServerErrorPayload.self, from: data) {
            throw WalkthroughAPIError.serverError(errorPayload.error)
        }

        throw WalkthroughAPIError.serverError("Backend request failed with status \(httpResponse.statusCode).")
    }

    func synthesizeSpeech(text: String, language: String) async throws -> Data {
        guard let baseURL = URL(string: normalizedServerBaseURL) else {
            throw WalkthroughAPIError.invalidServerURL
        }

        let endpoint = baseURL.appending(path: "api/tts")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        request.httpBody = try JSONEncoder().encode(TtsRequest(
            text: text,
            language: language
        ))

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WalkthroughAPIError.invalidResponse
        }

        if (200..<300).contains(httpResponse.statusCode) {
            return data
        }

        if let errorPayload = try? JSONDecoder().decode(ServerErrorPayload.self, from: data) {
            throw WalkthroughAPIError.serverError(errorPayload.error)
        }

        throw WalkthroughAPIError.serverError("Text-to-speech request failed with status \(httpResponse.statusCode).")
    }

    private var normalizedServerBaseURL: String {
        serverBaseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

private struct ServerErrorPayload: Codable {
    let error: String
}

private struct TtsRequest: Codable {
    let text: String
    let language: String
}
