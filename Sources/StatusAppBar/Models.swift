import Foundation

// MARK: - Metric snapshot modelleri
// Her monitor, anlık bir okuma sonucunu bu değer tipleri (struct) ile döndürür.
// Değer tipi olmaları, sampling'i arka plan kuyruğunda yapıp sonucu güvenle
// main thread'e taşımayı kolaylaştırır.

struct CPUMetrics {
    var total: Double = 0          // 0...1 toplam kullanım
    var cores: [Double] = []       // çekirdek başına 0...1
    var load: [Double] = [0, 0, 0] // 1, 5, 15 dakikalık load average
    var pCores: Int = 0            // performance core sayısı
    var eCores: Int = 0            // efficiency core sayısı
}

struct MemoryMetrics {
    var total: UInt64 = 0
    var used: UInt64 = 0
    var free: UInt64 = 0
    var swapTotal: UInt64 = 0
    var swapUsed: UInt64 = 0

    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
    var freeFraction: Double { total > 0 ? Double(free) / Double(total) : 0 }
    var swapFraction: Double { swapTotal > 0 ? Double(swapUsed) / Double(swapTotal) : 0 }
}

struct DiskVolume: Identifiable {
    let id = UUID()
    var name: String
    var total: UInt64
    var free: UInt64

    var used: UInt64 { total >= free ? total - free : 0 }
    var fraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

struct DiskMetrics {
    var volumes: [DiskVolume] = []
    var readPerSec: Double = 0   // bytes/sn
    var writePerSec: Double = 0  // bytes/sn
}

struct PowerMetrics {
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
}

struct NetworkMetrics {
    var downPerSec: Double = 0  // bytes/sn
    var upPerSec: Double = 0    // bytes/sn
    var ipAddress: String?
}

// MARK: - Statik makine bilgisi (uptime/health dışında değişmez)

struct MachineInfo {
    var chip: String = "—"           // örn. "Apple Silicon"
    var totalRAMBytes: UInt64 = 0
    var coreCount: Int = 0
    var refreshRateHz: Int = 0       // ekran yenileme hızı
    var osVersion: String = ""       // örn. "macOS 26.5"
}
