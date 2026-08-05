import Foundation

/// Kuralları değerlendirir, durum makinesini yürütür ve bildirimleri atar.
///
/// TASARIM — üç mekanizma yanlış-pozitifi ve spam'i birlikte çözer:
///
/// 1. HİSTEREZİS: tetik eşiği ile temizlenme eşiği farklı. Değer eşikte
///    salınırken uyarı açılıp kapanmaz (flapping yok).
/// 2. BEKLEME (dwell): koşulun N saniye kesintisiz sürmesi gerekir. Build,
///    uygulama açılışı gibi anlık tepeler bildirime dönüşmez.
/// 3. SOĞUMA (cooldown): aynı tür için iki bildirim arası minimum süre.
///    Uyarı listede kalmaya devam eder ama tekrar tekrar bildirilmez.
///
/// Ayrıca durum düzeldiğinde "normale döndü" bildirimi atılır — kullanıcı
/// sorunun geçtiğini bilmeli, yoksa uyarıya güvenmeyi bırakır.
final class AlertEngine {

    /// Değerlendirme için gereken tüm anlık veri.
    struct Snapshot {
        var cpu: CPUMetrics
        var memory: MemoryMetrics
        var power: PowerMetrics
        var thermal: ThermalMetrics
        var processes: ProcessMetrics
        var uptime: TimeInterval
        var machine: MachineInfo
    }

    private struct Runtime {
        var pendingSince: Date?
        var pendingSubject: Int32?   // cpuHog: hangi PID için sayıyoruz
        var firing: ActiveAlert?
        var lastNotified: Date?
    }

    /// Bir kuralın tek turluk kararı.
    /// `internal` — kural gövdeleri AlertRules.swift'teki extension'da.
    struct Verdict {
        var trigger: Bool
        var clear: Bool
        var subject: Int32?          // koşulun bağlı olduğu proses (varsa)
        var build: () -> ActiveAlert
    }

    private var runtime: [AlertKind: Runtime] = [:]
    private let notifier = Notifier.shared

    // MARK: - Ana döngü

    /// Tüm kuralları değerlendirir ve aktif uyarı listesini döndürür.
    /// Main thread'de çağrılmalı (AppSettings okur, bildirim tetikler).
    func evaluate(_ s: Snapshot, settings: AppSettings) -> [ActiveAlert] {
        let now = Date()

        guard settings.alertsEnabled else {
            runtime.removeAll()
            return []
        }

        for kind in AlertKind.allCases {
            guard settings.isEnabled(kind) else {
                runtime[kind] = Runtime()
                continue
            }
            guard let verdict = verdict(for: kind, s: s, settings: settings) else {
                runtime[kind] = Runtime()
                continue
            }
            step(kind: kind, verdict: verdict, now: now, settings: settings)
        }

        return AlertKind.allCases
            .compactMap { runtime[$0]?.firing }
            .sorted { ($0.severity, $0.since) > ($1.severity, $1.since) }
    }

    /// Tek bir kuralın durum makinesi adımı.
    private func step(kind: AlertKind, verdict v: Verdict, now: Date, settings: AppSettings) {
        var rt = runtime[kind] ?? Runtime()
        defer { runtime[kind] = rt }

        // --- Zaten uyarı veriyorsak ---
        if rt.firing != nil {
            if v.clear {
                rt.firing = nil
                rt.pendingSince = nil
                rt.pendingSubject = nil
                notifier.post(
                    title: String(format: String(localized: "%@ normale döndü"), kind.title),
                    body: String(localized: "Durum düzeldi."),
                    sound: false,
                    identifier: "\(kind.rawValue).recovered"
                )
            } else {
                // Uyarı sürüyor: içeriği tazele (suçlu ya da oran değişmiş olabilir),
                // ama başlangıç zamanını koru.
                let since = rt.firing!.since
                var fresh = v.build()
                fresh.since = since
                rt.firing = fresh
            }
            return
        }

        // --- Henüz uyarı vermiyoruz ---
        guard v.trigger else {
            rt.pendingSince = nil
            rt.pendingSubject = nil
            return
        }

        // Konu değiştiyse (başka bir proses tepeye çıktıysa) sayacı sıfırla —
        // "3 dakikadır aynı proses" şartı ancak böyle anlamlı olur.
        if rt.pendingSubject != v.subject {
            rt.pendingSubject = v.subject
            rt.pendingSince = now
        }
        if rt.pendingSince == nil { rt.pendingSince = now }

        guard now.timeIntervalSince(rt.pendingSince!) >= kind.dwell else { return }

        var alert = v.build()
        alert.since = now
        rt.firing = alert
        rt.pendingSince = nil

        let cooldown = kind.cooldownOverride ?? (settings.alertCooldownMinutes * 60)
        if let last = rt.lastNotified, now.timeIntervalSince(last) < cooldown {
            return // uyarı listede görünür ama bildirim atılmaz
        }
        rt.lastNotified = now
        notifier.post(
            title: alert.headline,
            body: "\(alert.detail)\n\(alert.advice)",
            sound: settings.alertSound && alert.severity == .critical,
            identifier: kind.rawValue
        )
    }
}
