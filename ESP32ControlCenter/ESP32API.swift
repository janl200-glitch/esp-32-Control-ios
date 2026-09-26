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

        self.session = URLSession(configuration: configuration)
    }

    // MARK: - URL

    func url(_ path: String) -> URL? {
        URL(string: path, relativeTo: baseURL)
    }

    // MARK: - Generic Request

    private func request(
        _ path: String,
        method: String = "GET",
        body: Data? = nil,
        contentType: String? = nil
    ) async throws -> (Data, HTTPURLResponse) {

        guard let url = url(path) else {
            throw APIError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body

        if let contentType {
            req.setValue(
                contentType,
                forHTTPHeaderField: "Content-Type"
            )
        }

        let (data, response) = try await session.data(for: req)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        // Session abgelaufen / nicht autorisiert
        if http.statusCode == 401 ||
           http.statusCode == 403 ||
           http.statusCode == 302 {

            throw APIError.unauthorized
        }

        // Fehlerhafte HTTP-Antwort
        guard (200...299).contains(http.statusCode) else {

            let text =
                String(data: data, encoding: .utf8)
                ?? "HTTP \(http.statusCode)"

            throw APIError.server(text)
        }

        return (data, http)
    }

    // MARK: - Login

    func login(password: String) async throws {

        let body = formData([
            "password": password
        ])

        _ = try await request(
            "/login",
            method: "POST",
            body: body,
            contentType: "application/x-www-form-urlencoded"
        )
    }

    // MARK: - Logout

    func logout() async throws {
        _ = try await request("/logout")
    }

    // MARK: - Stats

    func stats() async throws -> ESPStats {

        let (data, _) = try await request("/api/stats")

        return try JSONDecoder().decode(
            ESPStats.self,
            from: data
        )
    }

    // MARK: - Analytics

    func analytics() async throws -> Analytics {

        let (data, _) = try await request("/api/analytics")

        return try JSONDecoder().decode(
            Analytics.self,
            from: data
        )
    }

    // MARK: - Config

    func config() async throws -> ESPConfig {

        let (data, _) = try await request("/api/config")

        return try JSONDecoder().decode(
            ESPConfig.self,
            from: data
        )
    }

    // MARK: - Save Config

    func saveConfig(
        name: String,
        lang: String,
        theme: String
    ) async throws {

        let body = formData([
            "name": name,
            "lang": lang,
            "theme": theme
        ])

        _ = try await request(
            "/api/config",
            method: "POST",
            body: body,
            contentType: "application/x-www-form-urlencoded"
        )
    }

    // MARK: - Change Password

    func changePassword(
        _ password: String
    ) async throws {

        let body = formData([
            "password": password
        ])

        _ = try await request(
            "/api/password",
            method: "POST",
            body: body,
            contentType: "application/x-www-form-urlencoded"
        )
    }

    // MARK: - Files

    func files() async throws -> [ESPFile] {

        let (data, _) = try await request(
            "/api/files"
        )

        return try JSONDecoder().decode(
            [ESPFile].self,
            from: data
        )
    }

    // MARK: - Read File

    func readFile(
        _ path: String
    ) async throws -> String {

        let escaped =
            path.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed
            ) ?? path

        let (data, _) = try await request(
            "/api/read?file=\(escaped)"
        )

        return String(
            data: data,
            encoding: .utf8
        ) ?? ""
    }

    // MARK: - Save File

    func saveFile(
        _ path: String,
        content: String
    ) async throws {

        let body = formData([
            "file": path,
            "content": content
        ])

        _ = try await request(
            "/api/save",
            method: "POST",
            body: body,
            contentType: "application/x-www-form-urlencoded"
        )
    }

    // MARK: - Delete File

    func deleteFile(
        _ path: String
    ) async throws {

        let body = formData([
            "file": path
        ])

        _ = try await request(
            "/delete",
            method: "POST",
            body: body,
            contentType: "application/x-www-form-urlencoded"
        )
    }

    // MARK: - Upload File

    func uploadFile(
        name: String,
        data: Data
    ) async throws {

        guard let url = url("/upload") else {
            throw APIError.invalidURL
        }

        let boundary =
            "Boundary-\(UUID().uuidString)"

        var body = Data()

        // Boundary
        body.append(
            Data(
                "--\(boundary)\r\n".utf8
            )
        )

        // Filename
        let safeName =
            name.replacingOccurrences(
                of: "\"",
                with: ""
            )

        body.append(
            Data(
                "Content-Disposition: form-data; name=\"file\"; filename=\"\(safeName)\"\r\n"
                    .utf8
            )
        )

        // Content-Type
        body.append(
            Data(
                "Content-Type: application/octet-stream\r\n\r\n"
                    .utf8
            )
        )

        // File
        body.append(data)

        // End boundary
        body.append(
            Data(
                "\r\n--\(boundary)--\r\n".utf8
            )
        )

        var req = URLRequest(
            url: url
        )

        req.httpMethod = "POST"

        req.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )

        req.httpBody = body

        let (responseData, response) =
            try await session.data(
                for: req
            )

        // WICHTIG:
        // URLResponse zuerst zu HTTPURLResponse umwandeln
        guard let http =
                response as? HTTPURLResponse else {

            throw APIError.invalidResponse
        }

        // Nicht autorisiert
        if http.statusCode == 401 ||
           http.statusCode == 403 ||
           http.statusCode == 302 {

            throw APIError.unauthorized
        }

        // Upload fehlgeschlagen
        guard (200...299).contains(
            http.statusCode
        ) else {

            throw APIError.server(
                String(
                    data: responseData,
                    encoding: .utf8
                )
                ?? "Upload fehlgeschlagen."
            )
        }
    }

    // MARK: - Logs

    func logs() async throws -> String {

        let (data, _) =
            try await request(
                "/api/logs"
            )

        // Wenn der ESP32 ein String-Array zurückgibt
        if let array =
            try? JSONSerialization.jsonObject(
                with: data
            ) as? [String] {

            return array.joined(
                separator: "\n"
            )
        }

        // Falls der ESP32 normalen Text zurückgibt
        return String(
            data: data,
            encoding: .utf8
        ) ?? ""
    }

    // MARK: - Restart

    func restart() async throws {

        _ = try await request(
            "/api/restart",
            method: "POST"
        )
    }

    // MARK: - Format Storage

    func formatStorage() async throws {

        _ = try await request(
            "/api/format",
            method: "POST"
        )
    }

    // MARK: - Reset Analytics

    func resetAnalytics() async throws {

        _ = try await request(
            "/api/analytics/reset",
            method: "POST"
        )
    }

    // MARK: - Form Data

    private func formData(
        _ values: [String: String]
    ) -> Data {

        let encoded =
            values.map {

                "\(percent($0.key))=\(percent($0.value))"

            }
            .joined(
                separator: "&"
            )

        return Data(
            encoded.utf8
        )
    }

    // MARK: - URL Encoding

    private func percent(
        _ value: String
    ) -> String {

        var allowed =
            CharacterSet.urlQueryAllowed

        allowed.remove(
            charactersIn: "+&="
        )

        return value.addingPercentEncoding(
            withAllowedCharacters: allowed
        ) ?? value
    }
}
