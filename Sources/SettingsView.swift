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
            ShortcutsTab()
                .tabItem { Label("Pintasan", systemImage: "keyboard") }
            AboutTab()
                .tabItem { Label("Tentang", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 430)
    }
}

// MARK: - Umum

private struct GeneralTab: View {
    @ObservedObject var prefs: Prefs
    @ObservedObject var store: NoteStore
    var onLayoutChange: () -> Void
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError = ""

    var body: some View {
        Form {
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
                    Slider(value: $prefs.panelWidth, in: 300...560, step: 10) { _ in onLayoutChange() }
                    Text("\(Int(prefs.panelWidth))").monospacedDigit().foregroundStyle(.secondary).frame(width: 34)
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
                    Text(loginError).font(.footnote).foregroundStyle(.red)
                }
            }
            Section {
                HStack {
                    Button("Simpan cadangan (JSON)…", action: exportBackup)
                    Button("Pulihkan dari cadangan…", action: importBackup)
                }
                Button("Tampilkan folder data di Finder") { NSWorkspace.shared.open(store.dataFolder) }
                if !dataMessage.isEmpty {
                    Text(dataMessage).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("Data")
            } footer: {
                Text("Semua catatan tersimpan di Mac ini saja. Simpan cadangan sesekali, misalnya ke iCloud Drive.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @State private var dataMessage = ""

    private func exportBackup() {
        guard let data = store.exportJSON() else { return }
        let panel = NSSavePanel()
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = "notecu-\(f.string(from: Date())).json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            do { try data.write(to: url); dataMessage = "✓ Cadangan disimpan" } catch { dataMessage = "Gagal menyimpan: \(error.localizedDescription)" }
        }
    }

    private func importBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        let n = store.importJSON(data)
        dataMessage = n < 0 ? "File ini bukan cadangan notecu." : "✓ \(n) item dipulihkan (yang sudah ada & lebih baru tidak ditimpa)"
    }

    private func setLaunchAtLogin(_ on: Bool) {
        if (SMAppService.mainApp.status == .enabled) == on { return }
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = ""
        } catch {
            loginError = "Gagal mengubah: \(error.localizedDescription). Pastikan notecu ada di folder Applications."
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: - Fitur

private struct FeaturesTab: View {
    @ObservedObject var prefs: Prefs
    @ObservedObject var store: NoteStore
    @ObservedObject private var vault = Vault.shared
    private static let colorNames: [FolderColor: String] = [.amber: "Kuning", .coral: "Merah", .teal: "Hijau tosca", .blue: "Biru", .violet: "Ungu", .green: "Hijau"]

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
                Picker("Warna Agenda", selection: Binding(
                    get: { store.agendaColor },
                    set: { store.setAgendaColor($0) }
                )) {
                    ForEach(FolderColor.allCases, id: \.self) { c in
                        Text(Self.colorNames[c] ?? c.rawValue).tag(c)
                    }
                }
            }
            Section {
                Picker("Kunci lagi setelah", selection: $prefs.vaultLockMinutes) {
                    Text("1 menit").tag(1)
                    Text("5 menit").tag(5)
                    Text("15 menit").tag(15)
                    Text("30 menit").tag(30)
                }
                HStack {
                    Text(vault.isUnlocked ? "Rahasia sedang terbuka" : "Rahasia terkunci").foregroundStyle(.secondary)
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
    private let typing: [(String, String)] = [
        ("- [ ]", "Checklist"),
        ("#tag", "Tag"),
        ("[[Judul]]", "Tautan ke catatan lain (Tab = saran pertama)"),
        ("besok 10:00 !", "Tenggat, jam, penting — di kalimat to-do"),
        ("tiap senin", "To-do berulang"),
    ]

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
            LabeledContent(items[i].1) { Text(items[i].0).monospaced().foregroundStyle(.secondary) }
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
                Text("notecu").font(.system(size: 24, weight: .bold, design: .rounded))
                Text("v\(version)").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Text("note it, cu later.").font(.system(size: 14)).foregroundStyle(.secondary)
            Button {
                if let url = URL(string: "https://instagram.com/rezaprahenda") { NSWorkspace.shared.open(url) }
            } label: {
                HStack(spacing: 4) {
                    Text("made with").foregroundStyle(.secondary)
                    Text("♥").foregroundStyle(.red)
                    Text("by")
                        .foregroundStyle(.secondary)
                    Text("@rezaprahenda").foregroundStyle(Color.accentColor)
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
