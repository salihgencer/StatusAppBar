import Foundation
#if MAS
import AppKit
#endif

/// Proses listesini örnekler; uyarılarda "suçlu"yu adlandırmak için kullanılır.
///
/// İKİ YOL VAR — derleme varyantına göre (bkz. BuildVariant.swift):
/// - **Ücretsiz (SwiftPM)**: `ps` alt prosesi. `proc_pidinfo` başka
///   kullanıcıya ait prosesler için ayrıcalık ister ve boş döner — tam da
///   izlemek istediğimiz iki proses (`kernel_task` root, `WindowServer`
///   _windowserver) bu grupta. `ps` aynı veriyi sysctl'den ayrıcalıksız okur.
/// - **MAS (sandbox)**: `ps` çalışmaz (sandbox'lı uygulama sistem binary'si
///   spawn edemez; spawn edebilse bile child sandbox'ı miras alır ve başka
///   proses göremez). Bunun yerine `NSWorkspace` + `libproc` kullanılır —
///   bedeli: başka kullanıcıların prosesleri (kernel_task, WindowServer)
///   okunamaz; bu alanlar sıfır kalır ve ilgili uyarı kuralları (termal,
///   uptime) kendiliğinden sadeleşir. iStat Menus'ün MAS sürümü de aynı
///   sınıra ayrı "helper" indirerek çözüyor; biz helper'sız kalıyoruz.
///
/// MALİYET: varsayılan 10 sn'de bir örnekleme. Ana 1 sn'lik metrik
/// döngüsünden bilinçli olarak ayrık tutuldu; izlemenin kendisi ölçtüğü
/// soruna dönüşmesin diye.
nonisolated final class ProcessMonitor {

    /// Örnekleme aralığı (saniye).
    var interval: TimeInterval = 10

    private var cached = ProcessMetrics()
    private var lastRun: Date = .distantPast

    #if MAS
    /// CPU yüzdesi, `proc_pidinfo` toplam CPU zamanının iki örnekleme
    /// arasındaki delta'sından hesaplanır; pid başına son toplam burada tutulur.
    private var cpuBaseline: [Int32: (cpuTick: UInt64, at: Date)] = [:]

    /// mach tick → nanosaniye çarpanı. `pti_total_user/system` nanosaniye
    /// DEĞİL, mach_absolute_time tick'i döndürür (cihazda doğrulandı:
    /// Apple Silicon'da timebase 125/3 — ham değer ~41.7× küçük gelir).
    private static let tickToNs: Double = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return Double(tb.numer) / Double(tb.denom)
    }()
    #endif

    /// `force: true` — uyarı değerlendirmesi taze suçlu isterse aralığı atlar.
    func sample(force: Bool = false) -> ProcessMetrics {
        if !force, Date().timeIntervalSince(lastRun) < interval { return cached }
        lastRun = Date()
        if let fresh = read() { cached = fresh }
        return cached
    }

    // MARK: - Okuma

    private func read() -> ProcessMetrics? {
        #if MAS
        return readSandboxed()
        #else
        return readViaPS()
        #endif
    }

    #if MAS
    /// Sandbox uyumlu okuma: liste `NSWorkspace`'ten, RSS ve CPU toplamları
    /// `proc_pidinfo(PROC_PIDTASKINFO)`'dan.
    ///
    /// `proc_pid_rusage` BİLİNÇLİ olarak kullanılmıyor: sandbox'ta başka
    /// prosesler için `deny(1) process-info-rusage others` ile reddediliyor
    /// (cihazda doğrulandı, macOS 26). `proc_pidinfo` ise izinli; görev
    /// bilgisinin taşıdığı toplam CPU zamanı aynı işi görür.
    private func readSandboxed() -> ProcessMetrics? {
        let now = Date()
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var rows: [ProcessRow] = []
        rows.reserveCapacity(256)
        var newBaseline: [Int32: (cpuTick: UInt64, at: Date)] = [:]

        for app in NSWorkspace.shared.runningApplications {
            let pid = app.processIdentifier
            guard pid > 0, pid != ownPID else { continue }

            var info = proc_taskinfo()
            let infoSize = Int32(MemoryLayout<proc_taskinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, infoSize) == infoSize else {
                continue // başka kullanıcının prosesi ya da az önce öldü
            }

            // İlk turda referans yok, cpu=0 kalır — uyarı kurallarının bekleme
            // (dwell) süreleri bunu tolere eder.
            var cpu = 0.0
            let cpuTick = info.pti_total_user + info.pti_total_system
            if let prev = cpuBaseline[pid] {
                let dWall = now.timeIntervalSince(prev.at)
                if dWall > 0 {
                    cpu = Double(cpuTick &- prev.cpuTick) * Self.tickToNs / 1e9 / dWall * 100
                }
            }
            newBaseline[pid] = (cpuTick, now)

            let path = app.executableURL?.path ?? ""
            rows.append(ProcessRow(
                pid: pid,
                name: app.localizedName ?? Self.displayName(for: path),
                path: path,
                cpu: cpu,
                rss: info.pti_resident_size
            ))
        }
        cpuBaseline = newBaseline

        guard !rows.isEmpty else { return nil }

        var m = ProcessMetrics()
        m.total = rows.count
        m.sampledAt = now
        m.topCPU = Array(rows.sorted { $0.cpu > $1.cpu }.prefix(8))
        m.topMemory = Array(rows.sorted { $0.rss > $1.rss }.prefix(8))
        return m
    }
    #else
    /// Ücretsiz sürüm yolu: `ps` alt prosesi.
    private func readViaPS() -> ProcessMetrics? {
        // pcpu: son örneklemeye göre değil, prosesin ömrü boyunca ortalama DEĞİL —
        // ps bunu kısa aralıklı bir örnekten hesaplar; Activity Monitor ile
        // aynı mertebede olur. Sıralama için fazlasıyla yeterli.
        guard let out = Self.shell("/bin/ps", ["-Ao", "pid=,pcpu=,rss=,comm=", "-r"]) else {
            return nil
        }

        var rows: [ProcessRow] = []
        rows.reserveCapacity(512)

        var kernelCPU: Double = 0
        var wsRSS: UInt64 = 0
        var wsCPU: Double = 0

        for line in out.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let row = Self.parse(line) else { continue }

            if row.pid == 0 || row.path == "kernel_task" {
                kernelCPU = row.cpu
                continue // listede göstermeye gerek yok, ayrı alanda tutuyoruz
            }
            if row.path.hasSuffix("/WindowServer") {
                wsRSS = row.rss
                wsCPU = row.cpu
            }
            rows.append(row)
        }

        guard !rows.isEmpty else { return nil }

        var m = ProcessMetrics()
        m.total = rows.count + 1
        m.sampledAt = Date()
        m.kernelTaskCPU = kernelCPU
        m.windowServerRSS = wsRSS
        m.windowServerCPU = wsCPU
        // ps zaten -r ile CPU'ya göre sıralı geliyor; yine de garanti altına al.
        m.topCPU = Array(rows.sorted { $0.cpu > $1.cpu }.prefix(8))
        m.topMemory = Array(rows.sorted { $0.rss > $1.rss }.prefix(8))
        return m
    }
    #endif

    // MARK: - Satır ayrıştırma (yalnızca ücretsiz sürümün `ps` yolu kullanır)

    #if !MAS

    /// "  123  45.6  789012 /path/to/bin" -> ProcessRow
    ///
    /// Elle tokenize ediyoruz çünkü komut yolu boşluk içerebiliyor
    /// ("Claude Helper (Renderer)") ve `split(maxSplits:)` baştaki boşlukları
    /// son parçaya bulaştırıyor.
    private static func parse(_ line: Substring) -> ProcessRow? {
        var rest = line[...]

        func token() -> Substring? {
            while let f = rest.first, f == " " || f == "\t" { rest = rest.dropFirst() }
            guard !rest.isEmpty else { return nil }
            guard let idx = rest.firstIndex(where: { $0 == " " || $0 == "\t" }) else {
                let t = rest
                rest = rest[rest.endIndex...]
                return t
            }
            let t = rest[rest.startIndex..<idx]
            rest = rest[idx...]
            return t
        }

        guard let p = token(), let pid = Int32(p),
              let c = token(), let cpu = Double(c),
              let r = token(), let rssKB = UInt64(r) else { return nil }

        let path = String(rest.drop(while: { $0 == " " || $0 == "\t" }))
        guard !path.isEmpty else { return nil }

        return ProcessRow(
            pid: pid,
            name: displayName(for: path),
            path: path,
            cpu: cpu,
            rss: rssKB * 1024
        )
    }
    #endif

    /// Tam yolu insanın tanıyacağı bir ada indirger.
    ///
    /// "/Applications/Ghostty.app/Contents/MacOS/ghostty"        -> "Ghostty"
    /// ".../Claude.app/.../Claude Helper (Renderer)"             -> "Claude"
    /// ".../emulator/qemu/darwin-aarch64/qemu-system-aarch64"    -> "qemu-system-aarch64"
    ///
    /// Electron uygulamalarında helper'ları ana uygulama adına toplamak
    /// bilinçli: kullanıcı "Claude Helper (GPU)" değil "Claude" görmek ister.
    static func displayName(for path: String) -> String {
        let base = (path as NSString).lastPathComponent

        guard let marker = path.range(of: ".app/Contents/"),
              let slash = path[..<marker.lowerBound].lastIndex(of: "/") else {
            return base
        }
        let appName = String(path[path.index(after: slash)..<marker.lowerBound])
        guard !appName.isEmpty else { return base }

        let a = appName.lowercased(), b = base.lowercased()
        if b.hasPrefix(a) || a.hasPrefix(b) { return appName }
        return "\(appName) › \(base)"
    }

    // MARK: - Alt proses (yalnızca ücretsiz sürüm)

    #if !MAS
    private static func shell(_ launchPath: String, _ args: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = args

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
        } catch {
            return nil
        }

        // Önce oku sonra bekle: büyük çıktıda pipe dolup deadlock olmasın.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        return String(data: data, encoding: .utf8)
    }
    #endif
}
