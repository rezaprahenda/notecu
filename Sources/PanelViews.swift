import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Keadaan tampilan panel (bukan data catatan).
final class PanelUI: ObservableObject {
    @Published var filter: Filter = .all
    @Published var query = ""
    @Published var openID: String?
    @Published var openTaskID: String?
    /// Tag yang sedang dipakai untuk menyaring
    @Published var tag: String?
    /// Bulan yang dibuka di Harian, "yyyy-MM" (nil = semua bulan)
    @Published var dailyMonth: String?
    /// Deretan tag dibuka (normalnya dilipat jadi satu chip "# Tag").
    @Published var showTags = false
    /// Folder yang disaring di tab To-do (nil = semua)
    @Published var taskFolder: String?
    /// Panel Ringkasan (laporan bulanan) sedang dibuka.
    @Published var showSummary = false
    /// Filter catatan terakhir, untuk kembali dari tab To-do
    var lastNoteFilter: Filter = .all
    @Published var focusTaskForm = 0
    var focusTaskFormOnAppear = false
    @Published var readMode = false
    /// Panel tidak tertutup otomatis saat klik di luar.
    @Published var keepOpen = false
    @Published var addingFolder = false
    @Published var renamingFolder: String?
    @Published var focusSearch = 0
    @Published var focusEditor = 0
    @Published var checklist = 0
    /// Naikkan untuk merahasiakan teks yang sedang diblok di editor (⌘L).
    @Published var secret = 0
    /// Naikkan untuk membuka kolom "Tambah to-do" di bawah catatan.
    @Published var linkedAdd = 0
    /// Fokuskan kolom judul begitu editor muncul (catatan baru).
    @Published var wantsTitleFocus = false

    var openSettings: () -> Void = {}
    var hidePanel: () -> Void = {}
    /// Jadikan panel aktif lagi (setelah jendela pilih file ditutup).
    var refocusPanel: () -> Void = {}
    /// Ubah lebar panel mengikuti posisi x kursor (layar).
    var resizePanel: (CGFloat) -> Void = { _ in }
    var relayoutPanel: () -> Void = {}
    /// Jangan tutup panel walau kehilangan fokus (misalnya saat memilih file).
    var holdOpen = false
}

// MARK: - Root

struct PanelRootView: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var prefs: Prefs
    @ObservedObject var ui: PanelUI
    @ObservedObject var vault = Vault.shared

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(store: store, prefs: prefs, ui: ui)
            if ui.showSummary {
                SummaryView(store: store, ui: ui, fontStyle: prefs.noteFont)
            } else {
            KindTabs(store: store, ui: ui)
            if ui.filter == .tasks {
                TaskFolderStrip(store: store, ui: ui)
            } else {
                FolderStrip(store: store, ui: ui)
            }
            if ui.showTags { TagStrip(store: store, ui: ui) }
            Divider().opacity(0.6)
            if let task = store.task(ui.openTaskID) {
                TaskDetailView(store: store, ui: ui, task: task)
            } else if let id = ui.openID, let note = store.note(id) {
                if note.isTrashed {
                    TrashedNoteView(store: store, ui: ui, note: note, fontStyle: prefs.noteFont)
                } else {
                    EditorView(store: store, ui: ui, note: note, fontStyle: prefs.noteFont)
                }
            } else if ui.filter == .tasks {
                VStack(spacing: 0) {
                    SearchField(ui: ui, placeholder: "Cari to-do")
                        .padding(.horizontal, 12).padding(.top, 10)
                    TaskListView(store: store, ui: ui)
                }
            } else {
                NoteListView(store: store, prefs: prefs, ui: ui)
            }
            if ui.openID == nil && ui.openTaskID == nil {
                BrandFooter()
            }
            }
        }
        .overlay {
            if vault.prompting { VaultPromptView() }
        }
        .background(VisualEffect().ignoresSafeArea())
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .overlay(alignment: prefs.edge == "left" ? .trailing : .leading) {
            ResizeHandle(ui: ui, onReset: { prefs.panelWidth = 360; ui.relayoutPanel() })
        }
        .onChange(of: ui.openID) { old, new in
            if let old { store.closeNote(old) }
            if let new { store.noteOpened(new) }
        }
    }
}

/// Logo notecu kecil: huruf n gelap dengan sudut terlipat di atas kuning (sama dengan ikon app).
/// Tepi dalam panel: tarik untuk mengubah lebar, klik dua kali untuk kembali ke 360.
struct ResizeHandle: View {
    @ObservedObject var ui: PanelUI
    let onReset: () -> Void
    @State private var hover = false
    @State private var dragging = false

    var body: some View {
        Rectangle()
            .fill(Color.accentColor.opacity(dragging ? 0.35 : hover ? 0.18 : 0))
            .frame(width: 5)
            .padding(.vertical, 18)
            .contentShape(Rectangle())
            .onHover { inside in
                hover = inside
                if inside { NSCursor.resizeLeftRight.push() } else if !dragging { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { _ in
                        dragging = true
                        ui.resizePanel(NSEvent.mouseLocation.x)
                    }
                    .onEnded { _ in
                        dragging = false
                        if !hover { NSCursor.pop() }
                    }
            )
            .onTapGesture(count: 2, perform: onReset)
            .help("Tarik untuk mengubah lebar · klik dua kali untuk ukuran awal")
    }
}

struct NotecuMark: View {
    var body: some View {
        GeometryReader { geo in
            let k = min(geo.size.width, geo.size.height) / 160
            ZStack {
                RoundedRectangle(cornerRadius: 36 * k, style: .continuous)
                    .fill(Color(red: 1.0, green: 0.79, blue: 0.24))
                Path { p in
                    p.move(to: CGPoint(x: 42 * k, y: 124 * k))
                    p.addLine(to: CGPoint(x: 42 * k, y: 68 * k))
                    p.addQuadCurve(to: CGPoint(x: 72 * k, y: 38 * k), control: CGPoint(x: 42 * k, y: 38 * k))
                    p.addLine(to: CGPoint(x: 96 * k, y: 38 * k))
                    p.addLine(to: CGPoint(x: 118 * k, y: 60 * k))
                    p.addLine(to: CGPoint(x: 118 * k, y: 124 * k))
                    p.addLine(to: CGPoint(x: 92 * k, y: 124 * k))
                    p.addLine(to: CGPoint(x: 92 * k, y: 72 * k))
                    p.addQuadCurve(to: CGPoint(x: 84 * k, y: 64 * k), control: CGPoint(x: 92 * k, y: 64 * k))
                    p.addLine(to: CGPoint(x: 76 * k, y: 64 * k))
                    p.addQuadCurve(to: CGPoint(x: 68 * k, y: 72 * k), control: CGPoint(x: 68 * k, y: 64 * k))
                    p.addLine(to: CGPoint(x: 68 * k, y: 124 * k))
                    p.closeSubpath()
                }
                .fill(Color(red: 0.17, green: 0.19, blue: 0.25))
                Path { p in
                    p.move(to: CGPoint(x: 96 * k, y: 38 * k))
                    p.addLine(to: CGPoint(x: 118 * k, y: 60 * k))
                    p.addLine(to: CGPoint(x: 101 * k, y: 60 * k))
                    p.addQuadCurve(to: CGPoint(x: 96 * k, y: 55 * k), control: CGPoint(x: 96 * k, y: 60 * k))
                    p.closeSubpath()
                }
                .fill(Color(red: 1.0, green: 0.97, blue: 0.93))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Footer kecil di bawah daftar: logo, nama, dan slogan.
struct BrandFooter: View {
    static let slogan = "note it, cu later."
    var body: some View {
        HStack(spacing: 5) {
            NotecuMark().frame(width: 12, height: 12)
            Text("notecu").font(.system(size: 11, weight: .bold, design: .rounded))
            Text("· " + Self.slogan).font(.system(size: 11))
        }
        .foregroundStyle(.secondary)
        .opacity(0.65)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Divider().opacity(0.4) }
    }
}

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .popover
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Header

struct HeaderBar: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var prefs: Prefs
    @ObservedObject var ui: PanelUI

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                NotecuMark().frame(width: 18, height: 18)
                Text("notecu")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .fixedSize()
            }
            SyncBadge(store: store)
            Spacer()
            // Jarang dipakai: Ringkasan & Sampah dikumpulkan di menu ⋯
            Menu {
                Button {
                    ui.showSummary = true
                    ui.openID = nil
                    ui.openTaskID = nil
                } label: { Label(L("Ringkasan / laporan bulanan"), systemImage: "chart.bar.doc.horizontal") }
                Button {
                    ui.showSummary = false
                    ui.filter = .trash
                    ui.openID = nil
                    ui.openTaskID = nil
                    ui.tag = nil
                    ui.dailyMonth = nil
                } label: { Label(L("Sampah · %lld", store.count(.trash)), systemImage: "trash") }
                Divider()
                Button { ui.hidePanel() } label: { Label(L("Tutup panel (Esc)"), systemImage: prefs.edge == "left" ? "sidebar.left" : "sidebar.right") }
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 13, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(.secondary)
            .help(L("Lainnya"))
            IconButton(symbol: ui.keepOpen ? "pin.fill" : "pin",
                       help: ui.keepOpen ? "Panel tetap terbuka (klik untuk mematikan)" : "Biarkan panel tetap terbuka",
                       active: ui.keepOpen) { ui.keepOpen.toggle() }
            IconButton(symbol: "gearshape", help: "Pengaturan") { ui.openSettings() }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }
}

struct SyncBadge: View {
    @ObservedObject var store: NoteStore

    private var color: Color {
        if store.notice != nil { return .orange }
        switch store.status {
        case .ok: return .green
        case .saving, .connecting: return .orange
        case .offline, .badToken: return .red
        case .notConfigured: return .secondary
        }
    }

    /// Teks pendek di sebelah titik; kalau semua beres cukup titik hijau.
    private var label: String {
        if let n = store.notice { return n }
        switch store.status {
        case .ok: return ""
        case .saving, .connecting: return L("Sync…")
        case .offline: return store.pendingCount > 0 ? L("Offline · %lld", store.pendingCount) : L("Offline")
        case .badToken: return L("Token?")
        case .notConfigured: return ""
        }
    }

    /// Keterangan lengkap saat kursor diarahkan ke titiknya.
    private var detail: String {
        switch store.status {
        case .ok: return L("Tersinkron dengan server")
        case .saving: return L("Menyimpan ke server…")
        case .connecting: return L("Menghubungkan ke server…")
        case .offline: return store.pendingCount > 0 ? L("Offline · %lld perubahan belum terkirim", store.pendingCount) : L("Offline · server tidak terjangkau")
        case .badToken: return L("Token ditolak server — periksa di Pengaturan")
        case .notConfigured: return ""
        }
    }

    var body: some View {
        // Tanpa server (sinkron tidak dipakai): cukup tampilkan pesan singkat kalau ada.
        if store.status == .notConfigured {
            if let n = store.notice {
                Text(n).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
            }
        } else {
            dot
        }
    }

    private var dot: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            if !label.isEmpty {
                Text(label).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
            }
        }
        .help(store.notice ?? detail)
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    var active = false
    var role: ButtonRole? = nil
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .medium))
                .frame(width: 26, height: 24)
                .foregroundStyle(role == .destructive ? AnyShapeStyle(Color.red) : (active ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(HierarchicalShapeStyle.secondary)))
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(hover ? 0.08 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L(help))
        .onHover { hover = $0 }
    }
}

// MARK: - Tab utama

/// Dua tab paling atas: Catatan | To-do.
struct KindTabs: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var ui: PanelUI

    var body: some View {
        let openTasks = store.openTasks()
        let open = openTasks.count
        let late = openTasks.filter { TaskGroup.of($0) == .overdue }.count
        let today = openTasks.filter { TaskGroup.of($0) == .today }.count
        HStack(spacing: 2) {
            tab("Catatan", count: nil, late: 0, today: 0, selected: ui.filter != .tasks) {
                if ui.filter == .tasks { ui.filter = ui.lastNoteFilter }
            }
            tab("To-do", count: open > 0 ? open : nil, late: late, today: today, selected: ui.filter == .tasks) {
                if ui.filter != .tasks { ui.lastNoteFilter = ui.filter; ui.filter = .tasks }
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.07)))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    /// Angka abu-abu = semua yang belum selesai. Bulatan merah = yang terlambat saja,
    /// bulatan oranye = jatuh tempo hari ini (kalau tidak ada yang terlambat).
    private func tab(_ title: String, count: Int?, late: Int, today: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            ui.openID = nil
            ui.openTaskID = nil
            ui.tag = nil
            ui.showTags = false
            action()
        } label: {
            HStack(spacing: 4) {
                Text(verbatim: L(title)).font(.system(size: 12.5, weight: .semibold))
                if let count {
                    Text("\(count)").font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                }
                if late > 0 || today > 0 {
                    Text("\(late > 0 ? late : today)")
                        .font(.system(size: 9.5, weight: .bold)).monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(late > 0 ? Color.red : Color.orange))
                        .help(late > 0 ? L("%lld terlambat", late) : L("%lld jatuh tempo hari ini", today))
                }
            }
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Color(nsColor: .controlBackgroundColor) : Color.clear)
                .shadow(color: .black.opacity(selected ? 0.08 : 0), radius: 1, y: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Tab To-do: saring per folder + tag.
struct TaskFolderStrip: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var ui: PanelUI

    var body: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            Chip(title: L("Semua"), color: .primary, count: store.openTasks().count, selected: ui.taskFolder == nil) { pick(nil) }
            ForEach(store.folders) { f in
                let n = store.openTasks(folder: f.id).count
                if n > 0 || ui.taskFolder == f.id {
                    Chip(title: f.name ?? "Folder", color: FolderColor.of(f.color).color, count: n, selected: ui.taskFolder == f.id) { pick(f.id) }
                }
            }
            TagToggleChip(store: store, ui: ui)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func pick(_ id: String?) {
        ui.taskFolder = id
        ui.openTaskID = nil
        ui.tag = nil
    }
}

// MARK: - Folder

struct FolderStrip: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var ui: PanelUI
    @State private var newName = ""
    @State private var editName = ""
    @FocusState private var nameFocused: Bool
    @FocusState private var renameFocused: Bool

    @State private var expanded = false
    private let limit = 6

    var body: some View {
        let all = store.folders
        let shown = visibleFolders(all)
        FlowLayout(spacing: 6, lineSpacing: 6) {
            Chip(title: L("Semua"), color: .primary, count: store.count(.all) + store.count(.daily), selected: ui.filter == .all) { select(.all) }
            ForEach(shown) { f in
                if ui.renamingFolder == f.id {
                    TextField("Nama folder", text: $editName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 110)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().strokeBorder(Color.accentColor, lineWidth: 1))
                        .focused($renameFocused)
                        .onSubmit { finishRename(f.id) }
                        .onExitCommand { ui.renamingFolder = nil }
                        .onAppear { editName = f.name ?? ""; renameFocused = true }
                } else {
                    Chip(title: f.name ?? "Folder", color: FolderColor.of(f.color).color,
                         count: store.count(.folder(f.id)), selected: ui.filter == .folder(f.id)) { select(.folder(f.id)) }
                        .contextMenu {
                            Button("Ganti nama") { ui.renamingFolder = f.id }
                            Button("Ganti warna") { store.recolorFolder(f.id) }
                            Divider()
                            Button("Hapus folder (catatan tetap ada)", role: .destructive) {
                                if ui.filter == .folder(f.id) { ui.filter = .all }
                                store.deleteFolder(f.id)
                            }
                        }
                }
            }
            if all.count > limit {
                Button(expanded ? L("Ringkas") : L("+%lld lainnya", all.count - shown.count)) { expanded.toggle() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.vertical, 4)
                    .help(expanded ? L("Tampilkan lebih sedikit folder") : L("Tampilkan semua folder"))
            }
            if ui.addingFolder {
                TextField("Nama folder", text: $newName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 110)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().strokeBorder(Color.accentColor, lineWidth: 1))
                    .focused($nameFocused)
                    .onSubmit(addFolder)
                    .onExitCommand { ui.addingFolder = false; newName = "" }
                    .onAppear { nameFocused = true }
            } else {
                Button {
                    ui.addingFolder = true
                } label: {
                    Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 22)
                        .background(Capsule().strokeBorder(Color.primary.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Folder baru (klik kanan folder untuk ganti nama)")
            }
            // Agenda harian: tahun = folder, bulan = sub-folder, dikelompokkan "2026 › Oktober".
            // Selama belum ada agenda, cukup satu chip "Agenda" supaya tempatnya tetap kelihatan.
            if store.dailyYears.isEmpty {
                Chip(title: L("Agenda"), color: store.agendaColor.color, count: 0, selected: ui.filter == .daily) { select(.daily) }
            }
            ForEach(store.dailyYears, id: \.month) { y in
                HStack(spacing: 4) {
                    Chip(title: y.month, color: store.agendaColor.color, count: y.count,
                         selected: ui.filter == .daily && ui.dailyMonth == y.month) { selectDaily(y.month) }
                        .contextMenu {
                            Button("Ganti warna Agenda") { store.recolorAgenda() }
                        }
                    if ui.filter == .daily && (ui.dailyMonth ?? "").hasPrefix(y.month) {
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                        ForEach(store.dailyMonths.filter { $0.month.hasPrefix(y.month) }, id: \.month) { m in
                            MonthChip(title: DailyText.monthName(m.month), count: m.count, selected: ui.dailyMonth == m.month, tint: store.agendaColor.color) {
                                selectDaily(ui.dailyMonth == m.month ? y.month : m.month)
                            }
                        }
                    }
                }
                .fixedSize()
            }
            TagToggleChip(store: store, ui: ui)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    /// Folder yang tampil saat diringkas: 6 pertama, plus folder yang sedang dibuka.
    private func visibleFolders(_ all: [Item]) -> [Item] {
        guard !expanded, all.count > limit else { return all }
        var out = Array(all.prefix(limit))
        if case .folder(let id) = ui.filter, !out.contains(where: { $0.id == id }), let cur = all.first(where: { $0.id == id }) {
            out.append(cur)
        }
        if let r = ui.renamingFolder, !out.contains(where: { $0.id == r }), let cur = all.first(where: { $0.id == r }) {
            out.append(cur)
        }
        return out
    }

    private func select(_ f: Filter) {
        ui.filter = f
        ui.openID = nil
        ui.openTaskID = nil
        ui.renamingFolder = nil
        ui.tag = nil
        ui.dailyMonth = nil
    }

    /// prefix = "2026" (satu tahun) atau "2026-10" (satu bulan)
    private func selectDaily(_ prefix: String) {
        select(.daily)
        ui.dailyMonth = prefix
    }

    private func addFolder() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        ui.addingFolder = false
        newName = ""
        guard !name.isEmpty else { return }
        let id = store.createFolder(name)
        select(.folder(id))
    }

    private func finishRename(_ id: String) {
        let name = editName.trimmingCharacters(in: .whitespaces)
        ui.renamingFolder = nil
        if !name.isEmpty { store.renameFolder(id, name) }
    }
}

struct Chip: View {
    let title: String
    let color: Color
    let count: Int
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 6, height: 10)
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text("\(count)").font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
            }
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(selected ? Color.primary.opacity(0.12) : Color.primary.opacity(hover ? 0.06 : 0)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(selected ? 0 : 0.12), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - Daftar catatan

struct SearchField: View {
    @ObservedObject var ui: PanelUI
    let placeholder: String
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 12))
            TextField(L(placeholder), text: $ui.query)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit(onSubmit)
            if !ui.query.isEmpty {
                Button { ui.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
        .onChange(of: ui.focusSearch) { focused = true }
    }
}

/// Pengelompokan catatan per waktu: Hari ini, Kemarin, 7 hari terakhir, Bulan ini, lalu per bulan.
enum PeriodGroup {
    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = AppLang.locale
        f.setLocalizedDateFormatFromTemplate("MMMMyyyy")
        return f
    }()

    static func title(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return L("Hari ini") }
        if cal.isDateInYesterday(d) { return L("Kemarin") }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: Date())).day ?? 0
        if days < 7 { return L("7 hari terakhir") }
        if cal.isDate(d, equalTo: Date(), toGranularity: .month) { return L("Bulan ini") }
        return monthFormatter.string(from: d).capitalized
    }

    static func group(_ list: [Item], date: (Item) -> Date) -> [(String, [Item])] {
        var out: [(String, [Item])] = []
        for n in list {
            let t = title(date(n))
            if let last = out.indices.last, out[last].0 == t { out[last].1.append(n) } else { out.append((t, [n])) }
        }
        return out
    }
}

struct NoteListView: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var prefs: Prefs
    @ObservedObject var ui: PanelUI
    @State private var confirmEmpty = false
    @State private var addingTask = false
    @State private var openMonths: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                SearchField(ui: ui, placeholder: ui.filter == .trash ? "Cari di Sampah" : "Cari catatan", onSubmit: openFirst)

                if ui.filter == .trash {
                    if store.count(.trash) > 0 {
                        Button(confirmEmpty ? L("Yakin?") : L("Kosongkan")) {
                            if confirmEmpty {
                                store.emptyTrash()
                                confirmEmpty = false
                            } else {
                                confirmEmpty = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { confirmEmpty = false }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(confirmEmpty ? .red : .secondary)
                        .controlSize(.small)
                        .help("Hapus permanen semua isi Sampah")
                    }
                } else {
                    Menu {
                        Picker("Urutkan", selection: $prefs.noteSort) {
                            Text("Terakhir diubah").tag("updated")
                            Text("Tanggal dibuat").tag("created")
                            Text("Judul A–Z").tag("title")
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Image(systemName: "arrow.up.arrow.down").font(.system(size: 12, weight: .medium))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .foregroundStyle(.secondary)
                    .help("Urutkan catatan")

                    // Satu tombol "Baru" dengan pilihan ▾: catatan, agenda, atau to-do
                    HStack(spacing: 0) {
                        Button(action: newNote) {
                            Label(ui.filter == .daily ? L("Agenda") : L("Baru"), systemImage: ui.filter == .daily ? "calendar.badge.plus" : "square.and.pencil")
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.leading, 10).padding(.trailing, 8).padding(.vertical, 6)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(ui.filter == .daily ? L("Agenda baru hari ini (⌘D)") : L("Catatan baru (⌘N)"))
                        Rectangle().fill(Color.white.opacity(0.35)).frame(width: 1, height: 16)
                        Menu {
                            Button { newPlainNote() } label: { Label(L("Catatan baru"), systemImage: "square.and.pencil") }
                            Button { openDaily() } label: { Label(L("Agenda baru"), systemImage: "calendar.badge.plus") }
                            Button { newTodo() } label: { Label(L("To-do baru"), systemImage: "checkmark.circle") }
                        } label: {
                            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .padding(.horizontal, 7)
                        .help(L("Buat baru…"))
                    }
                    .foregroundStyle(.white)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)


            if ui.filter == .all && ui.query.isEmpty && ui.tag == nil {
                TodayCard(store: store, ui: ui)
                    .padding(.horizontal, 8)
            }

            let list = store.notes(ui.filter, query: ui.query, month: ui.dailyMonth).filter { store.hasTag($0, ui.tag) }
            let dailyCount = ui.filter == .all && ui.query.isEmpty && ui.tag == nil ? store.count(.daily) : 0

            if list.isEmpty && ui.filter == .daily {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Belum ada agenda").font(.system(size: 13, weight: .semibold))
                    Text("Tekan Agenda atau ⌘D, lalu tulis topiknya sebagai judul, misalnya “Kementan: Integrasi Data Harga”. Tanggalnya otomatis hari ini.").foregroundStyle(.secondary)
                }
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(16)
            } else if list.isEmpty && dailyCount == 0 {
                // To-do per folder ada di tab To-do; di sini folder cukup berisi catatan.
                EmptyState(query: ui.query, hasAny: store.count(.all) > 0, inTrash: ui.filter == .trash)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if dailyCount > 0 {
                            DailyRow(count: dailyCount, tint: store.agendaColor.color) {
                                select(.daily)
                                ui.dailyMonth = store.dailyYears.first?.month
                            }
                        }
                        if ui.filter == .daily {
                            let groups = dailyGroups(list)
                            // Satu bulan saja: judul bulan tidak perlu diulang (sudah ada di chip "2026 › Oktober").
                            let single = (ui.dailyMonth ?? "").count == 7 || groups.count == 1
                            ForEach(groups, id: \.month) { g in
                                if !single {
                                    Button { toggleMonth(g.month) } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: isOpen(g.month) ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .bold))
                                            Text(DailyText.monthLabel(g.month))
                                            Text("\(g.items.count)").foregroundStyle(.secondary).monospacedDigit()
                                        }
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 8).padding(.top, 12).padding(.bottom, 4)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                                if single || isOpen(g.month) {
                                    // Tanggal = label kelompok, tiap agenda = satu kartu.
                                    ForEach(dayGroups(g.items), id: \.month) { d in
                                        DayHeader(date: d.month, tint: store.agendaColor.color)
                                        ForEach(d.items) { n in
                                            NoteRow(store: store, note: n, showFolder: false, query: ui.query) { open(n.id) }
                                                .contextMenu { rowMenu(n) }
                                        }
                                    }
                                }
                            }
                        } else {
                            ForEach(Array(grouped(list).enumerated()), id: \.offset) { _, g in
                                if !g.0.isEmpty { SectionHeader(title: g.0, count: g.1.count) }
                                ForEach(g.1) { n in
                                    NoteRow(store: store, note: n, showFolder: ui.filter == .all, query: ui.query) { open(n.id) }
                                        .contextMenu { rowMenu(n) }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                }
            }
        }
        .onChange(of: ui.filter) { addingTask = false }
    }

    private struct DailyGroup { var month: String; var items: [Item] }

    private func dailyGroups(_ list: [Item]) -> [DailyGroup] {
        var out: [DailyGroup] = []
        for n in list {
            let m = String((n.dailyDate ?? "").prefix(7))
            if let last = out.indices.last, out[last].month == m { out[last].items.append(n) } else { out.append(DailyGroup(month: m, items: [n])) }
        }
        return out
    }

    /// Kelompok per hari (field month berisi "yyyy-MM-dd").
    private func dayGroups(_ list: [Item]) -> [DailyGroup] {
        var out: [DailyGroup] = []
        for n in list {
            let d = n.dailyDate ?? ""
            if let last = out.indices.last, out[last].month == d { out[last].items.append(n) } else { out.append(DailyGroup(month: d, items: [n])) }
        }
        return out
    }

    /// Bulan berjalan selalu terbuka; bulan lama terlipat sampai diklik.
    private func isOpen(_ month: String) -> Bool {
        month == String(DueDate.today().prefix(7)) || openMonths.contains(month) || !ui.query.isEmpty
    }

    private func toggleMonth(_ month: String) {
        if openMonths.contains(month) { openMonths.remove(month) } else { openMonths.insert(month) }
    }

    private func select(_ f: Filter) {
        ui.filter = f
        ui.openID = nil
        ui.openTaskID = nil
        ui.tag = nil
        ui.dailyMonth = nil
    }

    private func grouped(_ list: [Item]) -> [(String, [Item])] {
        if ui.filter == .trash || prefs.noteSort == "title" || !ui.query.isEmpty { return [("", list)] }
        var out: [(String, [Item])] = []
        let pinned = list.filter { $0.isPinned }
        if !pinned.isEmpty && ui.filter != .pinned { out.append(("Disematkan", pinned)) }
        let rest = ui.filter == .pinned ? list : list.filter { !$0.isPinned }
        let byCreated = prefs.noteSort == "created"
        out.append(contentsOf: PeriodGroup.group(rest) { byCreated ? $0.createdDate : $0.updatedDate })
        return out
    }

    @ViewBuilder private func rowMenu(_ n: Item) -> some View {
        if n.isTrashed {
            Button("Pulihkan") { store.restoreNote(n.id) }
            Divider()
            Button("Hapus permanen", role: .destructive) { store.purgeNote(n.id) }
        } else {
            Button(n.isPinned ? L("Lepas sematan") : L("Sematkan")) { store.setPinned(n.id, !n.isPinned) }
            Menu("Warna penanda") { ColorMenuItems(store: store, note: n) }
            Menu("Pindah ke folder") {
                Button("Tanpa folder") { store.move(n.id, to: nil) }
                ForEach(store.folders) { f in Button(f.name ?? "Folder") { store.move(n.id, to: f.id) } }
            }
            Button(n.isDaily ? L("Lepas dari Agenda harian") : L("Jadikan agenda hari ini")) {
                store.setDaily(n.id, n.isDaily ? nil : DueDate.today())
            }
            Divider()
            Button("Pindahkan ke Sampah", role: .destructive) { store.trashNote(n.id) }
        }
    }

    private func open(_ id: String) {
        if store.task(id) != nil { ui.openTaskID = id; return }
        let n = store.note(id)
        ui.readMode = NoteText.checks(n?.parts.body ?? "").total > 0
        ui.wantsTitleFocus = false
        ui.openID = id
    }

    private func openFirst() {
        if let first = store.notes(ui.filter, query: ui.query).first(where: { store.hasTag($0, ui.tag) }) { open(first.id) }
    }

    func newNote() {
        if ui.filter == .daily { openDaily(); return }   // di Harian, Baru = agenda baru hari ini
        newPlainNote()
    }

    /// Catatan biasa (juga dari menu ▾ saat sedang di Agenda).
    private func newPlainNote() {
        if ui.filter == .daily { ui.filter = .all; ui.dailyMonth = nil }
        var folder: String? = nil
        if case .folder(let id) = ui.filter { folder = id }
        let id = store.createNote(folder: folder, pinned: ui.filter == .pinned)
        if let t = ui.tag { store.addTag(id, t) }   // sedang menyaring tag: catatan baru ikut bertag itu
        ui.query = ""
        ui.readMode = false
        ui.wantsTitleFocus = true
        ui.openID = id
    }

    /// Pindah ke tab To-do dan fokus ke kolom tambah.
    private func newTodo() {
        ui.openID = nil
        ui.openTaskID = nil
        ui.query = ""
        ui.lastNoteFilter = ui.filter
        ui.focusTaskFormOnAppear = true
        ui.filter = .tasks
    }

    private func openDaily() {
        let id = store.newAgenda(tags: ui.tag.map { [$0] })
        ui.query = ""
        ui.readMode = false
        ui.wantsTitleFocus = true
        ui.openID = id
    }
}

/// Pilihan warna penanda catatan (garis kiri kartu).
struct ColorMenuItems: View {
    @ObservedObject var store: NoteStore
    let note: Item

    var body: some View {
        Button { store.setNoteColor(note.id, nil) } label: {
            if note.color == nil { Label("Ikut folder", systemImage: "checkmark") } else { Text("Ikut folder") }
        }
        Divider()
        ForEach(FolderColor.allCases, id: \.self) { c in
            Button { store.setNoteColor(note.id, c) } label: {
                if note.color == c.rawValue { Label(c.label, systemImage: "checkmark") } else { Text(verbatim: c.label) }
            }
        }
    }
}

/// Ringkasan "Hari ini" di atas Semua: to-do yang jatuh tempo / terlambat dan agenda hari ini.
struct TodayCard: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var ui: PanelUI

    var body: some View {
        let today = DueDate.today()
        let tasks = store.openTasks().filter { t in
            let g = TaskGroup.of(t)
            return g == .overdue || g == .today
        }
        let agendas = store.notes(.daily).filter { $0.dailyDate == today }
        if !tasks.isEmpty || !agendas.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: L("Hari ini").uppercased() + " · " + DailyText.shortLabel(today))
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.top, 4)
                ForEach(Array(tasks.prefix(5))) { t in
                    TaskRow(store: store, ui: ui, task: t, showFolder: false)
                }
                if tasks.count > 5 {
                    Button(L("+%lld lainnya", tasks.count - 5)) {
                        ui.lastNoteFilter = ui.filter
                        ui.filter = .tasks
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11.5))
                    .padding(.horizontal, 8)
                }
                ForEach(agendas) { n in
                    Button {
                        ui.readMode = NoteText.checks(n.parts.body).total > 0
                        ui.wantsTitleFocus = false
                        ui.openID = n.id
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "calendar").font(.system(size: 11)).foregroundStyle(store.agendaColor.color)
                            Text(verbatim: n.displayTitle).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.045)))
            .padding(.bottom, 6)
        }
    }
}

/// Label hari di Agenda harian: "RABU, 28 OKT · hari ini".
struct DayHeader: View {
    let date: String
    var tint: Color = FolderColor.teal.color
    var body: some View {
        let isToday = date == DueDate.today()
        HStack(spacing: 5) {
            Text(DailyText.shortLabel(date).uppercased())
                .font(.system(size: 10.5, weight: .bold))
                .tracking(0.6)
            if isToday { Text("hari ini").font(.system(size: 10.5)) }
        }
        .foregroundStyle(isToday ? AnyShapeStyle(tint) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
        .padding(.horizontal, 8).padding(.top, 10).padding(.bottom, 2)
    }
}

/// Baris ringkas di Semua: "Agenda harian · 23".
struct DailyRow: View {
    let count: Int
    var tint: Color = FolderColor.teal.color
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text("Agenda harian").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(count)").font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.vertical, 9).padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.primary.opacity(hover ? 0.18 : 0.1), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .padding(.bottom, 4)
    }
}

/// Sub-folder bulan di bawah Harian.
struct MonthChip: View {
    let title: String
    let count: Int
    let selected: Bool
    var tint: Color = FolderColor.teal.color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).lineLimit(1)
                Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
            }
            .font(.system(size: 11, weight: selected ? .semibold : .medium))
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(selected ? 0.22 : 0.10)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct EmptyState: View {
    let query: String
    let hasAny: Bool
    let inTrash: Bool
    var body: some View {
        VStack(spacing: 6) {
            if inTrash && query.isEmpty {
                Text("Sampah kosong").font(.system(size: 13, weight: .semibold))
                Text("Catatan yang dihapus disimpan di sini 30 hari sebelum hilang permanen.").foregroundStyle(.secondary)
            } else if !query.isEmpty {
                Text("Tidak ada yang cocok").font(.system(size: 13, weight: .semibold))
                Text(verbatim: L("Tidak ada catatan berisi “%@”.", query)).foregroundStyle(.secondary)
            } else if hasAny {
                Text("Folder ini masih kosong").font(.system(size: 13, weight: .semibold))
                Text("Tekan Baru atau ⌘N untuk menulis di sini.").foregroundStyle(.secondary)
            } else {
                Text("Belum ada catatan").font(.system(size: 13, weight: .semibold))
                Text("Tekan Baru atau ⌘N untuk mulai.")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12))
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .padding(.bottom, 60)
    }
}

/// Garis kiri kartu: warna penanda catatan, kalau tidak ada warna foldernya.
func stripeColor(note: Item, folder: Item?, agenda: FolderColor = .teal) -> Color {
    if let c = note.color, let fc = FolderColor(rawValue: c) { return fc.color }
    if let folder { return FolderColor.of(folder.color).color }
    return Color.primary.opacity(0.15)
}

struct NoteRow: View {
    @ObservedObject var store: NoteStore
    let note: Item
    let showFolder: Bool
    var titleOverride: String? = nil
    /// Kata yang sedang dicari: kalau cocoknya di lampiran, potongan isinya ditampilkan.
    var query: String = ""
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        let folder = store.folderOf(note)
        let content = note.parts.body
        let checks = NoteText.checks(content)
        let snippet = note.isLocked ? L("🔒 Catatan terkunci") : (attachmentSnippet(content) ?? NoteText.snippet(content))
        Button(action: action) {
            HStack(alignment: .top, spacing: 9) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(stripeColor(note: note, folder: folder, agenda: store.agendaColor))
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        if note.isPinned && !note.isTrashed {
                            Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(FolderColor.amber.color)
                        }
                        Text(titleOverride ?? note.displayTitle).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                    }
                    if !snippet.isEmpty {
                        Text(snippet).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                    }
                    HStack(spacing: 8) {
                        if note.isTrashed {
                            Text(verbatim: L("Hilang dalam %lld hari", note.trashDaysLeft))
                        } else {
                            Text(RelativeTime.string(note.updatedDate))
                            if checks.total > 0 {
                                Text(verbatim: L("%lld/%lld selesai", checks.done, checks.total))
                                    .foregroundStyle(checks.done == checks.total ? Color.green : Color.secondary)
                            }
                            if showFolder, let folder { Text(folder.name ?? "") }
                            if !note.attachmentList.isEmpty {
                                HStack(spacing: 2) {
                                    Image(systemName: "paperclip")
                                    Text("\(note.attachmentList.count)")
                                }
                                .help(note.attachmentList.map(\.name).joined(separator: "\n"))
                            }
                            TagLine(tags: note.tagList)
                        }
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8).padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(hover ? 0.07 : 0.035)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }

    /// "📎 Laporan.pdf: …potongan isi…" kalau kata yang dicari hanya ada di lampiran.
    private func attachmentSnippet(_ content: String) -> String? {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty, !(note.parts.title + "\n" + content).lowercased().contains(q),
              let hit = store.attachmentHit(note, q) else { return nil }
        return "📎 " + hit.attachment.name + (hit.context.isEmpty ? "" : ": " + hit.context)
    }
}

// MARK: - Editor

struct EditorView: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var ui: PanelUI
    let note: Item
    var fontStyle: String = "sans"
    @FocusState private var titleFocused: Bool
    @ObservedObject private var vault = Vault.shared
    @State private var linkQuery: String?
    @State private var linkToken = 0
    @State private var linkTitle = ""

    var body: some View {
        let locked = note.isLocked
        // Catatan terkunci: isi asli hanya ada di memori selama rahasia terbuka.
        let plain: String? = locked ? vault.plain(for: note) : note.parts.body
        let parts = (title: note.parts.title, body: plain ?? "")
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                IconButton(symbol: "chevron.left", help: "Kembali ke daftar (⌘[)") { ui.openID = nil }
                Picker("", selection: $ui.readMode) {
                    Text("Tulis").tag(false)
                    Text("Baca").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 110)
                .controlSize(.small)
                Spacer()
                if !ui.readMode && plain != nil {
                    IconButton(symbol: "checklist", help: "Tambah checklist") { ui.checklist += 1 }
                    if !locked {
                        IconButton(symbol: "key", help: "Rahasiakan teks yang diblok (⌘L)") { ui.secret += 1 }
                    }
                }
                if plain != nil {
                    IconButton(symbol: "checkmark.circle", help: "Tambah to-do dari catatan ini") { ui.linkedAdd += 1 }
                }
                if plain != nil && !locked {
                    IconButton(symbol: "paperclip", help: "Lampirkan file (bisa juga diseret ke catatan)") { pickFiles() }
                }
                IconButton(symbol: locked ? "lock.fill" : "lock.open",
                           help: locked ? "Catatan terkunci · klik untuk melepas kunci" : "Kunci seluruh catatan",
                           active: locked) {
                    let id = note.id
                    vault.withUnlocked {
                        if store.note(id)?.isLocked == true {
                            store.unlockNote(id)
                            store.noteNotice(L("Kunci catatan dilepas"))
                        } else {
                            store.lockNote(id)
                            store.noteNotice(L("Catatan dikunci"))
                        }
                    }
                }
                IconButton(symbol: note.isPinned ? "pin.fill" : "pin",
                           help: note.isPinned ? "Lepas sematan" : "Sematkan", active: note.isPinned) {
                    store.setPinned(note.id, !note.isPinned)
                }
                Menu {
                    ColorMenuItems(store: store, note: note)
                } label: {
                    Circle()
                        .fill(stripeColor(note: note, folder: store.folderOf(note), agenda: store.agendaColor))
                        .frame(width: 10, height: 10)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Warna penanda")
                Menu {
                    Button { store.move(note.id, to: nil) } label: {
                        if note.folderId == nil { Label("Tanpa folder", systemImage: "checkmark") } else { Text("Tanpa folder") }
                    }
                    ForEach(store.folders) { f in
                        Button { store.move(note.id, to: f.id) } label: {
                            if note.folderId == f.id { Label(f.name ?? "Folder", systemImage: "checkmark") } else { Text(f.name ?? "Folder") }
                        }
                    }
                } label: {
                    Image(systemName: "folder").font(.system(size: 12.5, weight: .medium))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundStyle(.secondary)
                .help("Pindah ke folder")
                IconButton(symbol: "trash", help: "Pindahkan ke Sampah", role: .destructive) {
                    let blank = note.isBlank
                    store.trashNote(note.id)
                    ui.openID = nil
                    if !blank { store.noteNotice(L("Dipindahkan ke Sampah")) }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider().opacity(0.5)

            if plain == nil {
                LockedNoteView(note: note)
            } else if ui.readMode {
                ReadView(store: store, note: note, editable: !locked, fontStyle: fontStyle, bodyOverride: locked ? plain : nil,
                         onOpenLink: { t in openLink(t) })
            } else {
                TextField(note.isDaily ? L("Topik agenda") : L("Judul"),
                          text: Binding(get: { note.parts.title },
                                        set: { store.setTitle(note.id, $0.replacingOccurrences(of: "\n", with: " ")) }),
                          axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .focused($titleFocused)
                    .onSubmit { ui.focusEditor += 1 }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 2)
                HStack(alignment: .top, spacing: 6) {
                    if let ds = note.dailyDate {
                        AgendaDateChip(store: store, ui: ui, noteID: note.id, date: ds)
                    }
                    TagEditor(store: store, item: note)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 2)
                NoteTextView(text: parts.body,
                             onChange: { v in
                                 if locked { store.setLockedBody(note.id, v) } else { store.setBody(note.id, v) }
                             },
                             focusToken: ui.focusEditor,
                             checklistToken: ui.checklist,
                             secretToken: ui.secret,
                             onSecret: { sel, done in
                                 vault.withUnlocked { done(vault.seal(sel)) }
                             },
                             onLinkQuery: { q in linkQuery = q },
                             linkToken: linkToken,
                             linkTitle: linkTitle,
                             firstLinkCandidate: { q in store.linkCandidates(q, excluding: note.id).first ?? (q.trimmingCharacters(in: .whitespaces).isEmpty ? nil : q) },
                             autofocus: !ui.wantsTitleFocus,
                             fontStyle: fontStyle,
                             attachments: note.attachmentList)
                    .id(note.id)
            }

            if let q = linkQuery, !ui.readMode, plain != nil {
                LinkSuggestBar(candidates: store.linkCandidates(q, excluding: note.id), query: q) { t in
                    linkTitle = t
                    linkToken += 1
                }
            }
            if plain != nil {
                AttachmentsBar(store: store, note: note)
            }
            BacklinksBar(store: store, ui: ui, note: note)
            LinkedTasksBar(store: store, ui: ui, noteID: note.id, alwaysShow: note.isDaily)
                .id(note.id)

            HStack {
                Text(verbatim: L("Dibuat %@ · diubah %@", DueDate.longDate(note.createdDate), RelativeTime.string(note.updatedDate)))
                    .lineLimit(1)
                Spacer()
                if locked { Label("Terenkripsi", systemImage: "lock.fill") }
                Text(verbatim: L("%lld kata", NoteText.wordCount(parts.title + " " + parts.body)))
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .onAppear {
            focusTitleIfWanted()
            let store = store, ui = ui
            FileDropTextView.onFiles = { urls in
                guard let id = ui.openID else { return [] }
                return store.addAttachments(id, urls: urls)
            }
        }
        .onDisappear { FileDropTextView.onFiles = nil }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            let id = note.id
            let group = DispatchGroup()
            var urls: [URL] = []
            for p in providers {
                group.enter()
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    DispatchQueue.main.async {
                        if let url { urls.append(url) }
                        group.leave()
                    }
                }
            }
            group.notify(queue: .main) { store.addAttachments(id, urls: urls) }
            return true
        }
        .onChange(of: ui.wantsTitleFocus) { focusTitleIfWanted() }
        .onChange(of: ui.readMode) { _, read in
            if !read { ui.focusEditor += 1 }
        }
    }

    /// Pilih file untuk dilampirkan. Panel tetap terbuka selama jendela pilih file tampil.
    private func pickFiles() {
        let id = note.id
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        p.canChooseDirectories = false
        p.canChooseFiles = true
        p.prompt = L("Lampirkan")
        p.message = L("Pilih file untuk dilampirkan ke catatan ini")
        p.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        ui.holdOpen = true
        NSApp.activate(ignoringOtherApps: true)
        let ok = p.runModal() == .OK
        let urls = p.urls
        ui.holdOpen = false
        ui.refocusPanel()
        if ok { store.appendEmbeds(id, store.addAttachments(id, urls: urls)) }
    }

    /// Klik [[Judul]]: buka catatannya, atau buat kalau belum ada.
    private func openLink(_ title: String) {
        let id = store.noteForLink(title)
        ui.readMode = false
        ui.openID = id
    }

    private func focusTitleIfWanted() {
        guard ui.wantsTitleFocus, !ui.readMode else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            titleFocused = true
            ui.wantsTitleFocus = false
        }
    }
}

/// Saran judul saat mengetik [[ (klik, atau Tab untuk yang pertama).
struct LinkSuggestBar: View {
    let candidates: [String]
    let query: String
    let pick: (String) -> Void

    var body: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        let exact = candidates.contains { $0.lowercased() == q.lowercased() }
        VStack(alignment: .leading, spacing: 2) {
            Text("Tautkan ke catatan · Tab untuk yang pertama")
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 6)
            ForEach(candidates, id: \.self) { t in
                Button { pick(t) } label: {
                    Label(t, systemImage: "doc.text").lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if !q.isEmpty && !exact {
                Button { pick(q) } label: {
                    Label(L("Buat “%@”", q), systemImage: "plus").lineLimit(1)
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 12))
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.06)))
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
    }
}

/// "Disebut di": catatan lain yang menautkan catatan ini lewat [[Judul]].
struct BacklinksBar: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var ui: PanelUI
    let note: Item
    @State private var open = true

    var body: some View {
        let links = store.backlinks(note)
        if !links.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Divider().opacity(0.5)
                Button { open.toggle() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 8.5, weight: .bold))
                        Text("Disebut di")
                        Text("\(links.count)").foregroundStyle(.secondary).monospacedDigit()
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.top, 6)
                if open {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(links) { l in
                                Button {
                                    ui.readMode = true
                                    ui.openID = l.note.id
                                } label: {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text((l.note.dailyDate.map { "📅 " + DailyText.shortLabel($0) + " · " } ?? "") + l.note.displayTitle)
                                            .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                        Text(NoteText.snippet(l.line)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: min(CGFloat(links.count) * 38, 150))
                    .padding(.horizontal, 6)
                }
            }
        }
    }
}

/// Tugas yang tertaut ke catatan (seperti backlink di Obsidian): dicentang langsung dari sini,
/// atau tambah tugas baru yang otomatis ikut folder & tag catatannya.
struct LinkedTasksBar: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var ui: PanelUI
    let noteID: String
    /// Agenda: selalu tampil (tempat tindak lanjut). Catatan lain: hanya kalau sudah ada to-do, atau dibuka lewat tombol ✓.
    var alwaysShow = false
    @State private var open = true
    @State private var newTitle = ""
    @State private var forced = false
    @FocusState private var adding: Bool

    var body: some View {
        let tasks = store.linkedTasks(noteID)
        let openCount = tasks.filter { $0.doneAt == nil }.count
        if tasks.isEmpty && !alwaysShow && !forced {
            Color.clear.frame(height: 0)
                .onChange(of: ui.linkedAdd) { reveal() }
        } else {
            bar(tasks, openCount)
                .onChange(of: ui.linkedAdd) { reveal() }
        }
    }

    private func reveal() {
        forced = true
        open = true
        DispatchQueue.main.async { adding = true }
    }

    @ViewBuilder private func bar(_ tasks: [Item], _ openCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Divider().opacity(0.5)
            HStack(spacing: 5) {
                Button { open.toggle() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 8.5, weight: .bold))
                        Text("To-do terkait")
                        if !tasks.isEmpty { Text("\(openCount)/\(tasks.count)").foregroundStyle(.secondary).monospacedDigit() }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.top, 6)

            if open {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(tasks) { t in TaskRow(store: store, ui: ui, task: t, showFolder: false) }
                    }
                }
                .frame(maxHeight: tasks.isEmpty ? 0 : min(CGFloat(tasks.count) * 40, 160))
                .padding(.horizontal, 6)
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    TextField("Tambah to-do", text: $newTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($adding)
                        .onSubmit {
                            let t = newTitle.trimmingCharacters(in: .whitespaces)
                            guard !t.isEmpty else { return }
                            store.addLinkedTask(note: noteID, title: t)
                            newTitle = ""
                            adding = true
                        }
                }
                .padding(.horizontal, 14).padding(.vertical, 5)
            }
        }
    }
}

/// Tanggal agenda sebagai label kecil di bawah judul; klik untuk mengganti tanggal.
struct AgendaDateChip: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var ui: PanelUI
    let noteID: String
    let date: String
    @State private var picking = false
    @State private var hover = false

    var body: some View {
        // Kalender tampil menempel di bawah label (bukan popover: panel ini tidak boleh kehilangan fokus).
        VStack(alignment: .leading, spacing: 6) {
            Button { picking.toggle() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "calendar").font(.system(size: 9.5, weight: .semibold))
                    Text(DailyText.shortLabel(date)).lineLimit(1)
                    Image(systemName: picking ? "chevron.up" : "chevron.down").font(.system(size: 7, weight: .bold))
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(hover || picking ? 0.09 : 0.0)))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
            .help("Ganti tanggal agenda")
            .fixedSize()

            if picking {
                DatePicker("", selection: Binding(
                    get: { DueDate.date(date) ?? Date() },
                    set: { d in set(DueDate.string(d)) }), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .frame(width: 220)
                HStack(spacing: 12) {
                    Button("Hari ini") { set(DueDate.today()) }
                    Button("Lepas dari Agenda") { picking = false; store.setDaily(noteID, nil) }
                }
                .buttonStyle(.link)
                .font(.system(size: 11.5))
            }
        }
    }

    private func set(_ ds: String) {
        store.setDaily(noteID, ds)
        if let m = ui.dailyMonth, !ds.hasPrefix(m) { ui.dailyMonth = String(ds.prefix(m.count)) }
        picking = false
    }
}

/// Catatan di Sampah: hanya bisa dibaca, dipulihkan, atau dihapus permanen.
struct TrashedNoteView: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var ui: PanelUI
    let note: Item
    var fontStyle: String = "sans"
    @State private var confirmPurge = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                IconButton(symbol: "chevron.left", help: "Kembali ke Sampah") { ui.openID = nil }
                Text(verbatim: L("Hilang dalam %lld hari", note.trashDaysLeft))
                    .font(.system(size: 11.5, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Button("Pulihkan") {
                    store.restoreNote(note.id)
                    store.noteNotice(L("Catatan dipulihkan"))
                }
                .controlSize(.small)
                Button(confirmPurge ? L("Yakin?") : L("Hapus permanen")) {
                    if confirmPurge {
                        store.purgeNote(note.id)
                        ui.openID = nil
                    } else {
                        confirmPurge = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { confirmPurge = false }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(confirmPurge ? .red : .secondary)
                .controlSize(.small)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            Divider().opacity(0.5)
            ReadView(store: store, note: note, editable: false, fontStyle: fontStyle)
        }
    }
}

struct ReadView: View {
    @ObservedObject var store: NoteStore
    let note: Item
    let editable: Bool
    var fontStyle: String = "sans"
    /// Isi catatan terkunci yang sudah dibuka.
    var bodyOverride: String? = nil
    /// Klik [[Judul]]
    var onOpenLink: ((String) -> Void)? = nil
    @State private var revealed: String?
    @State private var hideWork: DispatchWorkItem?
    @ObservedObject private var vault = Vault.shared

    private var bodyFont: Font { fontStyle == "serif" ? .system(size: 15, design: .serif) : .system(size: 14) }

    var body: some View {
        let parts = (title: note.parts.title, body: bodyOverride ?? note.parts.body)
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text(note.displayTitle)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .padding(.bottom, note.tagList.isEmpty && note.dailyDate == nil ? 6 : 0)
                if let ds = note.dailyDate {
                    Label(DailyText.shortLabel(ds), systemImage: "calendar")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, note.tagList.isEmpty ? 6 : 0)
                }
                if !note.tagList.isEmpty {
                    TagLine(tags: note.tagList)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 6)
                }
                let lines = NoteText.lines(parts.body)
                ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                    lineView(i, line)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .textSelection(.enabled)
        }
        // Klik "🔒 ••••••••" untuk membuka rahasia.
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == NoteText.noteScheme {
                let raw = String(url.absoluteString.dropFirst(NoteText.noteScheme.count + 1))
                onOpenLink?(raw.removingPercentEncoding ?? raw)
                return .handled
            }
            guard url.scheme == Vault.urlScheme else { return .systemAction }
            let payload = String(url.absoluteString.dropFirst(Vault.urlScheme.count + 1))
            Vault.shared.withUnlocked {
                if let t = Vault.shared.open(payload) { show(t) } else { store.noteNotice(L("Tidak bisa dibuka dengan kata sandi ini")) }
            }
            return .handled
        })
        .overlay(alignment: .bottom) {
            if let r = revealed {
                HStack(spacing: 8) {
                    Image(systemName: "lock.open.fill").foregroundStyle(.secondary)
                    Text(r).font(.system(size: 12, design: .monospaced)).lineLimit(3).textSelection(.enabled)
                    Spacer(minLength: 4)
                    Button("Salin") {
                        Vault.shared.copy(r)
                        store.noteNotice(L("Disalin · clipboard dibersihkan dalam 60 detik"))
                    }
                    Button { revealed = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }
                .controlSize(.small)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(.regularMaterial))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.12)))
                .padding(10)
            }
        }
        .onChange(of: vault.isUnlocked) { _, on in if !on { revealed = nil } }
    }

    private func show(_ text: String) {
        revealed = text
        hideWork?.cancel()
        let w = DispatchWorkItem { revealed = nil }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: w)
    }

    @ViewBuilder private func lineView(_ i: Int, _ line: String) -> some View {
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)
        if let name = NoteText.embedName(line) {
            EmbedView(note: note, name: name)
        } else if let m = NoteText.checkPattern.firstMatch(in: line, range: full),
           ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces).isEmpty {
            Color.clear.frame(height: 6)
        } else if line.range(of: #"^\s*[-*]\s*$"#, options: .regularExpression) != nil {
            Color.clear.frame(height: 6)
        } else if let m = NoteText.checkPattern.firstMatch(in: line, range: full) {
            let done = ns.substring(with: m.range(at: 1)) != " "
            let label = ns.substring(with: m.range(at: 2))
            Button {
                if editable { store.toggleCheck(note.id, line: i) }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: done ? "checkmark.square.fill" : "square")
                        .foregroundStyle(done ? Color.accentColor : Color.secondary)
                        .font(bodyFont)
                    Text(NoteText.inline(label))
                        .strikethrough(done)
                        .foregroundStyle(done ? Color.secondary : Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!editable)
            .font(bodyFont)
            .contextMenu {
                if editable {
                    Button("Jadikan to-do") {
                        if store.convertChecklistLine(note: note.id, line: i) != nil {
                            store.noteNotice(L("Jadi to-do terkait"))
                        }
                    }
                }
            }
        } else if let m = NoteText.headingPattern.firstMatch(in: line, range: full) {
            let level = m.range(at: 1).length
            Text(NoteText.inline(ns.substring(with: m.range(at: 2))))
                .font(.system(size: level == 1 ? 17 : level == 2 ? 15 : 14, weight: .bold, design: .rounded))
                .padding(.top, 6)
        } else if let m = NoteText.bulletPattern.firstMatch(in: line, range: full) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(.secondary)
                Text(NoteText.inline(ns.substring(with: m.range(at: 1))))
            }
            .font(bodyFont)
        } else if let m = NoteText.numberPattern.firstMatch(in: line, range: full) {
            let text = ns.substring(with: m.range(at: 2))
            if text.trimmingCharacters(in: .whitespaces).isEmpty {
                Color.clear.frame(height: 6)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(ns.substring(with: m.range(at: 1)) + ".").foregroundStyle(.secondary).monospacedDigit()
                    Text(NoteText.inline(text))
                }
                .font(bodyFont)
            }
        } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
            Color.clear.frame(height: 6)
        } else {
            Text(NoteText.inline(line)).font(bodyFont)
        }
    }
}
