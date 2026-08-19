import Foundation
import IOKit

/// Apple SMC (System Management Controller) üzerinden sıcaklık sensörü ve
/// fan hızı okuyan düşük seviye yardımcı.
///
/// SANDBOX KISITI: `AppleSMC` servise erişim App Sandbox'ta engellenir.
/// Bu okuyucu yalnızca sandbox dışı build'lerde (SwiftPM / doğrudan imzalı)
/// çalışır. MAS build'inde derlenmeyi #if !MAS ile engelleyebilirsiniz veya
/// çalışma zamanında `open` başarısızlığını sessizce yutabilirsiniz.
///
/// SMC'nin yapısı: 4 harflik anahtar (FourCC) → farklı veri tipleri. Sıcaklık
/// sensörleri `sp78` (signed 78 fixed-point), fan hızları `fpe2` (unsigned
/// fixed-point) formatında döner.
nonisolated final class SMCReader {

    private var connection: io_connect_t = 0
    private var isOpen = false

    init() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                   IOServiceNameMatching("AppleSMC"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        if IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS {
            isOpen = true
        }
    }

    deinit {
        if isOpen { IOServiceClose(connection) }
    }

    // MARK: - Sıcaklık

    /// Bilinen Apple Silicon sıcaklık sensör anahtarları. Model bazında tümü
    /// mevcut olmayabilir; okunamayan sensörler atlanır.
    static let temperatureKeys: [(key: String, label: String)] = [
        ("Tp09", "CPU Package"),
        ("Tp01", "CPU Core 1"),
        ("Tp05", "CPU Core 2"),
        ("Tg05", "GPU"),
        ("TW0P", "Wireless"),
        ("Tm02", "Memory"),
        ("TB0T", "Battery"),
    ]

    struct SensorReading: Sendable {
        var label: String
        var temperature: Double // °C
    }

    func readTemperatures() -> [SensorReading] {
        guard isOpen else { return [] }
        var readings: [SensorReading] = []

        for (key, label) in Self.temperatureKeys {
            if let value = readSP78(key: key), value > 0, value < 130 {
                readings.append(SensorReading(label: label, temperature: value))
            }
        }
        return readings
    }

    // MARK: - Fan

    struct FanReading: Sendable {
        var index: Int
        var currentRPM: Int
        var minRPM: Int
        var maxRPM: Int
    }

    func readFans() -> [FanReading] {
        guard isOpen else { return [] }
        guard let count = readUI8(key: "FNum"), count > 0 else { return [] }

        var fans: [FanReading] = []
        for i in 0..<Int(count) {
            let actual = readFPE2(key: "F\(i)Ac") ?? 0
            let minimum = readFPE2(key: "F\(i)Mn") ?? 0
            let maximum = readFPE2(key: "F\(i)Mx") ?? 0
            if maximum > 0 {
                fans.append(FanReading(index: i, currentRPM: actual,
                                       minRPM: minimum, maxRPM: maximum))
            }
        }
        return fans
    }

    // MARK: - SMC düşük seviye IO

    /// SMC çağrı yapısı (Apple'ın kernel sürücüsüne göre ters mühendislik).
    private struct SMCKeyData {
        struct Version {
            var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0
            var reserved: UInt8 = 0
            var release: UInt16 = 0
        }
        struct PLimitData { var version: UInt16 = 0; var length: UInt16 = 0; var cpuPLimit: UInt32 = 0; var gpuPLimit: UInt32 = 0; var memPLimit: UInt32 = 0 }
        struct KeyInfo { var dataSize: UInt32 = 0; var dataType: UInt32 = 0; var dataAttributes: UInt8 = 0 }

        var key: UInt32 = 0
        var vers: Version = Version()
        var pLimitData: PLimitData = PLimitData()
        var keyInfo: KeyInfo = KeyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
            (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    }

    private func fourCC(_ s: String) -> UInt32 {
        var result: UInt32 = 0
        for (i, c) in s.utf8.prefix(4).enumerated() {
            result |= UInt32(c) << UInt32((3 - i) * 8)
        }
        return result
    }

    private func readRaw(key: String) -> [UInt8]? {
        guard isOpen else { return nil }

        var input = SMCKeyData()
        var output = SMCKeyData()
        input.key = fourCC(key)
        input.data8 = 9 // kSMCGetKeyInfo

        let inputSize = MemoryLayout<SMCKeyData>.stride
        var outputSize = inputSize

        var kr = IOConnectCallStructMethod(connection, 2,
                                            &input, inputSize,
                                            &output, &outputSize)
        guard kr == KERN_SUCCESS else { return nil }

        input.keyInfo = output.keyInfo
        input.data8 = 5 // kSMCReadKey

        kr = IOConnectCallStructMethod(connection, 2,
                                        &input, inputSize,
                                        &output, &outputSize)
        guard kr == KERN_SUCCESS else { return nil }

        let size = Int(output.keyInfo.dataSize)
        return withUnsafeBytes(of: &output.bytes) { Array($0.prefix(size)) }
    }

    private func readSP78(key: String) -> Double? {
        guard let bytes = readRaw(key: key), bytes.count >= 2 else { return nil }
        let raw = Int16(bytes[0]) << 8 | Int16(bytes[1])
        return Double(raw) / 256.0
    }

    private func readFPE2(key: String) -> Int? {
        guard let bytes = readRaw(key: key), bytes.count >= 2 else { return nil }
        let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        return Int(raw) >> 2
    }

    private func readUI8(key: String) -> UInt8? {
        guard let bytes = readRaw(key: key), !bytes.isEmpty else { return nil }
        return bytes[0]
    }
}
