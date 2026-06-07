import Foundation
import IOKit

/// Disk metrikleri iki kaynaktan gelir:
///  1) Volume doluluk oranları -> FileManager / URLResourceValues
///  2) Anlık okuma/yazma hızı   -> IOKit "IOBlockStorageDriver" registry sayaçları
/// Sayaçlar kümülatif olduğu için hız, iki ölçüm arası fark / geçen süre.
final class DiskMonitor {

    private var prevRead: UInt64 = 0
    private var prevWrite: UInt64 = 0
    private var prevTime: TimeInterval = 0

    func sample() -> DiskMetrics {
        var metrics = DiskMetrics()
        metrics.volumes = volumeList()

        let (read, write) = totalIOBytes()
        let now = ProcessInfo.processInfo.systemUptime
        if prevTime > 0 {
            let elapsed = now - prevTime
            if elapsed > 0 {
                metrics.readPerSec = Double(read &- prevRead) / elapsed
                metrics.writePerSec = Double(write &- prevWrite) / elapsed
            }
        }
        prevRead = read
        prevWrite = write
        prevTime = now

        return metrics
    }

    private func volumeList() -> [DiskVolume] {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeIsBrowsableKey,
            .volumeIsLocalKey
        ]

        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) else { return [] }

        var result: [DiskVolume] = []
        var seen = Set<String>()

        for url in urls {
            guard let vals = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            guard vals.volumeIsLocal == true, vals.volumeIsBrowsable == true else { continue }

            let total = UInt64(max(0, vals.volumeTotalCapacity ?? 0))
            let free = UInt64(max(0, vals.volumeAvailableCapacityForImportantUsage ?? 0))
            guard total > 0 else { continue }

            let name = vals.volumeName ?? url.lastPathComponent
            // Aynı volume bazen birden çok kez listelenir; isim+boyutla tekilleştir.
            let key = "\(name)-\(total)"
            if seen.contains(key) { continue }
            seen.insert(key)

            result.append(DiskVolume(name: name, total: total, free: free))
        }

        return result.sorted { $0.total > $1.total }
    }

    private func totalIOBytes() -> (read: UInt64, write: UInt64) {
        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0

        var iterator = io_iterator_t()
        let matching = IOServiceMatching("IOBlockStorageDriver")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return (0, 0)
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any],
               let stats = dict["Statistics"] as? [String: Any] {
                if let r = stats["Bytes (Read)"] as? NSNumber { totalRead += r.uint64Value }
                if let w = stats["Bytes (Write)"] as? NSNumber { totalWrite += w.uint64Value }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }

        return (totalRead, totalWrite)
    }
}
