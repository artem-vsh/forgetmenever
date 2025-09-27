import Foundation

final class TranscriptionAPIClient {
    private let config: AppConfig
    private let urlSession: URLSession

    init(config: AppConfig, urlSession: URLSession = .shared) {
        self.config = config
        self.urlSession = urlSession
    }

    func transcribe(audioFileURL: URL) async throws -> String {
        var request = URLRequest(url: config.transcriptEndpoint)
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let apiKey = resolveAPIKey() {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = try makeMultipartBody(boundary: boundary, fileURL: audioFileURL)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let responseBody = String(data: data, encoding: .utf8) ?? "<empty>"
            throw TranscriptionError.server(status: httpResponse.statusCode, body: responseBody)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(TranscriptionResponse.self, from: data)
        return decoded.text
    }

    private func resolveAPIKey() -> String? {
        if let key = config.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            return key
        }
        if let envKey = ProcessInfo.processInfo.environment["FMN_API_KEY"], !envKey.isEmpty {
            return envKey
        }
        return nil
    }

    private func makeMultipartBody(boundary: String, fileURL: URL) throws -> Data {
        var body = Data()

        func append(_ string: String) {
            if let data = string.data(using: .utf8) {
                body.append(data)
            }
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"recording.m4a\"\r\n")
        append("Content-Type: audio/m4a\r\n\r\n")
        body.append(try Data(contentsOf: fileURL))
        append("\r\n")

        append("--\(boundary)--\r\n")
        return body
    }

    struct TranscriptionResponse: Decodable {
        let text: String
    }

    enum TranscriptionError: Error {
        case invalidResponse
        case server(status: Int, body: String)
    }
}

extension TranscriptionAPIClient: @unchecked Sendable {}
