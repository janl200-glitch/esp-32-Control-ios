import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var baseAddress = UserDefaults.standard.string(forKey: "esp32Address") ?? "http://192.168.178.67/"
    @Published var password = ""
    @Published var loggedIn = false
    @Published var loading = false
    @Published var errorMessage: String?
    @Published var stats: ESPStats?
    @Published var analytics: Analytics?
    @Published var config: ESPConfig?
    @Published var files: [ESPFile] = []
    @Published var logsText = ""

    private var api: ESP32API?

    func connect() {
        guard let url = URL(string: normalizedAddress) else {
            errorMessage = "Ungültige IP-Adresse oder URL."
            return
        }
        UserDefaults.standard.set(normalizedAddress, forKey: "esp32Address")
        api = ESP32API(baseURL: url)
    }

    var normalizedAddress: String {
        var value = baseAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.hasPrefix("http://") && !value.hasPrefix("https://") {
            value = "http://" + value
        }
        if !value.hasSuffix("/") { value += "/" }
        return value
    }

    func login() async {
        loading = true
        errorMessage = nil
        connect()
        do {
            try await api!.login(password: password)
            loggedIn = true
            password = ""
            await refreshAll()
        } catch {
            loggedIn = false
            errorMessage = error.localizedDescription
        }
        loading = false
    }

    func logout() async {
        try? await api?.logout()
        loggedIn = false
        stats = nil
        analytics = nil
        files = []
        logsText = ""
    }

    func refreshAll() async {
        guard let api else { return }
        do {
            async let s = api.stats()
            async let a = api.analytics()
            async let c = api.config()
            async let f = api.files()
            stats = try await s
            analytics = try await a
            config = try await c
            files = try await f
            logsText = (try? await api.logs()) ?? logsText
        } catch {
            if error is APIError {
                errorMessage = error.localizedDescription
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    func refreshStats() async {
        guard let api else { return }
        do { stats = try await api.stats() }
        catch { errorMessage = error.localizedDescription }
    }

    func loadFiles() async {
        guard let api else { return }
        do { files = try await api.files() }
        catch { errorMessage = error.localizedDescription }
    }

    func loadLogs() async {
        guard let api else { return }
        do { logsText = try await api.logs() }
        catch { errorMessage = error.localizedDescription }
    }

    func deleteFile(_ file: ESPFile) async {
        guard let api else { return }
        do {
            try await api.deleteFile(file.name)
            await loadFiles()
        } catch { errorMessage = error.localizedDescription }
    }

    func saveFile(_ path: String, content: String) async throws {
        try await api?.saveFile(path, content: content)
        await loadFiles()
    }

    func upload(name: String, data: Data) async throws {
        try await api?.uploadFile(name: name, data: data)
        await loadFiles()
    }

    func restart() async {
        do { try await api?.restart() }
        catch { errorMessage = error.localizedDescription }
        try? await Task.sleep(for: .seconds(3))
        await refreshStats()
    }

    func format() async {
        do { try await api?.formatStorage() }
        catch { errorMessage = error.localizedDescription }
        loggedIn = false
    }

    func saveConfig(name: String, lang: String, theme: String) async {
        do {
            try await api?.saveConfig(name: name, lang: lang, theme: theme)
            await refreshAll()
        } catch { errorMessage = error.localizedDescription }
    }

    func changePassword(_ password: String) async {
        do {
            try await api?.changePassword(password)
            loggedIn = false
        } catch { errorMessage = error.localizedDescription }
    }

    func resetAnalytics() async {
        do {
            try await api?.resetAnalytics()
            await refreshAll()
        } catch { errorMessage = error.localizedDescription }
    }

    func readFile(_ path: String) async throws -> String {
        guard let api else { throw APIError.invalidURL }
        return try await api.readFile(path)
    }
}
