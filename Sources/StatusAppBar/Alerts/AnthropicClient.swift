// YALNIZCA MAS (ücretli App Store sürümü) — bkz. BuildVariant.swift.
#if MAS

import Foundation

/// Anthropic (Claude) Messages API istemcisi — SSE streaming + tool use.
///
/// OpenAI uyumlulardan farkları: olay tipli SSE (`event:` + `data:` satır
/// çiftleri), araç çağrısı `tool_use` içerik bloğu olarak akar ve argümanlar
/// `input_json_delta` parçalarında birleştirilir, araç sonucu `user` rolüyle
/// `tool_result` bloğu olarak gider.
final class AnthropicClient: AIClient {

    private let apiKey: String
    private let model: String

    init(apiKey: String, model: String) {
        self.apiKey = apiKey
        self.model = model
    }

    enum Failure: LocalizedError {
        case missingKey
        case missingModel
        case http(Int, String)
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .missingKey:
                return String(localized: "Anthropic API anahtarı girilmemiş. Ayarlar → Derin analiz.")
            case .missingModel:
                return String(localized: "Model seçilmemiş — Ayarlar → Derin analiz'den \"Doğrula\" ile listeyi çekip seç.")
            case .http(let code, let message):
                return String(format: String(localized: "Claude hatası (%ld): %@"), code, message)
            case .emptyResponse:
                return String(localized: "Claude boş yanıt döndü.")
            }
        }
    }

    // MARK: - Akış

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
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure.missingModel
        }
        guard !messages.isEmpty else { throw Failure.emptyResponse }

        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw Failure.missingKey
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        var body: [String: Any] = [
            "model": model,
            "messages": messages.map(Self.message),
            "stream": true,
            // Düşük sıcaklık: teşhis işinde yaratıcılık değil tutarlılık isteriz.
            "temperature": 0.2,
            "max_tokens": 1200
        ]
        if !tools.isEmpty {
            body["tools"] = tools.map {
                [
                    "name": $0.rawValue,
                    "description": $0.toolDescription,
                    "input_schema": $0.parametersSchema
                ]
            }
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            var errorData = Data()
            for try await byte in bytes { errorData.append(byte) }
            throw Failure.http(http.statusCode, Self.errorMessage(from: errorData) ?? "bilinmeyen hata")
        }

        // Olay tipli SSE: "event: X" satırını takip eden "data: {...}" satırı
        // gövdeyi taşır. Araç çağrısı bir content_block olarak açılır, JSON
        // argümanları delta'larla birikir, block kapanınca yayınlanır.
        var pendingTool: (id: String, name: String, json: String)?
        var gotAnyContent = false

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = line.dropFirst(6)
            guard let data = payload.data(using: .utf8),
                  let event = try? JSONDecoder().decode(StreamEvent.self, from: data) else {
                continue
            }

            switch event.type {
            case "content_block_start":
                if event.contentBlock?.type == "tool_use", let block = event.contentBlock {
                    pendingTool = (block.id ?? "", block.name ?? "", "")
                }
            case "content_block_delta":
                if let text = event.delta?.text, !text.isEmpty {
                    gotAnyContent = true
                    yield(.text(text))
                }
                if let partial = event.delta?.partialJSON {
                    pendingTool?.json += partial
                }
            case "content_block_stop":
                if let tool = pendingTool, !tool.name.isEmpty {
                    gotAnyContent = true
                    var pid: Int32?
                    if let data = tool.json.data(using: .utf8),
                       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let p = obj["pid"] as? Int {
                        pid = Int32(p)
                    }
                    yield(.toolCall(AIToolCall(id: tool.id.isEmpty ? tool.name : tool.id,
                                               name: tool.name, pid: pid)))
                }
                pendingTool = nil
            case "error":
                throw Failure.http(0, event.error?.message ?? "bilinmeyen hata")
            default:
                break // message_start, message_delta, ping, message_stop…
            }
        }

        if !gotAnyContent { throw Failure.emptyResponse }
    }

    // MARK: - Mesaj çevirisi

    /// AIMessage → Anthropic `messages` öğesi. Araç sonucu `user` rolüyle
    /// `tool_result` bloğu olarak gider.
    private static func message(_ message: AIMessage) -> [String: Any] {
        switch message {
        case .user(let text):
            return ["role": "user", "content": [["type": "text", "text": text]]]
        case .model(let text, let calls):
            // Anthropic boş metin bloğunu reddeder; boşsa atla.
            var content: [[String: Any]] = []
            if !text.isEmpty { content.append(["type": "text", "text": text]) }
            for call in calls {
                var input: [String: Any] = [:]
                if let pid = call.pid { input["pid"] = Int(pid) }
                content.append(["type": "tool_use", "id": call.id, "name": call.name, "input": input])
            }
            return ["role": "assistant", "content": content]
        case .toolResult(let callID, _, let content):
            return [
                "role": "user",
                "content": [["type": "tool_result", "tool_use_id": callID, "content": content]]
            ]
        }
    }

    // MARK: - Model listesi (anahtar doğrulama)

    /// `GET /v1/models` — başarılı çağrı = anahtar geçerli.
    func listModels() async throws -> [String] {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure.missingKey
        }
        guard let url = URL(string: "https://api.anthropic.com/v1/models") else {
            throw Failure.missingKey
        }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw Failure.http(http.statusCode, Self.errorMessage(from: data) ?? "bilinmeyen hata")
        }

        struct ListResponse: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]
        }
        return try JSONDecoder().decode(ListResponse.self, from: data).data.map(\.id)
    }

    // MARK: - Yanıt modeli

    private struct StreamEvent: Decodable {
        struct ContentBlock: Decodable {
            let type: String?
            let id: String?
            let name: String?
        }
        struct Delta: Decodable {
            let text: String?
            let partialJSON: String?

            enum CodingKeys: String, CodingKey {
                case text
                case partialJSON = "partial_json"
            }
        }
        struct ErrorBody: Decodable { let message: String? }

        let type: String
        let contentBlock: ContentBlock?
        let delta: Delta?
        let error: ErrorBody?

        enum CodingKeys: String, CodingKey {
            case type
            case contentBlock = "content_block"
            case delta
            case error
        }
    }

    /// Hata gövdesi `{"error":{"message":"…"}}` şeklinde gelir.
    private static func errorMessage(from data: Data) -> String? {
        struct ErrorEnvelope: Decodable {
            struct Body: Decodable { let message: String? }
            let error: Body?
        }
        return (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error?.message
    }
}

#endif
