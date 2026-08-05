// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "StatusAppBar",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "StatusAppBar",
            path: "Sources/StatusAppBar",
            swiftSettings: [
                // Bu bir menu bar uygulaması: kodun ezici çoğunluğu UI ve ayar
                // okuma. Varsayılanı MainActor yapmak, izolasyonu istisna olan
                // tek yeri (örnekleme) açıkça yazmaya zorlar — tersi her dosyaya
                // @MainActor serpiştirmek olurdu.
                .defaultIsolation(MainActor.self),
                // Async fonksiyonlar çağıran aktörde kalsın. Örtük arka plana
                // atılma (Swift 6.1 ve öncesi) veri yarışı hatalarının en büyük
                // kaynağıydı; arka plan artık yalnızca `Sampler` aktöründe.
                .enableUpcomingFeature("NonisolatedNonsendingByDefault")
            ]
        )
    ]
)
