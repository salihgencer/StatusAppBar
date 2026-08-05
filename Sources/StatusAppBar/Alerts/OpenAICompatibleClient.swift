// YALNIZCA MAS (ücretli App Store sürümü) — bkz. BuildVariant.swift.
#if MAS

import Foundation

/// OpenAI uyumlu API istemcisi — OpenAI, Ollama ve LM Studio aynı uç noktayı
/// konuşur (`POST {base}/v1/chat/completions`, SSE streaming, function
/// calling). Yerel sunucularda apiKey boş gelir ve Authorization başlığı
/// hiç gönderilmez.
final class OpenAICompatibleClient: AIClient {

    private let baseURL: String
    private let apiKey: String?
    private var model: String
    /// Yerel sunucu mu — hata mesajları "anahtar yanlış" yerine "sunucuya
    /// ulaşılamadı" diyebilsin diye.
    private let isLocal: Bool

    init(baseURL: String, apiKey: String?, model: String, isLocal: Bool) {
        // Sondaki bölü işareti uç nokta birleşimini bozmasın.
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        self.apiKey = apiKey
        self.model = model
        self.isLocal = isLocal
    }

    enum Failure: LocalizedError {
        case missingKey
        case missingModel
        case unreachable(String)
        case http(Int, String)
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .missingKey:
                return String(localized: "API anahtarı girilmemiş. Ayarlar → Derin analiz.")
            case .missingModel:
                return String(localized: "Model seçilmemiş — Ayarlar → Derin analiz'den \"Doğrula\" ile listeyi çekip seç.")
            case .unreachable(let base):
                return String(format: String(localized: "Sunucuya ulaşılamadı (%@). Ollama / LM Studio çalışıyor mu?"), base)
            case .http(let code, let message):
                return String(format: String(localized: "Sunucu hatası (%ld): %@"), code, message)
            case .emptyResponse:
                return String(localized: "Model boş yanıt döndü.")
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
        if !isLocal, (apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw Failure.missingKey
        }
        // LM Studio gibi sunucularda model adı boş bırakılabilir; yüklü ilk
        // modeli kendimiz seçeriz.
        if model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            model = try await firstAvailableModel()
        }
        guard !messages.isEmpty else { throw Failure.emptyResponse }

        guard let url = URL(string: baseURL + "/v1/chat/completions") else {
            throw Failure.unreachable(baseURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = apiKey, !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

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
                    "type": "function",
                    "function": [
                        "name": $0.rawValue,
                        "description": $0.toolDescription,
                        "parameters": $0.parametersSchema
                    ]
                ]
            }
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (bytes, response) = try await URLSession.shared.bytes(for: request)
        } catch {
            // Yerel sunucu kapalıysa URLError döner; kullanıcıya "anahtar"
            // değil "sunucu" sorunu olduğunu söylemek gerekir.
            if isLocal { throw Failure.unreachable(baseURL) }
            throw error
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            var errorData = Data()
            for try await byte in bytes { errorData.append(byte) }
            let message = Self.errorMessage(from: errorData) ?? "bilinmeyen hata"
            throw Failure.http(http.statusCode, message)
        }

        // Araç çağrısı argümanları akışta PARÇA PARÇA gelir; index'e göre
        // biriktirip akış bitince tek seferde yayınlıyoruz.
        var pendingTools: [Int: (id: String, name: String, args: String)] = [:]
        var gotAnyContent = false

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = line.dropFirst(6)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
                  let choice = chunk.choices.first else { continue }

            if let text = choice.delta.content, !text.isEmpty {
                gotAnyContent = true
                yield(.text(text))
            }
            for call in choice.delta.toolCalls ?? [] {
                var acc = pendingTools[call.index] ?? ("", "", "")
                if let id = call.id { acc.id = id }
                if let name = call.function?.name { acc.name = name }
                if let args = call.function?.arguments { acc.args += args }
                pendingTools[call.index] = acc
            }
        }

        for index in pendingTools.keys.sorted() {
            guard let call = pendingTools[index], !call.name.isEmpty else { continue }
            gotAnyContent = true
            var pid: Int32?
            if let data = call.args.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let p = obj["pid"] as? Int {
                pid = Int32(p)
            }
            yield(.toolCall(AIToolCall(id: call.id.isEmpty ? call.name : call.id,
                                       name: call.name, pid: pid)))
        }

        if !gotAnyContent { throw Failure.emptyResponse }
    }

    // MARK: - Mesaj çevirisi

    /// AIMessage → OpenAI `messages` öğesi. Araç çağıran assistant mesajı ve
    /// `tool` rolü sonuç mesajı API'nin beklediği şema.
    private static func message(_ message: AIMessage) -> [String: Any] {
        switch message {
        case .user(let text):
            return ["role": "user", "content": text]
        case .model(let text, let calls):
            var out: [String: Any] = ["role": "assistant", "content": text]
            if !calls.isEmpty {
                out["tool_calls"] = calls.map { call -> [String: Any] in
                    var args: [String: Any] = [:]
                    if let pid = call.pid { args["pid"] = Int(pid) }
                    let argsData = try? JSONSerialization.data(withJSONObject: args)
                    return [
                        "id": call.id,
                        "type": "function",
                        "function": [
                            "name": call.name,
                            // OpenAI argümanları JSON STRING olarak ister.
                            "arguments": argsData.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                        ]
                    ]
                }
            }
            return out
        case .toolResult(let callID, _, let content):
            return ["role": "tool", "tool_call_id": callID, "content": content]
        }
    }

    // MARK: - Model listesi (anahtar/bağlantı doğrulama)

    /// `GET {base}/v1/models` — OpenAI, Ollama ve LM Studio'da aynı.
    /// Başarılı çağrı = anahtar/bağlantı geçerli.
    func listModels() async throws -> [String] {
        if !isLocal, (apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw Failure.missingKey
        }
        guard let url = URL(string: baseURL + "/v1/models") else {
            throw Failure.unreachable(baseURL)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15 // yerel sunucu kapalıysa uzun beklemeyelim
        if let key = apiKey, !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            if isLocal { throw Failure.unreachable(baseURL) }
            throw error
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw Failure.http(http.statusCode, Self.errorMessage(from: data) ?? "bilinmeyen hata")
        }

        struct ListResponse: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]
        }
        return try JSONDecoder().decode(ListResponse.self, from: data).data.map(\.id).sorted()
    }

    /// Model adı boş bırakıldığında: sunucudaki ilk model.
    private func firstAvailableModel() async throws -> String {
        guard let first = try await listModels().first else { throw Failure.missingModel }
        return first
    }

    // MARK: - Yanıt modeli

    private struct StreamChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                struct ToolCall: Decodable {
                    struct Function: Decodable {
                        let name: String?
                        let arguments: String?
                    }
                    let index: Int
                    let id: String?
                    let function: Function?
                }
                let content: String?
                let toolCalls: [ToolCall]?

                enum CodingKeys: String, CodingKey {
                    case content
                    case toolCalls = "tool_calls"
                }
            }
            let delta: Delta
        }
        let choices: [Choice]
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
