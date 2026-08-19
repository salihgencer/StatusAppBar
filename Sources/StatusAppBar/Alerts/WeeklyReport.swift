#if MAS
import Foundation

/// Haftalık sistem raporu oluşturur. Spike log desenleri, health score trendi
/// ve disk/pil sağlığı gibi uzun vadeli gözlemleri AI'ya analiz ettirir.
///
/// Rapor oluşturma tamamen yereldir — AI'ya gönderilen veriler kullanıcının
/// kendi API anahtarıyla gider, sunucu tarafımız yoktur.
enum WeeklyReport {

    /// AI'ya gönderilecek haftalık rapor metni.
    static func generate(metrics: MetricsManager) -> String {
        var lines: [String] = []

        lines.append("# Haftalık Sistem Raporu")
        lines.append("Tarih: \(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .short))")
        lines.append("")

        // Health Score
        lines.append("## Sağlık Skoru")
        lines.append("Anlık: \(metrics.health)/100")
        if metrics.healthHistory.count > 10 {
            let scores = metrics.healthHistory.map(\.score)
            let avg = scores.reduce(0, +) / scores.count
            lines.append("Ortalama (son oturum): \(avg)")
            lines.append("Min: \(scores.min() ?? 0), Maks: \(scores.max() ?? 100)")
        }
        lines.append("")

        // Spike özeti
        lines.append("## Spike Özeti (\(metrics.spikeLog.count) olay)")
        if metrics.spikeLog.isEmpty {
            lines.append("Son 24 saatte spike kaydedilmedi.")
        } else {
            let cpuSpikes = metrics.spikeLog.filter { $0.kind == .cpu }
            let memSpikes = metrics.spikeLog.filter { $0.kind == .memory }
            lines.append("- CPU spike: \(cpuSpikes.count)")
            lines.append("- Bellek spike: \(memSpikes.count)")

            // En sık spike üreten uygulamalar
            var culpritCounts: [String: Int] = [:]
            for spike in metrics.spikeLog {
                culpritCounts[spike.culpritName, default: 0] += 1
            }
            let topCulprits = culpritCounts.sorted { $0.value > $1.value }.prefix(5)
            if !topCulprits.isEmpty {
                lines.append("\nEn çok spike üreten uygulamalar:")
                for (name, count) in topCulprits {
                    lines.append("  - \(name): \(count) kez")
                }
            }
        }
        lines.append("")

        // Disk durumu
        lines.append("## Disk")
        for vol in metrics.disk.volumes {
            let pct = String(format: "%.0f%%", vol.fraction * 100)
            lines.append("- \(vol.name): \(Fmt.bytes(vol.used)) / \(Fmt.bytes(vol.total)) (\(pct) dolu)")
        }
        lines.append("")

        // Pil sağlığı
        if metrics.power.hasBattery {
            lines.append("## Pil")
            lines.append("- Sağlık: %\(Int(metrics.power.healthPercent))")
            lines.append("- Döngü: \(metrics.power.cycleCount)")
            lines.append("- Sıcaklık: \(String(format: "%.1f°C", metrics.power.temperature))")
            lines.append("")
        }

        // GPU
        lines.append("## GPU")
        lines.append("- Model: \(metrics.gpu.name)")
        lines.append("- Kullanım: \(String(format: "%.0f%%", metrics.gpu.utilization * 100))")
        lines.append("")

        // Termal
        lines.append("## Termal")
        lines.append("- Durum: \(metrics.thermal.label)")
        lines.append("")

        lines.append("---")
        lines.append("Bu raporu analiz et ve şu konularda önerilerde bulun:")
        lines.append("1. Spike desenleri — tekrarlayan sorunlar var mı?")
        lines.append("2. Disk doluluk trendi — yakında alan sıkıntısı olabilir mi?")
        lines.append("3. Pil sağlığı — anormal yıpranma var mı?")
        lines.append("4. Genel performans iyileştirme önerileri")

        return lines.joined(separator: "\n")
    }
}
#endif
