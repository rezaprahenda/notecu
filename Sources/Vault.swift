import AppKit
import CommonCrypto
import CryptoKit
import Foundation
import Security
import SwiftUI

/// Rahasia notecu: dienkripsi di Mac ini, yang tersimpan di disk hanya teks acak.
///
/// Format:
///   🔒[v1:BASE64(salt 16 B | nonce 12 B | ciphertext | tag 16 B)]
/// Kunci = PBKDF2-SHA256(kata sandi, salt, 210.000 putaran) → AES-256-GCM.
/// Kata sandi hanya disimpan di memori, dan terkunci lagi setelah 5 menit atau saat panel ditutup.
final class Vault: ObservableObject {
    static let shared = Vault()

    static let iterations: UInt32 = 210_000
    /// Menit sebelum terkunci lagi (Pengaturan → Fitur → Rahasia), bawaan 5.
    static var autoLockMinutes: Int {
        let m = UserDefaults.standard.integer(forKey: "vaultLockMinutes")
        return m > 0 ? m : 5
    }
    static var autoLock: TimeInterval { TimeInterval(autoLockMinutes * 60) }
    static let tokenRegex = try! NSRegularExpression(pattern: #"🔒\[v1:([A-Za-z0-9+/=]+)\]"#)
    static let urlScheme = "notecu-secret"

    @Published private(set) var isUnlocked = false
    /// Jendela kata sandi sedang ditampilkan.
    @Published var prompting = false
    /// Belum ada rahasia sama sekali: kata sandi baru dibuat (diminta dua kali).
    @Published private(set) var promptIsNew = false

    weak var store: NoteStore?

    private var password: String?
    private var salt: Data?
    private var keys: [Data: SymmetricKey] = [:]
    /// Isi catatan terkunci yang sedang dibuka: id -> (ciphertext, teks).
    private var plainCache: [String: (cipher: String, text: String)] = [:]
    private var pending: (() -> Void)?
    private var lockWork: DispatchWorkItem?
    private var clipWork: DispatchWorkItem?

    // MARK: - Token

    /// Isi token kalau seluruh teks adalah satu token (catatan terkunci).
    static func singlePayload(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let ns = t as NSString
        guard let m = tokenRegex.firstMatch(in: t, range: NSRange(location: 0, length: ns.length)),
              m.range.location == 0, m.range.length == ns.length else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    static func firstPayload(_ text: String) -> String? {
        let ns = text as NSString
        guard let m = tokenRegex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    /// Token diganti teks lain (untuk ringkasan / tampilan baca).
    static func replaceTokens(_ text: String, with template: String) -> String {
        guard text.contains("🔒[v1:") else { return text }
        let ns = text as NSString
        return tokenRegex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: template)
    }

    // MARK: - Kripto

    private func derive(_ salt: Data) -> SymmetricKey? {
        if let k = keys[salt] { return k }
        guard let pw = password else { return nil }
        var out = [UInt8](repeating: 0, count: 32)
        let saltBytes = [UInt8](salt)
        let status = CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pw, pw.utf8.count,
                                          saltBytes, saltBytes.count,
                                          CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), Self.iterations,
                                          &out, out.count)
        guard status == kCCSuccess else { return nil }
        let key = SymmetricKey(data: Data(out))
        keys[salt] = key
        return key
    }

    /// Teks -> token terenkripsi. nil kalau rahasia belum dibuka.
    func seal(_ plain: String) -> String? {
        guard let salt, let key = derive(salt),
              let box = try? AES.GCM.seal(Data(plain.utf8), using: key),
              let combined = box.combined else { return nil }
        return "🔒[v1:" + (salt + combined).base64EncodedString() + "]"
    }

    /// Isi token -> teks. nil kalau terkunci atau kata sandinya berbeda.
    func open(_ payload: String) -> String? {
        guard let all = Data(base64Encoded: payload), all.count >= 16 + 12 + 16 else { return nil }
        let bytes = [UInt8](all)
        guard let key = derive(Data(bytes[0..<16])),
              let box = try? AES.GCM.SealedBox(combined: Data(bytes[16...])),
              let pt = try? AES.GCM.open(box, using: key) else { return nil }
        bump()
        return String(data: pt, encoding: .utf8)
    }

    // MARK: - Kunci / buka

    /// Jalankan `action` setelah rahasia terbuka (minta kata sandi dulu kalau perlu).
    func withUnlocked(_ action: @escaping () -> Void) {
        if isUnlocked { bump(); action(); return }
        pending = action
        promptIsNew = store?.anySecretPayload() == nil
        prompting = true
    }

    /// Kata sandi dicek ke rahasia yang sudah ada, supaya semua rahasia memakai kata sandi yang sama.
    func unlock(_ pw: String) -> Bool {
        password = pw
        keys = [:]
        if let ex = store?.anySecretPayload() {
            guard open(ex) != nil, let all = Data(base64Encoded: ex) else {
                password = nil
                keys = [:]
                return false
            }
            salt = Data([UInt8](all)[0..<16])
        } else {
            var b = [UInt8](repeating: 0, count: 16)
            _ = SecRandomCopyBytes(kSecRandomDefault, b.count, &b)
            salt = Data(b)
        }
        isUnlocked = true
        prompting = false
        bump()
        let run = pending
        pending = nil
        run?()
        return true
    }

    func cancelPrompt() {
        prompting = false
        pending = nil
    }

    func lock() {
        guard isUnlocked || password != nil else { return }
        password = nil
        salt = nil
        keys = [:]
        plainCache = [:]
        lockWork?.cancel()
        isUnlocked = false
    }

    func bump() {
        guard password != nil else { return }
        lockWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.lock() }
        lockWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.autoLock, execute: w)
    }

    // MARK: - Catatan terkunci

    /// Isi catatan terkunci, kalau rahasia sedang terbuka.
    func plain(for note: Item) -> String? {
        guard isUnlocked, let payload = Self.singlePayload(note.body) else { return nil }
        if let c = plainCache[note.id], c.cipher == note.body { return c.text }
        guard let t = open(payload) else { return nil }
        plainCache[note.id] = (note.body, t)
        return t
    }

    /// Simpan teks baru catatan terkunci (dienkripsi ulang).
    func sealNote(_ id: String, _ text: String) -> String? {
        guard let token = seal(text) else { return nil }
        plainCache[id] = (token, text)
        bump()
        return token
    }

    // MARK: - Clipboard

    /// Salin, lalu bersihkan clipboard setelah 60 detik (kalau belum diganti).
    func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        let count = pb.changeCount
        clipWork?.cancel()
        let w = DispatchWorkItem {
            if NSPasteboard.general.changeCount == count { NSPasteboard.general.clearContents() }
        }
        clipWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: w)
    }
}

extension Item {
    /// Catatan yang seluruh isinya dikunci.
    var isLocked: Bool { isNote && (locked ?? false) && Vault.singlePayload(body) != nil }
}

extension NoteStore {
    /// Satu rahasia mana saja, untuk mengecek kata sandi.
    func anySecretPayload() -> String? {
        for it in items.values where it.isNote && !it.isDeleted {
            if let p = Vault.firstPayload(it.body) { return p }
        }
        return nil
    }

    /// Kunci seluruh isi catatan.
    func lockNote(_ id: String) {
        guard var n = items[id] else { return }
        let p = n.parts
        guard let token = Vault.shared.sealNote(id, p.body) else { return }
        n.title = p.title
        n.text = token
        n.locked = true
        commit(n)
    }

    /// Lepas kunci: isi disimpan biasa lagi.
    func unlockNote(_ id: String) {
        guard var n = items[id], let plain = Vault.shared.plain(for: n) else { return }
        n.text = plain
        n.locked = nil
        commit(n)
    }

    /// Editan pada catatan terkunci: dienkripsi ulang sebelum disimpan.
    func setLockedBody(_ id: String, _ text: String) {
        guard var n = items[id], let token = Vault.shared.sealNote(id, text) else { return }
        n.text = token
        commit(n)
    }
}

// MARK: - Tampilan

/// Jendela kata sandi di dalam panel.
struct VaultPromptView: View {
    @ObservedObject var vault = Vault.shared
    @State private var pw = ""
    @State private var pw2 = ""
    @State private var error = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
                .onTapGesture { vault.cancelPrompt() }
            VStack(alignment: .leading, spacing: 10) {
                Label(vault.promptIsNew ? "Buat kata sandi rahasia" : "Buka rahasia", systemImage: "lock.fill")
                    .font(.system(size: 14, weight: .bold))
                Text(vault.promptIsNew
                     ? "Dipakai untuk semua rahasia & catatan terkunci. Tidak disimpan di mana pun dan tidak bisa dipulihkan kalau lupa — simpan juga di password manager."
                     : "Masukkan kata sandi rahasia notecu. Terkunci lagi setelah \(Vault.autoLockMinutes) menit atau saat panel ditutup.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                SecureField("Kata sandi rahasia", text: $pw)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit(submit)
                if vault.promptIsNew {
                    SecureField("Ulangi kata sandi", text: $pw2)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(submit)
                }
                if !error.isEmpty {
                    Text(error).font(.system(size: 11.5)).foregroundStyle(.red)
                }
                HStack {
                    Spacer()
                    Button("Batal") { vault.cancelPrompt() }
                        .keyboardShortcut(.cancelAction)
                    Button(vault.promptIsNew ? "Simpan" : "Buka", action: submit)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
                .controlSize(.small)
            }
            .padding(16)
            .frame(width: 280)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .windowBackgroundColor)))
            .shadow(radius: 12)
        }
        .onAppear {
            pw = ""; pw2 = ""; error = ""
            DispatchQueue.main.async { focused = true }
        }
    }

    private func submit() {
        if vault.promptIsNew {
            guard pw.count >= 8 else { error = "Minimal 8 karakter."; return }
            guard pw == pw2 else { error = "Kedua kata sandi tidak sama."; return }
        }
        if !vault.unlock(pw) {
            error = "Kata sandi salah."
            pw = ""
            focused = true
        }
    }
}

/// Catatan terkunci yang belum dibuka.
struct LockedNoteView: View {
    let note: Item
    @ObservedObject var vault = Vault.shared

    var body: some View {
        VStack(spacing: 10) {
            Text(note.displayTitle)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer().frame(height: 18)
            Image(systemName: "lock.fill").font(.system(size: 28)).foregroundStyle(.secondary)
            Text("Catatan ini terkunci").font(.system(size: 13, weight: .semibold))
            Text("Isinya terenkripsi. Yang tersimpan di disk hanya teks acak.")
                .font(.system(size: 11.5)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Buka dengan kata sandi") { vault.withUnlocked {} }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
