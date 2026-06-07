import AppKit
import SwiftUI

/// Menu bar'da (üst bardaki dar alanda) görünen canlı etiket.
/// Ayarlardan açık olan metrikleri kompakt biçimde gösterir; metrikler her
/// güncellendiğinde otomatik yeniden çizilir (canlı görünüm).
///
/// İçeriği `ImageRenderer` ile tek bir `NSImage`'e çiziyoruz (MenuBarExtra
/// etiketi ikon+metin birleşimini güvenilir render etmiyor). Renk strese göre
/// değişir: sistem rahatken sönük/nötr (menu bar'a uyumlu), yük arttıkça
/// kırmızıya döner. Bu yüzden template DEĞİL, renkli çiziyoruz ve temel rengi
/// menu bar görünümüne göre kendimiz seçiyoruz.
struct MenuBarLabel: View {
    @ObservedObject var metrics: MetricsManager
    @ObservedObject var settings: AppSettings

    var body: some View {
        if let image = renderLabelImage() {
            Image(nsImage: image)
        } else {
            Text("Status")
        }
    }

    private struct Segment {
        var icon: String
        var text: String
        var width: CGFloat   // değer alanının sabit genişliği (sağa hizalı)
    }

    // Sabit alan genişlikleri: değer kısalsa da bu kadar yer rezerve edilir,
    // böylece rakam değişince toplam genişlik (ve öğe konumu) sabit kalır.
    private let fontSize: CGFloat = 13       // menu bar yazı boyutu
    private let percentWidth: CGFloat = 33   // "100%"
    private let rateWidth: CGFloat = 44      // "12.3M", "1023K", "0"

    private func segments() -> [Segment] {
        var result: [Segment] = []
        if settings.showCPU {
            result.append(Segment(icon: "cpu", text: Fmt.percent(metrics.cpu.total, decimals: 0), width: percentWidth))
        }
        if settings.showRAM {
            result.append(Segment(icon: "memorychip", text: Fmt.percent(metrics.memory.usedFraction, decimals: 0), width: percentWidth))
        }
        if settings.showDisk {
            let io = metrics.disk.readPerSec + metrics.disk.writePerSec
            result.append(Segment(icon: "internaldrive", text: Fmt.rateCompact(io), width: rateWidth))
        }
        if settings.showNetwork {
            // İki yön: ↓ download, ↑ upload.
            result.append(Segment(icon: "arrow.down", text: Fmt.rateCompact(metrics.network.downPerSec), width: rateWidth))
            result.append(Segment(icon: "arrow.up", text: Fmt.rateCompact(metrics.network.upPerSec), width: rateWidth))
        }
        return result
    }

    // MARK: - Stres -> renk

    /// 0 (rahat) ... 1 (tam yük). Esas sürücü CPU; RAM yalnızca çok yüksekken katkı verir.
    /// CPU eşiği günlük kullanımda görünür olsun diye düşük tutulur: ortalama CPU
    /// ~%25'te renklenmeye başlar, ~%75'te tam kırmızı.
    private func stressLevel() -> Double {
        let cpuStress = ramp(metrics.cpu.total, from: 0.25, to: 0.75)
        let ramStress = ramp(metrics.memory.usedFraction, from: 0.85, to: 0.98)
        return max(cpuStress, ramStress)
    }

    /// value'yu [from, to] aralığında 0...1'e lineer eşler (dışı clamp'lenir).
    private func ramp(_ value: Double, from: Double, to: Double) -> Double {
        guard to > from else { return value >= to ? 1 : 0 }
        return min(1, max(0, (value - from) / (to - from)))
    }

    /// Strese göre mürekkep rengi: nötr (menu bar temel rengi) -> kırmızı,
    /// rahatken hafif şeffaf, yük arttıkça opak.
    private func inkColor(stress: Double) -> Color {
        let isDark = NSApp.effectiveAppearance
            .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let base: CGFloat = isDark ? 1.0 : 0.0   // koyu bar -> beyaz, açık bar -> siyah

        // Hedef kırmızı.
        let target = (r: CGFloat(0.95), g: CGFloat(0.27), b: CGFloat(0.27))
        let s = CGFloat(stress)
        let r = base + (target.r - base) * s
        let g = base + (target.g - base) * s
        let b = base + (target.b - base) * s

        // Rahatken biraz şeffaf (sönük), yük arttıkça tam opak.
        let alpha = 0.65 + 0.35 * s

        return Color(nsColor: NSColor(srgbRed: r, green: g, blue: b, alpha: alpha))
    }

    // MARK: - Render

    @ViewBuilder
    private func labelContent(_ segs: [Segment], ink: Color) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(segs.enumerated()), id: \.offset) { _, seg in
                HStack(spacing: 3) {
                    if settings.showIcons {
                        Image(systemName: seg.icon)
                            .imageScale(.small)
                            .frame(width: 16, alignment: .center) // ikon alanı da sabit
                    }
                    Text(seg.text)
                        .frame(width: seg.width, alignment: .leading) // değer alanı sabit; sayı ikonuna yapışır
                }
            }
        }
        // Tam monospaced: rakamlar VE harfler (% K M) eşit genişlik -> kayma yok.
        .font(.system(size: fontSize, weight: .regular, design: .monospaced))
        .foregroundStyle(ink)
        .padding(.vertical, 1)
        .fixedSize() // metin asla kırpılmasın; her zaman ideal genişlikte çiz
    }

    @MainActor
    private func renderLabelImage() -> NSImage? {
        let segs = segments()
        guard !segs.isEmpty else { return nil }

        let ink = inkColor(stress: stressLevel())
        let renderer = ImageRenderer(content: labelContent(segs, ink: ink))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return nil }
        // Renkli çiziyoruz; sistem yeniden renklendirmesin.
        image.isTemplate = false
        return image
    }
}
