import Foundation

/// Pengaturan app, disimpan di UserDefaults.
final class Prefs: ObservableObject {
    private let d = UserDefaults.standard

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

    init() {
        edge = d.string(forKey: "edge") ?? "right"
        hoverOpen = d.object(forKey: "hoverOpen") as? Bool ?? true
        panelWidth = d.object(forKey: "panelWidth") as? Double ?? 360
        noteSort = d.string(forKey: "noteSort") ?? "updated"
        remindersOn = d.object(forKey: "remindersOn") as? Bool ?? true
        reminderTime = d.string(forKey: "reminderTime") ?? "09:00"
        noteFont = d.string(forKey: "noteFont") ?? "sans"
        vaultLockMinutes = d.object(forKey: "vaultLockMinutes") as? Int ?? 5
    }
}
