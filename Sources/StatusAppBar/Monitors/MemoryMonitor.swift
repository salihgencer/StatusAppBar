import Darwin
import Foundation

/// Bellek kullanımını Mach `host_statistics64` (VM istatistikleri) ile okur.
/// "Used" hesabı Activity Monitor'ın mantığına yakın olacak şekilde:
///   used = active + inactive + wired + compressed − purgeable − external(file-backed)
/// Bu formül, dosya cache'i ve geri alınabilir (purgeable) belleği "kullanımda"
/// saymaz; gerçekten uygulamaların tuttuğu belleği gösterir.
nonisolated final class MemoryMonitor {

    /// Swap giriş/çıkış hızını hesaplamak için önceki örneğin sayaçları.
    /// Sayaçlar kümülatiftir (açılıştan beri); anlamlı olan farkıdır.
    private var lastSwapIns: UInt64 = 0
    private var lastSwapOuts: UInt64 = 0
    private var lastSampleAt: Date?

    func sample() -> MemoryMetrics {
        var metrics = MemoryMetrics()
        metrics.total = ProcessInfo.processInfo.physicalMemory

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let page = UInt64(pageSize)

        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let kr = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPtr, &count)
            }
        }

        guard kr == KERN_SUCCESS else {
            // Okuyamazsak en azından total/free için kaba bir tahmin döndür.
            return metrics
        }

        let active = UInt64(stats.active_count) * page
        let inactive = UInt64(stats.inactive_count) * page
        let wired = UInt64(stats.wire_count) * page
        let compressed = UInt64(stats.compressor_page_count) * page
        let purgeable = UInt64(stats.purgeable_count) * page
        let external = UInt64(stats.external_page_count) * page

        let occupied = active + inactive + wired + compressed
        let reclaimable = purgeable + external
        let used = occupied > reclaimable ? occupied - reclaimable : occupied

        metrics.used = min(used, metrics.total)
        metrics.free = metrics.total > metrics.used ? metrics.total - metrics.used : 0
        metrics.compressed = compressed

        // Swap kullanımı ayrı bir sysctl ile gelir.
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.stride
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 {
            metrics.swapTotal = swap.xsu_total
            metrics.swapUsed = swap.xsu_used
        }

        // Swap trafiği: sayaçlar kümülatif olduğu için farkı zamana böleriz.
        // İlk örnekte referans yok — hız 0 bırakılır (yanlış tepe göstermesin).
        let now = Date()
        let ins = stats.swapins
        let outs = stats.swapouts
        if let previous = lastSampleAt {
            let elapsed = now.timeIntervalSince(previous)
            if elapsed > 0.05 {
                // Sayaç geri sarabilir (nadiren); negatif farkı 0 say.
                let dIn = ins >= lastSwapIns ? ins - lastSwapIns : 0
                let dOut = outs >= lastSwapOuts ? outs - lastSwapOuts : 0
                metrics.swapInsPerSec = Double(dIn) * Double(page) / elapsed
                metrics.swapOutsPerSec = Double(dOut) * Double(page) / elapsed
            }
        }
        lastSwapIns = ins
        lastSwapOuts = outs
        lastSampleAt = now

        return metrics
    }
}
