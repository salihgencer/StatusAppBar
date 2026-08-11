import Combine
import Foundation
import ServiceManagement

/// Menu bar'da hangi metriklerin görüneceğini, örnekleme aralığını ve uyarı
/// eşiklerini tutar. UserDefaults'a yazıp okuyarak kalıcı hale getirir.
///
/// `shared` singleton: MetricsManager arka planda uyarı değerlendirirken
/// eşiklere erişmek zorunda; iki ayrı örnek olsaydı arayüzden değiştirilen
/// eşik motora ulaşmazdı.
final class AppSettings: ObservableObject {

    static let shared = AppSettings()

    // MARK: - Menu bar içeriği

    @Published var showCPU: Bool { didSet { save(showCPU, "showCPU") } }
    @Published var showRAM: Bool { didSet { save(showRAM, "showRAM") } }
    @Published var showDisk: Bool { didSet { save(showDisk, "showDisk") } }
    @Published var showNetwork: Bool { didSet { save(showNetwork, "showNetwork") } }
    @Published var showIcons: Bool { didSet { save(showIcons, "showIcons") } }

    /// Menu bar etiketinin genişlik davranışı.
    @Published var menuBarMode: MenuBarMode { didSet { save(menuBarMode.rawValue, "menuBarMode") } }

    /// Örnekleme aralığı (saniye).
    @Published var refreshInterval: Double { didSet { save(refreshInterval, "refreshInterval") } }

    // MARK: - Uyarılar

    @Published var alertsEnabled: Bool { didSet { save(alertsEnabled, "alertsEnabled") } }
    @Published var alertSwap: Bool { didSet { save(alertSwap, "alertSwap") } }
    @Published var alertCPUHog: Bool { didSet { save(alertCPUHog, "alertCPUHog") } }
    @Published var alertThermal: Bool { didSet { save(alertThermal, "alertThermal") } }
    @Published var alertUptime: Bool { didSet { save(alertUptime, "alertUptime") } }
    @Published var alertBattery: Bool { didSet { save(alertBattery, "alertBattery") } }

    /// Swap doluluk eşiği (%). Temizlenme eşiği bunun 15 puan altıdır.
    @Published var swapWarnPercent: Double { didSet { save(swapWarnPercent, "swapWarnPercent") } }
    /// Tek proses CPU eşiği (%). 200 = iki çekirdek.
    @Published var cpuHogPercent: Double { didSet { save(cpuHogPercent, "cpuHogPercent") } }
    /// Uptime hatırlatma eşiği (gün).
    @Published var uptimeWarnDays: Double { didSet { save(uptimeWarnDays, "uptimeWarnDays") } }
    /// Pil deşarj eşiği (watt).
    @Published var batteryDrainWatts: Double { didSet { save(batteryDrainWatts, "batteryDrainWatts") } }
    /// Aynı uyarı için iki bildirim arası minimum süre (dakika).
    @Published var alertCooldownMinutes: Double { didSet { save(alertCooldownMinutes, "alertCooldownMinutes") } }
    /// Kritik uyarılarda ses. Varsayılan kapalı — sessiz mod istendi.
    @Published var alertSound: Bool { didSet { save(alertSound, "alertSound") } }

    // MARK: - Derin analiz (AI) — yalnızca ücretli MAS sürümü

    #if MAS
    /// Seçili sağlayıcı (AIProvider rawValue olarak saklanır — UserDefaults
    /// dostu).
    @Published var aiProviderRaw: String { didSet { save(aiProviderRaw, "aiProvider") } }

    @Published var geminiAPIKey: String { didSet { save(geminiAPIKey, "geminiAPIKey") } }
    @Published var geminiModel: String { didSet { save(geminiModel, "geminiModel") } }
    @Published var anthropicAPIKey: String { didSet { save(anthropicAPIKey, "anthropicAPIKey") } }
    @Published var anthropicModel: String { didSet { save(anthropicModel, "anthropicModel") } }
    @Published var openaiAPIKey: String { didSet { save(openaiAPIKey, "openaiAPIKey") } }
    @Published var openaiModel: String { didSet { save(openaiModel, "openaiModel") } }
    @Published var ollamaURL: String { didSet { save(ollamaURL, "ollamaURL") } }
    @Published var ollamaModel: String { didSet { save(ollamaModel, "ollamaModel") } }
    @Published var lmstudioURL: String { didSet { save(lmstudioURL, "lmstudioURL") } }
    @Published var lmstudioModel: String { didSet { save(lmstudioModel, "lmstudioModel") } }

    var aiProvider: AIProvider { AIProvider(rawValue: aiProviderRaw) ?? .gemini }

    /// Seçili sağlayıcı sohbet başlatmaya hazır mı (buton enable + ipucu
    /// metinleri bunu kullanır).
    var aiConfigured: Bool {
        switch aiProvider {
        case .gemini:    return !geminiAPIKey.isEmpty
        case .anthropic: return !anthropicAPIKey.isEmpty && !anthropicModel.isEmpty
        case .openai:    return !openaiAPIKey.isEmpty
        case .ollama:    return !ollamaModel.isEmpty
        case .lmstudio:  return true // model boşsa sunucudaki ilk model seçilir
        case .demo:      return true // anahtar gerektirmez
        }
    }
    #endif

    // MARK: - Açılışta başlat

    /// Kaynağı sistemdir (SMAppService), UserDefaults değil; kullanıcı System
    /// Settings'ten kapatsa bile tutarlı kalır.
    @Published var launchAtLogin: Bool {
        didSet {
            guard !suppressLaunchApply else { return }
            applyLaunchAtLogin()
        }
    }
    private var suppressLaunchApply = false

    // MARK: - Kurulum

    init() {
        let d = UserDefaults.standard

        showCPU = d.object(forKey: "showCPU") as? Bool ?? true
        showRAM = d.object(forKey: "showRAM") as? Bool ?? true
        showDisk = d.object(forKey: "showDisk") as? Bool ?? false
        showNetwork = d.object(forKey: "showNetwork") as? Bool ?? false
        showIcons = d.object(forKey: "showIcons") as? Bool ?? true

        // Varsayılan .adaptive: çentikli MacBook'ta menu bar dolunca geniş
        // etiket çentiğin altına itilip GÖRÜNMEZ oluyor. Dar başlamak
        // görünürlüğü garantiler; gerektiğinde kendisi genişler.
        menuBarMode = MenuBarMode(rawValue: d.string(forKey: "menuBarMode") ?? "")
            ?? .adaptive

        // Varsayılan 2 sn: 1 sn'de bir menu bar etiketini yeniden RENDER etmek
        // ölçülebilir CPU yakıyordu (izleme aracının kendisi ilk 10 tüketici
        // arasına giriyordu). 2 sn hiçbir bilgi kaybettirmiyor.
        refreshInterval = d.object(forKey: "refreshInterval") as? Double ?? 2.0

        alertsEnabled = d.object(forKey: "alertsEnabled") as? Bool ?? true
        alertSwap = d.object(forKey: "alertSwap") as? Bool ?? true
        alertCPUHog = d.object(forKey: "alertCPUHog") as? Bool ?? true
        alertThermal = d.object(forKey: "alertThermal") as? Bool ?? true
        alertUptime = d.object(forKey: "alertUptime") as? Bool ?? true
        alertBattery = d.object(forKey: "alertBattery") as? Bool ?? true

        swapWarnPercent = d.object(forKey: "swapWarnPercent") as? Double ?? 75
        cpuHogPercent = d.object(forKey: "cpuHogPercent") as? Double ?? 200
        uptimeWarnDays = d.object(forKey: "uptimeWarnDays") as? Double ?? 7
        batteryDrainWatts = d.object(forKey: "batteryDrainWatts") as? Double ?? 20
        alertCooldownMinutes = d.object(forKey: "alertCooldownMinutes") as? Double ?? 30
        alertSound = d.object(forKey: "alertSound") as? Bool ?? false

        #if MAS
        aiProviderRaw = d.string(forKey: "aiProvider") ?? AIProvider.gemini.rawValue
        geminiAPIKey = d.string(forKey: "geminiAPIKey") ?? ""
        geminiModel = d.string(forKey: "geminiModel") ?? AIProvider.gemini.defaultModel
        anthropicAPIKey = d.string(forKey: "anthropicAPIKey") ?? ""
        anthropicModel = d.string(forKey: "anthropicModel") ?? AIProvider.anthropic.defaultModel
        openaiAPIKey = d.string(forKey: "openaiAPIKey") ?? ""
        openaiModel = d.string(forKey: "openaiModel") ?? AIProvider.openai.defaultModel
        ollamaURL = d.string(forKey: "ollamaURL") ?? AIProvider.ollama.defaultBaseURL
        ollamaModel = d.string(forKey: "ollamaModel") ?? AIProvider.ollama.defaultModel
        lmstudioURL = d.string(forKey: "lmstudioURL") ?? AIProvider.lmstudio.defaultBaseURL
        lmstudioModel = d.string(forKey: "lmstudioModel") ?? AIProvider.lmstudio.defaultModel
        #endif

        // didSet init sırasında tetiklenmez; mevcut sistem durumunu yansıt.
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
            // Bundle dışı çalışma (swift run) veya imza sorununda gerçek duruma dön.
            suppressLaunchApply = true
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
            suppressLaunchApply = false
        }
    }

    private func save(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}

/// Menu bar etiketinin genişlik stratejisi.
enum MenuBarMode: String, CaseIterable, Identifiable {
    /// Sadece renkli nokta (~12 px). Hiçbir zaman yer sorunu yaratmaz.
    case minimal
    /// Nokta + tek en kritik metrik (~46 px).
    case compact
    /// Seçili tüm metrikler (~110 px+). Çentikli ekranda gizlenme riski var.
    case full
    /// Sakinken minimal, stres veya uyarı varken compact.
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
