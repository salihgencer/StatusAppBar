import Foundation
import IOKit

/// IOAccelerator üzerinden GPU kullanım oranını okur.
/// Apple Silicon'da GPU entegre olduğu için tek bir accelerator servisi yeterli.
/// IOKit performans istatistikleri her çağrıda anlık değer döner — delta hesabı gerekmez.
nonisolated final class GPUMonitor {

    func sample() -> GPUMetrics {
        var metrics = GPUMetrics()

        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOAccelerator")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return metrics
        }
        defer { IOObjectRelease(iterator) }

        var entry: io_registry_entry_t = IOIteratorNext(iterator)
        while entry != 0 {
            defer { IOObjectRelease(entry) }

            if let name = IORegistryEntryCreateCFProperty(entry, "model" as CFString, kCFAllocatorDefault, 0) {
                if let data = name.takeRetainedValue() as? Data, let str = String(data: data, encoding: .utf8) {
                    // C-string null terminator'ı atılır
                    metrics.name = str.replacingOccurrences(of: "\0", with: "")
                }
            }

            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any],
               let stats = dict["PerformanceStatistics"] as? [String: Any] {

                // Apple Silicon "Device Utilization %" kullanır,
                // eski Intel dGPU'lar "GPU Core Utilization %" raporlar.
                let raw = (stats["Device Utilization %"] as? Int)
                    ?? (stats["GPU Core Utilization %"] as? Int)
                    ?? 0
                metrics.utilization = Double(raw) / 100.0
            }

            entry = IOIteratorNext(iterator)
        }

        return metrics
    }
}
