import Combine
import Foundation

/// Semua catatan, agenda, to-do & folder. Disimpan di Mac ini saja
/// (~/Library/Application Support/notecu/cache.json), tanpa server.
final class NoteStore: ObservableObject {
    @Published private(set) var items: [String: Item] = [:]
    /// Pesan singkat di kepala panel.
    @Published private(set) var notice: String?
    /// To-do yang baru dicentang: tetap terlihat 3 detik dengan tombol Urungkan.
    struct Linger { var spawned: String?; var recur: String? }
    @Published var lingering: [String: Linger] = [:]
    var lingerWork: [String: DispatchWorkItem] = [:]
    private var noticeWork: DispatchWorkItem?

    let prefs: Prefs

    /// Catatan baru yang masih kosong: belum disimpan.
    private var pristine = Set<String>()
    private var saveWork: DispatchWorkItem?

    init(prefs: Prefs) {
        self.prefs = prefs
        load()
        migrateDaily()
    }

    // MARK: - Membaca

    var folders: [Item] {
        items.values.filter { $0.isFolder && !$0.isDeleted }
            .sorted { ($0.order ?? 0, $0.name ?? "") < ($1.order ?? 0, $1.name ?? "") }
    }

    /// Semua catatan yang ada, termasuk yang di Sampah.
    private var allNotes: [Item] { items.values.filter { $0.isNote && !$0.isDeleted } }
    private var liveNotes: [Item] { allNotes.filter { !$0.isTrashed } }
    /// Catatan dan tugas di Sampah.
    private var trashedItems: [Item] { items.values.filter { ($0.isNote || $0.isTask) && !$0.isDeleted && $0.isTrashed } }

    func folderOf(_ note: Item) -> Item? {
        guard let fid = note.folderId, let f = items[fid], f.isFolder, !f.isDeleted else { return nil }
        return f
    }

    func notes(_ filter: Filter, query: String = "", month: String? = nil) -> [Item] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let base = filter == .trash ? trashedItems : liveNotes
        return base.filter { n in
            switch filter {
            case .all:
                // catatan harian punya tempat sendiri (kecuali sedang mencari)
                if n.isDaily && q.isEmpty { return false }
            case .daily:
                guard let d = n.dailyDate else { return false }
                if let month, !d.hasPrefix(month) { return false }
            case .trash, .tasks: break
            case .pinned: if !n.isPinned { return false }
            case .folder(let id): if folderOf(n)?.id != id { return false }
            }
            if !q.isEmpty && !(n.parts.title + "\n" + n.body).lowercased().contains(q) { return false }
            return true
        }
        .sorted { a, b in
            if filter == .trash { return (a.trashedAt ?? 0) > (b.trashedAt ?? 0) }
            if filter == .daily {
                // hari terbaru dulu; agenda dalam satu hari urut sesuai dibuat
                let da = a.dailyDate ?? "", db = b.dailyDate ?? ""
                return da != db ? da > db : (a.createdAt ?? a.updatedAt) < (b.createdAt ?? b.updatedAt)
            }
            if a.isPinned != b.isPinned { return a.isPinned }
            switch prefs.noteSort {
            case "created": return (a.createdAt ?? a.updatedAt) > (b.createdAt ?? b.updatedAt)
            case "title": return a.displayTitle.localizedStandardCompare(b.displayTitle) == .orderedAscending
            default: return a.updatedAt > b.updatedAt
            }
        }
    }

    func count(_ filter: Filter) -> Int { notes(filter).count }

    func item(_ id: String?) -> Item? {
        guard let id, let it = items[id], !it.isDeleted else { return nil }
        return it
    }

    func note(_ id: String?) -> Item? {
        guard let id, let n = items[id], n.isNote, !n.isDeleted else { return nil }
        return n
    }

    // MARK: - Mengubah

    @discardableResult
    func createNote(folder: String?, pinned: Bool) -> String {
        let id = newID("n")
        let now = nowMillis()
        items[id] = Item(id: id, kind: "note", updatedAt: now, text: "", folderId: folder, pinned: pinned, createdAt: now, title: "")
        pristine.insert(id)
        return id
    }

    /// Ubah isi catatan (tanpa judul).
    func setBody(_ id: String, _ body: String) {
        guard var n = items[id] else { return }
        let p = n.parts
        guard n.title == nil || p.body != body else { return }
        n.title = p.title          // catatan lama: judul dari baris pertama disimpan di kolomnya sendiri
        n.text = body
        commit(n)
    }

    func setTitle(_ id: String, _ title: String) {
        guard var n = items[id] else { return }
        let p = n.parts
        guard n.title == nil || p.title != title else { return }
        n.title = title
        n.text = p.body
        commit(n)
    }

    func toggleCheck(_ id: String, line: Int) {
        guard let n = items[id] else { return }
        setBody(id, NoteText.toggleCheck(n.parts.body, line: line))
    }

    func setPinned(_ id: String, _ pinned: Bool) {
        guard var n = items[id] else { return }
        n.pinned = pinned
        commit(n)
    }

    /// Warna penanda catatan (garis kiri). nil = ikut warna folder.
    func setNoteColor(_ id: String, _ color: FolderColor?) {
        guard var n = items[id] else { return }
        n.color = color?.rawValue
        commit(n)
    }

    /// Buka atau buat catatan harian berjudul tanggal hari ini.
    /// Agenda baru: satu kartu per topik, bertanggal hari ini. Baru tersimpan kalau ada judul atau isinya.
    func newAgenda(date: String = DueDate.today(), tags: [String]? = nil) -> String {
        let id = createNote(folder: nil, pinned: false)
        items[id]?.daily = date
        items[id]?.text = NoteText.agendaTemplate
        items[id]?.tags = tags
        return id
    }

    /// Ganti tanggal agenda, atau nil untuk melepasnya dari Agenda harian.
    func setDaily(_ id: String, _ date: String?) {
        guard var n = items[id] else { return }
        let p = n.parts
        n.title = p.title
        n.text = p.body
        if date == nil, DailyText.parseLegacyTitle(p.title) != nil { n.title = "" }
        n.daily = date
        commit(n)
    }

    /// Agenda lama yang judulnya tanggal ("Rabu, 28 Oktober 2026"): baris pertama isi jadi judul,
    /// tanggal tetap di field daily.
    func migrateDaily() {
        for n in allNotes where !pristine.contains(n.id) {
            let p = n.parts
            guard let ds = DailyText.parseLegacyTitle(p.title) else { continue }
            let sp = NoteText.splitLegacy(p.body)
            guard !sp.title.isEmpty else { continue }
            var m = n
            m.daily = n.daily ?? ds
            m.title = sp.title
            m.text = sp.body
            commit(m)
        }
    }

    // MARK: - Tautan [[Judul]]

    struct Backlink: Identifiable {
        let note: Item
        let line: String
        var id: String { note.id }
    }

    func noteByTitle(_ title: String) -> Item? {
        let k = title.trimmingCharacters(in: .whitespaces).lowercased()
        guard !k.isEmpty else { return nil }
        return liveNotes.first { $0.parts.title.trimmingCharacters(in: .whitespaces).lowercased() == k }
    }

    /// Catatan lain yang menyebut catatan ini, beserta baris yang menyebutnya. Terbaru dulu.
    func backlinks(_ note: Item) -> [Backlink] {
        let k = note.parts.title.trimmingCharacters(in: .whitespaces).lowercased()
        guard !k.isEmpty else { return [] }
        var out: [Backlink] = []
        for m in liveNotes where m.id != note.id && !m.isLocked {
            if let line = NoteText.lines(m.parts.body).first(where: { l in
                NoteText.wikiTitles(l).contains { $0.trimmingCharacters(in: .whitespaces).lowercased() == k }
            }) {
                out.append(Backlink(note: m, line: line))
            }
        }
        func key(_ n: Item) -> String { n.dailyDate.map { $0 + "T" } ?? ISO8601DateFormatter().string(from: n.updatedDate) }
        return out.sorted { key($0.note) > key($1.note) }
    }

    /// Judul saran saat mengetik [[...
    func linkCandidates(_ query: String, excluding id: String?) -> [String] {
        let k = query.trimmingCharacters(in: .whitespaces).lowercased()
        let hits = liveNotes.filter { $0.id != id && !$0.parts.title.trimmingCharacters(in: .whitespaces).isEmpty }
            .filter { k.isEmpty || $0.parts.title.lowercased().contains(k) }
            .sorted { a, b in
                let pa = a.parts.title.lowercased().hasPrefix(k), pb = b.parts.title.lowercased().hasPrefix(k)
                return pa != pb ? pa : a.updatedAt > b.updatedAt
            }
        var seen = Set<String>()
        var out: [String] = []
        for n in hits {
            let t = n.parts.title.trimmingCharacters(in: .whitespaces)
            if seen.insert(t.lowercased()).inserted { out.append(t) }
            if out.count == 6 { break }
        }
        return out
    }

    /// Buka catatan yang ditautkan; kalau belum ada, buat dengan judul itu.
    func noteForLink(_ title: String) -> String {
        if let n = noteByTitle(title) { return n.id }
        let id = createNote(folder: nil, pinned: false)
        setTitle(id, title.trimmingCharacters(in: .whitespaces))
        showNotice("Catatan baru: \(title)")
        return id
    }

    /// Judul catatan diganti: semua [[judul lama]] ikut diganti. Hasilnya jumlah catatan yang berubah.
    @discardableResult
    func renameLinks(from old: String, to new: String) -> Int {
        let k = old.trimmingCharacters(in: .whitespaces).lowercased()
        var count = 0
        for m in allNotes where !m.isLocked && m.body.contains("[[") {
            let p = m.parts
            let ns = p.body as NSString
            var out = ""
            var last = 0
            var changed = false
            for r in NoteText.wikiRegex.matches(in: p.body, range: NSRange(location: 0, length: ns.length)) {
                out += ns.substring(with: NSRange(location: last, length: r.range.location - last))
                let t = ns.substring(with: r.range(at: 1))
                if t.trimmingCharacters(in: .whitespaces).lowercased() == k {
                    out += "[[\(new)]]"
                    changed = true
                } else {
                    out += ns.substring(with: r.range)
                }
                last = r.range.location + r.range.length
            }
            out += ns.substring(from: last)
            if changed {
                var n = m
                n.title = p.title
                n.text = out
                commit(n)
                count += 1
            }
        }
        return count
    }

    /// Warna Agenda harian (disimpan sebagai item "set-agenda", bisa diganti lewat klik kanan chip tahun).
    var agendaColor: FolderColor {
        guard let it = items["set-agenda"], !it.isDeleted else { return .teal }
        return FolderColor.of(it.color ?? "teal")
    }

    func setAgendaColor(_ c: FolderColor) {
        var it = items["set-agenda"] ?? Item(id: "set-agenda", kind: "setting", updatedAt: 0)
        it.color = c.rawValue
        it.deleted = nil
        commit(it)
    }

    func recolorAgenda() {
        var it = items["set-agenda"] ?? Item(id: "set-agenda", kind: "setting", updatedAt: 0)
        it.color = agendaColor.next.rawValue
        it.deleted = nil
        commit(it)
    }

    /// Tahun-tahun yang punya catatan harian, terbaru dulu (field month berisi "2026").
    var dailyYears: [MonthCount] {
        var c: [String: Int] = [:]
        for m in dailyMonths { c[String(m.month.prefix(4)), default: 0] += m.count }
        return c.map { MonthCount(month: $0.key, count: $0.value) }.sorted { $0.month > $1.month }
    }

    /// Bulan-bulan yang punya catatan harian, terbaru dulu.
    var dailyMonths: [MonthCount] {
        var c: [String: Int] = [:]
        for n in liveNotes { if let d = n.dailyDate { c[String(d.prefix(7)), default: 0] += 1 } }
        return c.map { MonthCount(month: $0.key, count: $0.value) }.sorted { $0.month > $1.month }
    }

    func move(_ id: String, to folder: String?) {
        guard var n = items[id] else { return }
        n.folderId = folder
        commit(n)
    }

    /// Pindahkan ke Sampah (bisa dipulihkan selama 30 hari).
    func trashNote(_ id: String) {
        guard var n = items[id] else { return }
        if pristine.contains(id) { discard(id); return }
        n.trashedAt = nowMillis()
        commit(n)
    }

    func restoreNote(_ id: String) {
        guard var n = items[id] else { return }
        n.trashedAt = nil
        commit(n)
    }

    /// Hapus permanen.
    func purgeNote(_ id: String) {
        guard let n = items[id] else { return }
        if pristine.contains(id) { discard(id); return }
        commit(Item(id: id, kind: n.kind, updatedAt: n.updatedAt, deleted: true, rev: n.rev))
    }

    func emptyTrash() {
        for n in notes(.trash) { purgeNote(n.id) }
    }

    private func discard(_ id: String) {
        pristine.remove(id)
        items.removeValue(forKey: id)
    }

    /// Judul saat catatan dibuka, untuk mengganti [[tautan]] kalau judulnya diubah.
    private static var openTitles: [String: String] = [:]

    func noteOpened(_ id: String) {
        if let n = items[id], n.isNote { Self.openTitles[id] = n.parts.title }
    }

    /// Dipanggil saat catatan ditutup: catatan yang kosong dibuang.
    func closeNote(_ id: String) {
        guard let n = items[id], n.isNote, !n.isDeleted, !n.isTrashed else { return }
        if let old = Self.openTitles[id] {
            let new = n.parts.title.trimmingCharacters(in: .whitespaces)
            if !old.trimmingCharacters(in: .whitespaces).isEmpty, !new.isEmpty, new.lowercased() != old.trimmingCharacters(in: .whitespaces).lowercased() {
                let c = renameLinks(from: old, to: new)
                if c > 0 { showNotice("Tautan di \(c) catatan ikut diganti") }
            }
            Self.openTitles[id] = n.parts.title
        }
        if n.isBlank { purgeNote(id) }
        scheduleSave()
    }

    @discardableResult
    func createFolder(_ name: String) -> String {
        let id = newID("f")
        let fs = folders
        let color = FolderColor.allCases[fs.count % FolderColor.allCases.count]
        let order = (fs.map { $0.order ?? 0 }.max() ?? 0) + 1
        commit(Item(id: id, kind: "folder", updatedAt: 0, name: name, color: color.rawValue, order: order))
        return id
    }

    func renameFolder(_ id: String, _ name: String) {
        guard var f = items[id], !name.isEmpty else { return }
        f.name = name
        commit(f)
    }

    func recolorFolder(_ id: String) {
        guard var f = items[id] else { return }
        f.color = FolderColor.of(f.color).next.rawValue
        commit(f)
    }

    /// Hapus folder; catatan di dalamnya tetap ada (pindah ke "tanpa folder").
    func deleteFolder(_ id: String) {
        for n in allNotes where n.folderId == id { move(n.id, to: nil) }
        guard let f = items[id] else { return }
        commit(Item(id: id, kind: f.kind, updatedAt: f.updatedAt, deleted: true, rev: f.rev))
    }

    func commit(_ item: Item) {
        var it = item
        it.updatedAt = max(nowMillis(), it.updatedAt + 1)
        let emptyNew = pristine.contains(it.id) && it.isBlank && !it.isDeleted
        if it.isDeleted {
            items.removeValue(forKey: it.id)   // langsung dibuang dari penyimpanan
        } else {
            items[it.id] = it
        }
        if emptyNew { return }          // catatan kosong belum perlu disimpan
        pristine.remove(it.id)
        scheduleSave()
    }

    private func showNotice(_ text: String) {
        noticeWork?.cancel()
        notice = text
        let w = DispatchWorkItem { [weak self] in self?.notice = nil }
        noticeWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: w)
    }

    func noteNotice(_ text: String) { showNotice(text) }

    // MARK: - Simpan di Mac

    private struct Cache: Codable {
        var items: [Item]
    }

    private var cacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("notecu", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("cache.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: cacheURL),
              let c = try? JSONDecoder().decode(Cache.self, from: data) else { return }
        items = Dictionary(c.items.filter { !$0.isDeleted }.map { ($0.id, $0) }, uniquingKeysWith: { a, b in a.updatedAt >= b.updatedAt ? a : b })
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: w)
    }

    func saveNow() {
        saveWork?.cancel()
        // Catatan baru yang masih kosong tidak ikut disimpan.
        let keep = items.values.filter { !pristine.contains($0.id) }
        let c = Cache(items: Array(keep))
        guard let data = try? JSONEncoder().encode(c) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    /// Folder tempat data disimpan (untuk "Tampilkan di Finder").
    var dataFolder: URL { cacheURL.deletingLastPathComponent() }

    /// Pulihkan dari file cadangan JSON. Yang lebih baru menang; hasilnya jumlah item yang masuk.
    @discardableResult
    func importJSON(_ data: Data) -> Int {
        struct Export: Decodable { var items: [Item] }
        guard let e = try? JSONDecoder().decode(Export.self, from: data) else { return -1 }
        var n = 0
        var next = items
        for it in e.items where !it.isDeleted {
            if let cur = next[it.id], cur.updatedAt >= it.updatedAt { continue }
            next[it.id] = it
            n += 1
        }
        items = next
        saveNow()
        return n
    }

    /// Semua catatan & folder aktif, untuk cadangan.
    func exportJSON() -> Data? {
        struct Export: Codable { var app = "notecu"; var exportedAt: Double; var items: [Item] }
        let live = items.values.filter { !$0.isDeleted && !pristine.contains($0.id) }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? enc.encode(Export(exportedAt: nowMillis(), items: Array(live)))
    }
}
