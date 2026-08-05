import Foundation

/// Tüm monitor'leri sahiplenen ve onları örnekleyen aktör.
///
/// NEDEN AKTÖR, NEDEN `DispatchQueue` DEĞİL:
/// Eski tasarımda monitor'ler tek bir serial `DispatchQueue`'da çağrılıyordu.
/// Bu doğruydu ama yalnızca KONVANSİYONLA doğruydu — hiçbir şey bir monitor'ü
/// yanlışlıkla main thread'den çağırmayı engellemiyordu ve monitor'lerin
/// içindeki "önceki örnek" state'i sessizce bozulabilirdi.
///
/// Aktör aynı garantiyi tip sisteminde verir: monitor'ler bu aktörün izole
/// deposundadır, dolayısıyla erişim sıralıdır ve main thread dışındadır.
/// Davranış birebir aynı; değişen tek şey garantinin denetlenebilir olması.
///
/// Monitor'ler bilinçli olarak `nonisolated` (izolasyonsuz) sınıflar: kendi
/// başlarına thread-safe değiller ve olmaları da gerekmiyor — güvenlikleri
/// bu aktörün içinde yaşamalarından geliyor. Bu yüzden `Sendable` değiller ve
/// aktörden dışarı sızmaları derleyici tarafından engellenir.
actor Sampler {

    /// Tek turluk örnekleme sonucu. Tümü değer tipi, dolayısıyla aktör
    /// sınırından main thread'e güvenle geçer.
    struct Sample: Sendable {
        var cpu: CPUMetrics
        var memory: MemoryMetrics
        var disk: DiskMetrics
        var power: PowerMetrics
        var network: NetworkMetrics
        var processes: ProcessMetrics
        var thermal: ThermalMetrics
        var uptime: TimeInterval
        var health: Int
    }

    private let cpuMonitor = CPUMonitor()
    private let memoryMonitor = MemoryMonitor()
    private let diskMonitor = DiskMonitor()
    private let powerMonitor = PowerMonitor()
    private let networkMonitor = NetworkMonitor()
    private let processMonitor = ProcessMonitor()
    private let thermalMonitor = ThermalMonitor()

    /// Bir tur örnekleme. Monitor'ler sırayla çağrılır — hepsi delta tabanlı
    /// olduğu için çağrı sırasının ve zamanlamasının tutarlı kalması önemli.
    ///
    /// BİLİNÇLİ OLARAK `async` DEĞİL. `ProcessMonitor` 10 sn'de bir `ps`
    /// çalıştırır ve çıktısını beklerken (~30 ms) cooperative pool'un bir
    /// thread'ini bloklar. Bunu `await`'e çevirmek thread'i serbest bırakırdı
    /// ama aktör reentrancy'si açardı: askıdayken ikinci bir tur içeri girip
    /// monitor'lerin delta state'ini bozabilirdi. 10 saniyede bir 30 ms,
    /// bozulmuş bir ölçüme tercih edilir.
    func sample() -> Sample {
        let cpu = cpuMonitor.sample()
        let memory = memoryMonitor.sample()
        let disk = diskMonitor.sample()
        let power = powerMonitor.sample()
        let network = networkMonitor.sample()
        // Proses listesi kendi aralığında (varsayılan 10 sn) tazelenir;
        // ara turlarda önbellekten döner, alt proses açılmaz.
        let processes = processMonitor.sample()
        let thermal = thermalMonitor.sample()

        return Sample(
            cpu: cpu,
            memory: memory,
            disk: disk,
            power: power,
            network: network,
            processes: processes,
            thermal: thermal,
            uptime: ProcessInfo.processInfo.systemUptime,
            health: HealthScore.compute(cpu: cpu, memory: memory, disk: disk,
                                        power: power, thermal: thermal)
        )
    }
}
