// YALNIZCA MAS (ücretli App Store sürümü) — bkz. BuildVariant.swift.
#if MAS

import Foundation

/// Demo sağlayıcısı: anahtar ve bağlantı gerektirmez — analizi cihaz
/// üzerinde, canlı ölçümden üretir. App Review'ın 2.1(a) "demonstration
/// mode" isteği için eklendi; anahtarı olmayan kullanıcı da özelliği
/// buradan deneyebilir.
///
/// AKIŞ: ilk turda proses listesini araçla sorar (agent döngüsü uçtan uca
/// çalışır), ikinci turda gerçek ölçümü yoruma katar. Bulut modeli gibi
/// davranır ama hiçbir veri Mac'ten çıkmaz.
final class DemoClient: AIClient {

    func stream(messages: [AIMessage], tools: [AITool]) -> AsyncThrowingStream<AIEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for event in self.events(for: messages) {
                        try Task.checkCancellation()
                        // SSE akışı hissi: metin parça parça gelir.
                        if case .text = event {
                            try await Task.sleep(for: .milliseconds(20))
                        }
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func listModels() async throws -> [String] { ["demo-analyst"] }

    // MARK: - Tur mantığı

    private func events(for messages: [AIMessage]) -> [AIEvent] {
        guard let last = messages.last else { return [] }

        switch last {
        case .user(let text):
            if text.contains("# Sistem Durumu") {
                // İlk rapor veya "güncel durum": analizi canlı listeyle
                // temellendirmek için aracı çağır, döngü turlasın.
                var events = chunks(of: intro).map { AIEvent.text($0) }
                events.append(.toolCall(AIToolCall(
                    id: "demo-list-processes",
                    name: AITool.listProcesses.rawValue)))
                return events
            }
            return chunks(of: followUp).map { AIEvent.text($0) }
        case .toolResult(_, _, let content):
            return chunks(of: analysis(from: content)).map { AIEvent.text($0) }
        case .model:
            return []
        }
    }

    /// Akış hissi için metni küçük parçalara böler (SSE taklidi).
    private func chunks(of text: String) -> [String] {
        var out: [String] = []
        var current = ""
        for ch in text {
            current.append(ch)
            if current.count >= 24 {
                out.append(current)
                current = ""
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    // MARK: - Metinler

    private var intro: String {
        AILocale.isTurkish
        ? "Demo modu açık — analiz cihaz üzerinde üretilir, hiçbir veri Mac'ten çıkmaz. Yorumu canlı ölçüme dayandırmak için proses listesini sorguluyorum."
        : "Demo mode is on — the analysis is generated on-device; no data leaves this Mac. I'm querying the process list to ground the assessment in live measurements."
    }

    private var followUp: String {
        AILocale.isTurkish
        ? "Demo modu tek atımlık analiz üretir, takip sorusu değerlendiremez. Canlı bir sohbet için Ayarlar → Derin analiz bölümünden gerçek bir sağlayıcı seç; \"Raporu kopyala\" butonu tam teşhis metnini verir, onu istediğin modele yapıştırabilirsin."
        : "Demo mode produces a one-shot analysis and can't evaluate follow-up questions. For a live conversation pick a real provider in Settings → Deep analysis; the \"Copy report\" button gives you the full diagnostic text to paste into any model."
    }

    /// Araç sonucundaki gerçek proses satırlarını yoruma katar.
    private func analysis(from toolContent: String) -> String {
        let rows = parseCPURows(toolContent)
        let list: String
        if rows.isEmpty {
            list = AILocale.isTurkish
                ? "- Liste boş — ölçüm henüz olgunlaşmamış."
                : "- The list is empty — measurements haven't matured yet."
        } else {
            list = rows.map { row in
                // cpu alanı zaten "%84 CPU" biçiminde — ayrıca "CPU" yazma.
                let template = AILocale.isTurkish
                    ? "- %@: %@, %@ bellek (PID %@)"
                    : "- %@: %@, %@ memory (PID %@)"
                return String(format: template, row.name, row.cpu, row.mem, row.pid)
            }
            .joined(separator: "\n")
        }

        let template = AILocale.isTurkish
        ? """
        Demo analizi (cihaz üzerinde üretildi; hiçbir veri Mac'ten çıkmadı).

        Şu an en çok tüketenler:
        %@

        Değerlendirme:
        - Listenin tepesindeki proses, fan/ısınma ve pil tüketiminin ilk şüphelisidir; yük süreklilik arz ediyorsa Activity Monitor'de izleyin.
        - Bellek sütunu toplam RAM'e yaklaşıyorsa swap baskısı oluşabilir; paneldeki bellek uyarısı bunu ayrıca izler.
        - Tek anlık görüntüyle kesin hüküm verilmez; gerçek sağlayıcıda model güncel sayıları araçlarıyla kendisi doğrular.

        Bu mod takip sorusu yanıtlayamaz. Gerçek bir sağlayıcı (Gemini, Claude, OpenAI veya yerel Ollama/LM Studio) seçildiğinde rapor canlı modele gider ve sohbet devam eder.
        """
        : """
        Demo analysis (generated on-device; no data left this Mac).

        Top consumers right now:
        %@

        Assessment:
        - The process at the top of the list is the first suspect for fan noise, heat and battery drain; if the load is sustained, watch it in Activity Monitor.
        - If the memory column approaches total RAM, swap pressure can build; the panel's memory alert tracks that separately.
        - A single snapshot never justifies a hard verdict; with a real provider the model re-checks current numbers via its tools.

        This mode can't answer follow-up questions. Pick a real provider (Gemini, Claude, OpenAI or local Ollama/LM Studio) and the report goes to a live model, continuing the conversation.
        """
        return String(format: template, list)
    }

    // MARK: - Araç çıktısı ayrıştırma

    private struct Row {
        let name: String
        let cpu: String
        let mem: String
        let pid: String
    }

    /// `list_processes` çıktısındaki CPU satırları:
    /// "- ad · %12 CPU · 1,2 GB · PID 34" — bellek satırları 3 parçalıdır,
    /// burası 4 parça + "CPU" içeren ikinci parça ister.
    private func parseCPURows(_ content: String) -> [Row] {
        var rows: [Row] = []
        for line in content.split(separator: "\n") where line.hasPrefix("- ") {
            let parts = line.dropFirst(2)
                .split(separator: "·")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 4,
                  parts[1].contains("CPU"),
                  parts[3].hasPrefix("PID ")
            else { continue }
            rows.append(Row(name: parts[0], cpu: parts[1], mem: parts[2],
                            pid: String(parts[3].dropFirst(4))))
            if rows.count == 3 { break }
        }
        return rows
    }
}

#endif
