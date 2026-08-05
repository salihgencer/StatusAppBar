import Foundation

/// Kural değerlendirmeleri. AlertEngine'in durum makinesinden ayrı tutuldu:
/// makine "ne zaman bildirilir"i, buradaki kurallar "ne olduğunu" bilir.
extension AlertEngine {

    /// Bir kural için tetik/temizlenme kararı ve mesaj üreticisi.
    /// `nil` dönerse kural bu makinede uygulanamaz (ör. pilsiz cihaz).
    func verdict(for kind: AlertKind, s: Snapshot, settings: AppSettings) -> Verdict? {
        switch kind {
        case .swapPressure: return swapVerdict(s, settings)
        case .cpuHog:       return cpuHogVerdict(s, settings)
        case .thermal:      return thermalVerdict(s, settings)
        case .uptimeLeak:   return uptimeVerdict(s, settings)
        case .batteryDrain: return batteryVerdict(s, settings)
        }
    }

    // MARK: - Swap baskısı

    private func swapVerdict(_ s: Snapshot, _ settings: AppSettings) -> Verdict? {
        guard s.memory.swapTotal > 0 else { return nil }

        let f = s.memory.swapFraction
        let high = settings.swapWarnPercent / 100.0
        // Histerezis: temizlenme eşiği 15 puan aşağıda. Değer eşikte
        // salınırken uyarı açılıp kapanmasın.
        let low = max(0.10, high - 0.15)

        return Verdict(trigger: f >= high, clear: f < low, subject: nil) {
            let hog = s.processes.topMemory.first
            let severity: AlertSeverity = (f >= 0.90 || s.memory.isThrashing) ? .critical : .warning

            var detail = String(format: String(localized: "Swap %@ / %@"),
                                Fmt.bytes(s.memory.swapUsed), Fmt.bytes(s.memory.swapTotal))
            detail += String(format: String(localized: " · RAM %@/%@"),
                             Fmt.bytes(s.memory.used), Fmt.bytes(s.memory.total))
            if s.memory.compressed > 0 {
                detail += String(format: String(localized: " · sıkıştırılmış %@"),
                                 Fmt.bytes(s.memory.compressed))
            }
            if let h = hog {
                detail += String(format: String(localized: "\nEn çok RAM: %@ · %@"),
                                 h.name, Fmt.bytes(h.rss))
            }

            var advice: String
            if let h = hog {
                advice = String(format: String(localized: "%@ uygulamasını kapatmak en hızlı rahatlama."), h.name)
            } else {
                advice = String(localized: "Açık uygulamaları azalt.")
            }
            if s.memory.isThrashing {
                advice += String(localized: " Sistem şu an aktif olarak diske takas yapıyor — CPU'nun bir kısmı bu işe gidiyor, fan bu yüzden dönüyor.")
            }

            return ActiveAlert(
                kind: .swapPressure,
                severity: severity,
                headline: String(format: String(localized: "Swap %%%ld dolu"), Int(f * 100)),
                detail: detail,
                advice: advice,
                culprit: hog,
                since: Date()
            )
        }
    }

    // MARK: - CPU canavarı

    private func cpuHogVerdict(_ s: Snapshot, _ settings: AppSettings) -> Verdict? {
        guard let top = s.processes.topCPU.first else { return nil }

        let threshold = settings.cpuHogPercent
        // Temizlenme: tek çekirdeğin altına insin. Eşiğin hemen altında
        // gidip gelen bir proses uyarıyı yakıp söndürmesin.
        let clearAt = min(100.0, threshold * 0.5)

        return Verdict(trigger: top.cpu >= threshold, clear: top.cpu < clearAt, subject: top.pid) {
            let cores = top.cpu / 100.0
            let severity: AlertSeverity = top.cpu >= threshold * 2 ? .critical : .warning

            let detail = String(
                format: String(localized: "≈%.1f çekirdek (toplam %d) · %@ · PID %d"),
                cores, s.machine.coreCount, Fmt.bytes(top.rss), top.pid
            )

            return ActiveAlert(
                kind: .cpuHog,
                severity: severity,
                headline: String(format: String(localized: "%@ %%%ld CPU"), top.name, Int(top.cpu)),
                detail: detail,
                advice: String(localized: "Bilerek çalıştırmadıysan kapat. Emülatör/simülatör, izleyici (watch) süreçleri ve takılmış build'ler en sık sebepler."),
                culprit: top,
                since: Date()
            )
        }
    }

    // MARK: - Termal / kernel_task

    private func thermalVerdict(_ s: Snapshot, _ settings: AppSettings) -> Verdict? {
        let thermalHigh = s.thermal.severity >= 2          // serious / critical
        // MAS'ta kernelTaskCPU hep 0 (başka kullanıcının prosesi okunamaz) —
        // kural orada kendiliğinden yalnızca thermalState'e iner.
        let kernelHigh = s.processes.kernelTaskCPU >= 25

        let trigger = thermalHigh || kernelHigh
        let clear = s.thermal.severity == 0 && s.processes.kernelTaskCPU < 10

        return Verdict(trigger: trigger, clear: clear, subject: nil) {
            let severity: AlertSeverity = s.thermal.severity >= 3 ? .critical : .warning

            var detail = String(format: String(localized: "Termal durum: %@"), s.thermal.label)
            if s.processes.kernelTaskCPU > 0 {
                detail += String(format: String(localized: " · kernel_task %%%.0f"), s.processes.kernelTaskCPU)
            }

            // Atıf kararı detaya taşınır. Proses nedeni suçluyu zaten
            // adlandırıyor — eski "En çok CPU" satırıyla aynı şeyi söyleyip
            // bildirimi şişirmesin diye yalnız o dalda yerine geçer.
            let attribution = ThermalAttribution.attribute(s)
            if attribution.cause == .process {
                detail += "\n" + attribution.message
            } else {
                if let top = s.processes.topCPU.first {
                    detail += String(format: String(localized: "\nEn çok CPU: %@ %%%ld"), top.name, Int(top.cpu))
                }
                if attribution.cause != .none {
                    detail += "\n" + attribution.message
                }
            }

            // ÖNEMLİ AYRIM: kernel_task yüksekse iki farklı sebep olabilir ve
            // çözümleri taban tabana zıt. Swap doluysa suçlu bellektir, sıcaklık
            // değil — kullanıcıyı yanlış yöne göndermeyelim.
            let advice: String
            if kernelHigh && s.memory.swapFraction > 0.6 {
                advice = String(localized: "kernel_task yükü sıcaklıktan değil bellek sıkıştırmasından geliyor. Çözüm soğutma değil: RAM boşalt.")
            } else if thermalHigh {
                advice = String(localized: "Sistem kendini kısıyor. Havalandırmayı kontrol et, ağır süreçleri duraklat.")
            } else {
                advice = String(localized: "kernel_task yükseldi — genelde yoğun disk I/O ya da bellek baskısının belirtisi.")
            }

            return ActiveAlert(
                kind: .thermal,
                severity: severity,
                headline: thermalHigh
                    ? String(format: String(localized: "Termal baskı: %@"), s.thermal.label)
                    : String(format: String(localized: "kernel_task %%%.0f CPU"), s.processes.kernelTaskCPU),
                detail: detail,
                advice: advice,
                culprit: s.processes.topCPU.first,
                since: Date()
            )
        }
    }

    // MARK: - Uptime / birikmiş sızıntı

    private func uptimeVerdict(_ s: Snapshot, _ settings: AppSettings) -> Verdict? {
        let limit = settings.uptimeWarnDays * 86_400
        let wsLimit: UInt64 = 1_200 * 1024 * 1024

        let longUptime = s.uptime >= limit
        // MAS'ta windowServerRSS hep 0 — orada yalnızca uptime eşiği kalır.
        let bloatedWS = s.processes.windowServerRSS >= wsLimit

        return Verdict(trigger: longUptime || bloatedWS, clear: !longUptime && !bloatedWS, subject: nil) {
            var detail = String(format: String(localized: "Uptime %@"), Fmt.uptime(s.uptime))
            if s.processes.windowServerRSS > 0 {
                detail += String(format: String(localized: " · WindowServer %@"),
                                 Fmt.bytes(s.processes.windowServerRSS))
            }
            if s.memory.swapTotal > 0 {
                detail += String(format: String(localized: " · swap %%%ld"), Int(s.memory.swapFraction * 100))
            }

            return ActiveAlert(
                kind: .uptimeLeak,
                severity: .info,
                headline: bloatedWS && !longUptime
                    ? String(localized: "WindowServer belleği şişti")
                    : String(format: String(localized: "%ld gündür açık"), Int(s.uptime / 86_400)),
                detail: detail,
                advice: String(localized: "Yeniden başlatmak swap'i sıfırlar ve birikmiş bellek sızıntılarını temizler. Tek adımda en büyük kazanç budur."),
                culprit: nil,
                since: Date()
            )
        }
    }

    // MARK: - Pil tüketimi

    private func batteryVerdict(_ s: Snapshot, _ settings: AppSettings) -> Verdict? {
        guard s.power.hasBattery else { return nil }
        guard s.power.voltageMV > 0 else { return nil }

        let w = s.power.watts
        let onBattery = s.power.isDischarging
        let high = settings.batteryDrainWatts
        let low = max(5.0, high * 0.6)

        return Verdict(trigger: onBattery && w >= high,
                       clear: !onBattery || w < low,
                       subject: nil) {
            let severity: AlertSeverity = w >= high * 1.5 ? .critical : .warning

            var detail = String(format: String(localized: "%.1f W · pil %%%.0f"), w, s.power.level * 100)
            if s.power.timeRemainingMinutes > 0 {
                detail += String(format: String(localized: " · tahmini %@"),
                                 Fmt.timeRemaining(s.power.timeRemainingMinutes))
            }
            if let top = s.processes.topCPU.first {
                detail += String(format: String(localized: "\nEn çok CPU: %@ %%%ld"), top.name, Int(top.cpu))
            }

            return ActiveAlert(
                kind: .batteryDrain,
                severity: severity,
                headline: String(format: String(localized: "Pil %.0f W çekiyor"), w),
                detail: detail,
                advice: String(localized: "Boştaki bir MacBook 3-8 W çeker. Bu seviye arka planda ağır bir iş olduğunu gösterir — en çok CPU kullanan prosesle başla."),
                culprit: s.processes.topCPU.first,
                since: Date()
            )
        }
    }
}
