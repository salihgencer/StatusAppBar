import Combine
import Foundation

/// Tüm monitor'leri sahiplenir, belirli aralıkla örnekler ve sonuçları
/// `@Published` olarak yayınlar. SwiftUI view'lar bu nesneyi izler.
///
/// Sampling, UI'yi bloklamamak için arka plan kuyruğunda yapılır; sadece
/// sonucun yayını main thread'e geri alınır. Monitor'ler bu serial kuyrukta
/// sırayla çağrıldığı için içlerindeki "önceki örnek" state'i thread-safe kalır.
final class MetricsManager: ObservableObject {

    @Published private(set) var cpu = CPUMetrics()
    @Published private(set) var memory = MemoryMetrics()
    @Published private(set) var disk = DiskMetrics()
    @Published private(set) var power = PowerMetrics()
    @Published private(set) var network = NetworkMetrics()
    @Published private(set) var uptime: TimeInterval = 0
    @Published private(set) var health: Int = 0

    let machine: MachineInfo

    private let cpuMonitor = CPUMonitor()
    private let memoryMonitor = MemoryMonitor()
    private let diskMonitor = DiskMonitor()
    private let powerMonitor = PowerMonitor()
    private let networkMonitor = NetworkMonitor()

    private let queue = DispatchQueue(label: "io.github.salihgencer.statusappbar.sampling", qos: .utility)
    private var timer: Timer?

    init() {
        machine = MachineInfoProvider.current()
        start(interval: 1.0)
    }

    /// Timer başlatmayan, dışarıdan veri set edilen kurucu (mock/dökümantasyon için).
    private init(machine: MachineInfo) {
        self.machine = machine
    }

    /// README görselleri için tamamen TEMSİLİ veri. Gerçek makineden hiçbir
    /// bilgi okumaz; IP, disk adı, donanım vb. hepsi jeneriktir.
    static func mock(cpuTotal: Double) -> MetricsManager {
        let gb: UInt64 = 1024 * 1024 * 1024
        let machine = MachineInfo(
            chip: "Apple Silicon",
            totalRAMBytes: 16 * gb,
            coreCount: 10,
            refreshRateHz: 60,
            osVersion: "macOS 15.0"
        )
        let m = MetricsManager(machine: machine)

        var cpu = CPUMetrics()
        cpu.total = cpuTotal
        cpu.cores = (0..<10).map { (i: Int) -> Double in
            if cpuTotal > 0.9 {
                return i < 5 ? 1.0 : Double((i * 7) % 28) / 100.0
            } else {
                return Double((i * 13) % 65) / 100.0
            }
        }
        cpu.load = [2.10, 1.84, 1.62]
        cpu.pCores = 6
        cpu.eCores = 4
        m.cpu = cpu

        var mem = MemoryMetrics()
        mem.total = 16 * gb
        mem.used = UInt64(Double(16 * gb) * 0.59)
        mem.free = mem.total - mem.used
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
        m.power = power

        var net = NetworkMetrics()
        net.downPerSec = 1.2 * 1024 * 1024
        net.upPerSec = 240 * 1024
        net.ipAddress = "192.168.1.10" // jenerik özel-ağ örneği
        m.network = net

        m.uptime = 187_200 // 2g 4s
        m.health = HealthScore.compute(cpu: cpu, memory: mem, disk: disk, power: power)

        return m
    }

    /// Örnekleme aralığını ayarlar / yeniden başlatır.
    func start(interval: TimeInterval) {
        timer?.invalidate()
        // İlk örneği hemen al (kullanıcı menüyü açar açmaz veri görsün).
        tick()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // .common mode: menü/popover açıkken (tracking run loop) de timer çalışsın.
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        queue.async { [weak self] in
            guard let self else { return }

            let cpu = self.cpuMonitor.sample()
            let memory = self.memoryMonitor.sample()
            let disk = self.diskMonitor.sample()
            let power = self.powerMonitor.sample()
            let network = self.networkMonitor.sample()
            let uptime = ProcessInfo.processInfo.systemUptime
            let health = HealthScore.compute(cpu: cpu, memory: memory, disk: disk, power: power)

            DispatchQueue.main.async {
                self.cpu = cpu
                self.memory = memory
                self.disk = disk
                self.power = power
                self.network = network
                self.uptime = uptime
                self.health = health
            }
        }
    }

    deinit {
        timer?.invalidate()
    }
}
