import AppKit
import SwiftUI

/// Uygulama giriş noktası. Yalnızca bir `MenuBarExtra` sahnesi içerir —
/// pencere yok, Dock ikonu yok; sadece menu bar uygulaması.
@main
struct StatusAppBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var metrics = MetricsManager()
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(metrics)
                .environmentObject(settings)
        } label: {
            MenuBarLabel(metrics: metrics, settings: settings)
        }
        .menuBarExtraStyle(.window) // tıklayınca özel SwiftUI penceresi açılsın
    }
}

/// Bundle'sız (swift run) çalıştırıldığında bile Dock ikonu çıkmasın diye
/// aktivasyon politikasını accessory'e sabitler.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Dökümantasyon görseli üretme modu:
        //   StatusAppBar --make-docs <dizin>
        // TAMAMEN mock veriyle (gerçek makineden hiçbir bilgi okumadan) README
        // görsellerini üretir ve çıkar.
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
        // Tutarlı, şık koyu tema.
        NSApp.appearance = NSAppearance(named: .darkAqua)

        // Demo için bardaki tüm metrikleri aç; kullanıcının GERÇEK ayarlarını
        // bozmamak için önce mevcut değerleri saklayıp sonra geri yükle.
        let settings = AppSettings()
        let saved = (settings.showCPU, settings.showRAM, settings.showDisk,
                     settings.showNetwork, settings.showIcons)
        settings.showCPU = true
        settings.showRAM = true
        settings.showDisk = true
        settings.showNetwork = true
        settings.showIcons = true

        // Popover (mock)
        writePNG(
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                PopoverView()
                    .environmentObject(MetricsManager.mock(cpuTotal: 0.34))
                    .environmentObject(settings)
            }
            .frame(width: 460)
            .fixedSize()
            .environment(\.colorScheme, .dark),
            to: dir + "/popover.png"
        )

        // Menu bar etiketi — normal/rahat (nötr)
        writePNG(barStrip(MetricsManager.mock(cpuTotal: 0.20), settings),
                 to: dir + "/menubar.png")

        // Menu bar etiketi — yük altında (kırmızı)
        writePNG(barStrip(MetricsManager.mock(cpuTotal: 0.97), settings),
                 to: dir + "/menubar-load.png")

        // Kullanıcı ayarlarını geri yükle.
        (settings.showCPU, settings.showRAM, settings.showDisk,
         settings.showNetwork, settings.showIcons) = saved
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
            FileHandle.standardError.write(Data("snapshot: nsImage nil for \(path)\n".utf8))
            return
        }
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("snapshot: png encode failed for \(path)\n".utf8))
            return
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            FileHandle.standardError.write(Data("snapshot: wrote \(path)\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("snapshot: write error \(error) for \(path)\n".utf8))
        }
    }
}
