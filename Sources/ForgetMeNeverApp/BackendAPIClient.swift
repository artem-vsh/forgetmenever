import Foundation

final class BackendAPIClient {
    struct TranscriptionResponse: Decodable {
        let text: String
    }

    struct TodoItemDTO: Decodable, Hashable {
        let text: String
        let due: String?
    }

    struct TodoListResponse: Decodable {
        let items: [TodoItemDTO]
    }

    struct TodoListEventResponse: Decodable {
        let type: String
        let newList: TodoListResponse
        let updated: [TodoItemDTO]?
        let removed: [TodoItemDTO]?
    }

    enum APIError: Error {
        case invalidResponse
        case server(status: Int, body: String)
    }

    private let config: AppConfig
    private let urlSession: URLSession

    init(config: AppConfig, urlSession: URLSession = .shared) {
        self.config = config
        self.urlSession = urlSession
    }

    func transcribe(audioFileURL: URL) async throws -> String {
        let boundary = UUID().uuidString
        var request = URLRequest(url: config.transcriptEndpoint)
        applyCommonHeaders(to: &request)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try makeMultipartBody(boundary: boundary, fileURL: audioFileURL)
        let data = try await perform(request: request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(TranscriptionResponse.self, from: data).text
    }

    func fetchTodoList() async throws -> [TodoItemDTO] {
        var request = URLRequest(url: config.todoListEndpoint)
        applyCommonHeaders(to: &request)
        request.httpMethod = "GET"
        let data = try await perform(request: request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(TodoListResponse.self, from: data).items
    }

    func process(prompt: String) async throws -> TodoListEventResponse {
        var request = URLRequest(url: config.processEndpoint)
        applyCommonHeaders(to: &request)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["prompt": prompt]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await perform(request: request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(TodoListEventResponse.self, from: data)
    }

    // MARK: - Helpers

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

    private func applyCommonHeaders(to request: inout URLRequest) {
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let apiKey = resolveAPIKey() {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
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

    private func perform(request: URLRequest) async throws -> Data {
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<empty>"
            throw APIError.server(status: httpResponse.statusCode, body: body)
        }
        return data
    }
}

extension BackendAPIClient: @unchecked Sendable {}
