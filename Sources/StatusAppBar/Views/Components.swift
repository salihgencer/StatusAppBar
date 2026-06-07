import SwiftUI

/// Doluluk barı: arka plan ray + renkli dolum. Görseldeki blok barların
/// native karşılığı.
struct MetricBar: View {
    var fraction: Double
    var color: Color?      // nil => eşik-renk (yeşil/sarı/kırmızı) otomatik

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(color ?? Theme.level(fraction))
                    .frame(width: max(2, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 6)
    }
}

/// Etiket + bar + sağda değer şeklinde tek satır.
struct MetricRow: View {
    var label: String
    var value: String
    var fraction: Double
    var color: Color?

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(width: 52, alignment: .leading)
                .foregroundStyle(.secondary)
            MetricBar(fraction: fraction, color: color)
            Text(value)
                .frame(width: 70, alignment: .trailing)
                .monospacedDigit()
        }
        .font(.system(size: 11))
    }
}

/// Sadece "etiket: değer" gösteren, barsız satır (load, IP, sıcaklık vb.).
struct InfoRow: View {
    var label: String
    var value: String
    var valueColor: Color = .primary

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(width: 52, alignment: .leading)
                .foregroundStyle(.secondary)
            Text(value)
                .foregroundStyle(valueColor)
                .monospacedDigit()
            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
    }
}

/// İkon + başlıklı, kenarlıklı bölüm kartı.
struct SectionCard<Content: View>: View {
    var icon: String
    var title: String
    var accent: Color
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .foregroundStyle(accent)
                Text(title)
                    .fontWeight(.semibold)
                Spacer()
            }
            .font(.system(size: 11))

            content
        }
        .padding(8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }
}
