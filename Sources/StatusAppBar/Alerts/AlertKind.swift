import Foundation

/// İzlenen uyarı türleri.
///
/// Dört kural bilinçli olarak az tutuldu. Her ek kural yanlış-pozitif riski
/// getirir; yanlış-pozitif üreten bir uyarı sistemi kapatılır ve hiçbir işe
/// yaramaz. Bu dördü "fan neden dönüyor" sorusunun pratikteki cevaplarının
/// tamamına yakınını kapsıyor.
enum AlertKind: String, CaseIterable, Identifiable {
    /// Swap doluluğu — RAM yetmiyor, sistem diske takas yapıyor.
    case swapPressure
    /// Tek bir proses çekirdekleri doldurmuş.
    case cpuHog
    /// Sistem kendini kısıyor ya da kernel_task yükü fırlamış.
    case thermal
    /// Uzun uptime / birikmiş bellek sızıntısı.
    case uptimeLeak
    /// Pilden anormal yüksek güç çekiliyor.
    case batteryDrain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .swapPressure: return String(localized: "Bellek baskısı")
        case .cpuHog:       return String(localized: "CPU canavarı")
        case .thermal:      return String(localized: "Termal baskı")
        case .uptimeLeak:   return String(localized: "Uzun uptime")
        case .batteryDrain: return String(localized: "Pil tüketimi")
        }
    }

    var icon: String {
        switch self {
        case .swapPressure: return "memorychip.fill"
        case .cpuHog:       return "flame.fill"
        case .thermal:      return "thermometer.high"
        case .uptimeLeak:   return "clock.arrow.circlepath"
        case .batteryDrain: return "battery.25percent"
        }
    }

    /// Tetiklendikten sonra uyarıya dönüşmesi için koşulun kaç saniye
    /// kesintisiz sürmesi gerektiği. Anlık tepeler (build, uygulama açılışı)
    /// bildirime dönüşmesin diye.
    var dwell: TimeInterval {
        switch self {
        case .swapPressure: return 60
        case .cpuHog:       return 180
        case .thermal:      return 90
        case .uptimeLeak:   return 0
        case .batteryDrain: return 120
        }
    }

    /// Bu tür için özel bekleme süresi (yoksa kullanıcının genel ayarı).
    /// Uptime uyarısı bir "durum" değil "hatırlatma"; günde bir yeter.
    var cooldownOverride: TimeInterval? {
        switch self {
        case .uptimeLeak: return 24 * 3600
        default:          return nil
        }
    }
}

/// Uyarı ağırlığı. Menü çubuğu rengi ve sıralama bunu kullanır.
enum AlertSeverity: Int, Comparable {
    case info = 0
    case warning = 1
    case critical = 2

    static func < (a: AlertSeverity, b: AlertSeverity) -> Bool { a.rawValue < b.rawValue }
}

/// Şu an aktif olan bir uyarı.
struct ActiveAlert: Identifiable, Equatable {
    var kind: AlertKind
    var severity: AlertSeverity
    /// Tek satırlık başlık — "Swap %92 dolu"
    var headline: String
    /// Kanıt satırı — "en çok yiyen: qemu-system-aarch64 · 5.6 GB"
    var detail: String
    /// Ne yapmalı — eyleme dönük, tek cümle.
    var advice: String
    var culprit: ProcessRow?
    var since: Date

    var id: String { kind.rawValue }
}
