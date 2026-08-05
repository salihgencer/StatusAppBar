// YALNIZCA MAS (ücretli App Store sürümü) — bkz. BuildVariant.swift.
#if MAS

import Foundation

/// Tüm AI istemcilerinin konuştuğu protokol. AdvisorStore sağlayıcı
/// ayrımını bilmez; bu akış üzerinden olay alır.
protocol AIClient {
    /// Yanıtı SSE ile parça parça yayınlar; araç çağrıları akışın sonunda
    /// tamamlanmış olarak gelir.
    func stream(messages: [AIMessage], tools: [AITool]) -> AsyncThrowingStream<AIEvent, Error>

    /// Kullanılabilir model listesini çeker. Ayarlardaki "Doğrula" butonu
    /// bunu çağırır: çağrı başarılıysa anahtar/bağlantı geçerli demektir
    /// (ayrı bir doğrulama uç noktasına gerek kalmaz).
    func listModels() async throws -> [String]
}

/// Google Gemini (Generative Language API) istemcisi — SSE streaming +
/// function calling.
///
/// NEDEN BULUT VARSAYILAN: uygulamaya gömülü bir yerel model 6-10 GB RAM
/// ister; bu uygulamanın izlediği asıl sorun zaten RAM yetersizliği.
/// (Kullanıcının KENDİ Ollama/LM Studio sunucusu ayrı — o seçenek
/// AIProvider üzerinden sunulur, RAM'i kullanıcının kendi tercihiyle yer.)
///
/// Çağrı yalnızca kullanıcı butona bastığında yapılır; arka planda periyodik
/// istek yok (hem maliyet hem gizlilik).
final class GeminiClient: AIClient {

    private let apiKey: String
    private let model: String

    init(apiKey: String, model: String) {
        self.apiKey = apiKey
        self.model = model
    }

    enum Failure: LocalizedError {
        case missingKey
        case http(Int, String)
        case emptyResponse
        case blocked(String)

        var errorDescription: String? {
            switch self {
            case .missingKey:
                return String(localized: "Gemini API anahtarı girilmemiş. Ayarlar → Derin analiz.")
            case .http(let code, let message):
                return String(format: String(localized: "Gemini hatası (%ld): %@"), code, message)
            case .emptyResponse:
                return String(localized: "Gemini boş yanıt döndü.")
            case .blocked(let reason):
                return String(format: String(localized: "Yanıt engellendi: %@"), reason)
            }
        }
    }

    // MARK: - Akış

    /// `streamGenerateContent?alt=sse` üzerinden çok turlu sohbet.
    /// API durumsuzdur; bağlam her istekte gönderilen `contents`'tir.
    /// Geçmişin uzunluğunu çağıran sınırlar (bkz. `AdvisorStore.historyLimit`).
    func stream(messages: [AIMessage], tools: [AITool]) -> AsyncThrowingStream<AIEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.run(messages: messages, tools: tools, yield: { continuation.yield($0) })
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(
        messages: [AIMessage],
        tools: [AITool],
        yield: (AIEvent) -> Void
    ) async throws {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure.missingKey
        }
        guard !messages.isEmpty else { throw Failure.emptyResponse }

        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/"
                     + "\(model):streamGenerateContent?alt=sse"
        guard let url = URL(string: endpoint) else { throw Failure.missingKey }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Anahtarı query string yerine header'da gönderiyoruz: URL'ler loglara,
        // proxy kayıtlarına ve crash raporlarına sızar.
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        var body: [String: Any] = [
            "contents": messages.map(Self.content),
            "generationConfig": [
                // Düşük sıcaklık: teşhis işinde yaratıcılık değil tutarlılık isteriz.
                "temperature": 0.2,
                "maxOutputTokens": 1200
            ]
        ]
        if !tools.isEmpty {
            body["tools"] = [[
                "function_declarations": tools.map {
                    [
                        "name": $0.rawValue,
                        "description": $0.toolDescription,
                        "parameters": $0.parametersSchema
                    ]
                }
            ]]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            var errorData = Data()
            for try await byte in bytes { errorData.append(byte) }
            let message = Self.errorMessage(from: errorData) ?? "bilinmeyen hata"
            throw Failure.http(http.statusCode, message)
        }

        var gotAnyContent = false
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = line.dropFirst(6)
            guard let data = payload.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data) else {
                continue
            }
            if let reason = chunk.promptFeedback?.blockReason {
                throw Failure.blocked(reason)
            }
            for part in chunk.candidates?.first?.content?.parts ?? [] {
                if let text = part.text, !text.isEmpty {
                    gotAnyContent = true
                    yield(.text(text))
                }
                if let call = part.functionCall {
                    gotAnyContent = true
                    // Gemini araç çağrısında id taşımaz; name id yerine geçer.
                    yield(.toolCall(AIToolCall(id: call.name, name: call.name, pid: call.args?.pid)))
                }
            }
        }
        if !gotAnyContent { throw Failure.emptyResponse }
    }

    // MARK: - Mesaj çevirisi

    /// AIMessage → Gemini `contents` öğesi. Araç sonucu `user` rolüyle ve
    /// `functionResponse` part'ıyla gider (API kuralı).
    private static func content(_ message: AIMessage) -> [String: Any] {
        switch message {
        case .user(let text):
            return ["role": "user", "parts": [["text": text]]]
        case .model(let text, let calls):
            var parts: [[String: Any]] = []
            if !text.isEmpty { parts.append(["text": text]) }
            for call in calls {
                var args: [String: Any] = [:]
                if let pid = call.pid { args["pid"] = Int(pid) }
                parts.append(["functionCall": ["name": call.name, "args": args]])
            }
            return ["role": "model", "parts": parts]
        case .toolResult(_, let name, let content):
            return [
                "role": "user",
                "parts": [["functionResponse": [
                    "name": name,
                    "response": ["result": content]
                ]]]
            ]
        }
    }

    // MARK: - Model listesi (anahtar doğrulama)

    /// `GET /v1beta/models` — `generateContent` destekleyen modelleri döndürür.
    /// 401/403 ise anahtar geçersizdir; ayarlar ekranı bunu gösterir.
    func listModels() async throws -> [String] {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure.missingKey
        }
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=100") else {
            throw Failure.missingKey
        }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw Failure.http(http.statusCode, Self.errorMessage(from: data) ?? "bilinmeyen hata")
        }

        struct ListResponse: Decodable {
            struct Model: Decodable {
                let name: String
                let supportedGenerationMethods: [String]?
            }
            let models: [Model]
        }
        let decoded = try JSONDecoder().decode(ListResponse.self, from: data)
        // Yanıt "models/gemini-..." biçiminde; istem yalnızca son parçayı ister.
        return decoded.models
            .filter { $0.supportedGenerationMethods?.contains("generateContent") ?? false }
            .map { $0.name.replacingOccurrences(of: "models/", with: "") }
    }

    // MARK: - Yanıt modeli

    private struct StreamChunk: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable {
                    struct FunctionCall: Decodable {
                        struct Args: Decodable { let pid: Int32? }
                        let name: String
                        let args: Args?
                    }
                    let text: String?
                    let functionCall: FunctionCall?
                }
                let parts: [Part]?
            }
            let content: Content?
        }
        struct PromptFeedback: Decodable { let blockReason: String? }

        let candidates: [Candidate]?
        let promptFeedback: PromptFeedback?
    }

    /// Hata gövdesi `{"error":{"code":…,"message":"…"}}` şeklinde gelir.
    private static func errorMessage(from data: Data) -> String? {
        struct ErrorEnvelope: Decodable {
            struct Body: Decodable { let message: String? }
            let error: Body?
        }
        return (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error?.message
    }
}

#endif
