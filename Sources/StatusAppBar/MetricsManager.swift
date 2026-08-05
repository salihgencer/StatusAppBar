import Combine
import Foundation

/// Örneklemeyi sürer ve sonuçları `@Published` olarak yayınlar. SwiftUI
/// view'lar bu nesneyi izler.
///
/// Bu sınıf `@MainActor` (paket genelinde varsayılan izolasyon). Örnekleme
/// UI'yi bloklamasın diye `Sampler` aktöründe yapılır; buraya yalnızca değer
/// tipinden oluşan hazır bir `Sample` döner.
///
/// Uyarı değerlendirmesi bilinçli olarak MAIN ACTOR'de kalır: AppSettings
/// okur ve bildirim tetikler. Değerlendirme birkaç karşılaştırmadan ibaret,
/// main thread'i meşgul etmez.
final class MetricsManager: ObservableObject {

    @Published private(set) var cpu = CPUMetrics()
    @Published private(set) var memory = MemoryMetrics()
    @Published private(set) var disk = DiskMetrics()
    @Published private(set) var power = PowerMetrics()
    @Published private(set) var network = NetworkMetrics()
    @Published private(set) var processes = ProcessMetrics()
    @Published private(set) var thermal = ThermalMetrics()
    @Published private(set) var thermalAttribution = ThermalVerdict()
    @Published private(set) var uptime: TimeInterval = 0
    @Published private(set) var health: Int = 0

    /// Aktif uyarılar. AlertEngine'i doğrudan @Published yapmak yerine düz
    /// diziyi yayınlıyoruz — iç içe ObservableObject SwiftUI'da güncellemeyi
    /// tetiklemez, bu klasik bir tuzak.
    @Published private(set) var alerts: [ActiveAlert] = []

    let machine: MachineInfo

    private let sampler = Sampler()
    private let alertEngine = AlertEngine()

    private var timer: Timer?

    /// Süren örnekleme turu. Bir tur (özellikle `ps` çağrısının düştüğü tur)
    /// aralıktan uzun sürerse turlar üst üste binip sonuçları sırasız
    /// yayınlayabilirdi; bu bayrak binmeyi engeller.
    private var samplingTask: Task<Void, Never>?

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
        // İlk örneği hemen al (kullanıcı menüyü açar açmaz veri görsün).
        tick()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            // Timer RunLoop.main'e eklendiği için gövde her zaman main
            // thread'de çalışır; `assumeIsolated` bunu derleyiciye bildirir
            // (yeni bir Task açmak gereksiz gecikme olurdu).
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        // .common mode: menü/popover açıkken (tracking run loop) de timer çalışsın.
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        // Önceki tur bitmediyse yenisini başlatma. Aksi halde iki tur aynı
        // anda aktöre girip sonuçları sırasız yayınlayabilir.
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
        uptime = s.uptime
        health = s.health

        let snapshot = AlertEngine.Snapshot(
            cpu: s.cpu, memory: s.memory, power: s.power, thermal: s.thermal,
            processes: s.processes, uptime: s.uptime, machine: machine
        )
        // Isınma nedeni çıkarımı uyarı motoruyla aynı anlık veriden beslenir;
        // popover bölümü, uyarı detayı ve teşhis raporu aynı kararı paylaşır.
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
        net.ipAddress = "192.168.1.10" // jenerik özel-ağ örneği
        m.network = net

        var procs = ProcessMetrics()
        procs.total = 480
        procs.kernelTaskCPU = cpuTotal > 0.9 ? 31 : 3
        procs.windowServerRSS = 420 * 1024 * 1024
        procs.topCPU = [
            // Mock adları katalogdan gelir: App Store ekran görüntüleri her
            // dilde üretiliyor, sahte veri bile lokalize olmalı.
            ProcessRow(pid: 101, name: String(localized: "Örnek Emülatör"), path: "/tmp/emulator",
                       cpu: cpuTotal > 0.9 ? 290 : 22, rss: 3 * gb),
            ProcessRow(pid: 102, name: String(localized: "Örnek Tarayıcı"), path: "/tmp/browser",
                       cpu: 18, rss: 900 * 1024 * 1024)
        ]
        procs.topMemory = procs.topCPU
        procs.sampledAt = Date()
        m.processes = procs

        m.uptime = 187_200 // 2g 4s
        // Mock görseller sakin bir makine gösterir; termal durum nominal kalır.
        m.health = HealthScore.compute(cpu: cpu, memory: mem, disk: disk,
                                       power: power, thermal: m.thermal)

        return m
    }
}
