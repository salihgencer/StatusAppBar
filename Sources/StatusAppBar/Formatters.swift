import Foundation

// Byte ve hız değerlerini insan-okunur stringlere çeviren yardımcılar.
enum Fmt {

    /// 1_500_000_000 -> "1.50 GB" gibi. Binary (1024) tabanlı, macOS storage
    /// gösteriminden farklı olarak bellek/RAM için uygundur.
    static func bytes(_ value: UInt64) -> String {
        bytes(Double(value))
    }

    static func bytes(_ value: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var v = value
        var i = 0
        while v >= 1024 && i < units.count - 1 {
            v /= 1024
            i += 1
        }
        // Küçük birimlerde ondalık göstermek gereksiz.
        if i <= 1 {
            return String(format: "%.0f %@", v, units[i])
        }
        return String(format: "%.1f %@", v, units[i])
    }

    /// Menu bar için kompakt hız: "1.2M", "320K", "0" (birim harfi tek karakter,
    /// "/s" yok). Dar alanda iki yön (↓↑) yan yana sığsın diye.
    static func rateCompact(_ bytesPerSec: Double) -> String {
        let units = ["", "K", "M", "G"]
        var v = bytesPerSec
        var i = 0
        while v >= 1024 && i < units.count - 1 {
            v /= 1024
            i += 1
        }
        if i == 0 { return "0" } // byte/sn seviyesi pratikte boşta demektir
        if v >= 100 { return String(format: "%.0f%@", v, units[i]) }
        return String(format: "%.1f%@", v, units[i])
    }

    /// Saniyedeki byte miktarını "43.8 MB/s" formatına çevirir.
    static func rate(_ bytesPerSec: Double) -> String {
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var v = bytesPerSec
        var i = 0
        while v >= 1024 && i < units.count - 1 {
            v /= 1024
            i += 1
        }
        return String(format: "%.1f %@", v, units[i])
    }

    /// 0.764 -> "76.4%"
    static func percent(_ fraction: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f%%", fraction * 100)
    }

    /// Saniye cinsinden uptime -> "1d 9h" / "9h 12m" / "12m"
    static func uptime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    /// Dakika cinsinden kalan süre -> "2:35"
    static func timeRemaining(_ minutes: Int) -> String {
        guard minutes >= 0 else { return "—" }
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
}
