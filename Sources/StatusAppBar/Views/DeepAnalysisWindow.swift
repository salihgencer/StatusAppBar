// YALNIZCA MAS (ücretli App Store sürümü) — bkz. BuildVariant.swift.
#if MAS

import AppKit
import SwiftUI

/// Derin analiz sohbet penceresi.
///
/// NEDEN POPOVER DEĞİL AYRI PENCERE:
/// `MenuBarExtra(.window)` paneli odağı kaybettiği anda kapanır — başka bir
/// uygulamaya tıklamak, Cmd-Tab, hatta bazı metin alanı davranışları paneli
/// yok eder. Sohbetin ortasında konuşmanın ekrandan kaybolması kabul edilemez,
/// ayrıca 460 px genişlik uzun bir yazışma için dar. Bu yüzden gerçek,
/// yeniden boyutlandırılabilir bir pencere.
struct DeepAnalysisWindow: View {

    @ObservedObject private var advisor = AdvisorStore.shared
    @ObservedObject private var settings = AppSettings.shared
    @EnvironmentObject var metrics: MetricsManager

    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            transcript
            Divider()
            composer
        }
        .frame(minWidth: 480, minHeight: 360)
        .onAppear {
            inputFocused = true
            // Araçlar ve "güncel durum" butonu taze ölçümü buradan alır.
            advisor.configure(
                snapshot: { metrics.snapshot() },
                alerts: { metrics.alerts }
            )
        }
    }

    // MARK: - Yazışma

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(advisor.messages) { message in
                        MessageRow(message: message, modelLabel: settings.aiProvider.label)
                            .id(message.id)
                    }

                    // Akış halindeki yanıt: her SSE parçasında canlı büyür.
                    if !advisor.streamingText.isEmpty {
                        MessageRow(
                            message: ChatMessage(role: .model, text: advisor.streamingText),
                            modelLabel: settings.aiProvider.label
                        )
                        .id(Self.streamingAnchor)
                    } else if advisor.isRunning {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Düşünüyor…")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .id(Self.thinkingAnchor)
                    }

                    if let error = advisor.errorText {
                        HStack(spacing: 8) {
                            Text(error)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.cpu)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Tekrar dene") { advisor.retry() }
                                .font(.system(size: 11))
                        }
                        .id(Self.errorAnchor)
                    }

                    // Yıkıcı araç onayı: model ne derse desin proses
                    // sonlandırma ancak kullanıcı buradan onaylarsa çalışır.
                    if let pending = advisor.executor.pendingKill {
                        KillConfirmCard(pending: pending)
                            .id(Self.killAnchor)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Yeni mesaj geldiğinde en alta kaydır — sohbette beklenen davranış.
            .onChange(of: advisor.messages.count) { scrollToEnd(proxy) }
            .onChange(of: advisor.isRunning) { scrollToEnd(proxy) }
            .onChange(of: advisor.streamingText) { scrollToEnd(proxy) }
        }
    }

    private static let thinkingAnchor = "thinking"
    private static let streamingAnchor = "streaming"
    private static let errorAnchor = "error"
    private static let killAnchor = "kill"

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        let target: (any Hashable)? = {
            if advisor.executor.pendingKill != nil { return Self.killAnchor }
            if advisor.errorText != nil { return Self.errorAnchor }
            if !advisor.streamingText.isEmpty { return Self.streamingAnchor }
            if advisor.isRunning { return Self.thinkingAnchor }
            return advisor.messages.last?.id
        }()
        guard let target else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(AnyHashable(target), anchor: .bottom)
        }
    }

    // MARK: - Giriş

    private var composer: some View {
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Takip sorusu sor…", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .font(.system(size: 12))
                    .focused($inputFocused)
                    .disabled(!canSend)
                    .onSubmit(submit)

                Button(action: submit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .disabled(!canSend || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: [])
            }

            HStack(spacing: 10) {
                if !settings.aiConfigured {
                    Text(String(format: String(localized: "%@ ayarlanmamış — panelde Ayarlar → Derin analiz."),
                                settings.aiProvider.label))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if advisor.hasConversation {
                    // İlk rapor sohbet ilerledikçe eskir; taze ölçüm gönder.
                    Button {
                        advisor.refreshStatus()
                    } label: {
                        Label("Güncel durum", systemImage: "arrow.clockwise")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(advisor.isRunning)

                    Button("Yazışmayı kopyala") { advisor.copy(plainTranscript()) }
                        .buttonStyle(.plain)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    Button("Yeni analiz") { advisor.clear() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
    }

    private var canSend: Bool {
        !advisor.isRunning && settings.aiConfigured && advisor.hasConversation
    }

    private func submit() {
        let text = draft
        draft = ""
        advisor.ask(text)
    }

    /// Panoya kopyalanabilir düz metin. Sistem raporu VE araç sonuçları
    /// dahil edilmez — ikisi de makinenin IP'sini, disk adlarını ve proses
    /// listesini taşır; yazışmayı paylaşan kullanıcı bunları paylaşmamalı.
    private func plainTranscript() -> String {
        advisor.messages
            .filter { !$0.isSnapshot && $0.role != .tool }
            .map { "\($0.role == .user ? String(localized: "Sen") : settings.aiProvider.label):\n\($0.text)" }
            .joined(separator: "\n\n")
    }
}

// MARK: - Proses sonlandırma onay kartı

/// Model `kill_process` çağırdığında görünür. Onay verilmeden araç çalışmaz —
/// kart kapatılamaz, ancak "Sonlandır" veya "Reddet" ile yanıtlanır.
private struct KillConfirmCard: View {
    let pending: (pid: Int32, name: String)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("AI bir prosesi sonlandırmak istiyor", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.cpu)

            Text(String(format: String(localized: "%@ (PID %d) — SIGTERM gönderilecek. Kaydedilmemiş işler kaybolabilir."), pending.name, pending.pid))
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button("Sonlandır", role: .destructive) {
                    AdvisorStore.shared.executor.resolveKill(true)
                }
                Button("Reddet") {
                    AdvisorStore.shared.executor.resolveKill(false)
                }
            }
            .font(.system(size: 11))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cpu.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Theme.cpu.opacity(0.4), lineWidth: 1)
        )
    }
}

// MARK: - Tek mesaj

private struct MessageRow: View {
    let message: ChatMessage
    var modelLabel: String = "AI"
    @State private var snapshotExpanded = false

    var body: some View {
        if message.isSnapshot {
            snapshotRow
        } else if message.role == .tool {
            toolRow
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(message.role == .user ? String(localized: "Sen") : modelLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(message.role == .user ? Theme.memory : Theme.power)

                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.system(size: 12))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Metin + araç çağrısı aynı model turunda olabilir.
                if let calls = message.toolCalls {
                    ForEach(calls, id: \.id) { call in
                        toolBadge(call.name)
                    }
                }
            }
        }
    }

    /// Araç sonucu: ham içerik binlerce karakter olabilir — katlanmış satır.
    private var toolRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                snapshotExpanded.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: snapshotExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                    toolBadge(message.toolName ?? "tool")
                }
            }
            .buttonStyle(.plain)

            if snapshotExpanded {
                Text(message.text)
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.04),
                                in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func toolBadge(_ name: String) -> some View {
        Label(name, systemImage: "wrench.and.screwdriver")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.06), in: Capsule())
    }

    /// Sistem raporu binlerce karakter — katlanmış gösterilir, istenirse açılır.
    private var snapshotRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                snapshotExpanded.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: snapshotExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 10))
                    Text("Sistem anlık görüntüsü gönderildi")
                        .font(.system(size: 11))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if snapshotExpanded {
                Text(message.text)
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.04),
                                in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}

#endif
