import AppKit
import SwiftUI

/// Editor teks polos berbasis NSTextView.
/// Enter di baris checklist / poin otomatis membuat butir baru, Enter di butir kosong mengakhirinya.
struct NoteTextView: NSViewRepresentable {
    let text: String
    let onChange: (String) -> Void
    /// Naikkan angkanya untuk memfokuskan editor.
    var focusToken: Int
    /// Naikkan angkanya untuk menyisipkan "- [ ] " di posisi kursor.
    var checklistToken: Int
    /// Naikkan angkanya untuk merahasiakan teks yang diblok.
    var secretToken: Int = 0
    /// Teks terpilih -> token rahasia (dipanggil balik lewat `done`, nil = batal).
    var onSecret: ((String, @escaping (String?) -> Void) -> Void)? = nil
    /// Teks setelah "[[" di posisi kursor (nil = tidak sedang menautkan).
    var onLinkQuery: ((String?) -> Void)? = nil
    /// Naikkan angkanya untuk menyisipkan [[linkTitle]] di posisi kursor.
    var linkToken: Int = 0
    var linkTitle: String = ""
    /// Saran pertama, dipakai saat menekan Tab.
    var firstLinkCandidate: ((String) -> String?)? = nil
    /// Fokus ke editor begitu muncul.
    var autofocus: Bool = true
    /// "sans" atau "serif"
    var fontStyle: String = "sans"
    /// Lampiran catatan: gambar di baris ![[nama]] ditampilkan di bawah barisnya.
    var attachments: [Attachment] = []

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// Sans: huruf sistem 14. Serif: New York 15.
    static func font(_ style: String) -> NSFont {
        if style == "serif", let d = NSFont.systemFont(ofSize: 15).fontDescriptor.withDesign(.serif), let f = NSFont(descriptor: d, size: 15) {
            return f
        }
        return .systemFont(ofSize: 14)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        let tv = scroll.documentView as! NSTextView
        // File yang diseret ke editor jadi lampiran (lihat FileDropTextView).
        object_setClass(tv, FileDropTextView.self)
        tv.registerForDraggedTypes([.fileURL])
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.font = NoteTextView.font(fontStyle)
        tv.textColor = .labelColor
        tv.insertionPointColor = .controlAccentColor
        tv.textContainerInset = NSSize(width: 12, height: 12)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 3
        tv.defaultParagraphStyle = para
        tv.typingAttributes = [.font: NoteTextView.font(fontStyle), .foregroundColor: NSColor.labelColor, .paragraphStyle: para]
        context.coordinator.lastFont = fontStyle
        tv.string = text

        context.coordinator.textView = tv
        context.coordinator.lastAttachments = attachments
        tv.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.frameChanged),
                                               name: NSView.frameDidChangeNotification, object: tv)
        context.coordinator.scheduleEmbeds()
        context.coordinator.lastFocus = focusToken
        context.coordinator.lastChecklist = checklistToken
        context.coordinator.lastSecret = secretToken
        context.coordinator.lastLink = linkToken
        if autofocus {
            DispatchQueue.main.async {
                tv.window?.makeFirstResponder(tv)
                tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
            }
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        c.parent = self
        guard let tv = c.textView else { return }
        if c.lastFont != fontStyle {
            c.lastFont = fontStyle
            let f = NoteTextView.font(fontStyle)
            tv.font = f
            tv.typingAttributes[.font] = f
            c.scheduleEmbeds()
        }
        if attachments != c.lastAttachments {
            c.lastAttachments = attachments
            c.scheduleEmbeds()
        }

        if tv.string != text {
            // Perubahan datang dari perangkat lain.
            let sel = tv.selectedRange()
            tv.string = text
            let len = (text as NSString).length
            tv.setSelectedRange(NSRange(location: min(sel.location, len), length: 0))
            c.scheduleEmbeds()
        }
        if focusToken != c.lastFocus {
            c.lastFocus = focusToken
            DispatchQueue.main.async {
                tv.window?.makeFirstResponder(tv)
                let s = tv.string
                // Kerangka agenda yang belum diisi: kursor langsung di butir Peserta.
                if NoteText.isUntouchedTemplate(s),
                   let r = s.range(of: "- ") {
                    tv.setSelectedRange(NSRange(location: s.distance(from: s.startIndex, to: r.upperBound), length: 0))
                } else {
                    tv.setSelectedRange(NSRange(location: (s as NSString).length, length: 0))
                }
            }
        }
        if linkToken != c.lastLink {
            c.lastLink = linkToken
            let t = linkTitle
            DispatchQueue.main.async { c.insertLink(t) }
        }
        if secretToken != c.lastSecret {
            c.lastSecret = secretToken
            DispatchQueue.main.async { c.makeSecret() }
        }
        if checklistToken != c.lastChecklist {
            c.lastChecklist = checklistToken
            DispatchQueue.main.async { c.insertChecklist() }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteTextView
        weak var textView: NSTextView?
        var lastFocus = 0
        var lastChecklist = 0
        var lastSecret = 0
        var lastLink = 0
        private var lastQuery: String?
        var lastFont = ""
        var lastAttachments: [Attachment] = []
        private var embedPending = false
        private var hadEmbeds = false
        private var placements: [(range: NSRange, image: NSImage, url: URL, size: CGSize)] = []
        private var embedViews: [EmbedImageView] = []

        private static let listPattern = try! NSRegularExpression(pattern: #"^(\s*)(- \[[ xX]\] |- |\* |\d+[.)] )"#)

        init(_ parent: NoteTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            parent.onChange(tv.string)
            reportLinkQuery()
            scheduleEmbeds()
        }

        // MARK: Gambar di mode Tulis

        /// Hitung ulang sekali di putaran berikutnya (bukan di tengah proses mengetik).
        func scheduleEmbeds() {
            guard !embedPending else { return }
            embedPending = true
            DispatchQueue.main.async { [weak self] in
                self?.embedPending = false
                self?.applyEmbeds()
            }
        }

        @objc func frameChanged() { layoutEmbeds() }

        /// Baris ![[gambar]] diberi ruang di bawahnya (paragraphSpacing) dan teksnya dibuat redup.
        /// Teks catatan sendiri tidak berubah sama sekali.
        private func applyEmbeds() {
            guard let tv = textView, let storage = tv.textStorage, let tc = tv.textContainer else { return }
            let ns = tv.string as NSString
            var found: [(range: NSRange, image: NSImage, url: URL, size: CGSize)] = []
            var embedLines: [NSRange] = []
            let maxW = max(80, tv.bounds.width - tv.textContainerInset.width * 2 - tc.lineFragmentPadding * 2)

            if tv.string.contains("![[") {
                var start = 0
                while start < ns.length {
                    let lr = ns.lineRange(for: NSRange(location: start, length: 0))
                    let line = ns.substring(with: lr).trimmingCharacters(in: .newlines)
                    if let name = NoteText.embedName(line) {
                        embedLines.append(lr)
                        if let a = parent.attachments.first(where: { $0.name.lowercased() == name.lowercased() }),
                           Attachments.isImage(a), Attachments.exists(a),
                           let img = Attachments.image(a), img.size.width > 0, img.size.height > 0 {
                            var size = CGSize(width: min(img.size.width, maxW), height: 0)
                            size.height = img.size.height * size.width / img.size.width
                            if size.height > 200 { size = CGSize(width: size.width * 200 / size.height, height: 200) }
                            found.append((lr, img, Attachments.url(a), size))
                        }
                    }
                    start = NSMaxRange(lr)
                }
            }
            guard hadEmbeds || !embedLines.isEmpty else { return }

            let full = NSRange(location: 0, length: ns.length)
            let para = NSMutableParagraphStyle()
            para.lineSpacing = 3
            storage.beginEditing()
            storage.addAttribute(.paragraphStyle, value: para, range: full)
            let baseFont = NoteTextView.font(parent.fontStyle)
            storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: full)
            storage.addAttribute(.font, value: baseFont, range: full)
            let labelFont = NSFont.systemFont(ofSize: 10.5)
            for lr in embedLines {
                storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: lr)
                storage.addAttribute(.font, value: labelFont, range: lr)
            }
            for f in found {
                let p = NSMutableParagraphStyle()
                p.lineSpacing = 3
                p.paragraphSpacing = f.size.height + 12
                storage.addAttribute(.paragraphStyle, value: p, range: f.range)
            }
            storage.endEditing()
            tv.typingAttributes[.paragraphStyle] = para
            tv.typingAttributes[.foregroundColor] = NSColor.labelColor
            tv.typingAttributes[.font] = baseFont

            placements = found
            hadEmbeds = !embedLines.isEmpty
            layoutEmbeds()
        }

        /// Taruh gambar tepat di bawah barisnya.
        private func layoutEmbeds() {
            guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
            let ns = tv.string as NSString
            var shown = 0
            if !placements.isEmpty { lm.ensureLayout(for: tc) }
            for p in placements where NSMaxRange(p.range) <= ns.length {
                var len = p.range.length
                while len > 1 && ns.character(at: p.range.location + len - 1) == 10 { len -= 1 }
                let glyphs = lm.glyphRange(forCharacterRange: NSRange(location: p.range.location, length: max(1, len)),
                                           actualCharacterRange: nil)
                guard glyphs.length > 0 else { continue }
                let used = lm.lineFragmentUsedRect(forGlyphAt: NSMaxRange(glyphs) - 1, effectiveRange: nil)
                let origin = tv.textContainerOrigin
                let frame = NSRect(x: origin.x + tc.lineFragmentPadding, y: origin.y + used.maxY + 5,
                                   width: p.size.width, height: p.size.height)
                let v: EmbedImageView
                if shown < embedViews.count {
                    v = embedViews[shown]
                } else {
                    v = EmbedImageView()
                    tv.addSubview(v)
                    embedViews.append(v)
                }
                v.image = p.image
                v.url = p.url
                v.frame = frame
                shown += 1
            }
            while embedViews.count > shown { embedViews.removeLast().removeFromSuperview() }
        }

        func textViewDidChangeSelection(_ notification: Notification) { reportLinkQuery() }

        /// Teks setelah "[[" yang belum ditutup, di posisi kursor.
        func linkQuery() -> String? {
            guard let tv = textView else { return nil }
            let sel = tv.selectedRange()
            guard sel.length == 0 else { return nil }
            let before = (tv.string as NSString).substring(to: sel.location)
            guard let r = before.range(of: "[[", options: .backwards) else { return nil }
            let q = String(before[r.upperBound...])
            if q.contains("]") || q.contains("[") || q.contains("\n") { return nil }
            return q
        }

        private func reportLinkQuery() {
            let q = linkQuery()
            guard q != lastQuery else { return }
            lastQuery = q
            let cb = parent.onLinkQuery
            DispatchQueue.main.async { cb?(q) }
        }

        /// Ganti "[[kata" di depan kursor dengan "[[Judul]]".
        func insertLink(_ title: String) {
            guard let tv = textView, linkQuery() != nil else { return }
            let ns = tv.string as NSString
            let sel = tv.selectedRange()
            let before = ns.substring(to: sel.location) as NSString
            let start = before.range(of: "[[", options: .backwards).location
            guard start != NSNotFound else { return }
            var end = sel.location
            if ns.length >= end + 2, ns.substring(with: NSRange(location: end, length: 2)) == "]]" { end += 2 }
            tv.window?.makeFirstResponder(tv)
            tv.insertText("[[\(title)]]", replacementRange: NSRange(location: start, length: end - start))
        }

        func textView(_ tv: NSTextView, doCommandBy selector: Selector) -> Bool {
            // Tab saat mengetik [[...: pakai saran pertama
            if selector == #selector(NSResponder.insertTab(_:)), let q = linkQuery(),
               let first = parent.firstLinkCandidate?(q) {
                insertLink(first)
                return true
            }
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            let ns = tv.string as NSString
            let sel = tv.selectedRange()
            guard sel.length == 0 else { return false }
            let lineStart = ns.lineRange(for: NSRange(location: sel.location, length: 0)).location
            let before = ns.substring(with: NSRange(location: lineStart, length: sel.location - lineStart))
            let beforeNS = before as NSString
            guard let m = Self.listPattern.firstMatch(in: before, range: NSRange(location: 0, length: beforeNS.length)) else {
                return false
            }
            let indent = beforeNS.substring(with: m.range(at: 1))
            let marker = beforeNS.substring(with: m.range(at: 2))
            if before.trimmingCharacters(in: .whitespaces) == marker.trimmingCharacters(in: .whitespaces) {
                // Butir kosong: hapus penandanya, berhenti membuat daftar.
                tv.insertText("", replacementRange: NSRange(location: lineStart, length: sel.location - lineStart))
            } else {
                var fresh = marker.replacingOccurrences(of: #"\[[xX]\]"#, with: "[ ]", options: .regularExpression)
                // 1. -> 2.
                if let num = Int(marker.prefix { $0.isNumber }) {
                    let sep = marker.contains(")") ? ")" : "."
                    fresh = "\(num + 1)\(sep) "
                }
                tv.insertText("\n" + indent + fresh, replacementRange: sel)
            }
            return true
        }

        /// Teks yang diblok diganti token rahasia (bisa di-undo).
        func makeSecret() {
            guard let tv = textView, let onSecret = parent.onSecret else { return }
            let sel = tv.selectedRange()
            let ns = tv.string as NSString
            guard sel.length > 0 else { NSSound.beep(); return }
            let chosen = ns.substring(with: sel)
            guard !chosen.contains("🔒[v1:") else { return }
            let before = tv.string
            onSecret(chosen) { [weak tv] token in
                guard let tv, let token, tv.string == before else { return }
                tv.window?.makeFirstResponder(tv)
                tv.insertText(token, replacementRange: sel)
            }
        }

        func insertChecklist() {
            guard let tv = textView else { return }
            tv.window?.makeFirstResponder(tv)
            let ns = tv.string as NSString
            let sel = tv.selectedRange()
            let lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))
            var line = ns.substring(with: lineRange)
            if line.hasSuffix("\n") { line.removeLast() }
            if line.range(of: #"^\s*- \[[ xX]\] "#, options: .regularExpression) != nil { return }
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                tv.insertText("- [ ] ", replacementRange: NSRange(location: lineRange.location, length: (line as NSString).length))
            } else {
                let end = lineRange.location + (line as NSString).length
                tv.insertText("\n- [ ] ", replacementRange: NSRange(location: end, length: 0))
            }
        }
    }
}

/// Gambar di dalam editor. Klik untuk membuka file-nya.
final class EmbedImageView: NSImageView {
    var url: URL?

    override init(frame: NSRect) {
        super.init(frame: frame)
        imageScaling = .scaleProportionallyUpOrDown
        isEditable = false
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor
        unregisterDraggedTypes()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        if let url { NSWorkspace.shared.open(url) }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
