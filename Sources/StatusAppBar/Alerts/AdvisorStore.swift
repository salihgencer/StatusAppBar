// YALNIZCA MAS (ücretli App Store sürümü): derin analiz, ücretli sürümün
// ayrıcalığıdır; ücretsiz GitHub derlemesinde bu dosyanın tamamı derleme
// dışıdır. Bkz. BuildVariant.swift.
#if MAS

import AppKit
import Combine
import Foundation

/// "Derin analiz" sohbetini tutar.
///
/// Singleton çünkü sohbet penceresi kapanıp yeniden açılabilir ve popover her
/// açılışta yeniden kurulur; konuşma kaybolmasın. Diske hiçbir şey yazılmaz —
/// anlık bir teşhis konuşması, saklanacak veri değil.
///
/// AKIŞ: yanıtlar SSE ile parça parça akar (`streamingText`); model araç
/// isterse (`AITool`) araç yerelde çalıştırılır, sonucu geri gönderilir ve
/// model devam eder — mini bir agent döngüsü.
@MainActor
final class AdvisorStore: ObservableObject {

    static let shared = AdvisorStore()

    /// Modele gönderilen en fazla mesaj sayısı. API'ler durumsuzdur; bağlamı
    /// taşıyan tek şey her istekte gönderilen geçmiştir, yani sınır olmazsa
    /// token maliyeti turla birlikte büyür. İlk mesaj (sistem raporu) bu
    /// sınırın DIŞINDA tutulur — bağlamın çıpası odur, düşerse model neyi
    /// konuştuğunu unutur.
    private static let historyLimit = 20

    /// Bir istekte üst üste en fazla kaç araç turu. Tavan şart: araç
    /// sonucundan tatmin olmayıp sürekli yeni araç isteyen bir model
    /// kontrolsüz API maliyeti üretir.
    private static let maxToolTurns = 6

    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var isRunning = false
    @Published private(set) var errorText: String?
    @Published private(set) var startedAt: Date?

    /// Akış halindeki yanıtın şu ana kadar gelen kısmı. Tamamlanınca
    /// `messages`'a taşınır; her parça için diziyi güncellemek SwiftUI
    /// kimliklerini (ve kaydırma konumunu) bozardı.
    @Published private(set) var streamingText = ""

    /// Araçları çalıştıran taraf. Onay kartı UI'ı `pendingKill`'i buradan okur.
    let executor = AIToolExecutor()

    private var task: Task<Void, Never>?

    var hasConversation: Bool { !messages.isEmpty }

    private init() {}

    // MARK: - Kurulum

    /// Taze veri kaynaklarını bağlar (DeepAnalysisWindow açılışta çağırır).
    /// Araçlar ve "güncel durum" butonu GÜNCEL ölçümü buradan alır.
    func configure(snapshot: @escaping () -> AlertEngine.Snapshot,
                   alerts: @escaping () -> [ActiveAlert]) {
        executor.snapshotProvider = snapshot
        executor.alertsProvider = alerts
    }

    // MARK: - Başlatma

    /// Anlık durumu modele gönderip ilk teşhisi ister. Sohbet zaten
    /// başlamışsa hiçbir şey yapmaz — kullanıcı yeni bir analiz istiyorsa
    /// önce `clear()` çağırmalı (pencerede "Yeni analiz" butonu).
    func start(snapshot: AlertEngine.Snapshot, alerts: [ActiveAlert]) {
        guard !hasConversation, !isRunning else { return }

        messages = [
            ChatMessage(
                role: .user,
                text: DiagnosticReport.prompt(snapshot, alerts: alerts),
                isSnapshot: true
            )
        ]
        startedAt = Date()
        send()
    }

    // MARK: - Devam

    /// Kullanıcının takip sorusunu ekler ve yanıt ister.
    func ask(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isRunning else { return }
        messages.append(ChatMessage(role: .user, text: trimmed))
        send()
    }

    /// "Güncel durumu gönder": ilk rapor sohbet ilerledikçe eskir; taze
    /// ölçümü yeni bir anlık görüntü mesajı olarak ekler.
    func refreshStatus() {
        guard !isRunning, hasConversation,
              let snapshot = executor.snapshotProvider?() else { return }
        messages.append(
            ChatMessage(
                role: .user,
                text: DiagnosticReport.promptUpdate(
                    snapshot, alerts: executor.alertsProvider?() ?? []
                ),
                isSnapshot: true
            )
        )
        send()
    }

    /// Son istek hata verdiyse aynı geçmişle tekrar dener.
    func retry() {
        guard !isRunning, errorText != nil, !messages.isEmpty else { return }
        send()
    }

    // MARK: - Agent döngüsü

    private func send() {
        task?.cancel()
        isRunning = true
        errorText = nil
        streamingText = ""

        task = Task { [weak self] in
            guard let self else { return }
            do {
                for _ in 0..<Self.maxToolTurns {
                    let client = Self.makeClient(AppSettings.shared)
                    var calls: [AIToolCall] = []

                    let stream = client.stream(messages: apiHistory(), tools: AITool.allCases)
                    for try await event in stream {
                        if Task.isCancelled { return }
                        switch event {
                        case .text(let delta):
                            streamingText += delta
                        case .toolCall(let call):
                            calls.append(call)
                        }
                    }

                    let text = streamingText
                    streamingText = ""

                    if calls.isEmpty {
                        if !text.isEmpty {
                            messages.append(ChatMessage(role: .model, text: text))
                        }
                        break // saf metin yanıt — döngü bitti
                    }

                    // Model araç istedi: çalıştır, sonucu geçmişe ekle, tur at.
                    messages.append(ChatMessage(role: .model, text: text, toolCalls: calls))
                    for call in calls {
                        let result = await executor.execute(call)
                        if Task.isCancelled { return }
                        messages.append(ChatMessage(
                            role: .tool,
                            text: result,
                            toolName: call.name,
                            toolCallID: call.id
                        ))
                    }
                }
            } catch {
                if !Task.isCancelled { errorText = error.localizedDescription }
            }
            self.isRunning = false
            self.streamingText = ""
        }
    }

    /// Sağlayıcı ayarlarından istemci üretir. Ayarlar ekranındaki "Doğrula"
    /// butonu da bunu kullanır (listModels çağrısı için).
    static func makeClient(_ s: AppSettings) -> any AIClient {
        switch s.aiProvider {
        case .gemini:
            return GeminiClient(apiKey: s.geminiAPIKey, model: s.geminiModel)
        case .anthropic:
            return AnthropicClient(apiKey: s.anthropicAPIKey, model: s.anthropicModel)
        case .openai:
            return OpenAICompatibleClient(baseURL: AIProvider.openai.defaultBaseURL,
                                          apiKey: s.openaiAPIKey,
                                          model: s.openaiModel, isLocal: false)
        case .ollama:
            return OpenAICompatibleClient(baseURL: s.ollamaURL,
                                          apiKey: nil,
                                          model: s.ollamaModel, isLocal: true)
        case .lmstudio:
            return OpenAICompatibleClient(baseURL: s.lmstudioURL,
                                          apiKey: nil,
                                          model: s.lmstudioModel, isLocal: true)
        case .demo:
            return DemoClient()
        }
    }

    // MARK: - Geçmiş

    /// İlk mesaj (sistem raporu) + son `historyLimit` mesaj.
    private func trimmedHistory() -> [ChatMessage] {
        guard messages.count > Self.historyLimit + 1 else { return messages }
        var tail = Array(messages.suffix(Self.historyLimit))
        // Araç sonuçları, istedikleri çağrı mesajı olmadan gönderilemez
        // (üç API de bunu hata sayar) — kuyruğu ilk "temiz" mesajdan başlat.
        while let first = tail.first,
              first.role == .tool || first.toolCalls?.isEmpty == false {
            tail.removeFirst()
        }
        return [messages[0]] + tail
    }

    private func apiHistory() -> [AIMessage] {
        trimmedHistory().map { m in
            switch m.role {
            case .user:
                return .user(m.text)
            case .model:
                return .model(text: m.text, toolCalls: m.toolCalls ?? [])
            case .tool:
                return .toolResult(
                    callID: m.toolCallID ?? m.toolName ?? "tool",
                    name: m.toolName ?? "tool",
                    content: m.text
                )
            }
        }
    }

    // MARK: - Yardımcılar

    /// Anahtar yoksa ya da kullanıcı başka bir araca yapıştırmak isterse:
    /// tam teşhis raporunu panoya kopyala.
    func copyReport(snapshot: AlertEngine.Snapshot, alerts: [ActiveAlert]) {
        copy(DiagnosticReport.prompt(snapshot, alerts: alerts))
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func clear() {
        task?.cancel()
        executor.cancelPendingKill()
        isRunning = false
        streamingText = ""
        messages = []
        errorText = nil
        startedAt = nil
    }
}

#endif
