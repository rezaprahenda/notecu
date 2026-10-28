import Foundation

/// Pengaturan app, disimpan di UserDefaults.
final class Prefs: ObservableObject {
    private let d = UserDefaults.standard

    @Published var serverURL: String { didSet { d.set(serverURL, forKey: "serverURL") } }
    @Published var token: String { didSet { d.set(token, forKey: "token") } }
    /// "right" atau "left"
    @Published var edge: String { didSet { d.set(edge, forKey: "edge") } }
    /// Buka panel saat kursor didorong ke tepi layar
    @Published var hoverOpen: Bool { didSet { d.set(hoverOpen, forKey: "hoverOpen") } }
    @Published var panelWidth: Double { didSet { d.set(panelWidth, forKey: "panelWidth") } }
    /// Urutan catatan: "updated", "created", atau "title"
    @Published var noteSort: String { didSet { d.set(noteSort, forKey: "noteSort") } }
    /// Notifikasi saat tugas jatuh tempo
    @Published var remindersOn: Bool { didSet { d.set(remindersOn, forKey: "remindersOn") } }
    /// Jam pengingat untuk tugas tanpa jam, "HH:mm"
    @Published var reminderTime: String { didSet { d.set(reminderTime, forKey: "reminderTime") } }
    /// Huruf isi catatan: "sans" atau "serif"
    @Published var noteFont: String { didSet { d.set(noteFont, forKey: "noteFont") } }
    /// Rahasia terkunci lagi setelah sekian menit tidak dipakai
    @Published var vaultLockMinutes: Int { didSet { d.set(vaultLockMinutes, forKey: "vaultLockMinutes") } }
    /// Kerangka Agenda baru: "" = ikut bahasa app, "id", "en", "none" (kosong), atau "custom"
    @Published var agendaTemplate: String { didSet { d.set(agendaTemplate, forKey: "agendaTemplate") } }
    /// Kerangka buatan sendiri (dipakai kalau agendaTemplate = "custom")
    @Published var agendaCustom: String { didSet { d.set(agendaCustom, forKey: "agendaCustom") } }

    init() {
        serverURL = d.string(forKey: "serverURL") ?? ""
        token = d.string(forKey: "token") ?? ""
        edge = d.string(forKey: "edge") ?? "right"
        hoverOpen = d.object(forKey: "hoverOpen") as? Bool ?? true
        panelWidth = d.object(forKey: "panelWidth") as? Double ?? 360
        noteSort = d.string(forKey: "noteSort") ?? "updated"
        remindersOn = d.object(forKey: "remindersOn") as? Bool ?? true
        reminderTime = d.string(forKey: "reminderTime") ?? "09:00"
        noteFont = d.string(forKey: "noteFont") ?? "sans"
        vaultLockMinutes = d.object(forKey: "vaultLockMinutes") as? Int ?? 5
        agendaTemplate = d.string(forKey: "agendaTemplate") ?? ""
        agendaCustom = d.string(forKey: "agendaCustom") ?? NoteText.agendaTemplateID
    }

    var isConfigured: Bool { baseURLString != nil && !token.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Alamat server yang sudah dirapikan, misalnya "http://homeserver:8787"
    var baseURLString: String? {
        var s = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "http://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    func apiURL(_ path: String) -> URL? {
        guard let base = baseURLString else { return nil }
        return URL(string: base + "/" + path)
    }

    var cleanToken: String { token.trimmingCharacters(in: .whitespacesAndNewlines) }
}
