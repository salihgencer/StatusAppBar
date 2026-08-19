import Foundation
import os

/// Uygulama genelinde yapısal loglama. `os.Logger` macOS'un Console ve
/// Instruments araçlarıyla entegre çalışır; `print`/`stderr` yerine bunu kullan.
///
/// Kullanım: `Log.metrics.debug("CPU örneği alındı: \(total)")`
nonisolated enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "dev.salihgencer.StatusAppBar"

    static let metrics = Logger(subsystem: subsystem, category: "metrics")
    static let alerts  = Logger(subsystem: subsystem, category: "alerts")
    static let notify  = Logger(subsystem: subsystem, category: "notifications")
    static let ai      = Logger(subsystem: subsystem, category: "ai")
    static let general = Logger(subsystem: subsystem, category: "general")
}
