import AppKit
import SwiftUI

/// Ringkasan kegiatan (laporan bulanan).
struct SummaryOptions: Equatable {
    var from: String
    var to: String
    var group = "date"      // "date" = per jenis, "tag" = per tag / proyek
    var tag = ""
    var agenda = true
    var done = true
    var open = true

    static func month(_ ym: String) -> SummaryOptions {
        SummaryOptions(from: ym + "-01", to: Summary.monthEnd(ym))
    }
}

enum Summary {
    private static let cal = Calendar(identifier: .gregorian)
    private static let shortFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "id_ID")
        f.dateFormat = "d MMM"
        return f
    }()

    static func monthEnd(_ ym: String) -> String {
        guard let first = DueDate.date(ym + "-01"),
              let next = cal.date(byAdding: .month, value: 1, to: first),
              let last = cal.date(byAdding: .day, value: -1, to: next) else { return ym + "-28" }
        return DueDate.string(last)
    }

    static func short(_ ds: String) -> String { DueDate.date(ds).map { shortFmt.string(from: $0) } ?? ds }

    /// Butir checklist / poin jadi teks bersih ("✓ …", "○ …").
    private static func clean(_ line: String) -> String {
        let ns = line as NSString
        if let m = NoteText.checkPattern.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
            let t = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? "" : (ns.substring(with: m.range(at: 1)) == " " ? "○ " : "✓ ") + t
        }
        return line.replacingOccurrences(of: #"^\s*([-*]\s+|\d+[.)]\s+)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Isi agenda: bagian Kesimpulan & Tindak lanjut kalau ada, kalau tidak seluruh isinya.
    static func gist(_ n: Item) -> [String] {
        if n.isLocked { return ["- 🔒 (catatan terkunci)"] }
        let lines = NoteText.lines(Vault.replaceTokens(n.parts.body, with: "🔒••••"))
        var sections: [String: [String]] = [:]
        var cur = ""
        for l in lines {
            if let r = l.range(of: #"^#{1,3}\s+"#, options: .regularExpression) {
                cur = String(l[r.upperBound...]).trimmingCharacters(in: .whitespaces).lowercased()
                sections[cur, default: []] += []
                continue
            }
            sections[cur, default: []].append(l)
        }
        let pick = ["kesimpulan", "tindak lanjut"].filter { k in (sections[k] ?? []).contains { !clean($0).isEmpty } }
        if !pick.isEmpty {
            var out: [String] = []
            for k in pick {
                let cap = k.prefix(1).uppercased() + String(k.dropFirst())
                out.append("**\(cap)**")
                out += (sections[k] ?? []).map(clean).filter { !$0.isEmpty }.map { "- " + $0 }
            }
            return out
        }
        return lines.compactMap { l in
            if let r = l.range(of: #"^#{1,3}\s+"#, options: .regularExpression) {
                return "**" + l[r.upperBound...].trimmingCharacters(in: .whitespaces) + "**"
            }
            let c = clean(l)
            return c.isEmpty ? nil : "- " + c
        }
    }

    static func build(_ store: NoteStore, _ o: SummaryOptions) -> (title: String, body: String) {
        let fromT = (DueDate.date(o.from) ?? Date()).timeIntervalSince1970 * 1000
        let toT = (DueDate.date(o.to) ?? Date()).timeIntervalSince1970 * 1000 + 86_400_000 - 1
        func tagOK(_ x: Item) -> Bool { o.tag.isEmpty || x.tagList.contains(o.tag) }
        func tags(_ x: Item) -> String { x.tagList.isEmpty ? "" : "  " + x.tagList.map { "#" + $0 }.joined(separator: " ") }

        let agenda = o.agenda ? store.notes(.daily).filter { n in
            guard let d = n.dailyDate else { return false }
            return d >= o.from && d <= o.to && tagOK(n)
        }.sorted { a, b in
            let da = a.dailyDate ?? "", db = b.dailyDate ?? ""
            return da != db ? da < db : (a.createdAt ?? 0) < (b.createdAt ?? 0)
        } : []
        let done = o.done ? store.tasks.filter { t in
            guard let d = t.doneAt else { return false }
            return d >= fromT && d <= toT && tagOK(t)
        }.sorted { ($0.doneAt ?? 0) < ($1.doneAt ?? 0) } : []
        let open = o.open ? store.tasks.filter { t in t.doneAt == nil && (t.createdAt ?? 0) <= toT && tagOK(t) }
            .sorted(by: NoteStore.taskOrder) : []

        let whole = o.from.hasSuffix("-01") && o.to == monthEnd(String(o.from.prefix(7)))
        let label = whole ? DailyText.monthLabel(String(o.from.prefix(7))) : "\(short(o.from)) – \(short(o.to)) \(o.to.prefix(4))"

        func agendaLines(_ n: Item) -> [String] {
            ["### \(DailyText.shortLabel(n.dailyDate ?? "")) — \(n.displayTitle)\(tags(n))"] + gist(n) + [""]
        }
        func doneLine(_ t: Item) -> String {
            let d = DueDate.string(Date(timeIntervalSince1970: (t.doneAt ?? 0) / 1000))
            return "- ✓ \(short(d)) — \(t.displayTitle)\(tags(t))"
        }
        func openLine(_ t: Item) -> String {
            var late = ""
            if DueDate.isOverdue(t), let d = DueDate.daysFromToday(t.due) { late = " — ⚠ terlambat \(-d) hari" }
            else if let due = t.due { late = " — tenggat \(short(due))" }
            return "- ○ \(t.displayTitle)\(late)\(tags(t))"
        }

        var out: [String] = []
        if o.group == "tag" {
            struct Bucket { var agenda: [Item] = []; var done: [Item] = []; var open: [Item] = [] }
            var buckets: [String: Bucket] = [:]
            func add(_ x: Item, _ kind: Int) {
                let ts = x.tagList.filter { o.tag.isEmpty || $0 == o.tag }
                for k in (x.tagList.isEmpty ? [""] : ts) {
                    var b = buckets[k] ?? Bucket()
                    if kind == 0 { b.agenda.append(x) } else if kind == 1 { b.done.append(x) } else { b.open.append(x) }
                    buckets[k] = b
                }
            }
            agenda.forEach { add($0, 0) }
            done.forEach { add($0, 1) }
            open.forEach { add($0, 2) }
            let keys = buckets.keys.sorted { a, b in
                if a.isEmpty != b.isEmpty { return !a.isEmpty }
                let ca = buckets[a].map { $0.agenda.count + $0.done.count + $0.open.count } ?? 0
                let cb = buckets[b].map { $0.agenda.count + $0.done.count + $0.open.count } ?? 0
                return ca != cb ? ca > cb : a < b
            }
            for k in keys {
                guard let b = buckets[k] else { continue }
                out += ["## " + (k.isEmpty ? "Tanpa tag" : "#" + k), ""]
                for n in b.agenda { out += agendaLines(n) }
                if !b.done.isEmpty { out += ["**Selesai (\(b.done.count))**"] + b.done.map(doneLine) + [""] }
                if !b.open.isEmpty { out += ["**Masih berjalan (\(b.open.count))**"] + b.open.map(openLine) + [""] }
            }
        } else {
            if o.agenda { out += ["## Agenda (\(agenda.count))", ""] + (agenda.isEmpty ? ["- Tidak ada agenda", ""] : agenda.flatMap(agendaLines)) }
            if o.done { out += ["## Selesai (\(done.count))"] + (done.isEmpty ? ["- Belum ada"] : done.map(doneLine)) + [""] }
            if o.open { out += ["## Masih berjalan (\(open.count))"] + (open.isEmpty ? ["- Tidak ada"] : open.map(openLine)) + [""] }
        }
        let body = out.joined(separator: "\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ("Ringkasan Kegiatan — \(label)" + (o.tag.isEmpty ? "" : " · #\(o.tag)"), body)
    }

    /// Untuk dibawa keluar notecu: [[Judul]] jadi teks biasa.
    static func plainLinks(_ s: String) -> String {
        s.replacingOccurrences(of: #"\[\[([^\[\]\n]+?)\]\]"#, with: "$1", options: .regularExpression)
    }
}

/// Panel Ringkasan: pilih periode & susunan, lihat hasilnya, salin atau simpan jadi catatan.
struct SummaryView: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var ui: PanelUI
    var fontStyle = "sans"
    @State private var month = String(DueDate.today().prefix(7))
    @State private var opts = SummaryOptions.month(String(DueDate.today().prefix(7)))

    private var months: [String] {
        var out: [String] = []
        var d = Calendar(identifier: .gregorian).date(from: Calendar(identifier: .gregorian).dateComponents([.year, .month], from: Date())) ?? Date()
        for _ in 0..<12 {
            out.append(String(DueDate.string(d).prefix(7)))
            d = Calendar(identifier: .gregorian).date(byAdding: .month, value: -1, to: d) ?? d
        }
        return out
    }

    var body: some View {
        let result = Summary.build(store, opts)
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                IconButton(symbol: "chevron.left", help: "Kembali") { ui.showSummary = false }
                Text("Ringkasan").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Salin") {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(Summary.plainLinks("# \(result.title)\n\n\(result.body)\n"), forType: .string)
                    store.noteNotice("Ringkasan disalin (Markdown)")
                }
                Button("Simpan jadi catatan") {
                    let id = store.createNote(folder: nil, pinned: false)
                    store.setTitle(id, result.title.replacingOccurrences(of: "Ringkasan Kegiatan — ", with: "Ringkasan "))
                    store.setBody(id, result.body)
                    ui.showSummary = false
                    ui.filter = .all
                    ui.readMode = true
                    ui.openID = id
                }
            }
            .controlSize(.small)
            .padding(.horizontal, 8).padding(.vertical, 6)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Picker("Periode", selection: $month) {
                        ForEach(months, id: \.self) { m in Text(DailyText.monthLabel(m)).tag(m) }
                    }
                    .onChange(of: month) { _, m in opts.from = m + "-01"; opts.to = Summary.monthEnd(m) }
                    Picker("Tag", selection: $opts.tag) {
                        Text("Semua").tag("")
                        ForEach(store.allTags, id: \.self) { t in Text("#" + t).tag(t) }
                    }
                }
                Picker("Susun per", selection: $opts.group) {
                    Text("Jenis").tag("date")
                    Text("Tag / proyek").tag("tag")
                }
                .pickerStyle(.segmented)
                HStack(spacing: 12) {
                    Toggle("Agenda", isOn: $opts.agenda)
                    Toggle("Selesai", isOn: $opts.done)
                    Toggle("Berjalan", isOn: $opts.open)
                }
                .toggleStyle(.checkbox)
            }
            .font(.system(size: 11.5))
            .controlSize(.small)
            .padding(.horizontal, 12).padding(.bottom, 8)

            Divider().opacity(0.5)

            ReadView(store: store, note: preview(result), editable: false, fontStyle: fontStyle, onOpenLink: { t in
                ui.showSummary = false
                ui.readMode = true
                ui.openID = store.noteForLink(t)
            })

            Text("Bagian 🔒 tidak ikut. Agenda yang punya Kesimpulan / Tindak lanjut diringkas ke bagian itu saja.")
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func preview(_ r: (title: String, body: String)) -> Item {
        var it = Item(id: "summary-preview", kind: "note", updatedAt: 0)
        it.title = r.title
        it.text = r.body
        return it
    }
}
