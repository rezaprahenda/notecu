import Combine
import Foundation
import UserNotifications

/// Pengingat tugas lewat Notification Center macOS.
/// Setiap kali tugas berubah, jadwal notifikasi notecu disusun ulang.
final class Reminders: NSObject, UNUserNotificationCenterDelegate {
    private let store: NoteStore
    private let prefs: Prefs
    private var cancellables = Set<AnyCancellable>()
    private static let prefix = "notecu.task."
    /// Dipanggil saat notifikasi diklik.
    var onOpenTask: (String) -> Void = { _ in }

    init(store: NoteStore, prefs: Prefs) {
        self.store = store
        self.prefs = prefs
        super.init()
        UNUserNotificationCenter.current().delegate = self

        store.$items
            .combineLatest(prefs.$remindersOn, prefs.$reminderTime)
            .debounce(for: .seconds(1.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.reschedule() }
            .store(in: &cancellables)

        // Minta izin sekali, saat ada tugas bertenggat pertama kali.
        prefs.$remindersOn
            .sink { [weak self] on in if on { self?.requestPermissionIfNeeded() } }
            .store(in: &cancellables)
    }

    func requestPermissionIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    func reschedule() {
        let center = UNUserNotificationCenter.current()
        let on = prefs.remindersOn
        let defaultTime = prefs.reminderTime
        let now = Date()
        let upcoming: [(Item, Date)] = store.tasks
            .filter { !$0.isDone && $0.due != nil }
            .compactMap { t in
                guard let due = t.due, let fire = DueDate.fireDate(due: due, time: t.dueTime, defaultTime: defaultTime), fire > now else { return nil }
                return (t, fire)
            }
            .sorted { $0.1 < $1.1 }
        let next = Array(upcoming.prefix(60))   // macOS membatasi jumlah notifikasi terjadwal

        center.getPendingNotificationRequests { requests in
            let ours = requests.map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)
            guard on else { return }
            for (task, fire) in next {
                let content = UNMutableNotificationContent()
                content.title = task.displayTitle
                content.body = task.dueTime != nil ? L("Jatuh tempo %@", DueDate.label(task)) : L("Jatuh tempo hari ini")
                content.sound = .default
                content.userInfo = ["taskId": task.id]
                let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                let id = Self.prefix + task.id + "." + String(Int(fire.timeIntervalSince1970))
                center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            }
        }
    }

    // Tampilkan juga saat notecu sedang dipakai.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let id = response.notification.request.content.userInfo["taskId"] as? String {
            DispatchQueue.main.async { self.onOpenTask(id) }
        }
        completionHandler()
    }
}
