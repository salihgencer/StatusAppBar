import Foundation

/// Sistemin genel "sağlık" skoru (0-100). Görseldeki `Health ● 66` değeri.
///
/// Bu BİLİNÇLİ bir tasarım kararıdır — tek doğru formül yoktur. Skor, farklı
/// metriklerin baskısını ağırlıklandırarak tek bir sezgisel sayıya indirir:
///  - Yüksek CPU / RAM / disk doluluğu skoru DÜŞÜRÜR (sistem zorlanıyor).
///  - Yüksek batarya sıcaklığı skoru düşürür.
///  - Her metriğin "ağırlığı" ne kadar önemli olduğunu belirler.
///
/// Trade-off'lar:
///  - Ağırlıkları eşit verirsen hiçbir metrik öne çıkmaz; CPU'ya ağırlık
///    verirsen skor anlık yüke daha duyarlı (ama daha "zıplayan") olur.
///  - Lineer ceza basit ama eşik mantığı yok; "0.85 üstü kritik" gibi
///    keskin eşikler istersen non-lineer ceza ekleyebilirsin.
enum HealthScore {

    static func compute(
        cpu: CPUMetrics,
        memory: MemoryMetrics,
        disk: DiskMetrics,
        power: PowerMetrics
    ) -> Int {
        // En dolu disk volume'unun oranı (kök disk genelde en kritik olan).
        let diskPressure = disk.volumes.map(\.fraction).max() ?? 0

        // Sıcaklık baskısı: ~45°C ve üstü tam ceza olacak şekilde 0...1'e ölçekle.
        let tempPressure = power.hasBattery ? min(1.0, max(0.0, (power.temperature - 30) / 15)) : 0

        // Ağırlıklı baskı toplamı. Ağırlıklar 1.0'a tamamlanır.
        let pressure =
            cpu.total       * 0.35 +
            memory.usedFraction * 0.30 +
            diskPressure    * 0.20 +
            tempPressure    * 0.15

        // Baskı ne kadar yüksekse skor o kadar düşük.
        let score = (1.0 - pressure) * 100
        return Int(max(0, min(100, score.rounded())))
    }

    /// Skor rengini kategorize eder (gösterge noktası için).
    static func color(for score: Int) -> (label: String, isGood: Bool) {
        switch score {
        case 75...100: return ("Healthy", true)
        case 50..<75:  return ("Fair", true)
        default:       return ("Strained", false)
        }
    }
}
