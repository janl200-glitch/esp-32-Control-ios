import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case unauthorized
    case server(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Ungültige ESP32-Adresse."
        case .unauthorized:
            return "Nicht angemeldet oder Sitzung abgelaufen."
        case .server(let message):
            return message
        case .invalidResponse:
            return "Ungültige Antwort vom ESP32."
        }
    }
}

final class ESP32API {
    private let session: URLSession
    private let baseURL: URL

    init(baseURL: URL) {
        self.baseURL = baseURL
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 15
        self.session = URLSession(configuration: configuration)
    }

    func url(_ path: String) -> URL? {
        URL(string: path, relativeTo: baseURL)
    }

    private func request(
        _ path: String,
        method: String = "GET",
        body: Data? = nil,
        contentType: String? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        guard let url = url(path) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body

        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 401 ||
           httpResponse.statusCode == 403 ||
           httpResponse.statusCode == 302 {
            throw APIError.unauthorized
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(
                data: data,
                encoding: .utf8
            ) ?? "HTTP \(httpResponse.statusCode)"

            throw APIError.server(message)
        }

        return (data, httpResponse)
    }

    private func json<T: Decodable>(
        _ path: String,
        method: String = "GET",
        body: Data? = nil
    ) async throws -> T {
        let (data, _) = try await request(
            path,
            method: method,
            body: body,
            contentType: body == nil ? nil : "application/json"
        )

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.server(
                String(data: data, encoding: .utf8) ?? error.localizedDescription
            )
        }
    }

    // MARK: - Authentication

    func login(username: String, password: String) async throws {
        let body = formData([
            "username": username,
            "password": password
        ])

        _ = try await request(
            "/login",
            method: "POST",
            body: body,
            contentType: "application/x-www-form-urlencoded"
        )
    }

    func logout() async throws {
        _ = try await request("/logout")
    }

    // MARK: - Dashboard

    func stats() async throws -> StatsResponse {
        try await json("/api/stats")
    }

    // MARK: - Analytics

    func analytics() async throws -> AnalyticsResponse {
        try await json("/api/analytics")
    }

    func resetAnalytics() async throws {
        _ = try await request(
            "/api/analytics/reset",
            method: "POST"
        )
    }

    // MARK: - Config

    func config() async throws -> ServerConfig {
        try await json("/api/config")
    }

    func saveConfig(_ config: ServerConfig) async throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(config)

        _ = try await request(
            "/api/config",
            method: "POST",
            body: data,
            contentType: "application/json"
        )
    }

    // MARK: - Password

    func changePassword(
        oldPassword: String,
        newPassword: String
    ) async throws {
        let body = formData([
            "oldPassword": oldPassword,
            "newPassword": newPassword
        ])

        _ = try await request(
            "/api/password",
            method: "POST",
            body: body,
            contentType: "application/x-www-form-urlencoded"
        )
    }

    // MARK: - Files

    func files() async throws -> [FileItem] {
        try await json("/api/files")
    }

    func readFile(path: String) async throws -> String {
        let encoded = path.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) ?? path

        let (data, _) = try await request(
            "/api/read?path=\(encoded)"
        )

        return String(data: data, encoding: .utf8) ?? ""
    }

    func saveFile(path: String, content: String) async throws {
        let body: [String: String] = [
            "path": path,
            "content": content
        ]

        let data = try JSONSerialization.data(
            withJSONObject: body
        )

        _ = try await request(
            "/api/save",
            method: "POST",
            body: data,
            contentType: "application/json"
        )
    }

    func deleteFile(path: String) async throws {
        let body: [String: String] = [
            "path": path
        ]

        let data = try JSONSerialization.data(
            withJSONObject: body
        )

        _ = try await request(
            "/delete",
            method: "POST",
            body: data,
            contentType: "application/json"
        )
    }

    // MARK: - Upload

    func uploadFile(
        data fileData: Data,
        filename: String,
        mimeType: String = "application/octet-stream"
    ) async throws {
        guard let url = url("/upload") else {
            throw APIError.invalidURL
        }

        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )

        var body = Data()

        body.append(
            Data("--\(boundary)\r\n".utf8)
        )

        body.append(
            Data(
                "Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n"
                    .utf8
            )
        )

        body.append(
            Data(
                "Content-Type: \(mimeType)\r\n\r\n"
                    .utf8
            )
        )

        body.append(fileData)
        body.append(Data("\r\n".utf8))
        body.append(Data("--\(boundary)--\r\n".utf8))

        let (responseData, response) = try await session.data(
            for: request,
            delegate: nil
        )

        // IMPORTANT:
        // URLSession returns URLResponse here, not HTTPURLResponse.
        // Always cast before accessing statusCode.
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 401 ||
           httpResponse.statusCode == 403 ||
           httpResponse.statusCode == 302 {
            throw APIError.unauthorized
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(
                data: responseData,
                encoding: .utf8
            ) ?? "Upload fehlgeschlagen."

            throw APIError.server(message)
        }
    }

    // MARK: - Logs

    func logs() async throws -> LogsResponse {
        try await json("/api/logs")
    }

    // MARK: - Server actions

    func restart() async throws {
        _ = try await request(
            "/api/restart",
            method: "POST"
        )
    }

    func formatStorage() async throws {
        _ = try await request(
            "/api/format",
            method: "POST"
        )
    }

    // MARK: - Helpers

    private func formData(
        _ values: [String: String]
    ) -> Data {
        let allowed = CharacterSet.urlQueryAllowed

        let string = values
            .map { key, value in
                let encodedKey = key.addingPercentEncoding(
                    withAllowedCharacters: allowed
                ) ?? key

                let encodedValue = value.addingPercentEncoding(
                    withAllowedCharacters: allowed
                ) ?? value

                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")

        return Data(string.utf8)
    }

    static func percent(_ value: Double) -> Int {
        Int(max(0, min(100, value * 100)))
    }
}
