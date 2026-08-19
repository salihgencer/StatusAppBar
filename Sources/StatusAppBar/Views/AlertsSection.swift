import AppKit
import SwiftUI

/// Aktif uyarılar + suçlu proses + tek tıklık aksiyonlar.
/// Uyarı yoksa hiç çizilmez — sakin durumda panel şişmesin.
struct AlertsSection: View {
    @Environment(MetricsManager.self) var metrics

    var body: some View {
        if !metrics.alerts.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(metrics.alerts) { alert in
                    AlertCard(alert: alert)
                }
            }
        }
    }
}

private struct AlertCard: View {
    let alert: ActiveAlert

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: alert.kind.icon)
                    .foregroundStyle(accent)
                Text(alert.headline)
                    .fontWeight(.semibold)
                Spacer()
                Text(Fmt.uptime(Date().timeIntervalSince(alert.since)))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 11))

            Text(alert.detail)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(alert.advice)
                .font(.system(size: 10))
                .fixedSize(horizontal: false, vertical: true)

            if let culprit = alert.culprit {
                HStack(spacing: 6) {
                    Button("Activity Monitor'de aç") { openActivityMonitor() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                    Text("·").foregroundStyle(.secondary)
                    Button(String(format: String(localized: "PID %d kopyala"), culprit.pid)) { copy("\(culprit.pid)") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                }
                .font(.system(size: 10))
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(accent.opacity(0.35), lineWidth: 1)
        )
    }

    private var accent: Color {
        switch alert.severity {
        case .critical: return Theme.cpu
        case .warning:  return Theme.disk
        case .info:     return Theme.memory
        }
    }

    /// Prosesi öldürme butonu BİLİNÇLİ olarak yok: menu bar uygulamasından
    /// tek tıkla proses sonlandırmak, yanlış tıklamada veri kaybı demek.
    /// Kullanıcıyı Activity Monitor'e yönlendirip kararı ona bırakıyoruz.
    private func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Derin analiz

#if MAS
/// Gemini ile teşhis. Sadece kullanıcı bastığında çalışır; arka planda
/// periyodik istek yok. Yalnızca ücretli MAS sürümünde derlenir (BuildVariant).
struct DeepAnalysisSection: View {
    @Environment(MetricsManager.self) var metrics
    @Environment(AppSettings.self) var settings
    private var advisor: AdvisorStore { AdvisorStore.shared }
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    openChat()
                } label: {
                    Label(advisor.hasConversation
                          ? String(localized: "Sohbeti aç")
                          : String(localized: "Derin analiz"),
                          systemImage: "sparkles")
                        .font(.system(size: 11))
                }
                .disabled(!settings.aiConfigured)

                Button {
                    advisor.copyReport(snapshot: metrics.snapshot(), alerts: metrics.alerts)
                } label: {
                    Label("Raporu kopyala", systemImage: "doc.on.doc")
                        .font(.system(size: 11))
                }

                Spacer()

                if advisor.hasConversation || advisor.errorText != nil {
                    Button("Temizle") { advisor.clear() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            if !settings.aiConfigured {
                Text(String(format: String(localized: "%@ ayarlanmamış — \"Raporu kopyala\" ile tam teşhis metnini alıp istediğin yere yapıştırabilirsin."), settings.aiProvider.label))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Anahtarsız tam tur: sağlayıcıyı demo'ya çekip sohbeti açar.
                // App Review'ın 2.1(a) "demonstration mode" isteğinin girişi.
                Button {
                    settings.aiProviderRaw = AIProvider.demo.rawValue
                    openChat()
                } label: {
                    Label("Demo dene", systemImage: "sparkles")
                        .font(.system(size: 11))
                }
            }

            if let error = advisor.errorText {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.cpu)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Yazışmanın kendisi ayrı pencerede; burada yalnızca durum satırı.
            if advisor.hasConversation {
                Text(advisor.isRunning
                     ? String(localized: "Analiz ediliyor…")
                     : String(format: String(localized: "Sohbet açık — %ld mesaj"), advisor.messages.count))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    /// Sohbeti açar; ilk kez açılıyorsa analizi de başlatır.
    ///
    /// `NSApp.activate` şart: uygulama `LSUIElement` (accessory) olduğu için
    /// pencere açmak onu öne getirmez — arkada açılır ve kullanıcı hiçbir şey
    /// olmadı sanır.
    private func openChat() {
        advisor.start(snapshot: metrics.snapshot(), alerts: metrics.alerts)
        openWindow(id: StatusAppBarApp.deepAnalysisWindowID)
        NSApp.activate(ignoringOtherApps: true)
    }
}
#endif

// MARK: - En çok tüketen prosesler

struct TopProcessesSection: View {
    @Environment(MetricsManager.self) var metrics

    var body: some View {
        let procs = metrics.processes
        SectionCard(icon: "list.bullet", title: String(localized: "En çok tüketenler"), accent: Theme.network) {
            if procs.isEmpty {
                Text("Ölçülüyor…").font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                ForEach(procs.topCPU.prefix(4)) { p in
                    ProcessLine(name: p.name,
                                right: "\(Int(p.cpu))% · \(Fmt.bytes(p.rss))")
                }
                if procs.kernelTaskCPU > 5 {
                    ProcessLine(name: "kernel_task",
                                right: "\(Int(procs.kernelTaskCPU))%",
                                muted: true)
                }
            }
        }
    }
}

private struct ProcessLine: View {
    var name: String
    var right: String
    var muted: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Text(name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text(right)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 10))
        .foregroundStyle(muted ? .secondary : .primary)
    }
}
