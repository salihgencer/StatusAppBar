import SwiftUI

/// Görseldeki terminal estetiğine yakın renk paleti ve eşik-renk mantığı.
enum Theme {
    static let cpu = Color(red: 0.95, green: 0.45, blue: 0.45)      // kırmızımsı
    static let memory = Color(red: 0.55, green: 0.75, blue: 0.95)   // mavi
    static let disk = Color(red: 0.95, green: 0.80, blue: 0.40)     // sarı
    static let power = Color(red: 0.55, green: 0.85, blue: 0.55)    // yeşil
    static let network = Color(red: 0.75, green: 0.65, blue: 0.95)  // mor

    /// Bir doluluk oranını (0...1) duruma göre renklendirir:
    /// düşük=yeşil, orta=sarı, yüksek=kırmızı. Bar dolulukları bunu kullanır.
    static func level(_ fraction: Double) -> Color {
        switch fraction {
        case ..<0.60: return Color(red: 0.45, green: 0.80, blue: 0.45)
        case ..<0.85: return Color(red: 0.95, green: 0.78, blue: 0.35)
        default:      return Color(red: 0.92, green: 0.40, blue: 0.40)
        }
    }
}
