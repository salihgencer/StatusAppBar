import AppKit
import Darwin
import Foundation

/// Çalışma boyunca değişmeyen makine bilgilerini bir kez toplar.
enum MachineInfoProvider {

    static func current() -> MachineInfo {
        var info = MachineInfo()
        info.chip = cpuBrand()
        info.totalRAMBytes = ProcessInfo.processInfo.physicalMemory
        info.coreCount = ProcessInfo.processInfo.processorCount
        info.refreshRateHz = NSScreen.main?.maximumFramesPerSecond ?? 0

        let v = ProcessInfo.processInfo.operatingSystemVersion
        info.osVersion = "macOS \(v.majorVersion).\(v.minorVersion)"

        return info
    }

    private static func cpuBrand() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return "—" }
        var bytes = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &bytes, &size, nil, 0)
        return String(cString: bytes)
    }
}
