import Combine
import Foundation
import ServiceManagement

/// Menu bar'da hangi metriklerin görüneceğini ve örnekleme aralığını tutar.
/// UserDefaults'a yazıp okuyarak kalıcı hale getirir; @Published olduğu için
/// değişiklikte hem menu bar etiketi hem ayar arayüzü anında güncellenir.
final class AppSettings: ObservableObject {

    @Published var showCPU: Bool { didSet { save(\.showCPU, "showCPU") } }
    @Published var showRAM: Bool { didSet { save(\.showRAM, "showRAM") } }
    @Published var showDisk: Bool { didSet { save(\.showDisk, "showDisk") } }
    @Published var showNetwork: Bool { didSet { save(\.showNetwork, "showNetwork") } }
    @Published var showIcons: Bool { didSet { save(\.showIcons, "showIcons") } }

    /// Örnekleme aralığı (saniye).
    @Published var refreshInterval: Double { didSet { save(\.refreshInterval, "refreshInterval") } }

    /// Açılışta otomatik başlat. Kaynağı sistemdir (SMAppService), UserDefaults değil;
    /// kullanıcı System Settings'ten kapatsa bile tutarlı kalır.
    @Published var launchAtLogin: Bool {
        didSet {
            guard !suppressLaunchApply else { return }
            applyLaunchAtLogin()
        }
    }
    private var suppressLaunchApply = false

    init() {
        let d = UserDefaults.standard
        showCPU = d.object(forKey: "showCPU") as? Bool ?? true
        showRAM = d.object(forKey: "showRAM") as? Bool ?? true
        showDisk = d.object(forKey: "showDisk") as? Bool ?? false
        showNetwork = d.object(forKey: "showNetwork") as? Bool ?? false
        showIcons = d.object(forKey: "showIcons") as? Bool ?? true
        refreshInterval = d.object(forKey: "refreshInterval") as? Double ?? 1.0
        // didSet init sırasında tetiklenmez; mevcut sistem durumunu yansıt.
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            // Bundle dışı çalışma (swift run) veya imza sorununda gerçek duruma dön.
            suppressLaunchApply = true
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
            suppressLaunchApply = false
        }
    }

    private func save<T>(_ keyPath: KeyPath<AppSettings, T>, _ key: String) {
        UserDefaults.standard.set(self[keyPath: keyPath], forKey: key)
    }
}
