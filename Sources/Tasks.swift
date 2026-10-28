import Foundation

/// Tanggal tenggat disimpan sebagai tanggal lokal "yyyy-MM-dd" (+ jam "HH:mm" opsional),
/// sama seperti di web app, supaya tidak bergeser karena zona waktu.
enum DueDate {
    static var cal: Calendar { Calendar.current }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()
    private static let shortFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = AppLang.locale
        f.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return f
    }()
    private static let longFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = AppLang.locale
        f.setLocalizedDateFormatFromTemplate("d MMM yyyy")
        return f
    }()
    private static let dailyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = AppLang.locale
        f.dateFormat = "EEEE, d MMMM yyyy"
        return f
    }()

    static func string(_ d: Date) -> String { dayFormatter.string(from: d) }
    static func date(_ s: String?) -> Date? { s.flatMap { dayFormatter.date(from: $0) } }
    static func timeString(_ d: Date) -> String { timeFormatter.string(from: d) }
    static func time(_ s: String?) -> Date? { s.flatMap { timeFormatter.date(from: $0) } }

    static func today() -> String { string(Date()) }
    static func inDays(_ n: Int) -> String { string(cal.date(byAdding: .day, value: n, to: Date()) ?? Date()) }

    /// Senin berikutnya.
    static func nextWeek() -> String {
        var d = cal.startOfDay(for: Date())
        repeat { d = cal.date(byAdding: .day, value: 1, to: d) ?? d } while cal.component(.weekday, from: d) != 2
        return string(d)
    }

    /// Selisih hari dari hari ini (negatif = sudah lewat).
    static func daysFromToday(_ s: String?) -> Int? {
        guard let d = date(s) else { return nil }
        return cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: d)).day
    }

    /// Waktu notifikasi: jam tenggat, atau jam bawaan kalau tugas tanpa jam.
    static func fireDate(due: String, time: String?, defaultTime: String) -> Date? {
        guard let day = date(due) else { return nil }
        let t = Self.time(time) ?? Self.time(defaultTime) ?? Self.time("09:00")!
        let hm = cal.dateComponents([.hour, .minute], from: t)
        return cal.date(bySettingHour: hm.hour ?? 9, minute: hm.minute ?? 0, second: 0, of: day)
    }

    /// "Hari ini", "Besok", "Kemarin", "3 hari lalu", "Sen 3 Nov" (+ " 14:00")
    static func label(_ task: Item) -> String {
        guard let due = task.due, let days = daysFromToday(due), let d = date(due) else { return "" }
        let base: String
        switch days {
        case 0: base = L("Hari ini")
        case 1: base = L("Besok")
        case -1: base = L("Kemarin")
        case let n where n < -1 && n > -7: base = L("%lld hari lalu", -n)
        default: base = cal.component(.year, from: d) == cal.component(.year, from: Date()) ? shortFormatter.string(from: d) : longFormatter.string(from: d)
        }
        if let t = task.dueTime { return base + " " + t }
        return base
    }

    static func isOverdue(_ task: Item) -> Bool {
        guard !task.isDone, let due = task.due, let days = daysFromToday(due) else { return false }
        if days < 0 { return true }
        if days == 0, let t = task.dueTime, let fire = fireDate(due: due, time: t, defaultTime: t) { return fire < Date() }
        return false
    }

    static func dailyTitle(_ d: Date) -> String { dailyFormatter.string(from: d) }
    static func longDate(_ d: Date) -> String { longFormatter.string(from: d) }
}

enum TaskGroup: Int, CaseIterable {
    case overdue, today, tomorrow, week, later, noDate

    var title: String {
        switch self {
        case .overdue: return L("Terlambat")
        case .today: return L("Hari ini")
        case .tomorrow: return L("Besok")
        case .week: return L("7 hari ke depan")
        case .later: return L("Nanti")
        case .noDate: return L("Tanpa tanggal")
        }
    }

    static func of(_ task: Item) -> TaskGroup {
        guard let days = DueDate.daysFromToday(task.due) else { return .noDate }
        if DueDate.isOverdue(task) { return .overdue }
        switch days {
        case ..<1: return .today
        case 1: return .tomorrow
        case 2...7: return .week
        default: return .later
        }
    }
}

extension NoteStore {
    /// Tugas aktif (bukan di Sampah).
    var tasks: [Item] { items.values.filter { $0.isTask && !$0.isDeleted && !$0.isTrashed } }

    func task(_ id: String?) -> Item? {
        guard let id, let t = items[id], t.isTask, !t.isDeleted else { return nil }
        return t
    }

    /// Tugas yang belum selesai, diurutkan: penting dulu, lalu tenggat terdekat.
    func openTasks(folder: String? = nil, query: String = "") -> [Item] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return tasks.filter { t in
            if t.isDone && lingering[t.id] == nil { return false }
            if let folder, t.folderId != folder { return false }
            if !q.isEmpty && !(t.displayTitle + "\n" + t.body).lowercased().contains(q) { return false }
            return true
        }
        .sorted(by: Self.taskOrder)
    }

    /// Riwayat: tugas selesai 30 hari terakhir, yang terbaru dulu.
    func doneTasks(query: String = "", all: Bool = false) -> [Item] {
        let cutoff = all ? 0 : nowMillis() - 30 * 86_400_000
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return tasks.filter { t in
            guard let done = t.doneAt, done >= cutoff, lingering[t.id] == nil else { return false }
            return q.isEmpty || (t.displayTitle + "\n" + t.body).lowercased().contains(q)
        }
        .sorted { ($0.doneAt ?? 0) > ($1.doneAt ?? 0) }
    }

    /// Tugas terlambat + jatuh tempo hari ini (angka di menu bar).
    var dueCount: Int {
        tasks.filter { t in
            guard !t.isDone else { return false }
            let g = TaskGroup.of(t)
            return g == .overdue || g == .today
        }.count
    }

    static func taskOrder(_ a: Item, _ b: Item) -> Bool {
        let da = (a.due ?? "9999-12-31") + (a.dueTime ?? "99:99")
        let db = (b.due ?? "9999-12-31") + (b.dueTime ?? "99:99")
        if da != db { return da < db }
        if a.isImportant != b.isImportant { return a.isImportant }
        return (a.createdAt ?? a.updatedAt) < (b.createdAt ?? b.updatedAt)
    }

    @discardableResult
    func addTask(title: String, due: String?, dueTime: String?, important: Bool, folder: String?,
                 text: String = "", sourceNote: String? = nil) -> String {
        let id = newID("t")
        let now = nowMillis()
        var t = Item(id: id, kind: "task", updatedAt: now, text: text, folderId: folder, createdAt: now, title: title)
        t.due = due
        t.dueTime = due == nil ? nil : dueTime
        t.important = important ? true : nil
        t.sourceNoteId = sourceNote
        commit(t)
        return id
    }

    func updateTask(_ id: String, _ change: (inout Item) -> Void) {
        guard var t = items[id] else { return }
        let before = t
        change(&t)
        if t.due == nil { t.dueTime = nil }
        if t != before { commit(t) }
    }

    func toggleDone(_ id: String) {
        // To-do berulang: yang ini selesai (masuk riwayat), salinannya muncul di jadwal berikutnya.
        if let t = items[id], t.doneAt == nil, let rule = t.recur, let due = t.due {
            var next = Recur.next(rule, after: due)
            while let n = next, n < DueDate.today() { next = Recur.next(rule, after: n) }
            var spawned: String?
            if let next {
                var copy = t
                copy.id = newID("t")
                copy.due = next
                copy.createdAt = nowMillis()
                copy.rev = nil
                copy.doneAt = nil
                copy.trashedAt = nil
                commit(copy)
                spawned = copy.id
                noteNotice(L("Berikutnya: %@ · %@", DueDate.label(copy), Recur.label(rule)))
            }
            linger(id, spawned: spawned, recur: rule)
            updateTask(id) { $0.doneAt = nowMillis(); $0.recur = nil }
            return
        }
        if items[id]?.doneAt == nil { linger(id, spawned: nil, recur: nil) } else { endLinger(id) }
        updateTask(id) { t in t.doneAt = t.doneAt == nil ? nowMillis() : nil }
    }

    /// Biarkan to-do yang baru dicentang terlihat 3 detik, lalu pindah ke Selesai.
    private func linger(_ id: String, spawned: String?, recur: String?) {
        lingerWork[id]?.cancel()
        lingering[id] = Linger(spawned: spawned, recur: recur)
        let w = DispatchWorkItem { [weak self] in self?.endLinger(id) }
        lingerWork[id] = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: w)
    }

    private func endLinger(_ id: String) {
        lingerWork[id]?.cancel()
        lingerWork[id] = nil
        lingering[id] = nil
    }

    /// Batalkan centang: to-do kembali aktif, salinan to-do berulang dibuang.
    func undoDone(_ id: String) {
        guard let l = lingering[id] else { return }
        endLinger(id)
        if let s = l.spawned { purgeNote(s) }
        updateTask(id) { t in
            t.doneAt = nil
            if let r = l.recur { t.recur = r }
        }
        noteNotice(L("Dibatalkan"))
    }

    /// Ubah butir checklist di catatan menjadi tugas; butir itu dihapus dari catatan.
    @discardableResult
    func convertChecklistLine(note noteID: String, line index: Int) -> String? {
        guard let n = note(noteID) else { return nil }
        var lines = NoteText.lines(n.parts.body)
        guard lines.indices.contains(index) else { return nil }
        let line = lines[index]
        let ns = line as NSString
        guard let m = NoteText.checkPattern.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let label = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty else { return nil }
        let done = ns.substring(with: m.range(at: 1)) != " "
        lines.remove(at: index)
        setBody(noteID, lines.joined(separator: "\n"))
        let id = addLinkedTask(note: noteID, title: label)
        if done { toggleDone(id) }
        return id
    }

    /// Tugas yang lahir dari catatan ini: belum selesai dulu, lalu yang sudah selesai.
    func linkedTasks(_ noteID: String) -> [Item] {
        items.values.filter { $0.isTask && !$0.isDeleted && !$0.isTrashed && $0.sourceNoteId == noteID }
            .sorted { a, b in
                if (a.doneAt == nil) != (b.doneAt == nil) { return a.doneAt == nil }
                return NoteStore.taskOrder(a, b)
            }
    }

    /// Tugas baru yang tertaut ke catatan: ikut folder dan tag catatannya.
    @discardableResult
    func addLinkedTask(note noteID: String, title: String) -> String {
        let n = note(noteID)
        let p = TodoParser(title)
        let id = addTask(title: p.title, due: p.due, dueTime: p.dueTime, important: p.important, folder: n?.folderId, sourceNote: noteID)
        if let r = p.recur, p.due != nil { updateTask(id) { $0.recur = r } }
        var tags = n?.tagList ?? []
        for t in p.tags where !tags.contains(t) { tags.append(t) }
        if !tags.isEmpty { updateTask(id) { $0.tags = tags } }
        return id
    }
}

/// Kalimat to-do: "Surati Kapusdatin besok 10:00 ! #kementan" → judul + tenggat + jam + penting + tag.
/// Aturannya sama dengan parseTodo di web app. Kata yang dikenali dibuang dari judul.
struct TodoParser {
    var title = ""
    var due: String?
    var dueTime: String?
    var important = false
    var tags: [String] = []
    var recur: String?

    private static let cal = Calendar(identifier: .gregorian)

    init(_ raw: String) {
        var s = " " + raw.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression) + " "

        /// Cari semua kecocokan, olah, lalu ganti dengan spasi.
        /// `fn` mengembalikan false kalau kata itu harus dibiarkan di judul.
        func take(_ pattern: String, _ fn: ([String?]) -> Bool) {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return }
            let ns = s as NSString
            var out = ""
            var last = 0
            for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
                let groups: [String?] = (0..<m.numberOfRanges).map { i in
                    let r = m.range(at: i)
                    return r.location == NSNotFound ? nil : ns.substring(with: r)
                }
                out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                out += fn(groups) ? " " : ns.substring(with: m.range)
                last = m.range.location + m.range.length
            }
            out += ns.substring(from: last)
            s = out
        }
        func addMonths(_ n: Int, day: Int) -> String {
            var c = Self.cal.dateComponents([.year, .month], from: Date())
            c.month = (c.month ?? 1) + n
            c.day = 1
            let first = Self.cal.date(from: c) ?? Date()
            let last = Self.cal.range(of: .day, in: .month, for: first)?.count ?? 28
            c.day = min(day, last)
            return DueDate.string(Self.cal.date(from: c) ?? first)
        }
        func hm(_ h: String?, _ m: String?) -> String? {
            guard let h, let hh = Int(h), hh < 24 else { return nil }
            let mm = Int(m ?? "0") ?? 0
            guard mm < 60 else { return nil }
            return String(format: "%02d:%02d", hh, mm)
        }
        func dayIn(_ y: Int, _ month0: Int, _ d: Int) -> String? {
            var c = DateComponents()
            c.year = y + (month0 >= 12 ? 1 : 0)
            c.month = month0 % 12 + 1
            c.day = d
            guard let date = Self.cal.date(from: c), Self.cal.component(.month, from: date) == c.month else { return nil }
            return DueDate.string(date)
        }
        let today = DueDate.today()
        let now = Date()
        let year = Self.cal.component(.year, from: now)
        let month0 = Self.cal.component(.month, from: now) - 1

        take(#"\s#([\p{L}\p{N}_-]+)(?=\s)"#) { m in
            let t = TagText.normalize(m[1] ?? "")
            if !t.isEmpty && !tags.contains(t) { tags.append(t) }
            return true
        }
        take(#"\s!+(?=\s)"#) { _ in important = true; return true }
        take(#"\s(?:jam|pukul|pkl\.?)\s+(\d{1,2})(?:[:.](\d{2}))?(?=\s)"#) { m in dueTime = hm(m[1], m[2]) ?? dueTime; return true }
        // berulang: "tiap senin", "tiap tgl 25", "setiap hari kerja" (sebelum nama hari biasa)
        let dows = ["minggu", "senin", "selasa", "rabu", "kamis", "jumat", "sabtu"]
        take(#"\s(?:se)?tiap\s+hari\s+kerja(?=\s)"#) { _ in recur = "weekdays"; return true }
        take(#"\s(?:se)?tiap\s+hari\s+minggu(?=\s)"#) { _ in recur = "weekly:0"; return true }
        take(#"\s(?:se)?tiap\s+(?:hari\s+)?(senin|selasa|rabu|kamis|jum'?at|sabtu)(?=\s)"#) { m in
            if let d = dows.firstIndex(of: (m[1] ?? "").lowercased().replacingOccurrences(of: "'", with: "")) { recur = "weekly:\(d)" }
            return true
        }
        take(#"\s(?:se)?tiap\s+(?:tgl|tanggal)\.?\s*(\d{1,2})(?=\s)"#) { m in
            if let d = Int(m[1] ?? ""), (1...31).contains(d) { recur = "monthly:\(d)" }
            return true
        }
        take(#"\s(?:se)?tiap\s+minggu(?=\s)"#) { _ in recur = "weekly:?"; return true }
        take(#"\s(?:se)?tiap\s+bulan(?=\s)"#) { _ in recur = "monthly:?"; return true }
        take(#"\s(?:se)?tiap\s+hari(?=\s)"#) { _ in recur = "daily"; return true }
        // ---- English (selalu dikenali, apa pun bahasa app) ----
        let enDays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        func ampm(_ h: String?, _ m: String?, _ ap: String?) -> String? {
            guard var hh = Int(h ?? ""), (1...12).contains(hh) || ap == nil else { return nil }
            let p = (ap ?? "").lowercased()
            if p == "pm" && hh < 12 { hh += 12 }
            if p == "am" && hh == 12 { hh = 0 }
            return hm(String(hh), m)
        }
        take(#"\severy\s+weekday(?=\s)"#) { _ in recur = "weekdays"; return true }
        take(#"\severy\s+(sunday|monday|tuesday|wednesday|thursday|friday|saturday)(?=\s)"#) { m in
            if let d = enDays.firstIndex(of: (m[1] ?? "").lowercased()) { recur = "weekly:\(d)" }
            return true
        }
        take(#"\severy\s+month\s+on\s+the\s+(\d{1,2})(?:st|nd|rd|th)?(?=\s)|\severy\s+(\d{1,2})(?:st|nd|rd|th)(?=\s)"#) { m in
            if let d = Int(m[1] ?? m[2] ?? ""), (1...31).contains(d) { recur = "monthly:\(d)" }
            return true
        }
        take(#"\severy\s+week(?=\s)"#) { _ in recur = "weekly:?"; return true }
        take(#"\severy\s+month(?=\s)"#) { _ in recur = "monthly:?"; return true }
        take(#"\severy\s+day(?=\s)"#) { _ in recur = "daily"; return true }
        take(#"\stonight(?=\s)"#) { _ in
            if due == nil { due = today }
            if dueTime == nil { dueTime = "19:00" }
            return true
        }
        take(#"\s(?:the\s+)?day\s+after\s+tomorrow(?=\s)"#) { _ in if due == nil { due = DueDate.inDays(2) }; return true }
        take(#"\stoday(?=\s)"#) { _ in if due == nil { due = today }; return true }
        take(#"\s(?:tomorrow|tmrw?)(?=\s)"#) { _ in if due == nil { due = DueDate.inDays(1) }; return true }
        take(#"\snext\s+week(?=\s)"#) { _ in if due == nil { due = DueDate.nextWeek() }; return true }
        take(#"\s(?:by\s+)?(?:the\s+)?end\s+of\s+(?:the\s+)?month(?=\s)"#) { _ in if due == nil { due = addMonths(0, day: 31) }; return true }
        take(#"\s(?:start\s+of\s+|beginning\s+of\s+)?next\s+month(?=\s)"#) { _ in if due == nil { due = addMonths(1, day: 1) }; return true }
        take(#"\s(?:by\s+)?(?:the\s+)?end\s+of\s+(?:the\s+)?week(?=\s)"#) { _ in
            if due == nil {
                let todayDow = Self.cal.component(.weekday, from: now) - 1
                due = DueDate.inDays((5 - todayDow + 7) % 7)
            }
            return true
        }
        take(#"\sin\s+(?:(\d{1,3})|an?)\s+(days?|weeks?|months?)(?=\s)"#) { m in
            guard due == nil else { return true }
            let n = Int(m[1] ?? "") ?? 1
            let unit = (m[2] ?? "").lowercased()
            if unit.hasPrefix("day") { due = DueDate.inDays(n) }
            else if unit.hasPrefix("week") { due = DueDate.inDays(7 * n) }
            else { due = addMonths(n, day: Self.cal.component(.day, from: now)) }
            return true
        }
        take(#"\s(?:on\s+)?(next\s+)?(sunday|monday|tuesday|wednesday|thursday|friday|saturday)(?=\s)"#) { m in
            guard due == nil, let dow = enDays.firstIndex(of: (m[2] ?? "").lowercased()) else { return true }
            let todayDow = Self.cal.component(.weekday, from: now) - 1
            var diff = (dow - todayDow + 7) % 7
            if diff == 0 && m[1] != nil { diff = 7 }
            due = DueDate.inDays(diff)
            return true
        }
        take(#"\s(?:on\s+)?the\s+(\d{1,2})(?:st|nd|rd|th)(?=\s)|\son\s+the\s+(\d{1,2})(?=\s)|\son\s+(\d{1,2})(?:st|nd|rd|th)(?=\s)"#) { m in
            guard due == nil, let d = Int(m[1] ?? m[2] ?? m[3] ?? "") else { return true }
            var r = dayIn(year, month0, d)
            if let x = r, x < today { r = dayIn(year, month0 + 1, d) }
            due = r
            return true
        }
        take(#"\s(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s?(am|pm)(?=\s)"#) { m in
            if let t = ampm(m[1], m[2], m[3]) { dueTime = t }
            return true
        }
        take(#"\sat\s+(\d{1,2})(?::(\d{2}))?(?=\s)"#) { m in
            // "at 3" tanpa am/pm: jam kerja, jadi 1–6 dianggap siang/sore
            var h = Int(m[1] ?? "") ?? 0
            if (1...6).contains(h) && m[2] == nil { h += 12 }
            if let t = hm(String(h), m[2]) { dueTime = t }
            return true
        }
        take(#"\s(?:at\s+)?noon(?=\s)"#) { _ in
            if dueTime == nil { dueTime = "12:00" }
            if due == nil { due = today }
            return true
        }
        // ---- bahasa Indonesia ----
        take(#"\s(?:hari ini|hr ini)(?=\s)"#) { _ in if due == nil { due = today }; return true }
        take(#"\s(?:besok|bsk)(?=\s)"#) { _ in if due == nil { due = DueDate.inDays(1) }; return true }
        take(#"\slusa(?=\s)"#) { _ in if due == nil { due = DueDate.inDays(2) }; return true }
        take(#"\sminggu depan(?=\s)"#) { _ in if due == nil { due = DueDate.nextWeek() }; return true }
        take(#"\sakhir bulan(?=\s)"#) { _ in if due == nil { due = addMonths(0, day: 31) }; return true }
        take(#"\sawal bulan(?: depan)?(?=\s)"#) { _ in if due == nil { due = addMonths(1, day: 1) }; return true }
        take(#"\sakhir (?:minggu|pekan)(?=\s)"#) { _ in
            if due == nil {
                let todayDow = Self.cal.component(.weekday, from: now) - 1
                due = DueDate.inDays((5 - todayDow + 7) % 7)
            }
            return true
        }
        take(#"\s(?:(\d{1,3})\s+|se)(hari|minggu|bulan)\s+lagi(?=\s)"#) { m in
            guard due == nil else { return true }
            let n = Int(m[1] ?? "") ?? 1
            switch (m[2] ?? "").lowercased() {
            case "hari": due = DueDate.inDays(n)
            case "minggu": due = DueDate.inDays(7 * n)
            default: due = addMonths(n, day: Self.cal.component(.day, from: now))
            }
            return true
        }
        // "minggu" saja sering berarti pekan ("minggu ini"), jadi hari Minggu harus ditulis "hari minggu".
        take(#"\s(?:hari\s+)?(senin|selasa|rabu|kamis|jum'?at|sabtu)(\s+depan)?(?=\s)|\shari\s+(minggu)(\s+depan)?(?=\s)"#) { m in
            guard due == nil, let name = (m[1] ?? m[3])?.lowercased().replacingOccurrences(of: "'", with: "") else { return true }
            let names = ["minggu", "senin", "selasa", "rabu", "kamis", "jumat", "sabtu"]
            guard let dow = names.firstIndex(of: name) else { return true }
            let todayDow = Self.cal.component(.weekday, from: now) - 1
            var diff = (dow - todayDow + 7) % 7
            if diff == 0 && (m[2] ?? m[4]) != nil { diff = 7 }
            due = DueDate.inDays(diff)
            return true
        }
        take(#"\s(?:tgl|tanggal)\.?\s*(\d{1,2})(?=\s)"#) { m in
            guard due == nil, let d = Int(m[1] ?? "") else { return true }
            var r = dayIn(year, month0, d)
            if let x = r, x < today { r = dayIn(year, month0 + 1, d) }
            due = r
            return true
        }
        take(#"\s(\d{1,2})/(\d{1,2})(?=\s)"#) { m in
            guard due == nil, let d = Int(m[1] ?? ""), let mo = Int(m[2] ?? ""), mo >= 1, mo <= 12 else { return true }
            var r = dayIn(year, mo - 1, d)
            if let x = r, x < today { r = dayIn(year + 1, mo - 1, d) }
            due = r
            return true
        }
        // 10:00 selalu jam; 10.00 hanya kalau menitnya 00/15/30/45 (supaya "versi 2.10" tidak terbaca jam)
        take(#"\s(\d{1,2}):(\d{2})(?=\s)|\s(\d{1,2})\.(00|15|30|45)(?=\s)"#) { m in
            if dueTime == nil { dueTime = hm(m[1] ?? m[3], m[2] ?? m[4]) }
            return true
        }
        // pagi/siang/sore/malam hanya dibaca bersama tanggal ("besok sore") atau "nanti" ("nanti sore"),
        // supaya "beli makan siang" tidak tiba-tiba punya jam.
        take(#"\s(nanti\s+)?(pagi|siang|sore|malam)(?=\s)"#) { m in
            if m[1] == nil && due == nil { return false }
            if dueTime == nil {
                dueTime = ["pagi": "09:00", "siang": "12:00", "sore": "15:00", "malam": "19:00"][(m[2] ?? "").lowercased()]
            }
            if due == nil { due = today }
            return true
        }
        let cleaned = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        title = cleaned.isEmpty ? raw.trimmingCharacters(in: .whitespaces) : cleaned
        // "tomorrow morning", "this afternoon" (tanpa tanggal/this dibiarkan: "morning coffee")
        take(#"\s(this\s+)?(morning|afternoon|evening)(?=\s)"#) { m in
            if m[1] == nil && due == nil { return false }
            if dueTime == nil {
                dueTime = ["morning": "09:00", "afternoon": "15:00", "evening": "19:00"][(m[2] ?? "").lowercased()]
            }
            if due == nil { due = today }
            return true
        }
        let base = DueDate.date(due ?? today) ?? now
        if recur == "weekly:?" { recur = "weekly:\(Self.cal.component(.weekday, from: base) - 1)" }
        if recur == "monthly:?" { recur = "monthly:\(Self.cal.component(.day, from: base))" }
        if let r = recur, due == nil { due = Recur.next(r, after: today, inclusive: true) }
        if dueTime != nil && due == nil { due = today }
    }

    /// Ringkasan untuk ditampilkan di bawah kolom tambah to-do.
    var hint: String {
        var bits: [String] = []
        if let due {
            var t = Item(id: "", kind: "task", updatedAt: 0)
            t.due = due
            t.dueTime = dueTime
            bits.append("📅 " + DueDate.label(t))
        }
        if let recur { bits.append("🔁 " + Recur.label(recur)) }
        if important { bits.append(L("★ Penting")) }
        bits.append(contentsOf: tags.map { "#" + $0 })
        return bits.joined(separator: " · ")
    }
}

/// Aturan to-do berulang (sama dengan web app): daily | weekdays | weekly:<0-6, 0 = Minggu> | monthly:<1-31>
enum Recur {
    private static let cal = Calendar(identifier: .gregorian)
    /// Nama hari sesuai bahasa app, 0 = Minggu.
    static var dayNames: [String] {
        var c = Calendar(identifier: .gregorian)
        c.locale = AppLang.locale
        return c.weekdaySymbols.map { $0.prefix(1).uppercased() + String($0.dropFirst()) }
    }

    /// Pilihan di detail to-do, disesuaikan dengan tanggal tenggatnya.
    static func options(for task: Item) -> [String] {
        let base = DueDate.date(task.due ?? DueDate.today()) ?? Date()
        let dow = cal.component(.weekday, from: base) - 1
        let day = cal.component(.day, from: base)
        var out = ["", "daily", "weekdays", "weekly:\(dow)", "monthly:\(day)"]
        if let r = task.recur, !out.contains(r) { out.append(r) }
        return out
    }

    static func label(_ r: String) -> String {
        if r == "daily" { return L("Tiap hari") }
        if r == "weekdays" { return L("Tiap hari kerja") }
        let p = r.split(separator: ":")
        guard p.count == 2, let v = Int(p[1]) else { return "" }
        if p[0] == "weekly", (0...6).contains(v) { return L("Tiap %@", dayNames[v]) }
        if p[0] == "monthly" { return L("Tiap tgl %lld", v) }
        return ""
    }

    static func matches(_ r: String, _ d: Date) -> Bool {
        let dow = cal.component(.weekday, from: d) - 1
        if r == "daily" { return true }
        if r == "weekdays" { return (1...5).contains(dow) }
        let p = r.split(separator: ":")
        guard p.count == 2, let v = Int(p[1]) else { return false }
        if p[0] == "weekly" { return dow == v }
        if p[0] == "monthly" {
            let last = cal.range(of: .day, in: .month, for: d)?.count ?? 28
            return cal.component(.day, from: d) == min(v, last)
        }
        return false
    }

    /// Tanggal berikutnya yang cocok setelah `from` (atau mulai `from` kalau inclusive).
    static func next(_ r: String, after from: String, inclusive: Bool = false) -> String? {
        guard var d = DueDate.date(from) else { return nil }
        if !inclusive { d = cal.date(byAdding: .day, value: 1, to: d) ?? d }
        for _ in 0..<400 {
            if matches(r, d) { return DueDate.string(d) }
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        }
        return nil
    }
}
