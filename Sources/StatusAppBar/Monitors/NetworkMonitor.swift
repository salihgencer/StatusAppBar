import Darwin
import Foundation

/// Ağ trafiği `getifaddrs` ile okunur. Her arayüzün (en0, en1...) kümülatif
/// gelen/giden byte sayacı `if_data` içinde bulunur; hız = fark / geçen süre.
/// Sadece fiziksel "en*" arayüzlerini sayarız (loopback, utun, bridge hariç).
final class NetworkMonitor {

    private var prevRx: UInt64 = 0
    private var prevTx: UInt64 = 0
    private var prevTime: TimeInterval = 0

    func sample() -> NetworkMetrics {
        var metrics = NetworkMetrics()

        let (rx, tx) = interfaceBytes()
        let now = ProcessInfo.processInfo.systemUptime
        if prevTime > 0 {
            let elapsed = now - prevTime
            if elapsed > 0 {
                // &- taşma güvenliği için; clamp negatif -> 0.
                metrics.downPerSec = max(0, Double(rx &- prevRx) / elapsed)
                metrics.upPerSec = max(0, Double(tx &- prevTx) / elapsed)
            }
        }
        prevRx = rx
        prevTx = tx
        prevTime = now

        metrics.ipAddress = primaryIPAddress()
        return metrics
    }

    private func interfaceBytes() -> (rx: UInt64, tx: UInt64) {
        var rx: UInt64 = 0
        var tx: UInt64 = 0

        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0 else { return (0, 0) }
        defer { freeifaddrs(addrs) }

        var cursor = addrs
        while let ptr = cursor {
            defer { cursor = ptr.pointee.ifa_next }

            let name = String(cString: ptr.pointee.ifa_name)
            guard name.hasPrefix("en") else { continue }
            guard let addr = ptr.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_LINK),
                  let data = ptr.pointee.ifa_data else { continue }

            let ifData = data.assumingMemoryBound(to: if_data.self)
            rx += UInt64(ifData.pointee.ifi_ibytes)
            tx += UInt64(ifData.pointee.ifi_obytes)
        }

        return (rx, tx)
    }

    private func primaryIPAddress() -> String? {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0 else { return nil }
        defer { freeifaddrs(addrs) }

        var fallback: String?
        var cursor = addrs
        while let ptr = cursor {
            defer { cursor = ptr.pointee.ifa_next }

            let name = String(cString: ptr.pointee.ifa_name)
            guard name.hasPrefix("en") else { continue }
            guard let addr = ptr.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                addr,
                socklen_t(addr.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { continue }
            let ip = String(cString: host)

            // en0 tercih edilir; yoksa ilk bulunan en* fallback.
            if name == "en0" { return ip }
            if fallback == nil { fallback = ip }
        }

        return fallback
    }
}
