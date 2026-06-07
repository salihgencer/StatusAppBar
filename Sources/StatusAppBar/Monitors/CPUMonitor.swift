import Darwin
import Foundation

/// CPU kullanımını Mach `host_processor_info` ile okur.
/// Çekirdek tick sayaçları kümülatiftir; kullanım yüzdesi ancak iki ölçüm
/// arasındaki FARK'tan hesaplanır. Bu yüzden önceki örneği saklıyoruz ve
/// ilk tick'te (önceki yokken) 0 döndürüyoruz.
final class CPUMonitor {

    private struct CoreTicks {
        var user: UInt32
        var system: UInt32
        var idle: UInt32
        var nice: UInt32
    }

    private var previous: [CoreTicks] = []
    private let pCores: Int
    private let eCores: Int

    init() {
        // Apple Silicon'da perflevel0 = performance, perflevel1 = efficiency çekirdekler.
        pCores = CPUMonitor.sysctlInt("hw.perflevel0.logicalcpu") ?? 0
        eCores = CPUMonitor.sysctlInt("hw.perflevel1.logicalcpu") ?? 0
    }

    func sample() -> CPUMetrics {
        var metrics = CPUMetrics(pCores: pCores, eCores: eCores)

        // Load average (1/5/15 dk) — libc'den doğrudan.
        var loads = [Double](repeating: 0, count: 3)
        getloadavg(&loads, 3)
        metrics.load = loads

        var cpuCount: natural_t = 0
        var infoArray: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let kr = host_processor_info(
            mach_host_self(),
            processor_flavor_t(PROCESSOR_CPU_LOAD_INFO),
            &cpuCount,
            &infoArray,
            &infoCount
        )

        guard kr == KERN_SUCCESS, let info = infoArray else {
            return metrics
        }

        // host_processor_info bize VM içinde tahsis edilmiş bir buffer döndürür;
        // bittiğinde elle serbest bırakmak gerekir.
        defer {
            let address = vm_address_t(UInt(bitPattern: OpaquePointer(info)))
            vm_deallocate(
                mach_task_self_,
                address,
                vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)
            )
        }

        let stateMax = Int(CPU_STATE_MAX)
        var current: [CoreTicks] = []
        current.reserveCapacity(Int(cpuCount))

        for i in 0..<Int(cpuCount) {
            let base = i * stateMax
            let ticks = CoreTicks(
                user: UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                system: UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                idle: UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                nice: UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
            )
            current.append(ticks)
        }

        if previous.count == current.count {
            var cores: [Double] = []
            cores.reserveCapacity(current.count)
            for i in 0..<current.count {
                // &- : sayaç 32-bit'te taşsa bile fark doğru çıkar.
                let dUser = Double(current[i].user &- previous[i].user)
                let dSystem = Double(current[i].system &- previous[i].system)
                let dIdle = Double(current[i].idle &- previous[i].idle)
                let dNice = Double(current[i].nice &- previous[i].nice)
                let busy = dUser + dSystem + dNice
                let totalTicks = busy + dIdle
                cores.append(totalTicks > 0 ? busy / totalTicks : 0)
            }
            metrics.cores = cores
            metrics.total = cores.isEmpty ? 0 : cores.reduce(0, +) / Double(cores.count)
        }

        previous = current
        return metrics
    }

    static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? Int(value) : nil
    }
}
