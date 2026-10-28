import AppKit
import Carbon
import Combine
import ServiceManagement
import SwiftUI

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let prefs = Prefs()
    private lazy var store = NoteStore(prefs: prefs)
    private var panel: PanelController?
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var statusLine: NSMenuItem?
    private var syncItem: NSMenuItem?
    private var keepOpenItem: NSMenuItem?
    private var edgeItems: [NSMenuItem] = []
    private var hoverItem: NSMenuItem?
    private var loginItem: NSMenuItem?
    private var settingsWindow: NSWindow?
    private var hotKeys: [HotKey] = []
    private var reminders: Reminders?
    private var cancellables = Set<AnyCancellable>()
    private var badgeTimer: Timer?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // tanpa ikon di Dock
        withExtendedLifetime(delegate) {
            app.run()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let p = PanelController(store: store, prefs: prefs)
        p.ui.openSettings = { [weak self] in self?.openSettings() }
        panel = p
        setupStatusItem()

        // ⌃⌥N buka/tutup panel, ⌃⌥⇧N langsung catatan baru
        hotKeys.append(HotKey(id: 1, keyCode: kVK_ANSI_N, modifiers: controlKey | optionKey) { [weak self] in
            self?.panel?.toggle()
        })
        hotKeys.append(HotKey(id: 2, keyCode: kVK_ANSI_N, modifiers: controlKey | optionKey | shiftKey) { [weak self] in
            self?.panel?.newNoteFromAnywhere()
        })
        // ⌃⌥T tugas baru
        hotKeys.append(HotKey(id: 3, keyCode: kVK_ANSI_T, modifiers: controlKey | optionKey) { [weak self] in
            self?.panel?.newTaskFromAnywhere()
        })

        let r = Reminders(store: store, prefs: prefs)
        r.onOpenTask = { [weak self] id in self?.panel?.openTask(id) }
        reminders = r

        // Angka di menu bar: tugas terlambat + hari ini
        store.$items
            .debounce(for: .seconds(0.3), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.updateBadge() }
            .store(in: &cancellables)
        let t = Timer(timeInterval: 300, repeats: true) { [weak self] _ in self?.updateBadge() }
        RunLoop.main.add(t, forMode: .common)
        badgeTimer = t

        store.sync()
        store.setPolling(fast: false)

        // Pertama kali dipakai: langsung tampilkan panelnya.
        if !prefs.isConfigured && store.items.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.panel?.show() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveNow()
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.menuBarImage()
        item.button?.imagePosition = .imageLeading
        item.button?.toolTip = "notecu (⌃⌥N)"
        item.button?.target = self
        item.button?.action = #selector(statusClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        let line = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        line.isEnabled = false
        menu.addItem(line)
        statusLine = line
        menu.addItem(.separator())

        menu.addItem(makeItem("Buka notecu", #selector(togglePanel), key: "n", mods: [.control, .option]))
        menu.addItem(makeItem("Catatan baru", #selector(newNote), key: "N", mods: [.control, .option, .shift]))
        menu.addItem(makeItem("To-do baru", #selector(newTask), key: "t", mods: [.control, .option]))
        menu.addItem(makeItem("Agenda baru", #selector(dailyNote)))
        let sync = makeItem("Sinkron sekarang", #selector(syncNow))
        menu.addItem(sync)
        syncItem = sync
        menu.addItem(.separator())

        let keep = makeItem("Biarkan panel tetap terbuka", #selector(toggleKeepOpen))
        menu.addItem(keep)
        keepOpenItem = keep

        let hover = makeItem("Buka saat kursor ke tepi layar", #selector(toggleHover))
        menu.addItem(hover)
        hoverItem = hover

        let edge = NSMenuItem(title: L("Muncul dari tepi"), action: nil, keyEquivalent: "")
        let edgeMenu = NSMenu()
        edgeMenu.autoenablesItems = false
        for (title, value) in [("Kanan", "right"), ("Kiri", "left")] {
            let choice = makeItem(title, #selector(setEdge(_:)))
            choice.representedObject = value
            edgeMenu.addItem(choice)
            edgeItems.append(choice)
        }
        edge.submenu = edgeMenu
        menu.addItem(edge)

        let login = makeItem("Jalankan saat login", #selector(toggleLaunchAtLogin))
        menu.addItem(login)
        loginItem = login

        menu.addItem(.separator())
        menu.addItem(makeItem("Tentang notecu", #selector(openSettings)))
        menu.addItem(makeItem("Pengaturan…", #selector(openSettings), key: ","))
        menu.addItem(makeItem("Keluar notecu", #selector(quitApp), key: "q"))

        statusMenu = menu
        statusItem = item
    }

    private func makeItem(_ title: String, _ action: Selector, key: String = "", mods: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
        let i = NSMenuItem(title: L(title), action: action, keyEquivalent: key)
        i.keyEquivalentModifierMask = mods
        i.target = self
        return i
    }

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if wantsMenu, let menu = statusMenu, let item = statusItem {
            item.menu = menu
            item.button?.performClick(nil)
            item.menu = nil
        } else {
            panel?.toggle()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        // Sinkron itu opsional: tanpa server, baris status cukup berisi ringkasan to-do.
        var parts: [String] = []
        if prefs.isConfigured {
            switch store.status {
            case .ok: parts.append(L("Tersinkron dengan server"))
            case .saving: parts.append(L("Menyimpan ke server…"))
            case .connecting: parts.append(L("Menghubungkan…"))
            case .offline: parts.append(store.pendingCount > 0 ? L("Offline · %lld perubahan menunggu", store.pendingCount) : L("Server tidak terjangkau"))
            case .badToken: parts.append(L("Token ditolak server"))
            case .notConfigured: break
            }
        } else {
            parts.append("notecu")
        }
        let due = store.dueCount
        parts.append(due > 0 ? L("%lld to-do perlu dibereskan", due) : L("semua beres"))
        statusLine?.title = parts.joined(separator: " · ")
        syncItem?.isHidden = !prefs.isConfigured
        keepOpenItem?.state = panel?.ui.keepOpen == true ? .on : .off
        hoverItem?.state = prefs.hoverOpen ? .on : .off
        for i in edgeItems { i.state = (i.representedObject as? String) == prefs.edge ? .on : .off }
        loginItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func togglePanel() { panel?.toggle() }
    @objc private func newNote() { panel?.newNoteFromAnywhere() }
    @objc private func newTask() { panel?.newTaskFromAnywhere() }
    @objc private func dailyNote() { panel?.openDailyNote() }

    private func updateBadge() {
        guard let button = statusItem?.button else { return }
        let n = store.dueCount
        if n > 0 {
            button.attributedTitle = NSAttributedString(string: " \(n)", attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
                .baselineOffset: 0.5,
            ])
            button.toolTip = L("notecu · %lld to-do terlambat atau jatuh tempo hari ini", n)
        } else {
            button.attributedTitle = NSAttributedString(string: "")
            button.toolTip = "notecu (⌃⌥N)"
        }
    }
    @objc private func syncNow() { store.sync() }
    @objc private func toggleKeepOpen() { panel?.ui.keepOpen.toggle() }
    @objc private func toggleHover() { prefs.hoverOpen.toggle() }

    @objc private func setEdge(_ sender: NSMenuItem) {
        guard let v = sender.representedObject as? String else { return }
        prefs.edge = v
        panel?.relayout()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSSound.beep()
        }
    }

    @objc private func quitApp() {
        store.saveNow()
        NSApp.terminate(nil)
    }

    // MARK: - Pengaturan

    @objc func openSettings() {
        panel?.hide()
        if settingsWindow == nil {
            let view = SettingsView(prefs: prefs, store: store) { [weak self] in self?.panel?.relayout() }
            let host = NSHostingController(rootView: view)
            let w = NSWindow(contentViewController: host)
            w.title = L("Pengaturan notecu")
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Ikon menu bar: lembar miring dengan sudut terlipat

    static func menuBarImage() -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.translateBy(x: 9, y: 9)
            ctx.rotate(by: 9 * .pi / 180)
            ctx.translateBy(x: -9, y: -9)

            let x: CGFloat = 3.5, y: CGFloat = 2.5, w: CGFloat = 11, h: CGFloat = 13.5, fold: CGFloat = 4
            NSColor.black.set()

            let page = NSBezierPath()
            page.move(to: NSPoint(x: x + fold, y: y + h))
            page.line(to: NSPoint(x: x + w, y: y + h))
            page.line(to: NSPoint(x: x + w, y: y))
            page.line(to: NSPoint(x: x, y: y))
            page.line(to: NSPoint(x: x, y: y + h - fold))
            page.close()
            page.lineWidth = 1.4
            page.lineJoinStyle = .round
            page.stroke()

            let corner = NSBezierPath()
            corner.move(to: NSPoint(x: x, y: y + h - fold))
            corner.line(to: NSPoint(x: x + fold, y: y + h))
            corner.line(to: NSPoint(x: x + fold, y: y + h - fold))
            corner.close()
            corner.fill()

            for (i, len) in [CGFloat(6.5), 4.5].enumerated() {
                let ly = y + h - fold - 3.2 - CGFloat(i) * 2.8
                let l = NSBezierPath()
                l.move(to: NSPoint(x: x + 2.5, y: ly))
                l.line(to: NSPoint(x: x + 2.5 + len, y: ly))
                l.lineWidth = 1.2
                l.lineCapStyle = .round
                l.stroke()
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}
