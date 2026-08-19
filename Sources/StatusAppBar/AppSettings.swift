import Foundation
import Observation
import ServiceManagement

/// Menu bar'da hangi metriklerin görüneceğini, örnekleme aralığını ve uyarı
/// eşiklerini tutar. UserDefaults'a yazıp okuyarak kalıcı hale getirir.
///
/// `shared` singleton: MetricsManager arka planda uyarı değerlendirirken
/// eşiklere erişmek zorunda; iki ayrı örnek olsaydı arayüzden değiştirilen
/// eşik motora ulaşmazdı.
@Observable
final class AppSettings {

    static let shared = AppSettings()

    // MARK: - UserDefaults yardımcısı

    @ObservationIgnored private let defaults = UserDefaults.standard

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }

    private static func bool(_ key: String, default d: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? d
    }

    private static func double(_ key: String, default d: Double) -> Double {
        UserDefaults.standard.object(forKey: key) as? Double ?? d
    }

    private static func string(_ key: String, default d: String) -> String {
        UserDefaults.standard.string(forKey: key) ?? d
    }

    // MARK: - Menu bar içeriği

    var showCPU: Bool { didSet { save(showCPU, "showCPU") } }
    var showRAM: Bool { didSet { save(showRAM, "showRAM") } }
    var showDisk: Bool { didSet { save(showDisk, "showDisk") } }
    var showNetwork: Bool { didSet { save(showNetwork, "showNetwork") } }
    var showIcons: Bool { didSet { save(showIcons, "showIcons") } }

    /// Menu bar etiketinin genişlik davranışı.
    var menuBarMode: MenuBarMode { didSet { save(menuBarMode.rawValue, "menuBarMode") } }

    /// Örnekleme aralığı (saniye).
    var refreshInterval: Double { didSet { save(refreshInterval, "refreshInterval") } }

    // MARK: - Uyarılar

    var alertsEnabled: Bool { didSet { save(alertsEnabled, "alertsEnabled") } }
    var alertSwap: Bool { didSet { save(alertSwap, "alertSwap") } }
    var alertCPUHog: Bool { didSet { save(alertCPUHog, "alertCPUHog") } }
    var alertThermal: Bool { didSet { save(alertThermal, "alertThermal") } }
    var alertUptime: Bool { didSet { save(alertUptime, "alertUptime") } }
    var alertBattery: Bool { didSet { save(alertBattery, "alertBattery") } }

    /// Swap doluluk eşiği (%). Temizlenme eşiği bunun 15 puan altıdır.
    var swapWarnPercent: Double { didSet { save(swapWarnPercent, "swapWarnPercent") } }
    /// Tek proses CPU eşiği (%). 200 = iki çekirdek.
    var cpuHogPercent: Double { didSet { save(cpuHogPercent, "cpuHogPercent") } }
    /// Uptime hatırlatma eşiği (gün).
    var uptimeWarnDays: Double { didSet { save(uptimeWarnDays, "uptimeWarnDays") } }
    /// Pil deşarj eşiği (watt).
    var batteryDrainWatts: Double { didSet { save(batteryDrainWatts, "batteryDrainWatts") } }
    /// Aynı uyarı için iki bildirim arası minimum süre (dakika).
    var alertCooldownMinutes: Double { didSet { save(alertCooldownMinutes, "alertCooldownMinutes") } }
    /// Kritik uyarılarda ses. Varsayılan kapalı — sessiz mod istendi.
    var alertSound: Bool { didSet { save(alertSound, "alertSound") } }

    // MARK: - Derin analiz (AI) — yalnızca ücretli MAS sürümü

    #if MAS
    /// Seçili sağlayıcı (AIProvider rawValue olarak saklanır — UserDefaults
    /// dostu).
    var aiProviderRaw: String { didSet { save(aiProviderRaw, "aiProvider") } }

    var geminiAPIKey: String { didSet { save(geminiAPIKey, "geminiAPIKey") } }
    var geminiModel: String { didSet { save(geminiModel, "geminiModel") } }
    var anthropicAPIKey: String { didSet { save(anthropicAPIKey, "anthropicAPIKey") } }
    var anthropicModel: String { didSet { save(anthropicModel, "anthropicModel") } }
    var openaiAPIKey: String { didSet { save(openaiAPIKey, "openaiAPIKey") } }
    var openaiModel: String { didSet { save(openaiModel, "openaiModel") } }
    var ollamaURL: String { didSet { save(ollamaURL, "ollamaURL") } }
    var ollamaModel: String { didSet { save(ollamaModel, "ollamaModel") } }
    var lmstudioURL: String { didSet { save(lmstudioURL, "lmstudioURL") } }
    var lmstudioModel: String { didSet { save(lmstudioModel, "lmstudioModel") } }

    var aiProvider: AIProvider { AIProvider(rawValue: aiProviderRaw) ?? .gemini }

    /// Seçili sağlayıcı sohbet başlatmaya hazır mı (buton enable + ipucu
    /// metinleri bunu kullanır).
    var aiConfigured: Bool {
        switch aiProvider {
        case .gemini:    return !geminiAPIKey.isEmpty
        case .anthropic: return !anthropicAPIKey.isEmpty && !anthropicModel.isEmpty
        case .openai:    return !openaiAPIKey.isEmpty
        case .ollama:    return !ollamaModel.isEmpty
        case .lmstudio:  return true
        case .demo:      return true
        }
    }
    #endif

    // MARK: - Açılışta başlat

    /// Kaynağı sistemdir (SMAppService), UserDefaults değil; kullanıcı System
    /// Settings'ten kapatsa bile tutarlı kalır.
    var launchAtLogin: Bool {
        didSet {
            guard !suppressLaunchApply else { return }
            applyLaunchAtLogin()
        }
    }
    @ObservationIgnored private var suppressLaunchApply = false

    // MARK: - Kurulum

    init() {
        showCPU = Self.bool("showCPU", default: true)
        showRAM = Self.bool("showRAM", default: true)
        showDisk = Self.bool("showDisk", default: false)
        showNetwork = Self.bool("showNetwork", default: false)
        showIcons = Self.bool("showIcons", default: true)

        menuBarMode = MenuBarMode(rawValue: UserDefaults.standard.string(forKey: "menuBarMode") ?? "")
            ?? .adaptive

        refreshInterval = Self.double("refreshInterval", default: 2.0)

        alertsEnabled = Self.bool("alertsEnabled", default: true)
        alertSwap = Self.bool("alertSwap", default: true)
        alertCPUHog = Self.bool("alertCPUHog", default: true)
        alertThermal = Self.bool("alertThermal", default: true)
        alertUptime = Self.bool("alertUptime", default: true)
        alertBattery = Self.bool("alertBattery", default: true)

        swapWarnPercent = Self.double("swapWarnPercent", default: 75)
        cpuHogPercent = Self.double("cpuHogPercent", default: 200)
        uptimeWarnDays = Self.double("uptimeWarnDays", default: 7)
        batteryDrainWatts = Self.double("batteryDrainWatts", default: 20)
        alertCooldownMinutes = Self.double("alertCooldownMinutes", default: 30)
        alertSound = Self.bool("alertSound", default: false)

        #if MAS
        aiProviderRaw = Self.string("aiProvider", default: AIProvider.gemini.rawValue)
        geminiAPIKey = Self.string("geminiAPIKey", default: "")
        geminiModel = Self.string("geminiModel", default: AIProvider.gemini.defaultModel)
        anthropicAPIKey = Self.string("anthropicAPIKey", default: "")
        anthropicModel = Self.string("anthropicModel", default: AIProvider.anthropic.defaultModel)
        openaiAPIKey = Self.string("openaiAPIKey", default: "")
        openaiModel = Self.string("openaiModel", default: AIProvider.openai.defaultModel)
        ollamaURL = Self.string("ollamaURL", default: AIProvider.ollama.defaultBaseURL)
        ollamaModel = Self.string("ollamaModel", default: AIProvider.ollama.defaultModel)
        lmstudioURL = Self.string("lmstudioURL", default: AIProvider.lmstudio.defaultBaseURL)
        lmstudioModel = Self.string("lmstudioModel", default: AIProvider.lmstudio.defaultModel)
        #endif

        launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }

    // MARK: - Yardımcılar

    /// Bir uyarı türü açık mı.
    func isEnabled(_ kind: AlertKind) -> Bool {
        switch kind {
        case .swapPressure: return alertSwap
        case .cpuHog:       return alertCPUHog
        case .thermal:      return alertThermal
        case .uptimeLeak:   return alertUptime
        case .batteryDrain: return alertBattery
        }
    }

    func setEnabled(_ kind: AlertKind, _ value: Bool) {
        switch kind {
        case .swapPressure: alertSwap = value
        case .cpuHog:       alertCPUHog = value
        case .thermal:      alertThermal = value
        case .uptimeLeak:   alertUptime = value
        case .batteryDrain: alertBattery = value
        }
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
            suppressLaunchApply = true
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
            suppressLaunchApply = false
        }
    }
}

/// Menu bar etiketinin genişlik stratejisi.
enum MenuBarMode: String, CaseIterable, Identifiable {
    case minimal
    case compact
    case full
    case adaptive

    var id: String { rawValue }

    var label: String {
        switch self {
        case .minimal:  return String(localized: "Nokta")
        case .compact:  return String(localized: "Dar")
        case .full:     return String(localized: "Tam")
        case .adaptive: return String(localized: "Otomatik")
        }
    }
}
