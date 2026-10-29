import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// File yang dilampirkan ke catatan (misalnya laporan rapat .docx / .pdf di agenda).
/// File asli disalin ke ~/Library/Application Support/notecu/attachments/<id>/<nama file>.
/// Teksnya diambil sekali dan disimpan di sebelahnya supaya ikut terbaca saat mencari.
/// Kalau sinkron server aktif, file ikut diunggah ke server dan diunduh di perangkat lain (lihat AttachmentSync).
struct Attachment: Codable, Equatable, Hashable, Identifiable {
    var id: String
    var name: String
    var size: Int
    var addedAt: Double

    var ext: String { (name as NSString).pathExtension.lowercased() }
}

enum Attachments {
    static let maxBytes = 50 * 1024 * 1024

    enum ImportError: Error { case tooBig, failed }

    static var folder: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("notecu", isDirectory: true)
            .appendingPathComponent("attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func dir(_ id: String) -> URL { folder.appendingPathComponent(id, isDirectory: true) }
    static func url(_ a: Attachment) -> URL { dir(a.id).appendingPathComponent(a.name) }
    static func textURL(_ id: String) -> URL { dir(id).appendingPathComponent(".notecu-text.txt") }
    static func exists(_ a: Attachment) -> Bool { FileManager.default.fileExists(atPath: url(a).path) }
    private static func uploadedURL(_ id: String) -> URL { dir(id).appendingPathComponent(".notecu-uploaded") }
    static func isUploaded(_ a: Attachment) -> Bool { FileManager.default.fileExists(atPath: uploadedURL(a.id).path) }
    static func markUploaded(_ a: Attachment) { FileManager.default.createFile(atPath: uploadedURL(a.id).path, contents: Data()) }

    /// Salin file ke folder notecu. File aslinya tidak diubah.
    static func copyIn(_ src: URL, as name: String? = nil) throws -> Attachment {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: src.path, isDirectory: &isDir), !isDir.boolValue else {
            throw ImportError.failed
        }
        let size = ((try? FileManager.default.attributesOfItem(atPath: src.path))?[.size] as? NSNumber)?.intValue ?? 0
        if size > maxBytes { throw ImportError.tooBig }
        let id = newID("a")
        do {
            try FileManager.default.createDirectory(at: dir(id), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: src, to: dir(id).appendingPathComponent(name ?? src.lastPathComponent))
        } catch {
            try? FileManager.default.removeItem(at: dir(id))
            throw ImportError.failed
        }
        return Attachment(id: id, name: name ?? src.lastPathComponent, size: size, addedAt: nowMillis())
    }

    /// Pindahkan ke Sampah Mac (masih bisa dipulihkan dari Finder).
    static func remove(_ a: Attachment) {
        try? FileManager.default.trashItem(at: dir(a.id), resultingItemURL: nil)
        AttachmentIndex.shared.forget(a.id)
    }

    /// Ambil teks untuk pencarian. Format yang tidak dikenal: nil (tetap bisa dicari lewat nama file).
    static func extractText(_ a: Attachment) -> String? {
        let u = url(a)
        func rich(_ type: NSAttributedString.DocumentType) -> String? {
            try? NSAttributedString(url: u, options: [.documentType: type], documentAttributes: nil).string
        }
        switch a.ext {
        case "pdf": return PDFDocument(url: u)?.string
        case "docx", "dotx": return rich(.officeOpenXML)
        case "doc": return rich(.docFormat)
        case "rtf": return rich(.rtf)
        case "odt": return rich(.openDocument)
        case "txt", "md", "markdown", "csv", "json", "log":
            return (try? String(contentsOf: u, encoding: .utf8)) ?? (try? String(contentsOf: u, encoding: .isoLatin1))
        default: return nil
        }
    }

    static func icon(_ a: Attachment) -> NSImage {
        if exists(a) { return NSWorkspace.shared.icon(forFile: url(a).path) }
        return NSWorkspace.shared.icon(for: UTType(filenameExtension: a.ext) ?? .data)
    }

    private static let imageCache = NSCache<NSString, NSImage>()

    static func image(_ a: Attachment) -> NSImage? {
        if let img = imageCache.object(forKey: a.id as NSString) { return img }
        guard let img = NSImage(contentsOf: url(a)) else { return nil }
        imageCache.setObject(img, forKey: a.id as NSString)
        return img
    }

    /// Nama yang belum dipakai di catatan ini: "foto.png", "foto 2.png", …
    static func uniqueName(_ name: String, in list: [Attachment]) -> String {
        let taken = Set(list.map { $0.name.lowercased() })
        guard taken.contains(name.lowercased()) else { return name }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var i = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)"
            if !taken.contains(candidate.lowercased()) { return candidate }
            i += 1
        }
    }

    static func isImage(_ a: Attachment) -> Bool {
        ["png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "bmp"].contains(a.ext)
    }

    static func sizeLabel(_ a: Attachment) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(a.size), countStyle: .file)
    }
}

/// Teks lampiran di memori (dibaca dari disk sekali saja).
final class AttachmentIndex {
    static let shared = AttachmentIndex()
    private var cache: [String: String] = [:]
    private var missing = Set<String>()

    func text(_ id: String) -> String? {
        if let t = cache[id] { return t }
        if missing.contains(id) { return nil }
        if let t = try? String(contentsOf: Attachments.textURL(id), encoding: .utf8) {
            cache[id] = t
            return t
        }
        missing.insert(id)
        return nil
    }

    func save(_ id: String, _ text: String) {
        let t = text.replacingOccurrences(of: "\u{0}", with: "")
        try? t.write(to: Attachments.textURL(id), atomically: true, encoding: .utf8)
        cache[id] = t
        missing.remove(id)
    }

    func forget(_ id: String) {
        cache.removeValue(forKey: id)
        missing.remove(id)
    }
}

// MARK: - Sinkron file ke server

/// Unggah lampiran baru dan unduh lampiran dari perangkat lain, satu per satu, setelah tiap sinkron.
final class AttachmentSync: @unchecked Sendable {
    static let shared = AttachmentSync()
    /// Semua diakses dari main thread.
    var running = false
    /// Server lama tanpa /api/files: berhenti mencoba sampai app dibuka ulang.
    var unsupported = false
    var skipUpload = Set<String>()
    var lastFail: [String: Date] = [:]
    private(set) var downloading = Set<String>()

    func setDownloading(_ ids: Set<String>) { downloading = ids }

    static func upload(_ a: Attachment, to url: URL, token: String) async -> Int {
        var req = URLRequest(url: url, timeoutInterval: 300)
        req.httpMethod = "PUT"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        do {
            let (_, resp) = try await URLSession.shared.upload(for: req, fromFile: Attachments.url(a))
            return (resp as? HTTPURLResponse)?.statusCode ?? 0
        } catch {
            return 0
        }
    }

    static func download(_ a: Attachment, from url: URL, token: String) async -> Int {
        var req = URLRequest(url: url, timeoutInterval: 300)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else { return code }
            try FileManager.default.createDirectory(at: Attachments.dir(a.id), withIntermediateDirectories: true)
            try data.write(to: Attachments.url(a), options: .atomic)
            Attachments.markUploaded(a)
            return 200
        } catch {
            return 0
        }
    }
}

// MARK: - Di NoteStore

/// NoteStore hanya diubah dari main thread; hasil kerja di belakang layar selalu dikembalikan lewat DispatchQueue.main.
extension NoteStore: @unchecked Sendable {}

extension NoteStore {
    /// Lampirkan file ke catatan. Catatan terkunci tidak bisa diberi lampiran (filenya tidak terenkripsi).
    /// Hasilnya lampiran yang berhasil ditambahkan.
    @discardableResult
    func addAttachments(_ noteID: String, urls: [URL]) -> [Attachment] {
        guard var n = items[noteID], n.isNote, !n.isDeleted, !urls.isEmpty else { return [] }
        if n.isLocked {
            noteNotice(L("Catatan terkunci tidak bisa diberi lampiran"))
            return []
        }
        var list = n.attachments ?? []
        var added: [Attachment] = []
        var tooBig = 0
        for u in urls {
            do {
                let a = try Attachments.copyIn(u, as: Attachments.uniqueName(u.lastPathComponent, in: list))
                list.append(a)
                added.append(a)
            } catch Attachments.ImportError.tooBig {
                tooBig += 1
            } catch {}
        }
        if added.isEmpty {
            noteNotice(tooBig > 0 ? L("File terlalu besar (maks. 50 MB)") : L("File tidak bisa dilampirkan"))
            return []
        }
        n.attachments = list
        commit(n)
        noteNotice(added.count == 1 ? L("Dilampirkan: %@", added[0].name) : L("%lld file dilampirkan", added.count))
        for a in added { indexAttachment(a) }
        return added
    }

    /// Tambahkan ![[gambar]] di akhir catatan (dipakai tombol 📎; tempel / seret menaruhnya di posisi kursor).
    func appendEmbeds(_ noteID: String, _ attachments: [Attachment]) {
        let names = attachments.filter(Attachments.isImage).map(\.name)
        guard let n = items[noteID], !names.isEmpty else { return }
        var body = n.parts.body
        if !body.isEmpty && !body.hasSuffix("\n") { body += "\n" }
        body += names.map { "![[\($0)]]" }.joined(separator: "\n") + "\n"
        setBody(noteID, body)
    }

    func removeAttachment(_ noteID: String, _ attID: String) {
        guard var n = items[noteID], let a = n.attachments?.first(where: { $0.id == attID }) else { return }
        n.attachments?.removeAll { $0.id == attID }
        if n.attachments?.isEmpty == true { n.attachments = nil }
        commit(n)
        Attachments.remove(a)
        noteNotice(L("Lampiran dipindahkan ke Sampah Mac"))
    }

    /// Ambil teks di belakang layar, lalu segarkan daftar (supaya hasil pencarian ikut berubah).
    func indexAttachment(_ a: Attachment) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let text = Attachments.extractText(a) ?? ""
            DispatchQueue.main.async {
                AttachmentIndex.shared.save(a.id, text)
                self?.objectWillChange.send()
            }
        }
    }

    /// Lampiran yang cocok dengan kata kunci (nama file atau isinya), plus potongan kalimat di sekitarnya.
    func attachmentHit(_ n: Item, _ query: String) -> (attachment: Attachment, context: String)? {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, !n.isLocked else { return nil }
        let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        for a in n.attachmentList {
            if a.name.range(of: q, options: opts) != nil { return (a, "") }
            if let t = AttachmentIndex.shared.text(a.id), let r = t.range(of: q, options: opts) {
                let lo = t.index(r.lowerBound, offsetBy: -40, limitedBy: t.startIndex) ?? t.startIndex
                let hi = t.index(r.upperBound, offsetBy: 90, limitedBy: t.endIndex) ?? t.endIndex
                let piece = t[lo..<hi].split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
                return (a, (lo > t.startIndex ? "…" : "") + piece + (hi < t.endIndex ? "…" : ""))
            }
        }
        return nil
    }

    /// Dipanggil setelah sinkron berhasil: unggah yang belum ada di server, unduh yang belum ada di Mac ini.
    func syncAttachmentFiles() {
        let s = AttachmentSync.shared
        guard prefs.isConfigured, !s.running, !s.unsupported else { return }
        let all = items.values.filter { $0.isNote && !$0.isDeleted && !$0.isLocked }.flatMap { $0.attachmentList }
        let now = Date()
        let uploads = all.filter { Attachments.exists($0) && !Attachments.isUploaded($0) && !s.skipUpload.contains($0.id) }
        let downloads = all.filter { a in
            !Attachments.exists(a) && (s.lastFail[a.id].map { now.timeIntervalSince($0) > 600 } ?? true)
        }
        guard !uploads.isEmpty || !downloads.isEmpty else { return }
        let token = prefs.cleanToken
        let p = prefs
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let urlFor: (Attachment, Bool) -> URL? = { a, get in
            let name = a.name.addingPercentEncoding(withAllowedCharacters: safe) ?? ""
            return p.apiURL("api/files/\(a.id)" + (get ? "?name=\(name)" : ""))
        }
        s.running = true
        s.setDownloading(Set(downloads.map(\.id)))
        Task {
            var uploaded: [Attachment] = [], tooBig: [String] = [], fetched: [Attachment] = [], failed: [String] = []
            var unsupported = false
            for a in uploads {
                guard let url = urlFor(a, false) else { continue }
                let code = await AttachmentSync.upload(a, to: url, token: token)
                if code == 200 || code == 201 { uploaded.append(a) }
                else if code == 413 { tooBig.append(a.id) }
                else if code == 404 || code == 405 { unsupported = true; break }
                else if code == 401 || code == 0 { break }
            }
            if !unsupported {
                for a in downloads {
                    guard let url = urlFor(a, true) else { continue }
                    let code = await AttachmentSync.download(a, from: url, token: token)
                    if code == 200 { fetched.append(a) } else { failed.append(a.id) }
                    if code == 401 { break }
                }
            }
            DispatchQueue.main.async { [weak self] in
                for a in uploaded { Attachments.markUploaded(a) }
                s.skipUpload.formUnion(tooBig)
                if unsupported { s.unsupported = true }
                for id in failed { s.lastFail[id] = Date() }
                s.setDownloading([])
                s.running = false
                for a in fetched { self?.indexAttachment(a) }
                if !fetched.isEmpty { self?.objectWillChange.send() }
            }
        }
    }

    /// Hapus file lampiran saat catatan dihapus permanen.
    func removeAttachmentFiles(_ n: Item) {
        for a in n.attachmentList { Attachments.remove(a) }
    }
}

// MARK: - Tampilan

/// Daftar lampiran di bawah catatan.
struct AttachmentsBar: View {
    @ObservedObject var store: NoteStore
    let note: Item
    @State private var open = true

    var body: some View {
        let list = note.attachmentList
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Divider().opacity(0.5)
                Button { open.toggle() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 8.5, weight: .bold))
                        Text("Lampiran")
                        Text("\(list.count)").foregroundStyle(.secondary).monospacedDigit()
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
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(list) { a in AttachmentRow(store: store, noteID: note.id, attachment: a) }
                        }
                    }
                    .frame(maxHeight: min(CGFloat(list.count) * 38, 160))
                    .padding(.horizontal, 6)
                    .padding(.bottom, 2)
                }
            }
        }
    }
}

struct AttachmentRow: View {
    @ObservedObject var store: NoteStore
    let noteID: String
    let attachment: Attachment
    @State private var hover = false

    var body: some View {
        let a = attachment
        let exists = Attachments.exists(a)
        Button {
            if exists { NSWorkspace.shared.open(Attachments.url(a)) }
        } label: {
            HStack(spacing: 8) {
                if exists, Attachments.isImage(a), let thumb = NSImage(contentsOf: Attachments.url(a)) {
                    Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 26, height: 26).clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Image(nsImage: Attachments.icon(a)).resizable().frame(width: 18, height: 18)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: a.name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    Text(verbatim: exists ? Attachments.sizeLabel(a)
                         : AttachmentSync.shared.downloading.contains(a.id) ? L("Mengunduh dari server…")
                         : store.prefs.isConfigured ? L("Belum ada di Mac ini · akan diunduh saat sinkron")
                         : L("File tidak ada di Mac ini"))
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if hover && exists {
                    Image(systemName: "arrow.up.forward.square").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(hover ? 0.07 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(exists ? L("Klik untuk membuka · seret untuk menyalin ke app lain") : "")
        .onDrag { exists ? (NSItemProvider(contentsOf: Attachments.url(a)) ?? NSItemProvider()) : NSItemProvider() }
        .contextMenu {
            Button("Buka file") { NSWorkspace.shared.open(Attachments.url(a)) }.disabled(!exists)
            Button("Tampilkan di Finder") { NSWorkspace.shared.activateFileViewerSelecting([Attachments.url(a)]) }.disabled(!exists)
            Divider()
            Button("Hapus lampiran", role: .destructive) { store.removeAttachment(noteID, a.id) }
        }
    }
}

/// NSTextView editor menerima file yang diseret: jadi lampiran, bukan teks path.
final class FileDropTextView: NSTextView {
    /// Diisi oleh editor yang sedang terbuka.
    static var onFiles: (([URL]) -> [Attachment])?

    /// Gambar yang baru dilampirkan ditaruh sebagai ![[nama]] di posisi kursor, di barisnya sendiri.
    private func insertEmbeds(_ added: [Attachment], at location: Int? = nil) {
        let names = added.filter(Attachments.isImage).map(\.name)
        guard !names.isEmpty else { return }
        let ns = string as NSString
        let loc = min(location ?? selectedRange().location, ns.length)
        let atLineStart = loc == 0 || ns.character(at: loc - 1) == 10
        let nextIsNewline = loc < ns.length && ns.character(at: loc) == 10
        let text = (atLineStart ? "" : "\n") + names.map { "![[\($0)]]" }.joined(separator: "\n") + (nextIsNewline ? "" : "\n")
        let range = NSRange(location: loc, length: location == nil ? selectedRange().length : 0)
        if shouldChangeText(in: range, replacementString: text) {
            replaceCharacters(in: range, with: text)
            didChangeText()
        }
    }

    private func fileURLs(_ info: NSDraggingInfo) -> [URL] {
        (info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                              options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if Self.onFiles != nil, !fileURLs(sender).isEmpty { return .copy }
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if Self.onFiles != nil, !fileURLs(sender).isEmpty { return .copy }
        return super.draggingUpdated(sender)
    }

    /// ⌘V: file yang disalin di Finder → lampiran; gambar (screenshot, salin gambar dari browser) → lampiran PNG.
    /// Teks biasa tetap ditempel seperti biasa.
    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        if let handler = Self.onFiles {
            let files = (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
            if !files.isEmpty {
                insertEmbeds(handler(files))
                return
            }
            if Self.prefersImage(pb), let url = Self.saveImage(from: pb) {
                let added = handler([url])
                try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
                insertEmbeds(added)
                return
            }
        }
        super.paste(sender)
    }

    /// Clipboard berisi gambar, bukan teks? Teks dari Word/Pages juga membawa gambar pratinjau,
    /// jadi teks kaya (RTF) atau teks berisi spasi tetap ditempel sebagai teks. Gambar dari browser
    /// atau Maccy kadang membawa URL-nya sebagai teks — itu tetap dianggap gambar.
    private static func prefersImage(_ pb: NSPasteboard) -> Bool {
        let types = pb.types ?? []
        let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff, NSPasteboard.PasteboardType("public.jpeg")]
        guard types.contains(where: imageTypes.contains) else { return false }
        if types.contains(.rtf) || types.contains(.rtfd) { return false }
        guard let text = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return true
        }
        return !text.contains(where: { $0.isWhitespace }) && (text.hasPrefix("http") || text.hasPrefix("file:") || text.hasPrefix("/"))
    }

    /// Simpan gambar di clipboard sebagai PNG sementara ("Gambar 2026-10-29 10.28.15.png").
    private static func saveImage(from pb: NSPasteboard) -> URL? {
        let data: Data?
        if let png = pb.data(forType: .png) {
            data = png
        } else if let image = NSImage(pasteboard: pb), let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff) {
            data = rep.representation(using: .png, properties: [:])
        } else {
            data = nil
        }
        guard let data else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = dir.appendingPathComponent(L("Gambar %@.png", f.string(from: Date())))
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(sender)
        if let handler = Self.onFiles, !urls.isEmpty {
            let point = convert(sender.draggingLocation, from: nil)
            let loc = characterIndexForInsertion(at: point)
            insertEmbeds(handler(urls), at: loc == NSNotFound ? nil : loc)
            return true
        }
        return super.performDragOperation(sender)
    }
}

/// ![[nama]] di mode Baca: gambar tampil di tengah catatan; file lain jadi baris yang bisa diklik.
struct EmbedView: View {
    let note: Item
    let name: String

    var body: some View {
        if let a = note.attachmentList.first(where: { $0.name.lowercased() == name.lowercased() }), Attachments.exists(a) {
            let url = Attachments.url(a)
            if Attachments.isImage(a), let img = Attachments.image(a) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: img.size.width, maxHeight: min(img.size.height, 420))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.1)))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                    .onTapGesture { NSWorkspace.shared.open(url) }
                    .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
                    .help(a.name)
            } else {
                Button { NSWorkspace.shared.open(url) } label: {
                    HStack(spacing: 6) {
                        Image(nsImage: Attachments.icon(a)).resizable().frame(width: 16, height: 16)
                        Text(verbatim: a.name).underline()
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .padding(.vertical, 2)
            }
        } else {
            Label {
                Text(verbatim: L("%@ — lampiran tidak ditemukan", name))
            } icon: {
                Image(systemName: "photo")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.vertical, 2)
        }
    }
}
