import Foundation

/// Termal durumu `ProcessInfo.thermalState` üzerinden okur.
///
/// NEDEN BU API:
/// macOS'ta CPU/SoC sıcaklığını okumak SMC erişimi ister; Apple Silicon'da
/// sensör anahtarları modelden modele değişir ve imzasız bir uygulamada
/// güvenilir çalışmaz. `thermalState` ise resmi, ayrıcalıksız ve asıl
/// önemli soruyu cevaplar: sistem kendini kısıyor mu?
///
/// Sıcaklık değeri "kaç derece" merakını giderir; thermalState "fan neden
/// dönüyor" sorusunu cevaplar. İkincisi bu uygulamanın işi.
nonisolated final class ThermalMonitor {

    func sample() -> ThermalMetrics {
        var m = ThermalMetrics()
        m.state = ProcessInfo.processInfo.thermalState
        return m
    }
}
