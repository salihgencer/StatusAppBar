import Foundation
import Observation

/// Örneklemeyi sürer ve sonuçları yayınlar. SwiftUI view'lar bu nesneyi izler.
///
/// Bu sınıf `@MainActor` (paket genelinde varsayılan izolasyon). Örnekleme
/// UI'yi bloklamasın diye `Sampler` aktöründe yapılır; buraya yalnızca değer
/// tipinden oluşan hazır bir `Sample` döner.
///
/// Uyarı değerlendirmesi bilinçli olarak MAIN ACTOR'de kalır: AppSettings
/// okur ve bildirim tetikler. Değerlendirme birkaç karşılaştırmadan ibaret,
/// main thread'i meşgul etmez.
@Observable
final class MetricsManager {

    private(set) var cpu = CPUMetrics()
    private(set) var memory = MemoryMetrics()
    private(set) var disk = DiskMetrics()
    private(set) var power = PowerMetrics()
    private(set) var network = NetworkMetrics()
    private(set) var processes = ProcessMetrics()
    private(set) var thermal = ThermalMetrics()
    private(set) var thermalAttribution = ThermalVerdict()
    private(set) var gpu = GPUMetrics()
    private(set) var sensors = SensorMetrics()
    private(set) var uptime: TimeInterval = 0
    private(set) var health: Int = 0

    /// Aktif uyarılar. AlertEngine'i doğrudan yayınlamak yerine düz diziyi
    /// tutuyoruz — Observation framework property-düzeyinde izleme yapar,
    /// dolayısıyla sadece alerts değiştiğinde ilgili view güncellenir.
    private(set) var alerts: [ActiveAlert] = []

    /// Son 24 saatte tespit edilen CPU ve bellek spike'ları (maks 30).
    private(set) var spikeLog: [SpikeEvent] = []

    /// Health score geçmişi (son 1 saat, her tur bir veri noktası).
    private(set) var healthHistory: [(date: Date, score: Int)] = []
    private static let maxHealthHistory = 1800 // 2s aralıkla ~1 saat

    let machine: MachineInfo

    @ObservationIgnored private let sampler = Sampler()
    @ObservationIgnored private let alertEngine = AlertEngine()

    @ObservationIgnored private var timer: Timer?

    /// Süren örnekleme turu. Bir tur (özellikle `ps` çağrısının düştüğü tur)
    /// aralıktan uzun sürerse turlar üst üste binip sonuçları sırasız
    /// yayınlayabilirdi; bu bayrak binmeyi engeller.
    @ObservationIgnored private var samplingTask: Task<Void, Never>?

    init() {
        machine = MachineInfoProvider.current()
        start(interval: AppSettings.shared.refreshInterval)
    }

    /// Timer başlatmayan, dışarıdan veri set edilen kurucu (mock/dökümantasyon için).
    private init(machine: MachineInfo) {
        self.machine = machine
    }

    /// Derin analiz ve rapor için anlık tam durum.
    func snapshot() -> AlertEngine.Snapshot {
        AlertEngine.Snapshot(
            cpu: cpu,
            memory: memory,
            power: power,
            thermal: thermal,
            processes: processes,
            uptime: uptime,
            machine: machine
        )
    }

    /// Örnekleme aralığını ayarlar / yeniden başlatır.
    func start(interval: TimeInterval) {
        timer?.invalidate()
        tick()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            // Timer RunLoop.main'e eklendiği için gövde her zaman main
            // thread'de çalışır; `assumeIsolated` bunu derleyiciye bildirir.
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard samplingTask == nil else { return }

        samplingTask = Task { [weak self] in
            guard let self else { return }
            let sample = await sampler.sample()
            apply(sample)
            samplingTask = nil
        }
    }

    /// Aktörden gelen turu yayınlar ve uyarıları değerlendirir.
    private func apply(_ s: Sampler.Sample) {
        cpu = s.cpu
        memory = s.memory
        disk = s.disk
        power = s.power
        network = s.network
        processes = s.processes
        thermal = s.thermal
        gpu = s.gpu
        sensors = s.sensors
        uptime = s.uptime
        health = s.health

        // Health score geçmişi
        healthHistory.append((date: Date(), score: s.health))
        if healthHistory.count > Self.maxHealthHistory {
            healthHistory.removeFirst(healthHistory.count - Self.maxHealthHistory)
        }

        // Spike log: yeni spike'ları ekle, 24 saatten eskilerini at, maks 30 tut.
        if !s.spikes.isEmpty {
            spikeLog.append(contentsOf: s.spikes)
        }
        let cutoff = Date().addingTimeInterval(-86400)
        spikeLog.removeAll { $0.timestamp < cutoff }
        if spikeLog.count > 30 {
            spikeLog = Array(spikeLog.suffix(30))
        }

        let snapshot = AlertEngine.Snapshot(
            cpu: s.cpu, memory: s.memory, power: s.power, thermal: s.thermal,
            processes: s.processes, uptime: s.uptime, machine: machine
        )
        thermalAttribution = ThermalAttribution.attribute(snapshot)
        alerts = alertEngine.evaluate(snapshot, settings: AppSettings.shared)
    }

    /// `isolated deinit`: `Timer` Sendable değil, dolayısıyla izolasyonsuz bir
    /// deinit'ten ona dokunulamaz. Deinit'i MainActor'de çalıştırmak hem
    /// derleyiciyi hem de `Timer`'ın "yaratıldığı run loop'ta invalidate et"
    /// şartını karşılar.
    isolated deinit {
        timer?.invalidate()
        samplingTask?.cancel()
    }
}

// MARK: - Dökümantasyon için temsili veri

extension MetricsManager {

    /// README görselleri için tamamen TEMSİLİ veri. Gerçek makineden hiçbir
    /// bilgi okumaz; IP, disk adı, donanım vb. hepsi jeneriktir.
    static func mock(cpuTotal: Double) -> MetricsManager {
        let gb: UInt64 = 1024 * 1024 * 1024
        let machine = MachineInfo(
            chip: "Apple Silicon",
            totalRAMBytes: 16 * gb,
            coreCount: 10,
            refreshRateHz: 120,
            osVersion: "macOS 26.0"
        )
        let m = MetricsManager(machine: machine)

        var cpu = CPUMetrics()
        cpu.total = cpuTotal
        cpu.cores = (0..<10).map { (i: Int) -> Double in
            cpuTotal > 0.9
                ? (i < 5 ? 1.0 : Double((i * 7) % 28) / 100.0)
                : Double((i * 13) % 65) / 100.0
        }
        cpu.load = [2.10, 1.84, 1.62]
        cpu.pCores = 6
        cpu.eCores = 4
        m.cpu = cpu

        var mem = MemoryMetrics()
        mem.total = 16 * gb
        mem.used = UInt64(Double(16 * gb) * 0.59)
        mem.free = mem.total - mem.used
        mem.compressed = UInt64(Double(gb) * 1.4)
        mem.swapTotal = 2 * gb
        mem.swapUsed = UInt64(Double(2 * gb) * 0.28)
        m.memory = mem

        var disk = DiskMetrics()
        disk.volumes = [
            DiskVolume(name: "Macintosh HD", total: 994 * gb, free: 312 * gb),
            DiskVolume(name: "External SSD", total: 2000 * gb, free: 1100 * gb)
        ]
        disk.readPerSec = 1.4 * 1024 * 1024
        disk.writePerSec = 16 * 1024
        m.disk = disk

        var power = PowerMetrics()
        power.hasBattery = true
        power.level = 0.82
        power.onAC = true
        power.isCharging = true
        power.cycleCount = 142
        power.temperature = 30.0
        power.healthPercent = 96
        power.adapterWatts = 67
        power.timeRemainingMinutes = 35
        power.amperageMA = 1800
        power.voltageMV = 11_700
        m.power = power

        var net = NetworkMetrics()
        net.downPerSec = 1.2 * 1024 * 1024
        net.upPerSec = 240 * 1024
        net.ipAddress = "192.168.1.10"
        m.network = net

        var procs = ProcessMetrics()
        procs.total = 480
        procs.kernelTaskCPU = cpuTotal > 0.9 ? 31 : 3
        procs.windowServerRSS = 420 * 1024 * 1024
        procs.topCPU = [
            ProcessRow(pid: 101, name: String(localized: "Örnek Emülatör"), path: "/tmp/emulator",
                       cpu: cpuTotal > 0.9 ? 290 : 22, rss: 3 * gb),
            ProcessRow(pid: 102, name: String(localized: "Örnek Tarayıcı"), path: "/tmp/browser",
                       cpu: 18, rss: 900 * 1024 * 1024)
        ]
        procs.topMemory = procs.topCPU
        procs.sampledAt = Date()
        m.processes = procs

        var gpu = GPUMetrics()
        gpu.utilization = cpuTotal > 0.9 ? 0.72 : 0.15
        gpu.name = "Apple M1 Pro"
        m.gpu = gpu

        m.uptime = 187_200
        m.health = HealthScore.compute(cpu: cpu, memory: mem, disk: disk,
                                       power: power, thermal: m.thermal)

        return m
    }
}
