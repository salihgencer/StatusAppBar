import AppKit
import SwiftUI

/// Menu bar'da (üst bardaki dar alanda) görünen canlı etiket.
///
/// ÇÖZÜLEN İKİ SORUN:
///
/// 1. GÖRÜNMEZLİK. Çentikli MacBook'larda menu bar'ın kullanılabilir alanı
///    çentikte biter. Etiket genişse ve barda çok öğe varsa macOS öğeyi
///    çentiğin ALTINA iter — uygulama çalışır ama hiçbir şey görünmez, uyarı
///    da vermez. macOS bunu tespit etmek için API sunmuyor, dolayısıyla tek
///    güvenilir çözüm dar başlamak: varsayılan mod artık `.adaptive` — sakin
///    zamanda ~12 px'lik bir nokta, sorun çıkınca kendisi genişliyor.
///
/// 2. KENDİ TÜKETİMİ. Etiketi `ImageRenderer` ile NSImage'e çizmek pahalı bir
///    iş; her saniye yapıldığında izleme aracı sistemin en çok CPU yakan
///    uygulamalarından biri hâline geliyordu. Artık çizilen içerik gerçekten
///    değişmedikçe önbellekten dönüyor.
struct MenuBarLabel: View {
    @ObservedObject var metrics: MetricsManager
    @ObservedObject var settings: AppSettings

    var body: some View {
        if let image = MenuBarLabelRenderer.shared.image(for: descriptor()) {
            Image(nsImage: image)
        } else {
            Image(systemName: "gauge.with.dots.needle.33percent")
        }
    }

    /// Çizilecek her şeyi tanımlayan değer tipi. Eşitse yeniden çizmeye gerek
    /// yok — önbellek anahtarı olarak da bunu kullanıyoruz.
    private func descriptor() -> LabelDescriptor {
        let stress = stressLevel()
        let worstSeverity = metrics.alerts.map(\.severity).max()

        return LabelDescriptor(
            mode: effectiveMode(stress: stress, hasAlert: worstSeverity != nil),
            segments: segments(),
            compact: compactSegment(),
            // Rengi 20 kademeye yuvarlıyoruz: gözle ayırt edilemeyen 0.001'lik
            // değişimler yüzünden yeniden çizim yapmayalım.
            stressStep: Int((stress * 20).rounded()),
            alertLevel: worstSeverity?.rawValue ?? -1,
            showIcons: settings.showIcons,
            isDark: Self.isDarkMenuBar
        )
    }

    // MARK: - Mod seçimi

    private func effectiveMode(stress: Double, hasAlert: Bool) -> MenuBarMode {
        switch settings.menuBarMode {
        case .adaptive:
            // Uyarı varsa ya da sistem gerçekten zorlanıyorsa genişle.
            return (hasAlert || stress >= 0.5) ? .compact : .minimal
        default:
            return settings.menuBarMode
        }
    }

    // MARK: - Segmentler

    private func segments() -> [LabelSegment] {
        var result: [LabelSegment] = []
        if settings.showCPU {
            result.append(LabelSegment(icon: "cpu",
                                       text: Fmt.percent(metrics.cpu.total, decimals: 0),
                                       width: 33))
        }
        if settings.showRAM {
            result.append(LabelSegment(icon: "memorychip",
                                       text: Fmt.percent(metrics.memory.usedFraction, decimals: 0),
                                       width: 33))
        }
        if settings.showDisk {
            let io = metrics.disk.readPerSec + metrics.disk.writePerSec
            result.append(LabelSegment(icon: "internaldrive", text: Fmt.rateCompact(io), width: 44))
        }
        if settings.showNetwork {
            result.append(LabelSegment(icon: "arrow.down",
                                       text: Fmt.rateCompact(metrics.network.downPerSec), width: 44))
            result.append(LabelSegment(icon: "arrow.up",
                                       text: Fmt.rateCompact(metrics.network.upPerSec), width: 44))
        }
        return result
    }

    /// Dar modda gösterilecek TEK metrik: o an en çok baskı altında olan.
    /// Sabit bir metrik göstermek yerine "en kötüyü" göstermek, tek rakamdan
    /// gerçek bilgi almayı sağlar.
    private func compactSegment() -> LabelSegment {
        let candidates: [(pressure: Double, icon: String, text: String)] = [
            (metrics.memory.swapFraction, "arrow.triangle.swap",
             Fmt.percent(metrics.memory.swapFraction, decimals: 0)),
            (metrics.cpu.total, "cpu",
             Fmt.percent(metrics.cpu.total, decimals: 0)),
            (metrics.memory.usedFraction, "memorychip",
             Fmt.percent(metrics.memory.usedFraction, decimals: 0))
        ]
        let worst = candidates.max { $0.pressure < $1.pressure } ?? candidates[1]
        return LabelSegment(icon: worst.icon, text: worst.text, width: 33)
    }

    // MARK: - Stres

    /// 0 (rahat) ... 1 (tam yük). CPU esas sürücü; RAM ve swap yalnızca
    /// gerçekten yüksekken katkı verir.
    private func stressLevel() -> Double {
        let cpuStress = ramp(metrics.cpu.total, from: 0.25, to: 0.75)
        let ramStress = ramp(metrics.memory.usedFraction, from: 0.85, to: 0.98)
        let swapStress = ramp(metrics.memory.swapFraction, from: 0.60, to: 0.90)
        return max(cpuStress, max(ramStress, swapStress))
    }

    private func ramp(_ value: Double, from: Double, to: Double) -> Double {
        guard to > from else { return value >= to ? 1 : 0 }
        return min(1, max(0, (value - from) / (to - from)))
    }

    static var isDarkMenuBar: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}

// MARK: - Çizim tanımı

struct LabelSegment: Equatable {
    var icon: String
    var text: String
    var width: CGFloat
}

struct LabelDescriptor: Equatable {
    var mode: MenuBarMode
    var segments: [LabelSegment]
    var compact: LabelSegment
    var stressStep: Int
    var alertLevel: Int
    var showIcons: Bool
    var isDark: Bool
}
