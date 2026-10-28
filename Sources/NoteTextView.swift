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
        }

        if tv.string != text {
            // Perubahan datang dari perangkat lain.
            let sel = tv.selectedRange()
            tv.string = text
            let len = (text as NSString).length
            tv.setSelectedRange(NSRange(location: min(sel.location, len), length: 0))
        }
        if focusToken != c.lastFocus {
            c.lastFocus = focusToken
            DispatchQueue.main.async {
                tv.window?.makeFirstResponder(tv)
                let s = tv.string
                // Kerangka agenda yang belum diisi: kursor langsung di butir Peserta.
                if s.trimmingCharacters(in: .whitespacesAndNewlines) == NoteText.agendaTemplate.trimmingCharacters(in: .whitespacesAndNewlines),
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

        private static let listPattern = try! NSRegularExpression(pattern: #"^(\s*)(- \[[ xX]\] |- |\* |\d+[.)] )"#)

        init(_ parent: NoteTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            parent.onChange(tv.string)
            reportLinkQuery()
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
