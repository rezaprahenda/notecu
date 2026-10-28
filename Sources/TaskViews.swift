import AppKit
import SwiftUI

// MARK: - Daftar tugas

struct TaskListView: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var ui: PanelUI
    @State private var showDone = false
    @State private var allDone = false

    var body: some View {
        let tf = ui.taskFolder.flatMap { id in store.folders.contains { $0.id == id } ? id : nil }
        let open = store.openTasks(folder: tf, query: ui.query).filter { store.hasTag($0, ui.tag) }
        let doneAll = store.doneTasks(query: ui.query, all: true).filter { store.hasTag($0, ui.tag) && (tf == nil || $0.folderId == tf) }
        let cutoff = nowMillis() - 30 * 86_400_000
        let done = allDone ? doneAll : doneAll.filter { ($0.doneAt ?? 0) >= cutoff }
        let recentCount = doneAll.filter { ($0.doneAt ?? 0) >= cutoff }.count
        VStack(spacing: 0) {
            AddTaskForm(store: store, ui: ui, folder: tf)
                .id(tf ?? "all")
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 8)

            if open.isEmpty && doneAll.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: ui.query.isEmpty ? L("Belum ada to-do") : L("Tidak ada yang cocok")).font(.system(size: 13, weight: .semibold))
                    Text(ui.query.isEmpty
                         ? L("Ketik to-do di atas lalu Enter. Tulis besok, jumat, tgl 5, 10:00, ! (penting), atau #tag langsung di kalimatnya.")
                         : L("Tidak ada to-do berisi “%@”.", ui.query))
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(16)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(TaskGroup.allCases, id: \.self) { g in
                            let rows = open.filter { TaskGroup.of($0) == g }
                            if !rows.isEmpty {
                                SectionHeader(title: g.title, count: rows.count, alert: g == .overdue)
                                ForEach(rows) { t in TaskRow(store: store, ui: ui, task: t, showFolder: true) }
                            }
                        }
                        if !doneAll.isEmpty {
                            Button {
                                showDone.toggle()
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: showDone ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .bold))
                                    Text(verbatim: allDone ? L("Semua yang selesai") : L("Selesai · 30 hari terakhir"))
                                    Text("\(done.count)").foregroundStyle(.secondary).monospacedDigit()
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8).padding(.top, 14).padding(.bottom, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if showDone {
                                if allDone {
                                    // dikelompokkan per bulan selesai
                                    ForEach(doneMonths(done), id: \.month) { g in
                                        Text(DailyText.monthLabel(g.month).uppercased())
                                            .font(.system(size: 10, weight: .bold)).tracking(0.5)
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 8).padding(.top, 8)
                                        ForEach(g.items) { t in TaskRow(store: store, ui: ui, task: t, showFolder: true) }
                                    }
                                } else {
                                    ForEach(done) { t in TaskRow(store: store, ui: ui, task: t, showFolder: true) }
                                }
                                if doneAll.count > recentCount || allDone {
                                    Button(allDone ? L("Hanya 30 hari terakhir") : L("Lihat semua yang selesai (%lld)", doneAll.count)) { allDone.toggle() }
                                        .buttonStyle(.link)
                                        .font(.system(size: 11.5))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                }
            }
        }
    }
}

struct DoneMonth { var month: String; var items: [Item] }

/// To-do selesai dikelompokkan per bulan (urutan tetap: terbaru dulu).
func doneMonths(_ list: [Item]) -> [DoneMonth] {
    var out: [DoneMonth] = []
    for t in list {
        let m = String(DueDate.string(Date(timeIntervalSince1970: (t.doneAt ?? 0) / 1000)).prefix(7))
        if let i = out.indices.last, out[i].month == m { out[i].items.append(t) } else { out.append(DoneMonth(month: m, items: [t])) }
    }
    return out
}

struct SectionHeader: View {
    let title: String
    let count: Int
    var alert = false
    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: L(title)).foregroundStyle(alert ? Color.red : Color.secondary)
            Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
        }
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 8).padding(.top, 12).padding(.bottom, 4)
    }
}

struct TaskRow: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var ui: PanelUI
    let task: Item
    let showFolder: Bool
    @State private var hover = false

    var body: some View {
        let folder = store.folderOf(task)
        let overdue = DueDate.isOverdue(task)
        HStack(alignment: .top, spacing: 9) {
            Button {
                store.toggleDone(task.id)
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(task.isDone ? Color.accentColor : (task.isImportant ? Color.orange : Color.secondary))
            }
            .buttonStyle(.plain)
            .help(task.isDone ? L("Tandai belum selesai") : L("Tandai selesai"))

            Button {
                ui.openID = nil
                ui.openTaskID = task.id
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(task.displayTitle)
                            .font(.system(size: 13, weight: .medium))
                            .strikethrough(task.isDone)
                            .foregroundStyle(task.isDone ? Color.secondary : Color.primary)
                            .lineLimit(2)
                        if task.isImportant && !task.isDone {
                            Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.orange)
                        }
                    }
                    HStack(spacing: 8) {
                        if task.isDone, let d = task.doneAt {
                            Text(verbatim: L("Selesai %@", RelativeTime.string(Date(timeIntervalSince1970: d / 1000))))
                        } else if task.due != nil {
                            Label(DueDate.label(task), systemImage: "calendar")
                                .foregroundStyle(overdue ? Color.red : Color.secondary)
                        }
                        if let r = task.recur, !task.isDone {
                            Image(systemName: "repeat").help(Recur.label(r))
                        }
                        if showFolder, let folder {
                            HStack(spacing: 3) {
                                Circle().fill(FolderColor.of(folder.color).color).frame(width: 5, height: 5)
                                Text(folder.name ?? "")
                            }
                        }
                        TagLine(tags: task.tagList)
                        if !task.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Image(systemName: "text.alignleft")
                        }
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if store.lingering[task.id] != nil {
                Button("Urungkan") { store.undoDone(task.id) }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 1)
            }
        }
        .padding(.vertical, 6).padding(.horizontal, 8)
        .opacity(store.lingering[task.id] != nil ? 0.75 : 1)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(hover ? 0.06 : 0)))
        .onHover { hover = $0 }
        .contextMenu {
            Button(task.isDone ? L("Tandai belum selesai") : L("Tandai selesai")) { store.toggleDone(task.id) }
            Button(task.isImportant ? L("Hapus tanda penting") : L("Tandai penting")) {
                store.updateTask(task.id) { $0.important = $0.isImportant ? nil : true }
            }
            Menu("Tenggat") {
                Button("Hari ini") { store.updateTask(task.id) { $0.due = DueDate.today() } }
                Button("Besok") { store.updateTask(task.id) { $0.due = DueDate.inDays(1) } }
                Button("Minggu depan") { store.updateTask(task.id) { $0.due = DueDate.nextWeek() } }
                Divider()
                Button("Tanpa tenggat") { store.updateTask(task.id) { $0.due = nil } }
            }
            Divider()
            Button("Pindahkan ke Sampah", role: .destructive) { store.trashNote(task.id) }
        }
    }
}

// MARK: - Form tambah tugas

struct AddTaskForm: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var ui: PanelUI
    /// Folder bawaan (mis. saat dibuka dari dalam folder)
    let folder: String?

    @State private var title = ""
    @State private var due: String?
    @State private var dueTime: String?
    @State private var important = false
    @State private var folderID: String?
    @State private var folderTouched = false
    @FocusState private var focused: Bool

    private var expanded: Bool { focused || !title.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill").foregroundStyle(Color.accentColor).font(.system(size: 15))
                TextField("Tambah to-do", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($focused)
                    .onSubmit(save)
                    .onExitCommand { title = ""; focused = false }
                Button {
                    important.toggle()
                } label: {
                    Image(systemName: important ? "star.fill" : "star")
                        .foregroundStyle(important ? Color.orange : Color.secondary)
                }
                .buttonStyle(.plain)
                .help("Tandai penting")
            }
            let hint = title.isEmpty ? "" : TodoParser(title).hint
            if !hint.isEmpty {
                Text(hint).font(.system(size: 11.5)).foregroundStyle(Color.accentColor).padding(.leading, 23)
            }
            if expanded {
                DueEditor(due: due, dueTime: dueTime) { d, t in due = d; dueTime = t }
                FolderPicker(store: store, selection: folderTouched ? folderID : folder) { id in
                    folderID = id
                    folderTouched = true
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
        .onChange(of: ui.focusTaskForm) { focused = true }
        .onAppear { if ui.focusTaskFormOnAppear { ui.focusTaskFormOnAppear = false; DispatchQueue.main.async { focused = true } } }
    }

    private func save() {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        // "besok 10:00 ! #tag" di kalimat mengalahkan pilihan tombol
        let p = TodoParser(t)
        let id = store.addTask(title: p.title, due: p.due ?? due, dueTime: p.dueTime ?? (p.due == nil ? dueTime : nil),
                               important: important || p.important, folder: folderTouched ? folderID : folder)
        if let r = p.recur { store.updateTask(id) { $0.recur = r } }
        if let tag = ui.tag { store.addTag(id, tag) }
        for tag in p.tags { store.addTag(id, tag) }
        title = ""
        important = false
        // tenggat & folder dibiarkan, supaya enak menambah beberapa tugas sekaligus
        focused = true
    }
}

/// Pilihan tenggat: tombol cepat + tanggal & jam (tanpa popup, supaya panel tidak tertutup).
struct DueEditor: View {
    let due: String?
    let dueTime: String?
    let onChange: (String?, String?) -> Void
    @State private var custom = false

    var body: some View {
        let quick = [DueDate.today(), DueDate.inDays(1), DueDate.nextWeek()]
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                DueChip(title: "Hari ini", selected: due == quick[0] && !custom) { custom = false; onChange(quick[0], dueTime) }
                DueChip(title: "Besok", selected: due == quick[1] && !custom) { custom = false; onChange(quick[1], dueTime) }
                DueChip(title: "Senin depan", selected: due == quick[2] && !custom) { custom = false; onChange(quick[2], dueTime) }
                DueChip(title: "Tanggal…", selected: custom || (due != nil && !quick.contains(due!))) {
                    custom = true
                    if due == nil { onChange(DueDate.today(), dueTime) }
                }
                if due != nil {
                    Button { custom = false; onChange(nil, nil) } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("Tanpa tenggat")
                }
            }
            if due != nil {
                HStack(spacing: 8) {
                    if custom || !quick.contains(due!) {
                        DatePicker("", selection: Binding(
                            get: { DueDate.date(due) ?? Date() },
                            set: { onChange(DueDate.string($0), dueTime) }
                        ), displayedComponents: .date)
                        .datePickerStyle(.field)
                        .labelsHidden()
                        .fixedSize()
                    }
                    Toggle("Jam", isOn: Binding(
                        get: { dueTime != nil },
                        set: { on in onChange(due, on ? (dueTime ?? "09:00") : nil) }
                    ))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                    if dueTime != nil {
                        DatePicker("", selection: Binding(
                            get: { DueDate.time(dueTime) ?? Date() },
                            set: { onChange(due, DueDate.timeString($0)) }
                        ), displayedComponents: .hourAndMinute)
                        .datePickerStyle(.field)
                        .labelsHidden()
                        .fixedSize()
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

struct DueChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(verbatim: L(title))
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(selected ? Color.accentColor : Color.primary.opacity(0.07)))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct FolderPicker: View {
    @ObservedObject var store: NoteStore
    let selection: String?
    let onSelect: (String?) -> Void

    var body: some View {
        let current = selection.flatMap { id in store.folders.first { $0.id == id } }
        Menu {
            Button("Tanpa folder") { onSelect(nil) }
            ForEach(store.folders) { f in Button(f.name ?? "Folder") { onSelect(f.id) } }
        } label: {
            HStack(spacing: 5) {
                Circle().fill(current.map { FolderColor.of($0.color).color } ?? Color.secondary.opacity(0.4)).frame(width: 7, height: 7)
                Text(verbatim: current?.name ?? L("Tanpa folder")).font(.system(size: 11.5))
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

// MARK: - Detail tugas

struct TaskDetailView: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var ui: PanelUI
    let task: Item

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                IconButton(symbol: "chevron.left", help: "Kembali (⌘[)") { ui.openTaskID = nil }
                Spacer()
                if task.isTrashed {
                    Button("Pulihkan") { store.restoreNote(task.id) }.controlSize(.small)
                    Button("Hapus permanen") { store.purgeNote(task.id); ui.openTaskID = nil }
                        .controlSize(.small)
                } else {
                    Button(task.isDone ? L("Belum selesai") : L("Tandai selesai")) { store.toggleDone(task.id) }
                        .buttonStyle(.borderedProminent)
                        .tint(task.isDone ? .secondary : .accentColor)
                        .controlSize(.small)
                    IconButton(symbol: "trash", help: "Pindahkan ke Sampah", role: .destructive) {
                        store.trashNote(task.id)
                        ui.openTaskID = nil
                        store.noteNotice(L("To-do dipindahkan ke Sampah"))
                    }
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            Divider().opacity(0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Button { store.toggleDone(task.id) } label: {
                            Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 18))
                                .foregroundStyle(task.isDone ? Color.accentColor : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(task.isTrashed)
                        TextField("Judul to-do", text: Binding(
                            get: { task.parts.title },
                            set: { v in store.updateTask(task.id) { $0.title = v } }
                        ), axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .strikethrough(task.isDone)
                        .disabled(task.isTrashed)
                    }

                    LabeledRow(label: "Tenggat") {
                        DueEditor(due: task.due, dueTime: task.dueTime) { d, t in
                            store.updateTask(task.id) { $0.due = d; $0.dueTime = t }
                        }
                    }
                    LabeledRow(label: "Folder") {
                        FolderPicker(store: store, selection: task.folderId) { id in
                            store.updateTask(task.id) { $0.folderId = id }
                        }
                    }
                    LabeledRow(label: "Tag") {
                        TagEditor(store: store, item: task)
                    }
                    LabeledRow(label: "Ulangi") {
                        Picker("", selection: Binding(
                            get: { task.recur ?? "" },
                            set: { v in
                                store.updateTask(task.id) { t in
                                    t.recur = v.isEmpty ? nil : v
                                    if !v.isEmpty && t.due == nil { t.due = Recur.next(v, after: DueDate.today(), inclusive: true) }
                                }
                            })) {
                            ForEach(Recur.options(for: task), id: \.self) { o in
                                Text(verbatim: o.isEmpty ? L("Tidak") : (o == "weekdays" ? L("Tiap hari kerja (Sen–Jum)") : Recur.label(o))).tag(o)
                            }
                        }
                        .labelsHidden()
                        .controlSize(.small)
                        .fixedSize()
                        .disabled(task.isTrashed)
                    }
                    LabeledRow(label: "Penting") {
                        Toggle("", isOn: Binding(
                            get: { task.isImportant },
                            set: { on in store.updateTask(task.id) { $0.important = on ? true : nil } }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Keterangan").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        TextField("Keterangan", text: Binding(
                            get: { task.body },
                            set: { v in store.updateTask(task.id) { $0.text = v } }
                        ), axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .lineLimit(3...12)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                    }
                    if let src = store.note(task.sourceNoteId) {
                        Button {
                            ui.openTaskID = nil
                            ui.filter = .all
                            ui.readMode = true
                            ui.openID = src.id
                        } label: {
                            Label(L("Dari catatan: %@", src.displayTitle), systemImage: "doc.text")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.link)
                    }
                }
                .padding(16)
            }

            HStack {
                Text(verbatim: L("Dibuat %@", DueDate.longDate(task.createdDate)))
                Spacer()
                if let d = task.doneAt { Text(verbatim: L("Selesai %@", DueDate.longDate(Date(timeIntervalSince1970: d / 1000)))) }
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
    }
}

struct LabeledRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: L(label)).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }
}
