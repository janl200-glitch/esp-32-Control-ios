import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        Group {
            if app.loggedIn {
                MainView()
            } else {
                LoginView()
            }
        }
        .alert("ESP32", isPresented: Binding(
            get: { app.errorMessage != nil },
            set: { if !$0 { app.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { app.errorMessage = nil }
        } message: {
            Text(app.errorMessage ?? "")
        }
    }
}

struct LoginView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Spacer()
                Image(systemName: "cpu.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)
                Text("ESP32 Control Center")
                    .font(.largeTitle.bold())
                Text("Verbinde dich mit deinem ESP32-Webserver.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                TextField("ESP32 IP oder Domain", text: $app.baseAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textFieldStyle(.roundedBorder)

                SecureField("Admin-Passwort", text: $app.password)
                    .textFieldStyle(.roundedBorder)

                Button {
                    Task { await app.login() }
                } label: {
                    Label(app.loading ? "Verbinde..." : "Anmelden", systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(app.loading || app.password.isEmpty)

                Text("Standard im lokalen WLAN: http://192.168.178.67/")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(24)
            .navigationBarHidden(true)
        }
    }
}

struct MainView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "gauge.with.dots.needle.67percent") }
            FilesView()
                .tabItem { Label("Dateien", systemImage: "folder") }
            AnalyticsView()
                .tabItem { Label("Analytics", systemImage: "chart.bar.xaxis") }
            LogsView()
                .tabItem { Label("Logs", systemImage: "terminal") }
            SettingsView()
                .tabItem { Label("Einstellungen", systemImage: "gear") }
        }
        .task { await app.refreshAll() }
    }
}

struct DashboardView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(app.config?.name ?? "ESP32 Server")
                                .font(.largeTitle.bold())
                            Text(app.stats?.ip ?? "Verbinde...")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Circle()
                            .fill(app.stats == nil ? .orange : .green)
                            .frame(width: 13, height: 13)
                    }

                    if let s = app.stats {
                        StatCard(title: "RAM frei", value: ByteFormatter.string(s.ramFree), icon: "memorychip")
                        StatCard(title: "LittleFS", value: "\(ByteFormatter.string(s.fsUsed)) / \(ByteFormatter.string(s.fsTotal))", icon: "internaldrive")
                        StatCard(title: "Flash", value: ByteFormatter.string(s.flash), icon: "cpu")
                        StatCard(title: "CPU", value: "\(s.cpu) MHz", icon: "speedometer")
                        StatCard(title: "WLAN", value: "\(s.rssi) dBm", icon: "wifi")
                        StatCard(title: "Uptime", value: s.uptime, icon: "clock")
                    }

                    HStack {
                        Button("Aktualisieren") { Task { await app.refreshAll() } }
                            .buttonStyle(.borderedProminent)
                        Button("Neustart", role: .destructive) { Task { await app.restart() } }
                            .buttonStyle(.bordered)
                    }
                }
                .padding()
            }
            .navigationTitle("Dashboard")
            .refreshable { await app.refreshAll() }
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 42)
                .foregroundStyle(.blue)
            VStack(alignment: .leading) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.headline)
            }
            Spacer()
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct FilesView: View {
    @EnvironmentObject private var app: AppModel
    @State private var editorFile: ESPFile?
    @State private var showingImporter = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(app.files) { file in
                    Button {
                        editorFile = file
                    } label: {
                        HStack {
                            Image(systemName: "doc.text")
                            VStack(alignment: .leading) {
                                Text(file.name)
                                Text(ByteFormatter.string(file.size))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            Task { await app.deleteFile(file) }
                        } label: { Label("Löschen", systemImage: "trash") }
                    }
                }
            }
            .navigationTitle("Dateien")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { Task { await app.loadFiles() } } label: { Image(systemName: "arrow.clockwise") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingImporter = true } label: { Image(systemName: "arrow.up.doc") }
                }
            }
            .refreshable { await app.loadFiles() }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.data, .text, .image, .audio, .movie, .archive]) { result in
                Task {
                    do {
                        let url = try result.get()
                        let accessed = url.startAccessingSecurityScopedResource()
                        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                        let data = try Data(contentsOf: url)
                        try await app.upload(name: url.lastPathComponent, data: data)
                    } catch {
                        app.errorMessage = error.localizedDescription
                    }
                }
            }
            .sheet(item: $editorFile) { file in
                FileEditorView(file: file)
            }
        }
    }
}

struct FileEditorView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    let file: ESPFile
    @State private var content = ""
    @State private var loading = true

    var body: some View {
        NavigationStack {
            VStack {
                if loading {
                    ProgressView("Lade \(file.name)...")
                } else {
                    TextEditor(text: $content)
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .background(Color.black.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding()
                }
            }
            .navigationTitle(file.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Schließen") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Speichern") {
                        Task {
                            do {
                                try await app.saveFile(file.name, content: content)
                                dismiss()
                            } catch { app.errorMessage = error.localizedDescription }
                        }
                    }
                    .disabled(loading)
                }
            }
            .task {
                do {
                    content = try await app.readFile(file.name)
                } catch { app.errorMessage = error.localizedDescription }
                loading = false
            }
        }
    }
}

struct AnalyticsView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let a = app.analytics {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
                            Metric(title: "Aktuell", value: "\(a.current)")
                            Metric(title: "Peak", value: "\(a.peak)")
                            Metric(title: "1 Stunde", value: "\(a.h1)")
                            Metric(title: "24 Stunden", value: "\(a.h24)")
                            Metric(title: "30 Tage", value: "\(a.d30)")
                        }
                        .padding(.horizontal)

                        ChartBars(points: a.hours.map(\.c))
                            .frame(height: 190)
                            .padding()
                    }
                    Button("Statistik löschen", role: .destructive) {
                        Task { await app.resetAnalytics() }
                    }
                    .buttonStyle(.bordered)
                    .padding(.horizontal)
                }
                .padding(.top)
            }
            .navigationTitle("Analytics")
            .refreshable { await app.refreshAll() }
        }
    }
}

struct Metric: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct ChartBars: View {
    let points: [Int]
    var body: some View {
        GeometryReader { geo in
            let maxValue = max(points.max() ?? 1, 1)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(points.enumerated()), id: \.offset) { _, value in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.blue.gradient)
                        .frame(height: max(4, geo.size.height * CGFloat(value) / CGFloat(maxValue)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct LogsView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(app.logsText.isEmpty ? "Keine Logs." : app.logsText)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding()
            }
            .navigationTitle("Logs")
            .toolbar {
                Button { Task { await app.loadLogs() } } label: { Image(systemName: "arrow.clockwise") }
            }
            .refreshable { await app.loadLogs() }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var app: AppModel
    @State private var name = ""
    @State private var lang = "de"
    @State private var theme = "dark"
    @State private var newPassword = ""
    @State private var showingFormat = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Verbindung") {
                    TextField("ESP32 IP / Domain", text: $app.baseAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Verbindung übernehmen") { app.connect() }
                }

                Section("Server") {
                    TextField("Servername", text: $name)
                    Picker("Sprache", selection: $lang) {
                        Text("Deutsch").tag("de")
                        Text("English").tag("en")
                    }
                    Picker("Theme", selection: $theme) {
                        Text("Dark").tag("dark")
                        Text("Light").tag("light")
                    }
                    Button("Speichern") {
                        Task { await app.saveConfig(name: name, lang: lang, theme: theme) }
                    }
                }

                Section("Admin-Passwort") {
                    SecureField("Neues Passwort", text: $newPassword)
                    Button("Passwort ändern") {
                        Task {
                            await app.changePassword(newPassword)
                            newPassword = ""
                        }
                    }
                    .disabled(newPassword.count < 4)
                }

                Section("Gefahrenzone") {
                    Button("LittleFS formatieren", role: .destructive) {
                        showingFormat = true
                    }
                }

                Section {
                    Button("Abmelden", role: .destructive) {
                        Task { await app.logout() }
                    }
                }
            }
            .navigationTitle("Einstellungen")
            .task {
                if let c = app.config {
                    name = c.name; lang = c.lang; theme = c.theme
                } else {
                    await app.refreshAll()
                    if let c = app.config {
                        name = c.name; lang = c.lang; theme = c.theme
                    }
                }
            }
            .confirmationDialog("LittleFS wirklich formatieren?", isPresented: $showingFormat, titleVisibility: .visible) {
                Button("Formatieren", role: .destructive) {
                    Task { await app.format() }
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Dabei werden die Website-Dateien gelöscht und der ESP32 neu gestartet.")
            }
        }
    }
}

enum ByteFormatter {
    static func string(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .binary)
    }
}
