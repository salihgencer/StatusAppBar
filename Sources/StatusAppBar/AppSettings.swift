import Combine
import Foundation

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

    init() {
        let d = UserDefaults.standard
        showCPU = d.object(forKey: "showCPU") as? Bool ?? true
        showRAM = d.object(forKey: "showRAM") as? Bool ?? true
        showDisk = d.object(forKey: "showDisk") as? Bool ?? false
        showNetwork = d.object(forKey: "showNetwork") as? Bool ?? false
        showIcons = d.object(forKey: "showIcons") as? Bool ?? true
        refreshInterval = d.object(forKey: "refreshInterval") as? Double ?? 1.0
    }

    private func save<T>(_ keyPath: KeyPath<AppSettings, T>, _ key: String) {
        UserDefaults.standard.set(self[keyPath: keyPath], forKey: key)
    }
}
