import AppKit
import SwiftUI

/// Panel yang bisa jadi key window (untuk mengetik) tanpa mengaktifkan app,
/// jadi app yang sedang kamu pakai tetap di depan.
final class SidePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Klik pertama langsung bekerja walau panel belum aktif.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class PanelController {
    let ui = PanelUI()
    private let store: NoteStore
    private let prefs: Prefs
    private let panel: SidePanel

    private(set) var isShown = false
    /// Dibuka dengan mendorong kursor ke tepi; tertutup lagi kalau kursor pergi sebelum dipakai.
    private var openedByHover = false
    private var interacted = false
    private var lastHide = Date.distantPast
    private var monitors: [Any] = []
    private var dwellWork: DispatchWorkItem?
    private var resignWork: DispatchWorkItem?

    init(store: NoteStore, prefs: Prefs) {
        self.store = store
        self.prefs = prefs
        Vault.shared.store = store

        panel = SidePanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 600),
                          styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered,
                          defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false

        let host = FirstMouseHostingView(rootView: PanelRootView(store: store, prefs: prefs, ui: ui))
        host.sizingOptions = []
        panel.contentView = host

        ui.hidePanel = { [weak self] in self?.hide() }
        ui.resizePanel = { [weak self] x in self?.resize(toMouseX: x) }
        ui.relayoutPanel = { [weak self] in self?.relayout() }
        ui.refocusPanel = { [weak self] in self?.panel.makeKey() }

        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            self?.panelResignedKey()
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.isShown else { return }
            self.panel.setFrame(self.frames(on: self.currentScreen()).shown, display: true)
        }
        installMonitors()
    }

    // MARK: - Tampil / sembunyi

    func toggle() {
        if isShown { hide() }
        // Klik ikon menu bar membuat panel kehilangan fokus dulu (lalu tertutup); jangan langsung dibuka lagi.
        else if Date().timeIntervalSince(lastHide) > 0.3 { show() }
    }

    func show(byHover: Bool = false) {
        if isShown {
            if !byHover { activateForTyping() }
            return
        }
        isShown = true
        openedByHover = byHover
        interacted = !byHover

        let f = frames(on: currentScreen())
        panel.setFrame(f.hidden, display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        if !byHover { activateForTyping() }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(f.shown, display: true)
            panel.animator().alphaValue = 1
        }
        store.sync()
        store.setPolling(fast: true)
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        lastHide = Date()
        cancelDwell()
        if let id = ui.openID { store.closeNote(id) }
        // Rahasia ikut terkunci saat panel ditutup.
        Vault.shared.cancelPrompt()
        Vault.shared.lock()
        store.saveNow()
        store.sync()
        store.setPolling(fast: false)

        let hidden = frames(on: panel.screen ?? currentScreen()).hidden
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(hidden, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, !self.isShown else { return }
            self.panel.orderOut(nil)
        })
    }

    /// Jadikan panel tujuan ketikan dan fokuskan pencarian / editor.
    private func activateForTyping() {
        interacted = true
        panel.makeKey()
        if ui.openID != nil { ui.focusEditor += 1 } else { ui.focusSearch += 1 }
    }

    func newNoteFromAnywhere() {
        show()
        var folder: String? = nil
        if case .folder(let id) = ui.filter { folder = id }
        let id = store.createNote(folder: folder, pinned: ui.filter == .pinned)
        if ui.filter == .trash || ui.filter == .tasks { ui.filter = .all }
        ui.openTaskID = nil
        ui.query = ""
        ui.readMode = false
        ui.wantsTitleFocus = true
        ui.openID = id
    }

    func newTaskFromAnywhere() {
        show()
        ui.openID = nil
        ui.openTaskID = nil
        ui.query = ""
        if ui.filter != .tasks {
            ui.focusTaskFormOnAppear = true
            ui.filter = .tasks
        } else {
            ui.focusTaskForm += 1
        }
    }

    /// Agenda baru hari ini (⌘D, menu bar).
    func openDailyNote() {
        show()
        let id = store.newAgenda()
        if ui.filter == .trash || ui.filter == .tasks {
            ui.filter = .daily
            ui.dailyMonth = String(DueDate.today().prefix(4))
            ui.tag = nil
        }
        if let t = ui.tag { store.addTag(id, t) }
        ui.openTaskID = nil
        ui.query = ""
        ui.readMode = false
        ui.wantsTitleFocus = true
        ui.openID = id
    }

    /// Dari notifikasi: buka panel langsung di tugasnya.
    func openTask(_ id: String) {
        show()
        ui.filter = .tasks
        ui.openID = nil
        ui.openTaskID = id
    }

    private func panelResignedKey() {
        resignWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self, self.isShown, !self.panel.isKeyWindow, !self.ui.keepOpen, !self.ui.holdOpen else { return }
            self.hide()
        }
        resignWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: w)
    }

    // MARK: - Posisi

    private func currentScreen() -> NSScreen {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func frames(on screen: NSScreen) -> (shown: NSRect, hidden: NSRect) {
        let vf = screen.visibleFrame
        let w = min(max(CGFloat(prefs.panelWidth), Self.minWidth), Self.maxWidth(vf))
        let margin: CGFloat = 8
        let h = vf.height - margin * 2
        let y = vf.minY + margin
        let slide: CGFloat = 36
        if prefs.edge == "left" {
            let shown = NSRect(x: vf.minX + margin, y: y, width: w, height: h)
            return (shown, shown.offsetBy(dx: -slide, dy: 0))
        } else {
            let shown = NSRect(x: vf.maxX - w - margin, y: y, width: w, height: h)
            return (shown, shown.offsetBy(dx: slide, dy: 0))
        }
    }

    static let minWidth: CGFloat = 300
    static func maxWidth(_ vf: NSRect) -> CGFloat { max(minWidth, min(900, vf.width * 0.7)) }

    /// Tarik tepi dalam panel: lebar mengikuti posisi kursor, langsung disimpan.
    func resize(toMouseX x: CGFloat) {
        guard isShown else { return }
        let vf = (panel.screen ?? currentScreen()).visibleFrame
        let margin: CGFloat = 8
        let raw = prefs.edge == "left" ? x - (vf.minX + margin) : (vf.maxX - margin) - x
        let w = min(max(raw, Self.minWidth), Self.maxWidth(vf)).rounded()
        guard abs(CGFloat(prefs.panelWidth) - w) >= 1 else { return }
        prefs.panelWidth = Double(w)
        panel.setFrame(frames(on: panel.screen ?? currentScreen()).shown, display: true, animate: false)
    }

    /// Dipanggil saat lebar / sisi diubah di pengaturan.
    func relayout() {
        guard isShown else { return }
        panel.setFrame(frames(on: panel.screen ?? currentScreen()).shown, display: true, animate: true)
    }

    // MARK: - Mouse & keyboard

    private func installMonitors() {
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: { [weak self] _ in
            self?.mouseMoved()
        }) { monitors.append(m) }

        if let m = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { [weak self] e in
            self?.mouseMoved()
            return e
        }) { monitors.append(m) }

        // Klik di luar panel saat dibuka lewat tepi (belum dipakai) -> tutup.
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            guard let self, self.isShown, !self.ui.keepOpen, !self.panel.isKeyWindow else { return }
            self.hide()
        }) { monitors.append(m) }

        if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown], handler: { [weak self] e in
            guard let self else { return e }
            if e.window === self.panel {
                self.interacted = true
                if e.type == .keyDown, let handled = self.handleKey(e), handled { return nil }
            }
            return e
        }) { monitors.append(m) }
    }

    /// Shortcut di dalam panel. App ini tidak punya menu Edit, jadi ⌘C / ⌘V dkk. ditangani di sini.
    private func handleKey(_ e: NSEvent) -> Bool? {
        let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if e.keyCode == 53 && flags.isEmpty {           // Esc
            if ui.addingFolder { return false }
            hide()
            return true
        }
        guard flags.contains(.command), !flags.contains(.control), !flags.contains(.option) else { return false }
        let shift = flags.contains(.shift)
        let key = e.charactersIgnoringModifiers?.lowercased() ?? ""
        let send: (Selector) -> Bool = { NSApp.sendAction($0, to: nil, from: self.panel); return true }
        switch key {
        case "c": return send(#selector(NSText.copy(_:)))
        case "v": return shift ? send(#selector(NSTextView.pasteAsPlainText(_:))) : send(#selector(NSText.paste(_:)))
        case "x": return send(#selector(NSText.cut(_:)))
        case "a": return send(#selector(NSText.selectAll(_:)))
        case "z": return shift ? send(Selector(("redo:"))) : send(Selector(("undo:")))
        case "n": newNoteFromAnywhere(); return true
        case "f": ui.openID = nil; ui.openTaskID = nil; ui.focusSearch += 1; return true
        case "d": openDailyNote(); return true
        case "t": newTaskFromAnywhere(); return true
        case "l": ui.secret += 1; return true
        case "w": hide(); return true
        case "[": ui.openID = nil; ui.openTaskID = nil; return true
        default: return false
        }
    }

    private func mouseMoved() {
        let p = NSEvent.mouseLocation
        if isShown {
            // Dibuka lewat tepi tapi belum dipakai: tutup lagi kalau kursor menjauh.
            if openedByHover && !interacted && !ui.keepOpen && !panel.frame.insetBy(dx: -40, dy: -40).contains(p) {
                hide()
            }
            return
        }
        guard prefs.hoverOpen, let screen = NSScreen.screens.first(where: { NSMouseInRect(p, $0.frame, false) }) else {
            cancelDwell()
            return
        }
        if atEdge(p, screen) {
            if dwellWork == nil {
                let w = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.dwellWork = nil
                    let q = NSEvent.mouseLocation
                    if let s = NSScreen.screens.first(where: { NSMouseInRect(q, $0.frame, false) }), self.atEdge(q, s), NSEvent.pressedMouseButtons == 0 {
                        self.show(byHover: true)
                    }
                }
                dwellWork = w
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: w)
            }
        } else {
            cancelDwell()
        }
    }

    private func atEdge(_ p: NSPoint, _ screen: NSScreen) -> Bool {
        let f = screen.frame
        let x = prefs.edge == "left" ? p.x <= f.minX + 1 : p.x >= f.maxX - 1
        // Hanya bagian tengah tepi, supaya pojok (Hot Corners, menu bar, Dock) tidak terganggu.
        let band = p.y > f.minY + f.height * 0.15 && p.y < f.maxY - f.height * 0.15
        return x && band
    }

    private func cancelDwell() {
        dwellWork?.cancel()
        dwellWork = nil
    }
}
