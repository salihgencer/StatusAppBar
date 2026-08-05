// YALNIZCA MAS (ücretli App Store sürümü) — bkz. BuildVariant.swift.
#if MAS

import Foundation

/// Derin analiz sohbetindeki tek bir mesaj.
nonisolated struct ChatMessage: Identifiable, Equatable, Sendable {

    enum Role: Equatable, Sendable {
        case user
        case model
        /// Bir aracın çalıştırılma sonucu (model gördü, kullanıcıya katlanmış
        /// gösterilir).
        case tool
    }

    let id = UUID()
    var role: Role
    var text: String

    /// İlk mesaj, makinenin tam teşhis raporudur — binlerce karakter. Sohbet
    /// penceresinde ham hâlde göstermek ekranı boğar, ama modele gitmesi şart.
    /// Bu bayrak "gönder ama katlanmış göster" demek.
    var isSnapshot: Bool = false

    /// Araç çağrısı içeren model mesajları. Geçmişi API'ye geri çevirirken
    /// ayrı taşınması şart (OpenAI `tool_calls`, Gemini `functionCall`,
    /// Anthropic `tool_use` bloğu).
    var toolCalls: [AIToolCall]?

    /// Araç sonucu mesajlarında: hangi araç + hangi çağrının cevabı.
    var toolName: String?
    var toolCallID: String?
}

#endif
