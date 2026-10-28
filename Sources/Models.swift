import Foundation
import SwiftUI

/// Satu baris data: catatan, folder, to-do, atau pengaturan.
struct Item: Codable, Identifiable, Equatable {
    var id: String
    var kind: String            // "note" | "folder"
    var updatedAt: Double       // milidetik sejak 1970, dipakai untuk "yang terbaru menang"
    var deleted: Bool?

    // Catatan
    var text: String?
    var folderId: String?
    var pinned: Bool?
    var createdAt: Double?

    // Folder
    var name: String?
    var color: String?
    var order: Double?

    // Judul catatan (terpisah dari isi). nil = catatan lama, judulnya masih di baris pertama.
    var title: String?
    /// Versi data (dipertahankan supaya cadangan lama tetap terbaca).
    var rev: Int?
    /// Waktu dibuang ke Sampah (milidetik). nil = tidak di Sampah.
    var trashedAt: Double?

    // Tugas
    /// Tenggat, tanggal lokal "yyyy-MM-dd"
    var due: String?
    /// Jam tenggat "HH:mm" (opsional)
    var dueTime: String?
    var important: Bool?
    /// Waktu selesai (milidetik). nil = belum selesai.
    var doneAt: Double?
    /// Catatan asal kalau tugas dibuat dari checklist
    var sourceNoteId: String?
    /// Tag yang ditambahkan lewat tombol (selain #tag yang diketik di teks)
    var tags: [String]?
    /// Catatan harian: tanggal lokal "yyyy-MM-dd"
    var daily: String?
    /// Seluruh isi catatan dikunci (isinya satu token rahasia, lihat Vault.swift)
    var locked: Bool?
    /// To-do berulang: "daily" | "weekdays" | "weekly:<0-6>" | "monthly:<1-31>"
    var recur: String?

    var isDeleted: Bool { deleted ?? false }
    var isNote: Bool { kind == "note" }
    var isFolder: Bool { kind == "folder" }
    var isTask: Bool { kind == "task" }
    var isDone: Bool { doneAt != nil }
    var isImportant: Bool { important ?? false }
    var createdDate: Date { Date(timeIntervalSince1970: (createdAt ?? updatedAt) / 1000) }
    var isPinned: Bool { pinned ?? false }
    var isTrashed: Bool { trashedAt != nil }
    /// Sisa hari sebelum catatan di Sampah hilang permanen.
    var trashDaysLeft: Int {
        guard let t = trashedAt else { return 0 }
        let left = 30 - (nowMillis() - t) / 86_400_000
        return max(0, Int(left.rounded(.up)))
    }
    var body: String { text ?? "" }

    /// Judul dan isi. Catatan lama tanpa kolom judul dipecah dari baris pertamanya.
    var parts: (title: String, body: String) {
        if let title { return (title, body) }
        return NoteText.splitLegacy(body)
    }
    var displayTitle: String {
        let t = parts.title.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "Tanpa judul" : t
    }
    var isBlank: Bool {
        let p = parts
        let b = p.body.trimmingCharacters(in: .whitespacesAndNewlines)
        // Agenda yang kerangkanya belum diisi juga dianggap kosong.
        return p.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (b.isEmpty || b == NoteText.agendaTemplate.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Tanggal "yyyy-MM-dd" kalau ini catatan harian (field daily, atau judul lama "Rabu, 28 Oktober 2026").
    var dailyDate: String? {
        if let daily { return daily }
        guard isNote else { return nil }
        return DailyText.parseLegacyTitle(parts.title)
    }
    var isDaily: Bool { isNote && dailyDate != nil }
    var updatedDate: Date { Date(timeIntervalSince1970: updatedAt / 1000) }
}

enum Filter: Hashable {
    case all
    case pinned
    case tasks
    case daily
    case trash
    case folder(String)
}

enum FolderColor: String, CaseIterable {
    case amber, coral, teal, blue, violet, green

    var color: Color {
        switch self {
        case .amber:  return Color(red: 0.83, green: 0.60, blue: 0.07)
        case .coral:  return Color(red: 0.86, green: 0.35, blue: 0.25)
        case .teal:   return Color(red: 0.12, green: 0.58, blue: 0.52)
        case .blue:   return Color(red: 0.23, green: 0.45, blue: 0.85)
        case .violet: return Color(red: 0.52, green: 0.35, blue: 0.80)
        case .green:  return Color(red: 0.31, green: 0.60, blue: 0.20)
        }
    }

    static func of(_ raw: String?) -> FolderColor { FolderColor(rawValue: raw ?? "") ?? .blue }

    var next: FolderColor {
        let all = FolderColor.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

/// Aturan teks catatan:
/// baris pertama = judul, "- [ ]" / "- [x]" = checklist, "# " = judul bagian, "- " = poin.
enum NoteText {
    /// Kerangka Agenda baru.
    static let agendaTemplate = "## Peserta\n- \n\n## Pembahasan\n- \n\n## Kesimpulan\n- \n\n## Tindak lanjut\n- [ ] "
    static let wikiRegex = try! NSRegularExpression(pattern: #"\[\[([^\[\]\n]+?)\]\]"#)
    static let noteScheme = "notecu-note"
    private static let urlSafe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    /// Judul-judul yang ditautkan [[...]] di teks.
    static func wikiTitles(_ text: String) -> [String] {
        let ns = text as NSString
        return wikiRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
    }

    /// [[Judul]] -> tautan markdown notecu-note:Judul (untuk tampilan baca).
    static func linkWiki(_ text: String) -> String {
        guard text.contains("[[") else { return text }
        let ns = text as NSString
        var out = ""
        var last = 0
        for m in wikiRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let t = ns.substring(with: m.range(at: 1))
            let enc = t.addingPercentEncoding(withAllowedCharacters: urlSafe) ?? t
            out += "[\(t)](\(noteScheme):\(enc))"
            last = m.range.location + m.range.length
        }
        return out + ns.substring(from: last)
    }

    static let checkPattern = try! NSRegularExpression(pattern: #"^\s*- \[([ xX])\] ?(.*)$"#)
    static let headingPattern = try! NSRegularExpression(pattern: #"^(#{1,3})\s+(.*)$"#)
    static let bulletPattern = try! NSRegularExpression(pattern: #"^\s*[-*]\s+(.*)$"#)
    static let numberPattern = try! NSRegularExpression(pattern: #"^\s*(\d+)[.)]\s+(.*)$"#)

    static func lines(_ text: String) -> [String] {
        text.components(separatedBy: "\n")
    }

    /// Catatan lama: baris pertama yang berisi jadi judul, sisanya isi.
    static func splitLegacy(_ text: String) -> (title: String, body: String) {
        var ls = lines(text)
        guard let i = ls.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return ("", "") }
        var t = ls[i].trimmingCharacters(in: .whitespaces)
        t = t.replacingOccurrences(of: #"^#+\s*"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"^- \[[ xX]\]\s*"#, with: "", options: .regularExpression)
        ls.removeSubrange(0...i)
        while let first = ls.first, first.trimmingCharacters(in: .whitespaces).isEmpty { ls.removeFirst() }
        return (t, ls.joined(separator: "\n"))
    }

    /// Ringkasan isi untuk daftar catatan.
    static func snippet(_ body: String) -> String {
        lines(Vault.replaceTokens(body, with: "🔒••••"))
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.replacingOccurrences(of: #"^\s*(- \[[ xX]\] ?|#+\s*|[-*]\s+|\d+[.)]\s+)"#, with: "", options: .regularExpression) }
            .joined(separator: " · ")
    }

    static func checks(_ text: String) -> (done: Int, total: Int) {
        var done = 0, total = 0
        for line in lines(text) {
            let ns = line as NSString
            if let m = checkPattern.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
               !ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces).isEmpty {
                total += 1
                if ns.substring(with: m.range(at: 1)) != " " { done += 1 }
            }
        }
        return (done, total)
    }

    /// Teks satu baris dengan **tebal**, *miring*, `kode`, [tautan](url), dan link polos yang bisa diklik.
    static func inline(_ text: String) -> AttributedString {
        // Rahasia jadi tautan "🔒 ••••••••" yang ditangani ReadView (buka / salin).
        let masked = linkWiki(Vault.replaceTokens(text, with: "[🔒 ••••••••](\(Vault.urlScheme):$1)"))
        let linked = masked.replacingOccurrences(of: #"(?<![\(<\[])(https?://[^\s<>()]+)"#, with: "<$1>", options: .regularExpression)
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: linked, options: opts)) ?? AttributedString(text)
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    /// Centang / hapus centang di baris ke-`index`.
    static func toggleCheck(_ text: String, line index: Int) -> String {
        var ls = lines(text)
        guard ls.indices.contains(index) else { return text }
        let line = ls[index]
        if let r = line.range(of: "- [ ]") {
            ls[index] = line.replacingCharacters(in: r, with: "- [x]")
        } else if let r = line.range(of: #"- \[[xX]\]"#, options: .regularExpression) {
            ls[index] = line.replacingCharacters(in: r, with: "- [ ]")
        }
        return ls.joined(separator: "\n")
    }
}

enum RelativeTime {
    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "id_ID")
        f.unitsStyle = .short
        return f
    }()
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "id_ID")
        f.setLocalizedDateFormatFromTemplate("d MMM")
        return f
    }()

    static func string(_ date: Date) -> String {
        let s = Date().timeIntervalSince(date)
        if s < 60 { return "baru saja" }
        if s < 86_400 * 2 { return formatter.localizedString(for: date, relativeTo: Date()) }
        return dateFormatter.string(from: date)
    }
}

func newID(_ prefix: String) -> String {
    let t = String(Int(Date().timeIntervalSince1970 * 1000), radix: 36)
    let r = String(UInt32.random(in: 0...UInt32.max), radix: 36)
    return prefix + t + r
}

func nowMillis() -> Double { (Date().timeIntervalSince1970 * 1000).rounded() }

/// Aturan catatan harian.
enum DailyText {
    private static let months = ["januari", "februari", "maret", "april", "mei", "juni", "juli",
                                 "agustus", "september", "oktober", "november", "desember"]
    private static let legacy = try! NSRegularExpression(
        pattern: #"^(senin|selasa|rabu|kamis|jumat|sabtu|minggu),\s+(\d{1,2})\s+([a-z]+)\s+(\d{4})$"#,
        options: [.caseInsensitive])
    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "id_ID")
        f.dateFormat = "MMMM yyyy"
        return f
    }()
    private static let shortFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "id_ID")
        f.dateFormat = "EEEE, d MMM"
        return f
    }()

    static func parseLegacyTitle(_ title: String) -> String? {
        let t = title.trimmingCharacters(in: .whitespaces)
        let ns = t as NSString
        guard let m = legacy.firstMatch(in: t, range: NSRange(location: 0, length: ns.length)),
              let mi = months.firstIndex(of: ns.substring(with: m.range(at: 3)).lowercased()),
              let day = Int(ns.substring(with: m.range(at: 2))) else { return nil }
        return String(format: "%@-%02d-%02d", ns.substring(with: m.range(at: 4)), mi + 1, day)
    }

    /// "2026-10" -> "Oktober 2026"
    static func monthLabel(_ ym: String) -> String {
        guard let d = DueDate.date(ym + "-01") else { return ym }
        return monthFormatter.string(from: d).capitalized(with: Locale(identifier: "id_ID"))
    }

    /// "2026-10" -> "Oktober"
    static func monthName(_ ym: String) -> String {
        monthLabel(ym).replacingOccurrences(of: #"\s+\d{4}$"#, with: "", options: .regularExpression)
    }

    /// "2026-10-28" -> "Rabu, 28 Okt"
    static func shortLabel(_ ds: String) -> String {
        guard let d = DueDate.date(ds) else { return ds }
        return shortFormatter.string(from: d)
    }
}

struct MonthCount: Hashable {
    var month: String
    var count: Int
}
