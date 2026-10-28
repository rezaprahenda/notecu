import AppKit
import Foundation

/// Teks app. Kuncinya teks bahasa Indonesia; terjemahan bahasa Inggris ada di
/// Resources/en.lproj/Localizable.strings. Kunci yang tidak ada terjemahannya tampil apa adanya.
///
/// - Teks tetap di SwiftUI (`Text("…")`, `Button("…")`, `Toggle("…")`…) diterjemahkan otomatis.
/// - Teks yang disusun di kode memakai `L("…")`, dengan argumen ala `String(format:)`:
///   `L("%lld to-do perlu dibereskan", n)`.
func L(_ key: String, _ args: CVarArg...) -> String {
    let s = Bundle.main.localizedString(forKey: key, value: key, table: nil)
    return args.isEmpty ? s : String(format: s, locale: AppLang.locale, arguments: args)
}

/// Bahasa app: ikut sistem, atau dipilih di Pengaturan → Umum → Bahasa (berlaku setelah dibuka ulang).
enum AppLang {
    private static let key = "appLanguage"

    /// Bahasa yang sedang dipakai app ini.
    static var isEnglish: Bool { (Bundle.main.preferredLocalizations.first ?? "id").hasPrefix("en") }
    static var locale: Locale { Locale(identifier: isEnglish ? "en_US" : "id_ID") }

    /// "" = ikuti sistem, "id", atau "en".
    static var choice: String { UserDefaults.standard.string(forKey: key) ?? "" }
    /// Pilihan saat app dibuka (untuk tahu perlu dibuka ulang atau tidak).
    static let choiceAtLaunch = choice

    static func choose(_ c: String) {
        let d = UserDefaults.standard
        d.set(c, forKey: key)
        if c.isEmpty { d.removeObject(forKey: "AppleLanguages") } else { d.set([c], forKey: "AppleLanguages") }
    }

    /// Simpan, lalu buka ulang notecu supaya bahasa barunya terpakai.
    static func relaunch(store: NoteStore) {
        store.saveNow()
        let path = Bundle.main.bundlePath
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 0.6; /usr/bin/open \"$0\"", path]
        try? p.run()
        NSApp.terminate(nil)
    }
}
