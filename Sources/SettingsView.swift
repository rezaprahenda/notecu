import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// Pengaturan dibagi ke beberapa tab supaya jendelanya tidak terlalu tinggi.
struct SettingsView: View {
    @ObservedObject var prefs: Prefs
    @ObservedObject var store: NoteStore
    var onLayoutChange: () -> Void

    var body: some View {
        TabView {
            GeneralTab(prefs: prefs, store: store, onLayoutChange: onLayoutChange)
                .tabItem { Label("Umum", systemImage: "gearshape") }
            FeaturesTab(prefs: prefs, store: store)
                .tabItem { Label("Fitur", systemImage: "square.grid.2x2") }
            SyncTab(prefs: prefs, store: store)
                .tabItem { Label("Sinkron", systemImage: "arrow.triangle.2.circlepath") }
            ShortcutsTab()
                .tabItem { Label("Pintasan", systemImage: "keyboard") }
            AboutTab()
                .tabItem { Label("Tentang", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 440)
    }
}

// MARK: - Umum

private struct GeneralTab: View {
    @ObservedObject var prefs: Prefs
    @ObservedObject var store: NoteStore
    var onLayoutChange: () -> Void
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError = ""
    @State private var language = AppLang.choice
    @State private var dataMessage = ""

    var body: some View {
        Form {
            Section {
                Picker("Bahasa", selection: $language) {
                    Text("Ikuti sistem").tag("")
                    Text(verbatim: "Bahasa Indonesia").tag("id")
                    Text(verbatim: "English").tag("en")
                }
                .onChange(of: language) { _, v in AppLang.choose(v) }
                if language != AppLang.choiceAtLaunch {
                    HStack {
                        Text("Bahasa berganti setelah notecu dibuka ulang.").font(.footnote).foregroundStyle(.secondary)
                        Spacer()
                        Button("Buka ulang sekarang") { AppLang.relaunch(store: store) }
                    }
                }
            }
            Section("Panel") {
                Picker("Muncul dari tepi", selection: $prefs.edge) {
                    Text("Kiri").tag("left")
                    Text("Kanan").tag("right")
                }
                .pickerStyle(.segmented)
                .onChange(of: prefs.edge) { onLayoutChange() }
                Toggle("Buka saat kursor didorong ke tepi layar", isOn: $prefs.hoverOpen)
                HStack {
                    Text("Lebar panel")
                    Slider(value: $prefs.panelWidth, in: 300...900, step: 10) { _ in onLayoutChange() }
                    Text(verbatim: "\(Int(prefs.panelWidth))").monospacedDigit().foregroundStyle(.secondary).frame(width: 34)
                }
                Picker("Huruf isi catatan", selection: $prefs.noteFont) {
                    Text("Sans (rapat)").tag("sans")
                    Text("Serif (seperti buku)").tag("serif")
                }
            }
            Section("Sistem") {
                Toggle("Jalankan saat login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                if !loginError.isEmpty {
                    Text(verbatim: loginError).font(.footnote).foregroundStyle(.red)
                }
            }
            Section {
                HStack {
                    Button("Simpan cadangan (JSON)…", action: exportBackup)
                    Button("Pulihkan dari cadangan…", action: importBackup)
                }
                Button("Tampilkan folder data di Finder") { NSWorkspace.shared.open(store.dataFolder) }
                if !dataMessage.isEmpty {
                    Text(verbatim: dataMessage).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("Data")
            } footer: {
                Text("Semua catatan selalu tersimpan di Mac ini. Simpan cadangan sesekali, misalnya ke iCloud Drive.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func setLaunchAtLogin(_ on: Bool) {
        if (SMAppService.mainApp.status == .enabled) == on { return }
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = ""
        } catch {
            loginError = L("Gagal mengubah: %@. Pastikan notecu ada di folder Applications.", error.localizedDescription)
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func exportBackup() {
        guard let data = store.exportJSON() else { return }
        let panel = NSSavePanel()
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = "notecu-\(f.string(from: Date())).json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try data.write(to: url)
                dataMessage = L("✓ Cadangan disimpan")
            } catch {
                dataMessage = L("Gagal menyimpan: %@", error.localizedDescription)
            }
        }
    }

    private func importBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        let n = store.importJSON(data)
        dataMessage = n < 0 ? L("File ini bukan cadangan notecu.") : L("✓ %lld item dipulihkan (yang sudah ada & lebih baru tidak ditimpa)", n)
    }
}

// MARK: - Sinkron (opsional)

private struct SyncTab: View {
    @ObservedObject var prefs: Prefs
    @ObservedObject var store: NoteStore
    @State private var testResult = ""
    @State private var testing = false

    private var status: (Color, String) {
        switch store.status {
        case .ok: return (.green, L("Tersinkron"))
        case .saving: return (.orange, L("Menyimpan…"))
        case .connecting: return (.orange, L("Menghubungkan…"))
        case .offline: return (.red, store.pendingCount > 0 ? L("Offline · %lld perubahan belum terkirim", store.pendingCount) : L("Offline"))
        case .badToken: return (.red, L("Token ditolak server"))
        case .notConfigured: return (.secondary, L("Tidak dipakai — semua tersimpan di Mac ini saja"))
        }
    }

    var body: some View {
        Form {
            Section {
                TextField("Alamat server", text: $prefs.serverURL, prompt: Text(verbatim: "https://notecu.example.com"))
                SecureField("Token", text: $prefs.token, prompt: Text(verbatim: "NOTECU_TOKEN"))
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle().fill(status.0).frame(width: 7, height: 7)
                        Text(verbatim: status.1).foregroundStyle(.secondary)
                    }
                }
                if prefs.isConfigured {
                    HStack {
                        Button(testing ? L("Mengetes…") : L("Tes koneksi"), action: test).disabled(testing)
                        Button("Sinkron sekarang") { store.scheduleSync(after: 0) }
                        Text(verbatim: testResult).font(.callout).foregroundStyle(.secondary)
                    }
                    if let url = prefs.baseURLString.flatMap(URL.init(string:)) {
                        Link("Buka notecu versi web", destination: url)
                    }
                }
            } header: {
                Text("Sinkron (opsional)")
            } footer: {
                Text("Kosongkan kalau tidak perlu. Isi alamat & token server notecu milikmu sendiri untuk menyamakan catatan dengan Mac lain, iPhone, atau iPad.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func test() {
        guard let url = prefs.apiURL("api/sync?after=999999999") else { return }
        testing = true
        testResult = ""
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue("Bearer \(prefs.cleanToken)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: req) { _, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            DispatchQueue.main.async {
                testing = false
                if code == 200 {
                    testResult = L("✓ Terhubung")
                    store.scheduleSync(after: 0)
                } else if code == 401 {
                    testResult = L("Token salah")
                } else if let error {
                    testResult = L("Tidak terhubung: %@", error.localizedDescription)
                } else {
                    testResult = L("Server menjawab %lld", code)
                }
            }
        }.resume()
    }
}

// MARK: - Fitur

private struct FeaturesTab: View {
    @ObservedObject var prefs: Prefs
    @ObservedObject var store: NoteStore
    @ObservedObject private var vault = Vault.shared

    var body: some View {
        Form {
            Section {
                Toggle("Ingatkan saat to-do jatuh tempo", isOn: $prefs.remindersOn)
                DatePicker("Jam untuk to-do tanpa jam", selection: Binding(
                    get: { DueDate.time(prefs.reminderTime) ?? Date() },
                    set: { prefs.reminderTime = DueDate.timeString($0) }
                ), displayedComponents: .hourAndMinute)
                .disabled(!prefs.remindersOn)
            } header: {
                Text("Pengingat")
            } footer: {
                Text("Kalau notifikasi tidak muncul, izinkan notecu di System Settings → Notifications.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Agenda") {
                Picker("Kerangka agenda baru", selection: $prefs.agendaTemplate) {
                    Text("Ikuti bahasa app").tag("")
                    Text(verbatim: "Indonesia — Peserta, Pembahasan, Kesimpulan, Tindak lanjut").tag("id")
                    Text(verbatim: "English — Participants, Discussion, Conclusion, Follow-up").tag("en")
                    Text("Tanpa kerangka").tag("none")
                    Text("Kustom").tag("custom")
                }
                if prefs.agendaTemplate == "custom" {
                    VStack(alignment: .leading, spacing: 6) {
                        TextEditor(text: $prefs.agendaCustom)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(height: 110)
                            .scrollContentBackground(.hidden)
                            .padding(4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
                        HStack(spacing: 10) {
                            Text("Mulai dari:").font(.footnote).foregroundStyle(.secondary)
                            Button { prefs.agendaCustom = NoteText.agendaTemplateID } label: { Text(verbatim: "Indonesia") }
                            Button { prefs.agendaCustom = NoteText.agendaTemplateEN } label: { Text(verbatim: "English") }
                        }
                        .buttonStyle(.link)
                        .font(.footnote)
                        Text("Pakai # Judul bagian, - poin, - [ ] checklist. Bagian Kesimpulan / Conclusion dan Tindak lanjut / Follow-up dipakai Ringkasan.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Picker("Warna Agenda", selection: Binding(
                    get: { store.agendaColor },
                    set: { store.setAgendaColor($0) }
                )) {
                    ForEach(FolderColor.allCases, id: \.self) { c in
                        Text(verbatim: c.label).tag(c)
                    }
                }
            }
            Section {
                Picker("Kunci lagi setelah", selection: $prefs.vaultLockMinutes) {
                    ForEach([1, 5, 15, 30], id: \.self) { m in
                        Text(verbatim: L("%lld menit", m)).tag(m)
                    }
                }
                HStack {
                    Text(verbatim: vault.isUnlocked ? L("Rahasia sedang terbuka") : L("Rahasia terkunci")).foregroundStyle(.secondary)
                    Spacer()
                    Button("Kunci sekarang") { vault.lock() }.disabled(!vault.isUnlocked)
                }
            } header: {
                Text("Rahasia 🔒")
            } footer: {
                Text("Selalu terkunci juga saat panel ditutup. Kata sandi rahasia tidak bisa dipulihkan kalau lupa — simpan di password manager.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Pintasan

private struct ShortcutsTab: View {
    private let global: [(String, String)] = [
        ("⌃⌥N", "Buka / tutup panel"),
        ("⌃⌥⇧N", "Catatan baru"),
        ("⌃⌥T", "To-do baru"),
    ]
    private let inPanel: [(String, String)] = [
        ("⌘N", "Catatan baru"),
        ("⌘D", "Agenda baru"),
        ("⌘T", "To-do baru"),
        ("⌘F", "Cari"),
        ("⌘L", "Rahasiakan teks yang diblok"),
        ("⌘[", "Kembali ke daftar"),
        ("Esc / ⌘W", "Tutup panel"),
    ]
    /// Kata to-do bahasa Indonesia & Inggris selalu dikenali; contohnya mengikuti bahasa app.
    private var typing: [(String, String)] {
        AppLang.isEnglish ? [
            ("- [ ]", "Checklist"),
            ("#tag", "Tag"),
            ("[[Judul]]", "Tautan ke catatan lain (Tab = saran pertama)"),
            ("tomorrow 10am !", "Tenggat, jam, penting — di kalimat to-do"),
            ("every monday", "To-do berulang"),
        ] : [
            ("- [ ]", "Checklist"),
            ("#tag", "Tag"),
            ("[[Judul]]", "Tautan ke catatan lain (Tab = saran pertama)"),
            ("besok 10:00 !", "Tenggat, jam, penting — di kalimat to-do"),
            ("tiap senin", "To-do berulang"),
        ]
    }

    var body: some View {
        Form {
            Section("Dari mana saja") { rows(global) }
            Section("Di dalam panel") { rows(inPanel) }
            Section("Saat menulis") { rows(typing) }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private func rows(_ items: [(String, String)]) -> some View {
        ForEach(items.indices, id: \.self) { i in
            LabeledContent(L(items[i].1)) { Text(verbatim: items[i].0).monospaced().foregroundStyle(.secondary) }
        }
    }
}

// MARK: - Tentang

private struct AboutTab: View {
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            NotecuMark().frame(width: 72, height: 72)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: "notecu").font(.system(size: 24, weight: .bold, design: .rounded))
                Text(verbatim: "v\(version)").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Text(verbatim: "note it, cu later.").font(.system(size: 14)).foregroundStyle(.secondary)
            Button {
                if let url = URL(string: "https://instagram.com/rezaprahenda") { NSWorkspace.shared.open(url) }
            } label: {
                HStack(spacing: 4) {
                    Text(verbatim: "made with").foregroundStyle(.secondary)
                    Text(verbatim: "♥").foregroundStyle(.red)
                    Text(verbatim: "by").foregroundStyle(.secondary)
                    Text(verbatim: "@rezaprahenda").foregroundStyle(Color.accentColor)
                }
                .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .onHover { inside in if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
            .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
