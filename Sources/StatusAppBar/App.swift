import AppKit
import SwiftUI

/// Uygulama giriş noktası. Yalnızca bir `MenuBarExtra` sahnesi içerir —
/// pencere yok, Dock ikonu yok; sadece menu bar uygulaması.
@main
struct StatusAppBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // AppSettings.shared: uyarı motoru arka planda eşiklere erişiyor; iki ayrı
    // örnek olsaydı arayüzden değiştirilen eşik motora ulaşmazdı.
    @State private var settings = AppSettings.shared
    @State private var metrics = MetricsManager()

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(metrics)
                .environment(settings)
        } label: {
            MenuBarLabel(metrics: metrics, settings: settings)
        }
        .menuBarExtraStyle(.window)

        #if MAS
        // Derin analiz sohbeti ayrı bir pencerede yaşar: menu bar paneli odak
        // kaybedince kapanıyor, sohbet oraya sığmaz (bkz. DeepAnalysisWindow).
        // Yalnızca ücretli MAS sürümü (BuildVariant). `metrics` burada da
        // gerekli: araçlar ve "güncel durum" butonu taze ölçümü ondan alır.
        Window("Derin analiz", id: Self.deepAnalysisWindowID) {
            DeepAnalysisWindow()
                .environment(metrics)
                .environment(settings)
        }
        .defaultSize(width: 620, height: 560)
        .windowResizability(.contentMinSize)
        #endif
    }

    #if MAS
    static let deepAnalysisWindowID = "deep-analysis"
    #endif
}

/// Bundle'sız (swift run) çalıştırıldığında bile Dock ikonu çıkmasın diye
/// aktivasyon politikasını accessory'e sabitler.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Bildirim izni BURADA istenir. Daha erken (örn. init sırasında)
        // çağrıldığında istek sessizce düşüyor: uygulama henüz Launch
        // Services'e kaydolmadığı için Notification Center'a hiç ulaşmıyor.
        Notifier.shared.requestAuthorization()

        if let idx = CommandLine.arguments.firstIndex(of: "--make-docs") {
            let dir = idx + 1 < CommandLine.arguments.count
                ? CommandLine.arguments[idx + 1]
                : "docs"
            DispatchQueue.main.async {
                SnapshotRenderer.makeDocs(dir: dir)
                NSApp.terminate(nil)
            }
        }
    }
}

/// README görsellerini mock veriyle render eder. Gerçek makineden hiçbir
/// veri (IP, donanım, disk adı vb.) kullanmaz.
enum SnapshotRenderer {
    @MainActor
    static func makeDocs(dir: String) {
        NSApp.appearance = NSAppearance(named: .darkAqua)

        let settings = AppSettings()
        let saved = (settings.showCPU, settings.showRAM, settings.showDisk,
                     settings.showNetwork, settings.showIcons, settings.menuBarMode)
        settings.showCPU = true
        settings.showRAM = true
        settings.showDisk = true
        settings.showNetwork = true
        settings.showIcons = true
        settings.menuBarMode = .full

        writePNG(
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                PopoverContent()
                    .environment(MetricsManager.mock(cpuTotal: 0.34))
                    .environment(settings)
            }
            .fixedSize()
            .environment(\.colorScheme, .dark),
            to: dir + "/popover.png"
        )

        writePNG(barStrip(MetricsManager.mock(cpuTotal: 0.20), settings),
                 to: dir + "/menubar.png")

        writePNG(barStrip(MetricsManager.mock(cpuTotal: 0.97), settings),
                 to: dir + "/menubar-load.png")

        (settings.showCPU, settings.showRAM, settings.showDisk,
         settings.showNetwork, settings.showIcons, settings.menuBarMode) = saved
    }

    @MainActor
    private static func barStrip(_ metrics: MetricsManager, _ settings: AppSettings) -> some View {
        MenuBarLabel(metrics: metrics, settings: settings)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.13)))
            .fixedSize()
            .environment(\.colorScheme, .dark)
    }

    @MainActor
    private static func writePNG<V: View>(_ view: V, to path: String) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage else {
            Log.general.error("snapshot: nsImage nil for \(path)")
            return
        }
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            Log.general.error("snapshot: png encode failed for \(path)")
            return
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            Log.general.info("snapshot: wrote \(path)")
        } catch {
            Log.general.error("snapshot: write error \(error) for \(path)")
        }
    }
}
