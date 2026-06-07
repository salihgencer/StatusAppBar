import Foundation
import IOKit
import IOKit.ps

/// Güç / batarya bilgisi iki kaynaktan birleştirilir:
///  1) IOPowerSources API  -> şarj seviyesi, şarj durumu, kalan süre
///  2) AppleSmartBattery registry -> döngü sayısı, sıcaklık, sağlık %, adaptör watt
final class PowerMonitor {

    func sample() -> PowerMetrics {
        var metrics = PowerMetrics()

        readPowerSources(into: &metrics)
        readSmartBattery(into: &metrics)

        return metrics
    }

    private func readPowerSources(into metrics: inout PowerMetrics) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return }

        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }

            metrics.hasBattery = true

            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            metrics.level = max > 0 ? Double(current) / Double(max) : 0

            metrics.isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
            metrics.isCharged = desc[kIOPSIsChargedKey] as? Bool ?? false

            if let state = desc[kIOPSPowerSourceStateKey] as? String {
                metrics.onAC = (state == kIOPSACPowerValue)
            }

            // Kalan süre: şarjda -> "time to full", değilse "time to empty".
            // -1 hesaplanıyor / sınırsız anlamına gelir.
            let toEmpty = desc[kIOPSTimeToEmptyKey] as? Int ?? -1
            let toFull = desc[kIOPSTimeToFullChargeKey] as? Int ?? -1
            metrics.timeRemainingMinutes = metrics.onAC ? toFull : toEmpty
        }
    }

    private func readSmartBattery(into metrics: inout PowerMetrics) {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any]
        else { return }

        metrics.hasBattery = true

        if let cycles = dict["CycleCount"] as? Int {
            metrics.cycleCount = cycles
        }
        // Temperature: 1/100 °C cinsinden gelir (örn. 3080 -> 30.8°C).
        if let temp = dict["Temperature"] as? Int {
            metrics.temperature = Double(temp) / 100.0
        }
        // Sağlık: gerçek max kapasite / tasarım kapasitesi.
        let rawMax = dict["AppleRawMaxCapacity"] as? Int ?? (dict["MaxCapacity"] as? Int ?? 0)
        let design = dict["DesignCapacity"] as? Int ?? 0
        if design > 0 {
            metrics.healthPercent = min(100, Double(rawMax) / Double(design) * 100.0)
        }
        // Adaptör gücü (watt) AdapterDetails içinde.
        if let adapter = dict["AdapterDetails"] as? [String: Any],
           let watts = adapter["Watts"] as? Int {
            metrics.adapterWatts = watts
        }
    }
}
