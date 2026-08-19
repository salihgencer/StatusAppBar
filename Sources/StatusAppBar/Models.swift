import Foundation

// MARK: - Metric snapshot modelleri
// Her monitor, anlık bir okuma sonucunu bu değer tipleri (struct) ile döndürür.
// Değer tipi olmaları, sampling'i arka plan kuyruğunda yapıp sonucu güvenle
// main thread'e taşımayı kolaylaştırır.

nonisolated struct CPUMetrics {
    var total: Double = 0          // 0...1 toplam kullanım
    var cores: [Double] = []       // çekirdek başına 0...1
    var load: [Double] = [0, 0, 0] // 1, 5, 15 dakikalık load average
    var pCores: Int = 0            // performance core sayısı
    var eCores: Int = 0            // efficiency core sayısı
}

nonisolated struct MemoryMetrics {
    var total: UInt64 = 0
    var used: UInt64 = 0
    var free: UInt64 = 0
    var swapTotal: UInt64 = 0
    var swapUsed: UInt64 = 0

    /// Compressor'ın tuttuğu (sıkıştırılmış) bellek. Yüksekse sistem RAM
    /// yetmediği için sürekli sıkıştır/aç yapıyor demektir — CPU yakar, ısıtır.
    var compressed: UInt64 = 0

    /// Saniyedeki swap giriş/çıkışı (sayfa değil, byte). Sıfırdan farklıysa
    /// sistem aktif olarak diske takas yapıyor: gerçek darboğaz göstergesi.
    var swapInsPerSec: Double = 0
    var swapOutsPerSec: Double = 0

    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
    var freeFraction: Double { total > 0 ? Double(free) / Double(total) : 0 }
    var swapFraction: Double { swapTotal > 0 ? Double(swapUsed) / Double(swapTotal) : 0 }
    var compressedFraction: Double { total > 0 ? Double(compressed) / Double(total) : 0 }

    /// Swap trafiği var mı (thrashing sinyali).
    var isThrashing: Bool { swapInsPerSec + swapOutsPerSec > 1024 * 1024 }
}

nonisolated struct DiskVolume: Identifiable {
    let id = UUID()
    var name: String
    var total: UInt64
    var free: UInt64

    var used: UInt64 { total >= free ? total - free : 0 }
    var fraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

nonisolated struct DiskMetrics {
    var volumes: [DiskVolume] = []
    var readPerSec: Double = 0   // bytes/sn
    var writePerSec: Double = 0  // bytes/sn
}

nonisolated struct PowerMetrics {
    var hasBattery: Bool = false
    var level: Double = 0          // 0...1
    var isCharging: Bool = false
    var isCharged: Bool = false
    var onAC: Bool = false
    var cycleCount: Int = 0
    var temperature: Double = 0    // °C
    var healthPercent: Double = 0  // 0...100 (maxCapacity / designCapacity)
    var adapterWatts: Int = 0
    var timeRemainingMinutes: Int = -1 // -1 => bilinmiyor / hesaplanıyor

    /// Anlık akım (mA). Pozitif = şarj oluyor, negatif = pilden çekiliyor.
    var amperageMA: Int = 0
    /// Anlık pil voltajı (mV).
    var voltageMV: Int = 0

    /// Anlık güç (watt). İşaretsiz — yön için `isDischarging`'e bak.
    /// "İnanılmaz pil harcıyor" şikayetini sayıya çeviren tek metrik budur.
    var watts: Double { Double(abs(amperageMA)) * Double(voltageMV) / 1_000_000.0 }

    var isDischarging: Bool { hasBattery && !onAC && amperageMA < 0 }
}

nonisolated struct NetworkMetrics {
    var downPerSec: Double = 0  // bytes/sn
    var upPerSec: Double = 0    // bytes/sn
    var ipAddress: String?
}

// MARK: - GPU metrikleri

nonisolated struct GPUMetrics {
    var utilization: Double = 0  // 0...1
    var name: String = "—"
}

// MARK: - Sıcaklık sensörleri ve fan

nonisolated struct SensorMetrics {
    var temperatures: [TemperatureReading] = []
    var fans: [FanInfo] = []
}

nonisolated struct TemperatureReading: Identifiable, Sendable {
    let id = UUID()
    var label: String
    var celsius: Double

    var color: String {
        switch celsius {
        case ..<50:  return "green"
        case ..<80:  return "yellow"
        default:     return "red"
        }
    }
}

nonisolated struct FanInfo: Identifiable, Sendable {
    let id = UUID()
    var index: Int
    var currentRPM: Int
    var minRPM: Int
    var maxRPM: Int

    var utilizationFraction: Double {
        let range = maxRPM - minRPM
        guard range > 0 else { return 0 }
        return Double(currentRPM - minRPM) / Double(range)
    }
}

// MARK: - Spike kaydı

/// Anlık CPU veya bellek spike'ını tanımlar. Spike Log bu olayları biriktirir.
nonisolated struct SpikeEvent: Identifiable, Sendable {
    let id = UUID()
    var timestamp: Date
    var kind: Kind
    var peakValue: Double        // CPU: toplam %, Bellek: usedFraction
    var culpritName: String      // en çok kaynak yiyen proses
    var culpritPID: Int32
    var culpritValue: Double     // prosesin CPU% veya RSS byte

    enum Kind: String, Sendable {
        case cpu
        case memory
    }
}

// MARK: - Statik makine bilgisi (uptime/health dışında değişmez)

nonisolated struct MachineInfo {
    var chip: String = "—"           // örn. "Apple Silicon"
    var totalRAMBytes: UInt64 = 0
    var coreCount: Int = 0
    var refreshRateHz: Int = 0       // ekran yenileme hızı
    var osVersion: String = ""       // örn. "macOS 26.5"
}

// MARK: - Proses metrikleri

/// Tek bir prosesin anlık durumu.
nonisolated struct ProcessRow: Identifiable, Equatable {
    var pid: Int32
    var name: String        // gösterim adı (uygulama adına indirgenmiş)
    var path: String        // tam yürütülebilir yolu
    var cpu: Double         // yüzde — 100 = bir çekirdeğin tamamı
    var rss: UInt64         // yerleşik bellek (byte)

    var id: Int32 { pid }

    /// Kaç çekirdek dolduruyor (10 çekirdekli makinede 300% = 3 çekirdek).
    var coresBusy: Double { cpu / 100.0 }
}

/// Proses listesi özeti. Uyarılarda "suçlu"yu adlandırmak için kullanılır.
nonisolated struct ProcessMetrics {
    var topCPU: [ProcessRow] = []
    var topMemory: [ProcessRow] = []
    var total: Int = 0
    var sampledAt: Date = .distantPast

    /// kernel_task'ın CPU'su. Apple Silicon'da yüksek değer genelde iki şeyden
    /// birini söyler: termal yönetim ya da bellek compressor'ının yükü.
    var kernelTaskCPU: Double = 0

    /// WindowServer, uzun uptime'da bellek biriktirmesiyle bilinir.
    var windowServerRSS: UInt64 = 0
    var windowServerCPU: Double = 0

    var isEmpty: Bool { topCPU.isEmpty && topMemory.isEmpty }
}

// MARK: - Termal durum

/// `ProcessInfo.thermalState` sarmalayıcısı. Bu API bir sıcaklık değeri değil,
/// sistemin kendini ne kadar kıstığını söyler — fan/throttle için doğru sinyal.
nonisolated struct ThermalMetrics {
    var state: ProcessInfo.ThermalState = .nominal

    var label: String {
        switch state {
        case .nominal:  return String(localized: "Normal")
        case .fair:     return String(localized: "Ilıman")
        case .serious:  return String(localized: "Yüksek")
        case .critical: return String(localized: "Kritik")
        @unknown default: return String(localized: "Bilinmiyor")
        }
    }

    /// 0...3 — eşik karşılaştırmalarını basitleştirir.
    var severity: Int {
        switch state {
        case .nominal:  return 0
        case .fair:     return 1
        case .serious:  return 2
        case .critical: return 3
        @unknown default: return 0
        }
    }
}

// MARK: - Termal atıf sonucu

/// `ThermalAttribution` motorunun tek turluk çıkarımı. macOS'ta ısıyı kaynağa
/// atfeden resmî API yoktur; bu yapı vekil sinyallerden seçilen TEK baskın
/// nedeni taşır, katkı yüzdesi taşımaz — sahte kesinlik `thermalState`
/// felsefesiyle çelişir (bkz. ThermalMonitor).
nonisolated struct ThermalVerdict {
    enum Cause {
        case none      // termal baskı yok (nominal) — neden aranmaz
        case process   // tek proses CPU'ya abanıyor
        case memory    // bellek baskısı / takas trafiği — DOLAYLI neden
        case charging  // şarj (güç girişi ısı üretir)
        case unknown   // sinyaller yetersiz; GPU yükü ölçülemiyor
    }

    var cause: Cause = .none
    /// `process` nedeni için suçlu proses.
    var culprit: ProcessRow?
    /// Kullanıcıya gösterilecek hazır cümle (lokalize).
    var message: String = ""
    /// kernel_task kısarak soğutuyor — neden değil, SONUÇ; ayrı rozet olarak
    /// gösterilir. MAS varyantında kernel_task okunamadığı için hep false.
    var coolingActive: Bool = false
}
