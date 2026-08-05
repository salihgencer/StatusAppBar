import AppKit
import Foundation
import UserNotifications

/// macOS bildirimlerini gönderir.
///
/// ÜCRETSİZ SÜRÜMDE İKİ YOL VAR:
/// 1. `UNUserNotificationCenter` — doğru yol. Ama gerçek bir .app bundle
///    gerektirir; `swift run` ile çalıştırınca `Bundle.main.bundleIdentifier`
///    nil olur ve `UNUserNotificationCenter.current()` çağrısı CRASH eder.
/// 2. `osascript` yedeği — ücretsiz sürüm ad-hoc imzalı (TeamIdentifier yok).
///    Bildirim izni reddedilir ya da kayıt düşerse UN sessizce başarısız olur;
///    o durumda kullanıcının hiçbir uyarı almaması en kötü senaryo.
///
/// MAS sürümünde yedek YOK: sandbox'ta `osascript` spawn edilemez ve Apple
/// Events engellenir. Ücretli takım imzasıyla UN zaten çalışır — tek yol UN.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {

    /// Tek örnek: izin AppDelegate'te isteniyor, bildirimler AlertEngine'den
    /// atılıyor. İki ayrı örnek olsaydı ikincisi izinsiz kalırdı.
    static let shared = Notifier()

    /// Bundle yoksa UN'e hiç dokunma — çağrının kendisi crash sebebi.
    private var hasBundle: Bool { Bundle.main.bundleIdentifier != nil }

    private var didRequestAuthorization = false

    /// Son bilinen izin durumu — ayar panelinde göstermek için.
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    /// Yedeğe düştüysek bir daha UN'i denemeyelim (her seferinde 1 hata logu).
    /// Yalnızca ücretsiz sürümde anlamlı — MAS'ta yedek yol yok.
    private(set) var forceFallback = false

    /// Kullanıcıya gösterilecek durum metni. Bildirim zinciri sessizce
    /// bozulabildiği için bu bilgiyi gizlemek doğru olmaz.
    var statusText: String {
        #if MAS
        switch authorizationStatus {
        case .authorized, .provisional:
            return String(localized: "Bildirimler açık")
        case .denied:
            return String(localized: "Bildirim izni kapalı — Sistem Ayarları → Bildirimler'den aç")
        case .notDetermined:
            return String(localized: "Bildirim izni bekleniyor")
        @unknown default:
            return String(localized: "Bildirim durumu bilinmiyor")
        }
        #else
        if !hasBundle { return String(localized: "Bundle dışı çalışıyor — yedek yol kullanılıyor") }
        switch authorizationStatus {
        case .authorized, .provisional:
            return String(localized: "Bildirimler açık")
        case .denied:
            return String(localized: "macOS bildirim izni vermedi — yedek yol (Script Editor) kullanılıyor")
        case .notDetermined:
            return forceFallback
                ? String(localized: "Bildirim izni alınamadı — yedek yol kullanılıyor")
                : String(localized: "Bildirim izni bekleniyor")
        @unknown default:
            return String(localized: "Bildirim durumu bilinmiyor")
        }
        #endif
    }

    var isHealthy: Bool {
        hasBundle && (authorizationStatus == .authorized || authorizationStatus == .provisional)
    }

    // MARK: - İzin

    /// İZİN NE ZAMAN İSTENİR — bu sıralama önemli.
    ///
    /// `requestAuthorization`'ı `@StateObject` kurulumu sırasında çağırmak
    /// SESSİZCE başarısız oluyor: o anda uygulama henüz Launch Services'e tam
    /// kaydolmamış oluyor ve istek Notification Center'a hiç ulaşmıyor —
    /// uygulama bildirim ayarlarında görünmüyor bile. Doğru yer
    /// `applicationDidFinishLaunching`.
    func requestAuthorization() {
        guard hasBundle, !didRequestAuthorization else { return }
        didRequestAuthorization = true

        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            Self.log("requestAuthorization granted=\(granted) error=\(error.map(String.init(describing:)) ?? "yok")")
            // Completion handler izolasyonsuz bir arka plan thread'inde çağrılır;
            // durum alanları MainActor'e ait olduğu için oraya geçiyoruz.
            Task { @MainActor [weak self] in
                if !granted { self?.forceFallback = true }
                self?.refreshStatus()
            }
        }
    }

    /// Teşhis logu. Bildirim zinciri sessizce bozulabildiği için (izin düşmesi,
    /// imza sorunu) ne olduğunu görebilmek şart.
    ///
    /// Dosyaya da yazıyoruz: uygulama `open` ile başlatıldığında stderr
    /// hiçbir yere gitmiyor, yani tam da sorunu araştırmak istediğimiz
    /// senaryoda log kayboluyor.
    nonisolated static func log(_ message: String) {
        let line = "[\(Date().formatted(date: .omitted, time: .standard))] \(message)\n"
        FileHandle.standardError.write(Data("[Notifier] \(line)".utf8))

        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs", isDirectory: true)
        let url = dir.appendingPathComponent("StatusAppBar.log")
        guard let data = line.data(using: .utf8) else { return }

        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    func refreshStatus() {
        guard hasBundle else {
            #if !MAS
            Self.log("bundle yok -> UN devre disi, osascript yedegi kullanilacak")
            #endif
            return
        }
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let status = settings.authorizationStatus
            Self.log("authorizationStatus=\(status.rawValue) (0=belirsiz 1=red 2=izinli)")
            Task { @MainActor [weak self] in
                self?.authorizationStatus = status
            }
        }
    }

    /// Kullanıcının bildirim zincirini uçtan uca doğrulaması için.
    /// Ad-hoc imzalı bir uygulamada bu doğrulama olmadan sistemin sessizce
    /// çalışmadığını fark etmenin yolu yok.
    func sendTest() {
        post(
            title: String(localized: "StatusAppBar test bildirimi"),
            body: String(localized: "Bunu gördüysen uyarı zinciri çalışıyor."),
            sound: false,
            identifier: "test"
        )
    }

    /// Uygulama menu bar'da (accessory) çalıştığı için "ön planda" sayılabiliyor;
    /// bu delege olmadan bildirim hiç görünmeyebilir.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    // MARK: - Gönderim

    func post(title: String, body: String, sound: Bool, identifier: String) {
        #if MAS
        // MAS'ta yedek yol yok; bundle her zaman var, UN tek kanal.
        guard hasBundle else { return }
        #else
        guard hasBundle, !forceFallback else {
            fallback(title: title, body: body)
            return
        }
        #endif

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound { content.sound = .default }
        // Aynı türden yeni uyarı eskisinin yerine geçsin (bildirim yığılmasın).
        content.threadIdentifier = identifier

        let request = UNNotificationRequest(
            identifier: "\(identifier)-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { [weak self] error in
            guard let error else { return }
            Self.log("UN add hatasi: \(error)")
            #if !MAS
            Task { @MainActor [weak self] in
                self?.forceFallback = true
                self?.fallback(title: title, body: body)
            }
            #endif
        }
    }

    // MARK: - Yedek (yalnızca ücretsiz sürüm — sandbox'ta osascript çalışmaz)

    #if !MAS
    private func fallback(title: String, body: String) {
        let script = "display notification \"\(escape(body))\" with title \"\(escape(title))\""
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        task.standardError = FileHandle.nullDevice
        task.standardOutput = FileHandle.nullDevice
        try? task.run()
    }

    /// AppleScript string literal kaçışı. Ters bölü ÖNCE gelmeli, yoksa
    /// tırnak için eklediğimiz kaçışı ikinci geçişte tekrar kaçırırız.
    private func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }
    #endif
}
