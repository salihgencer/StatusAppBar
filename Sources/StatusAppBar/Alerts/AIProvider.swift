// YALNIZCA MAS (ücretli App Store sürümü) — bkz. BuildVariant.swift.
#if MAS

import Foundation

/// Derin analizin konuştuğu yapay zekâ sağlayıcısı.
///
/// OpenAI / Ollama / LM Studio aynı "OpenAI uyumlu" API'yi konuşur
/// (`/v1/chat/completions`); tek istemci üçüne de gider. Gemini ve Claude
/// (Anthropic) kendi API'lerine sahip, ayrı istemcileri var.
enum AIProvider: String, CaseIterable, Identifiable {
    case gemini, anthropic, openai, ollama, lmstudio, demo

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gemini:   return "Gemini"
        case .anthropic: return "Claude (Anthropic)"
        case .openai:   return "OpenAI"
        case .ollama:   return "Ollama"
        case .lmstudio: return "LM Studio"
        case .demo:     return String(localized: "Demo")
        }
    }

    /// Yerel sunucularda veri makineden çıkmaz ve API anahtarı gerekmez.
    var isLocal: Bool { self == .ollama || self == .lmstudio }
    /// Demo: analiz cihaz üzerinde üretilir; anahtar, bağlantı ve hesap yok.
    var isDemo: Bool { self == .demo }
    var needsAPIKey: Bool { !isLocal && !isDemo }

    var defaultBaseURL: String {
        switch self {
        case .anthropic: return "https://api.anthropic.com"
        case .openai:    return "https://api.openai.com"
        case .ollama:    return "http://localhost:11434"
        case .lmstudio:  return "http://localhost:1234"
        case .gemini:    return "" // Gemini sabit uç nokta kullanır
        case .demo:      return ""
        }
    }

    /// Boş bırakılanlar: "Doğrula" ile çekilen model listesinden seçim gerekir.
    var defaultModel: String {
        switch self {
        case .gemini:    return "gemini-2.5-flash"
        case .anthropic: return ""
        case .openai:    return "gpt-4o-mini"
        case .ollama:    return "llama3.1"
        case .lmstudio:  return ""
        case .demo:      return ""
        }
    }
}

/// Model tarafı metin dili: uygulama Türkçe çalışıyorsa Türkçe, değilse
/// İngilizce. Rapor istemi ve araç açıklamaları bunu izler.
enum AILocale {
    static var isTurkish: Bool {
        Locale.preferredLanguages.first?.hasPrefix("tr") ?? false
    }
}

// MARK: - Sağlayıcıdan bağımsız sohbet modeli

/// İstemcilere gönderilen nötr mesaj. Sağlayıcıya özgü şekle çevirmek
/// istemcinin işi (Gemini `contents`, OpenAI uyumluları `messages`,
/// Anthropic `messages` + içerik blokları).
enum AIMessage {
    case user(String)
    /// Model yanıtı: metin ve/veya araç çağrıları. İkisi aynı mesajda
    /// olabilir (Anthropic rollerin katı dönüşümünü ister; ayrı mesajlara
    /// bölmek API hatası doğurur).
    case model(text: String, toolCalls: [AIToolCall])
    case toolResult(callID: String, name: String, content: String)
}

/// Akış (streaming) sırasında istemciden gelen olay.
enum AIEvent {
    /// Yanıt metni parçası.
    case text(String)
    /// Model araç çağırmak istiyor (akışın sonunda, tam hâliyle gelir).
    case toolCall(AIToolCall)
}

/// Modelden gelen tek bir araç çağrısı. Tek argümanlı tek araç var
/// (kill_process → pid), o yüzden genel bir sözlük yerine açık alan.
struct AIToolCall: Equatable, Sendable {
    /// OpenAI uyumluları `tool_call_id` ister; Gemini id taşımaz, orada
    /// name id yerine geçer.
    var id: String
    var name: String
    var pid: Int32?
}

// MARK: - Araçlar

/// Modelin çağırabileceği araçlar.
///
/// Yıkıcı tek araç `killProcess` ve o bile yalnızca kullanıcının ekranda
/// onayıyla çalışır (AIToolExecutor). "AI proses öldürebilir" hem App
/// Review'da hem kullanıcı güveninde soru doğurur; onaysız eylem yok.
enum AITool: String, CaseIterable {
    case getSystemStatus = "get_system_status"
    case listProcesses = "list_processes"
    case openActivityMonitor = "open_activity_monitor"
    case killProcess = "kill_process"

    /// Modele gönderilen açıklama.
    var toolDescription: String {
        if AILocale.isTurkish {
            switch self {
            case .getSystemStatus:
                return "Sistemin GÜNCEL tam durum raporunu getirir (CPU, bellek, disk, güç, ağ, en çok tüketen prosesler, aktif uyarılar). Sohbet başlangıcındaki anlık görüntü eskimiş olabilir; güncel sayı gerektiğinde bunu çağır."
            case .listProcesses:
                return "En çok CPU ve bellek tüketen proseslerin GÜNCEL listesini döndürür (ad, PID, CPU%, RSS)."
            case .openActivityMonitor:
                return "Kullanıcı için Activity Monitor (Aktivite Monitörü) uygulamasını açar."
            case .killProcess:
                return "Verilen PID'ye sahip prosesi SIGTERM ile sonlandırır. Kullanıcıdan ekranda onay istenir; onaylanmazsa çalışmaz. Yalnızca kullanıcı açıkça istediğinde öner."
            }
        }
        switch self {
        case .getSystemStatus:
            return "Returns a FRESH full system status report (CPU, memory, disk, power, network, top processes, active alerts). The initial snapshot may be stale; call this whenever current numbers are needed."
        case .listProcesses:
            return "Returns the CURRENT top CPU and memory consuming processes (name, PID, CPU%, RSS)."
        case .openActivityMonitor:
            return "Opens Activity Monitor for the user."
        case .killProcess:
            return "Terminates the process with the given PID via SIGTERM. Requires explicit on-screen user approval; does nothing otherwise. Suggest only when the user explicitly asks."
        }
    }

    /// JSON Schema (hem Gemini `parameters` hem OpenAI `function.parameters`
    /// aynı şemayı kabul eder).
    var parametersSchema: [String: Any] {
        switch self {
        case .killProcess:
            return [
                "type": "object",
                "properties": [
                    "pid": ["type": "integer", "description": "Sonlandırılacak prosesin PID'si / PID of the process to terminate"]
                ],
                "required": ["pid"]
            ]
        default:
            return ["type": "object", "properties": [String: Any]()]
        }
    }
}

#endif
