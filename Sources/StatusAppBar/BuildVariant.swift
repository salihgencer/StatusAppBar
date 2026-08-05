import Foundation

/// Derleme varyantı.
///
/// İKİ KANAL VAR:
/// - **Ücretsiz (GitHub)**: SwiftPM ile derlenir (`swift build` / `build.sh`),
///   hiçbir özel bayrak yok. PolyForm Noncommercial lisanslı; ticari kullanım
///   yasak. Gemini derin analiz bu sürümde YOK.
/// - **Ücretli (Mac App Store)**: Xcode/fastlane ile derlenir, `MAS`
///   derleme koşulu tanımlıdır (project.yml → SWIFT_ACTIVE_COMPILATION_CONDITIONS).
///   App Sandbox açık; sandbox'ın izin vermediği yollar (`ps`, `osascript`)
///   bu varyantta alternatifleriyle değiştirilir.
///
/// Yeni bir "yalnızca MAS" veya "yalnızca ücretsiz" davranış eklerken
/// `#if MAS` kullan; derleme zamanı ayrımı, çalışma zamanı kontrolünden
/// güvenlidir — bayraksız derlemede kod derlemeye hiç girmez.
enum BuildVariant {
    #if MAS
    static let isMAS = true
    #else
    static let isMAS = false
    #endif
}
