import Foundation
import SwiftUI

// MARK: - Tata letak yang turun ke baris berikutnya

/// Menyusun anak-anaknya ke samping, lalu turun ke baris baru kalau sudah penuh.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxW {
                y += lineH + lineSpacing
                x = 0
                lineH = 0
            }
            x += size.width + spacing
            lineH = max(lineH, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += lineH + lineSpacing
                x = bounds.minX
                lineH = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineH = max(lineH, size.height)
        }
    }
}

// MARK: - Aturan tag

/// Tag = label tambahan. Bisa diketik sebagai #nama di judul / isi, atau ditambahkan lewat tombol Tag.
/// Disimpan kecil semua, tanpa spasi: "klien-a", "rapat".
enum TagText {
    private static let hashtag = try! NSRegularExpression(pattern: #"(?:^|\s)#([\p{L}\p{N}_\-]{1,40})"#)

    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while s.hasPrefix("#") { s.removeFirst() }
        s = s.replacingOccurrences(of: #"\s+"#, with: "-", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[^\p{L}\p{N}_\-]"#, with: "", options: .regularExpression)
        return String(s.prefix(40))
    }

    /// Semua #tag yang diketik di teks.
    static func hashtags(_ text: String) -> [String] {
        let ns = text as NSString
        var out: [String] = []
        for m in hashtag.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let t = ns.substring(with: m.range(at: 1)).lowercased()
            if !out.contains(t) { out.append(t) }
        }
        return out
    }

    /// Ganti "#lama" di teks (tanpa membedakan huruf besar kecil). replacement nil = buang tanda #.
    static func replace(_ tag: String, in text: String, with replacement: String?) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: tag)
        let pattern = #"(^|\s)#"# + escaped + #"(?![\p{L}\p{N}_\-])"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        let template = "$1" + (replacement.map { "#" + NSRegularExpression.escapedTemplate(for: $0) } ?? NSRegularExpression.escapedTemplate(for: tag))
        return re.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: template)
    }
}

struct TagCount: Hashable {
    var tag: String
    var count: Int
}

extension Item {
    /// Tag yang ditambahkan lewat tombol + #tag yang diketik di judul / isi.
    var tagList: [String] {
        var out = tags ?? []
        let p = parts
        for h in TagText.hashtags(p.title + "\n" + p.body) where !out.contains(h) { out.append(h) }
        return out
    }
}

extension NoteStore {
    func hasTag(_ item: Item, _ tag: String?) -> Bool {
        guard let tag else { return true }
        return item.tagList.contains(tag)
    }

    /// Item yang tampil di filter ini (untuk deretan tag).
    func itemsInScope(_ filter: Filter) -> [Item] {
        switch filter {
        case .trash: return []
        case .tasks: return openTasks()
        case .pinned: return notes(.pinned)
        case .daily: return notes(.daily)
        case .all: return notes(.all)
        case .folder(let id): return notes(.folder(id)) + openTasks(folder: id)
        }
    }

    /// Tag yang dipakai di filter ini, beserta jumlahnya. Yang paling sering dulu.
    func tagCounts(_ filter: Filter) -> [TagCount] {
        var counts: [String: Int] = [:]
        for it in itemsInScope(filter) { for t in it.tagList { counts[t, default: 0] += 1 } }
        return counts.map { TagCount(tag: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.tag < $1.tag }
    }

    /// Semua tag yang pernah dipakai (untuk saran).
    var allTags: [String] {
        var set = Set<String>()
        for it in items.values where !it.isDeleted && (it.isNote || it.isTask) { set.formUnion(it.tagList) }
        return set.sorted()
    }

    func addTag(_ id: String, _ raw: String) {
        let tag = TagText.normalize(raw)
        guard !tag.isEmpty, var it = items[id], !it.tagList.contains(tag) else { return }
        it.tags = (it.tags ?? []) + [tag]
        commit(it)
    }

    /// Lepas tag dari satu item, termasuk #tag yang diketik di teksnya.
    func removeTag(_ id: String, _ tag: String) {
        guard var it = items[id] else { return }
        it.tags = (it.tags ?? []).filter { $0 != tag }
        if it.tags?.isEmpty == true { it.tags = nil }
        rewriteText(&it) { TagText.replace(tag, in: $0, with: nil) }
        commit(it)
    }

    /// Ganti nama tag di semua catatan dan tugas.
    func renameTag(_ old: String, to raw: String) {
        let new = TagText.normalize(raw)
        guard !new.isEmpty, new != old else { return }
        for var it in items.values where !it.isDeleted && it.tagList.contains(old) {
            var list = (it.tags ?? []).map { $0 == old ? new : $0 }
            var seen = Set<String>()
            list = list.filter { seen.insert($0).inserted }
            it.tags = list.isEmpty ? nil : list
            rewriteText(&it) { TagText.replace(old, in: $0, with: new) }
            commit(it)
        }
    }

    /// Hapus tag dari semua catatan dan tugas (catatannya sendiri tetap ada).
    func deleteTag(_ tag: String) {
        for it in items.values where !it.isDeleted && it.tagList.contains(tag) { removeTag(it.id, tag) }
    }

    private func rewriteText(_ it: inout Item, _ f: (String) -> String) {
        if it.isNote && it.title == nil {
            let p = it.parts
            it.title = p.title
            it.text = p.body
        }
        if let t = it.title { it.title = f(t) }
        if let x = it.text { it.text = f(x) }
    }
}

// MARK: - Tampilan

/// Chip tag abu-abu.
struct TagChip: View {
    let tag: String
    var count: Int? = nil
    var selected = false
    var onRemove: (() -> Void)? = nil
    var action: (() -> Void)? = nil
    @State private var hover = false

    var body: some View {
        HStack(spacing: 3) {
            Text("#" + tag).lineLimit(1)
            if let count { Text("\(count)").foregroundStyle(.secondary).monospacedDigit() }
            if let onRemove {
                Button(action: onRemove) { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Lepas tag")
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(selected ? Color.primary : Color.secondary)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(Color.primary.opacity(selected ? 0.16 : (hover ? 0.09 : 0.06))))
        .contentShape(Capsule())
        .onTapGesture { action?() }
        .onHover { hover = $0 }
    }
}

/// Semua tag dilipat jadi satu chip: "# Tag ▾", atau "#sp2kp ✕" saat sedang menyaring.
struct TagToggleChip: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var ui: PanelUI
    @State private var hover = false

    var body: some View {
        let n = store.tagCounts(ui.filter).count
        if n > 0 || ui.tag != nil {
            HStack(spacing: 4) {
                if let t = ui.tag {
                    Text("#" + t).lineLimit(1)
                    Button { ui.tag = nil } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Berhenti menyaring tag")
                } else {
                    Text("# Tag").lineLimit(1)
                    Image(systemName: ui.showTags ? "chevron.up" : "chevron.down").font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(ui.tag != nil ? Color.primary : Color.secondary)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(Color.primary.opacity(ui.tag != nil || ui.showTags ? 0.12 : (hover ? 0.06 : 0))))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(ui.tag != nil || ui.showTags ? 0 : 0.12), lineWidth: 1))
            .contentShape(Capsule())
            .onTapGesture { ui.showTags.toggle() }
            .onHover { hover = $0 }
            .help(ui.showTags ? "Sembunyikan tag" : "Tampilkan \(n) tag")
        }
    }
}

/// Deretan tag di bawah deretan folder. Klik untuk menyaring, klik kanan untuk ganti nama / hapus.
struct TagStrip: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var ui: PanelUI
    @State private var expanded = false
    @State private var renaming: String?
    @State private var editName = ""
    @FocusState private var renameFocused: Bool
    private let limit = 10

    var body: some View {
        let counts = store.tagCounts(ui.filter)
        if !counts.isEmpty || ui.tag != nil {
            let shown = visible(counts)
            FlowLayout(spacing: 5, lineSpacing: 5) {
                ForEach(shown, id: \.tag) { c in
                    if renaming == c.tag {
                        TextField("Nama tag", text: $editName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 100)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Capsule().strokeBorder(Color.accentColor, lineWidth: 1))
                            .focused($renameFocused)
                            .onSubmit { finishRename(c.tag) }
                            .onExitCommand { renaming = nil }
                            .onAppear { editName = c.tag; renameFocused = true }
                    } else {
                        TagChip(tag: c.tag, count: c.count, selected: ui.tag == c.tag, action: {
                            ui.tag = ui.tag == c.tag ? nil : c.tag
                            ui.openID = nil
                            ui.openTaskID = nil
                            if ui.tag != nil { ui.showTags = false }
                        })
                        .contextMenu {
                            Button("Ganti nama tag") { renaming = c.tag }
                            Divider()
                            Button("Hapus tag dari semua item", role: .destructive) {
                                if ui.tag == c.tag { ui.tag = nil }
                                store.deleteTag(c.tag)
                            }
                        }
                    }
                }
                if let t = ui.tag, !counts.contains(where: { $0.tag == t }) {
                    TagChip(tag: t, count: 0, selected: true, action: { ui.tag = nil })
                }
                if counts.count > limit {
                    Button(expanded ? "Ringkas" : "+\(counts.count - shown.count) lainnya") { expanded.toggle() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.vertical, 3)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    private func visible(_ counts: [TagCount]) -> [TagCount] {
        guard !expanded, counts.count > limit else { return counts }
        var out = Array(counts.prefix(limit))
        if let t = ui.tag, !out.contains(where: { $0.tag == t }), let sel = counts.first(where: { $0.tag == t }) { out.append(sel) }
        return out
    }

    private func finishRename(_ old: String) {
        let name = editName
        renaming = nil
        store.renameTag(old, to: name)
        if ui.tag == old { ui.tag = TagText.normalize(name).isEmpty ? old : TagText.normalize(name) }
    }
}

/// Tag milik satu catatan / tugas: chip + tombol tambah dengan saran.
struct TagEditor: View {
    @ObservedObject var store: NoteStore
    let item: Item
    @State private var adding = false
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let mine = item.tagList
        let typed = Set(TagText.hashtags(item.parts.title + "\n" + item.parts.body))
        VStack(alignment: .leading, spacing: 5) {
            FlowLayout(spacing: 5, lineSpacing: 5) {
                ForEach(mine, id: \.self) { t in
                    TagChip(tag: t, onRemove: { store.removeTag(item.id, t) })
                        .help(typed.contains(t) ? "Diketik sebagai #\(t) di catatan" : "")
                }
                if adding {
                    TextField("tag", text: $text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 90)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().strokeBorder(Color.accentColor, lineWidth: 1))
                        .focused($focused)
                        .onSubmit { add(text) }
                        .onExitCommand { adding = false; text = "" }
                        .onAppear { focused = true }
                } else {
                    Button {
                        adding = true
                    } label: {
                        Text(mine.isEmpty ? "# Tambah tag" : "#")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Capsule().strokeBorder(Color.primary.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Tambah tag. Bisa juga mengetik #nama di catatan.")
                }
            }
            if adding {
                let q = TagText.normalize(text)
                let suggestions = store.allTags.filter { !mine.contains($0) && (q.isEmpty || $0.hasPrefix(q)) }.prefix(6)
                if !suggestions.isEmpty {
                    FlowLayout(spacing: 5, lineSpacing: 5) {
                        ForEach(Array(suggestions), id: \.self) { s in
                            TagChip(tag: s, action: { add(s) })
                        }
                    }
                }
            }
        }
    }

    private func add(_ raw: String) {
        store.addTag(item.id, raw)
        text = ""
        focused = true
    }
}

/// "#a #b" kecil untuk kartu di daftar.
struct TagLine: View {
    let tags: [String]
    var body: some View {
        if !tags.isEmpty {
            Text(tags.prefix(3).map { "#" + $0 }.joined(separator: " ") + (tags.count > 3 ? " +\(tags.count - 3)" : ""))
                .lineLimit(1)
        }
    }
}
