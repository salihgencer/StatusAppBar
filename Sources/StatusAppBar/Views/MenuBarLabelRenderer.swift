import AppKit
import SwiftUI

/// Menu bar etiketini NSImage'e çizer ve ÖNBELLEKLER.
///
/// `MenuBarExtra` etiketi ikon+metin birleşimini güvenilir render etmiyor, bu
/// yüzden içeriği kendimiz tek bir görsele çiziyoruz. Ama `ImageRenderer`
/// pahalı: her örnekleme turunda çağrıldığında uygulama kendi ölçtüğü CPU
/// tüketiminin gözle görülür bir kısmını üretiyordu.
///
/// Çözüm: çizim tanımı (`LabelDescriptor`) değişmedikçe son görseli döndür.
/// Pratikte CPU yüzdesi tam sayı olarak aynı kaldığı sürece — yani çoğu turda —
/// hiçbir çizim yapılmaz.
@MainActor
final class MenuBarLabelRenderer {

    static let shared = MenuBarLabelRenderer()

    private var lastDescriptor: LabelDescriptor?
    private var lastImage: NSImage?

    private let fontSize: CGFloat = 13

    private init() {}

    func image(for descriptor: LabelDescriptor) -> NSImage? {
        if descriptor == lastDescriptor, let cached = lastImage { return cached }

        let image = render(descriptor)
        lastDescriptor = descriptor
        lastImage = image
        return image
    }

    // MARK: - Çizim

    private func render(_ d: LabelDescriptor) -> NSImage? {
        let ink = inkColor(stressStep: d.stressStep, alertLevel: d.alertLevel, isDark: d.isDark)

        let content = Group {
            switch d.mode {
            case .minimal:
                // Sadece nokta. ~12 px — menu bar ne kadar dolu olursa olsun sığar.
                Circle()
                    .fill(ink)
                    .frame(width: 8, height: 8)
                    .padding(.horizontal, 2)

            case .compact:
                HStack(spacing: 4) {
                    Circle().fill(ink).frame(width: 6, height: 6)
                    self.segmentView(d.compact, showIcon: false, ink: ink)
                }

            case .full, .adaptive:
                HStack(spacing: 8) {
                    ForEach(Array(d.segments.enumerated()), id: \.offset) { _, seg in
                        self.segmentView(seg, showIcon: d.showIcons, ink: ink)
                    }
                }
            }
        }
        // Tam monospaced: rakamlar VE harfler (% K M) eşit genişlik -> kayma yok.
        .font(.system(size: fontSize, weight: .regular, design: .monospaced))
        .foregroundStyle(ink)
        .padding(.vertical, 1)
        .fixedSize()

        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return nil }
        // Renkli çiziyoruz; sistem yeniden renklendirmesin.
        image.isTemplate = false
        return image
    }

    @ViewBuilder
    private func segmentView(_ seg: LabelSegment, showIcon: Bool, ink: Color) -> some View {
        HStack(spacing: 3) {
            if showIcon {
                Image(systemName: seg.icon)
                    .imageScale(.small)
                    .frame(width: 16, alignment: .center) // ikon alanı sabit
            }
            Text(seg.text)
                // Değer alanı sabit genişlikte: rakam değişince toplam genişlik
                // ve dolayısıyla menu bar'daki komşu öğelerin konumu oynamasın.
                .frame(width: seg.width, alignment: .leading)
        }
    }

    // MARK: - Renk

    /// Strese göre mürekkep rengi: nötr (menu bar temel rengi) -> kırmızı.
    /// Aktif uyarı varsa doğrudan kırmızıya sabitlenir — uyarı varken sönük
    /// görünmek, uyarıyı görünmez yapmak demektir.
    private func inkColor(stressStep: Int, alertLevel: Int, isDark: Bool) -> Color {
        let stress: CGFloat = alertLevel >= 0
            ? (alertLevel >= AlertSeverity.critical.rawValue ? 1.0 : 0.85)
            : CGFloat(stressStep) / 20.0

        let base: CGFloat = isDark ? 1.0 : 0.0   // koyu bar -> beyaz, açık bar -> siyah
        let target = (r: CGFloat(0.95), g: CGFloat(0.27), b: CGFloat(0.27))

        let r = base + (target.r - base) * stress
        let g = base + (target.g - base) * stress
        let b = base + (target.b - base) * stress

        // Rahatken biraz şeffaf (sönük), yük arttıkça tam opak.
        let alpha = 0.65 + 0.35 * stress

        return Color(nsColor: NSColor(srgbRed: r, green: g, blue: b, alpha: alpha))
    }
}
