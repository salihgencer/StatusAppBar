// YALNIZCA MAS (ücretli App Store sürümü) — bkz. BuildVariant.swift.
#if MAS

import AppKit
import Foundation

/// Modelin istediği araçları yerelde çalıştırır.
///
/// ONAY KURALI: `kill_process` tek yıkıcı araçtır ve asla doğrudan çalışmaz —
/// kullanıcı sohbet penceresinde görünen onay kartından açıkça "Sonlandır"
/// demelidir. Model metniyle gelen talimat ne olursa olsun (prompt injection
/// dahil) bu onay atlanamaz: onay UI'da, kodda, burada.
@MainActor
final class AIToolExecutor: ObservableObject {

    /// Taze anlık görüntü sağlayıcılar — DeepAnalysisWindow açılışta bağlar.
    /// Sohbet başlangıcındaki rapor eskir; araçlar GÜNCEL veriyi buradan alır.
    var snapshotProvider: (() -> AlertEngine.Snapshot)?
    var alertsProvider: (() -> [ActiveAlert])?

    /// Kullanıcı onayı bekleyen sonlandırma isteği (UI bunu gösterir).
    @Published private(set) var pendingKill: (pid: Int32, name: String)?

    private var killContinuation: CheckedContinuation<Bool, Never>?

    // MARK: - Yürütme

    func execute(_ call: AIToolCall) async -> String {
        guard let tool = AITool(rawValue: call.name) else {
            return "Bilinmeyen araç: \(call.name)"
        }

        switch tool {
        case .getSystemStatus:
            guard let snapshot = snapshotProvider?() else {
                return "Sistem durumu şu an alınamıyor (panel henüz açılmadı)."
            }
            return DiagnosticReport.build(snapshot, alerts: alertsProvider?() ?? [])

        case .listProcesses:
            guard let snapshot = snapshotProvider?() else {
                return "Proses listesi şu an alınamıyor."
            }
            return processList(snapshot.processes)

        case .openActivityMonitor:
            let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
            // Açıkça completionHandler'lı varyant: async bağlamda derleyici
            // async overload'ı seçip try/await ister; senkron çağrı yeterli.
            NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
            return AILocale.isTurkish ? "Activity Monitor açıldı." : "Activity Monitor opened."

        case .killProcess:
            guard let pid = call.pid, pid > 0 else {
                return AILocale.isTurkish ? "Geçersiz PID." : "Invalid PID."
            }
            return await killWithConfirmation(pid: pid)
        }
    }

    // MARK: - Proses sonlandırma (kullanıcı onaylı)

    private func killWithConfirmation(pid: Int32) async -> String {
        // Model yalnızca kendi kullanıcısının proseslerini görebilir (MAS
        // sandbox) — ama yine de kendimizi öldürme girişimini reddet.
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard pid != ownPID else {
            return AILocale.isTurkish ? "Bu uygulamanın kendisi sonlandırılamaz."
                                      : "The app cannot terminate itself."
        }

        let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "PID \(pid)"
        let approved = await askUserToConfirmKill(pid: pid, name: name)
        guard approved else {
            return AILocale.isTurkish ? "Kullanıcı işlemi reddetti."
                                      : "The user declined the action."
        }

        if kill(pid, SIGTERM) == 0 {
            return AILocale.isTurkish ? "\(name) sonlandırıldı (SIGTERM)."
                                      : "\(name) terminated (SIGTERM)."
        }
        // Sandbox başka kullanıcıların proseslerine sinyal göndermeyi
        // engelleyebilir — model bunu dürüstçe öğrenmeli.
        return AILocale.isTurkish
            ? "İşletim sistemi izin vermedi (errno \(errno)). Sandbox yalnızca kendi kullanıcının proseslerine izin verir."
            : "The OS denied the signal (errno \(errno)). The sandbox only allows the user's own processes."
    }

    private func askUserToConfirmKill(pid: Int32, name: String) async -> Bool {
        await withCheckedContinuation { continuation in
            killContinuation = continuation
            pendingKill = (pid, name)
        }
    }

    /// UI'daki onay kartı bunu çağırır.
    func resolveKill(_ approved: Bool) {
        pendingKill = nil
        killContinuation?.resume(returning: approved)
        killContinuation = nil
    }

    /// Sohbet sıfırlanırken asılı onay kalmasın (continuation sızıntısı).
    func cancelPendingKill() {
        resolveKill(false)
    }

    // MARK: - Biçimleme

    private func processList(_ p: ProcessMetrics) -> String {
        var out: [String] = []
        let tr = AILocale.isTurkish
        out.append(tr ? "En çok CPU:" : "Top CPU:")
        for row in p.topCPU.prefix(10) {
            out.append(String(format: "- %@ · %%%.0f CPU · %@ · PID %d",
                              row.name, row.cpu, Fmt.bytes(row.rss), row.pid))
        }
        out.append(tr ? "En çok bellek:" : "Top memory:")
        for row in p.topMemory.prefix(10) {
            out.append(String(format: "- %@ · %@ · PID %d",
                              row.name, Fmt.bytes(row.rss), row.pid))
        }
        return out.joined(separator: "\n")
    }
}

#endif
