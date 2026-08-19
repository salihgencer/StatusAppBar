import Foundation

/// Bir klasör içindeki dosya ve alt klasörleri boyutlarına göre sıralar.
/// Sandbox'ta kullanıcının erişim izni verdiği klasörler taranabilir.
@Observable
final class DiskAnalyzer {

    struct Entry: Identifiable {
        let id = UUID()
        var name: String
        var path: URL
        var size: UInt64
        var isDirectory: Bool

        var sizeText: String { Fmt.bytes(size) }
    }

    private(set) var entries: [Entry] = []
    private(set) var isScanning = false
    private(set) var totalSize: UInt64 = 0
    private(set) var scannedPath: URL?

    @ObservationIgnored private var scanTask: Task<Void, Never>?

    /// Verilen klasörü tarar. Önceki taramayı iptal eder.
    func scan(url: URL) {
        scanTask?.cancel()
        isScanning = true
        scannedPath = url
        entries = []
        totalSize = 0

        scanTask = Task.detached(priority: .utility) { [weak self] in
            let fm = FileManager.default
            let keys: [URLResourceKey] = [.isDirectoryKey, .totalFileAllocatedSizeKey,
                                           .fileAllocatedSizeKey, .nameKey]

            var results: [Entry] = []

            guard let children = try? fm.contentsOfDirectory(
                at: url, includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            ) else {
                await MainActor.run { [weak self] in
                    self?.isScanning = false
                }
                return
            }

            for child in children {
                if Task.isCancelled { return }

                guard let vals = try? child.resourceValues(forKeys: Set(keys)) else { continue }
                let isDir = vals.isDirectory ?? false
                let size: UInt64

                if isDir {
                    size = Self.directorySize(url: child, fm: fm, keys: keys)
                } else {
                    size = UInt64(vals.totalFileAllocatedSize ?? vals.fileAllocatedSize ?? 0)
                }

                results.append(Entry(
                    name: vals.name ?? child.lastPathComponent,
                    path: child,
                    size: size,
                    isDirectory: isDir
                ))
            }

            results.sort { $0.size > $1.size }
            let total = results.reduce(0) { $0 + $1.size }

            await MainActor.run { [weak self] in
                guard !Task.isCancelled else { return }
                self?.entries = results
                self?.totalSize = total
                self?.isScanning = false
            }
        }
    }

    /// Alt dizin boyutunu özyinelemeli hesaplar. Çok derin ağaçlarda
    /// performans için enumerator kullanır (özyineleme yerine).
    nonisolated private static func directorySize(url: URL, fm: FileManager,
                                                   keys: [URLResourceKey]) -> UInt64 {
        guard let enumerator = fm.enumerator(
            at: url, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles], errorHandler: nil
        ) else { return 0 }

        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            if Task.isCancelled { break }
            guard let vals = try? fileURL.resourceValues(
                forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isDirectoryKey]
            ) else { continue }
            if vals.isDirectory == true { continue }
            total += UInt64(vals.totalFileAllocatedSize ?? vals.fileAllocatedSize ?? 0)
        }
        return total
    }
}
