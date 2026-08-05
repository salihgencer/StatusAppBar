// YALNIZCA MAS (ücretli App Store sürümü) — bkz. BuildVariant.swift.
#if MAS

import Foundation

/// Sistemin tam anlık durumunu düz metne çevirir.
///
/// İki yerde kullanılır:
///  - Gemini'ye gönderilen istem (prompt) gövdesi
///  - "Panoya kopyala" — anahtar yoksa kullanıcı raporu istediği yere yapıştırır
///
/// Kasıtlı olarak sade metin: LLM'ler tablo/JSON'dan çok düz sayı listesini
/// daha az hatayla okur, ayrıca insan da doğrudan okuyabilir.
enum DiagnosticReport {

    static func build(_ s: AlertEngine.Snapshot, alerts: [ActiveAlert]) -> String {
        var out: [String] = []

        out.append("# Sistem Durumu")
        out.append("Zaman: \(ISO8601DateFormatter().string(from: Date()))")
        out.append("Makine: \(s.machine.chip) · \(s.machine.coreCount) çekirdek · "
                 + "\(Fmt.bytes(s.machine.totalRAMBytes)) RAM · \(s.machine.osVersion)")
        out.append("Uptime: \(Fmt.uptime(s.uptime))")
        out.append("")

        out.append("## CPU")
        out.append(String(format: "Toplam: %%%.0f", s.cpu.total * 100))
        out.append(String(format: "Load average: %.2f / %.2f / %.2f (%d çekirdek)",
                          s.cpu.load[0], s.cpu.load[1], s.cpu.load[2], s.machine.coreCount))
        out.append("Çekirdek dağılımı: \(s.cpu.pCores)P + \(s.cpu.eCores)E")
        out.append(String(format: "kernel_task: %%%.0f", s.processes.kernelTaskCPU))
        out.append("")

        out.append("## Bellek")
        out.append("Kullanılan: \(Fmt.bytes(s.memory.used)) / \(Fmt.bytes(s.memory.total)) "
                 + "(%\(Int(s.memory.usedFraction * 100)))")
        out.append("Boş: \(Fmt.bytes(s.memory.free))")
        out.append("Sıkıştırılmış (compressor): \(Fmt.bytes(s.memory.compressed))")
        out.append("Swap: \(Fmt.bytes(s.memory.swapUsed)) / \(Fmt.bytes(s.memory.swapTotal)) "
                 + "(%\(Int(s.memory.swapFraction * 100)))")
        out.append("Swap trafiği: ↓\(Fmt.rate(s.memory.swapInsPerSec)) "
                 + "↑\(Fmt.rate(s.memory.swapOutsPerSec))")
        out.append("")

        out.append("## Termal")
        out.append("Durum: \(s.thermal.label)")
        // Atıf kararı modele de gider: AI aynı çıkarımı sıfırdan kurmaya
        // çalışmak yerine hazır kararı denetler, gerekirse itiraz eder.
        let attribution = ThermalAttribution.attribute(s)
        if attribution.cause != .none {
            out.append("Olası neden: \(attribution.message)")
        }
        if attribution.coolingActive {
            out.append(String(format: "Not: kernel_task %%%.0f — sistem kısarak soğutuyor (neden değil, sonuç)",
                              s.processes.kernelTaskCPU))
        }
        out.append("")

        if s.power.hasBattery {
            out.append("## Güç")
            out.append(String(format: "Seviye: %%%.0f · %@",
                              s.power.level * 100,
                              s.power.onAC ? "AC'ye bağlı" : "pilde"))
            if s.power.voltageMV > 0 {
                out.append(String(format: "Anlık güç: %.1f W (%@)",
                                  s.power.watts,
                                  s.power.amperageMA >= 0 ? "şarj" : "deşarj"))
            }
            out.append(String(format: "Pil sağlığı: %%%.0f · %d döngü · %.1f°C",
                              s.power.healthPercent, s.power.cycleCount, s.power.temperature))
            out.append("")
        }

        out.append("## En çok CPU kullanan prosesler")
        for p in s.processes.topCPU.prefix(8) {
            out.append(String(format: "- %@ · %%%.0f CPU · %@ · PID %d",
                              p.name, p.cpu, Fmt.bytes(p.rss), p.pid))
        }
        out.append("")

        out.append("## En çok bellek kullanan prosesler")
        for p in s.processes.topMemory.prefix(8) {
            out.append(String(format: "- %@ · %@ · %%%.0f CPU · PID %d",
                              p.name, Fmt.bytes(p.rss), p.cpu, p.pid))
        }
        out.append("")

        if !alerts.isEmpty {
            out.append("## Aktif uyarılar")
            for a in alerts {
                out.append("- [\(a.kind.title)] \(a.headline)")
                for line in a.detail.split(separator: "\n") {
                    out.append("  \(line)")
                }
            }
            out.append("")
        }

        return out.joined(separator: "\n")
    }

    /// Modele gönderilecek tam istem.
    ///
    /// Talimat kasıtlı olarak sert: LLM'ler sistem teşhisinde genel geçer
    /// tavsiyeye ("uygulamaları kapatın") kayma eğiliminde. Sayıya dayanmayan
    /// cevap işe yaramaz, o yüzden açıkça yasaklıyoruz.
    static func prompt(_ s: AlertEngine.Snapshot, alerts: [ActiveAlert]) -> String {
        if AILocale.isTurkish {
            """
            Aşağıda bir macOS makinesinin anlık sistem ölçümleri var. \
            Kullanıcının şikayeti: fan sürekli çalışıyor ve pil hızlı bitiyor.

            Görevin: verilen sayılara dayanarak teşhis koymak.

            Kurallar:
            - SADECE aşağıdaki verilere dayan. Veride olmayan şeyi uydurma.
            - Genel geçer tavsiye verme ("uygulamaları kapatın", "yeniden başlatın" \
            gibi tek başına anlamsız cümleler). Her önerini bir sayıya bağla.
            - En fazla 5 madde. Her madde: NEDEN (hangi ölçüm) → NE YAPMALI.
            - Maddeleri etki büyüklüğüne göre sırala, en etkili en üstte.
            - Emin olmadığın yerde "kesin değil" de. Uydurma kesinlik gösterme.
            - Araçların var: güncel sayı gerektiğinde get_system_status veya \
            list_processes çağır; eski veriyle yorum yapma.
            - Türkçe yaz. Kısa ve doğrudan ol. Giriş cümlesi yazma, doğrudan maddelere geç.

            ---
            \(build(s, alerts: alerts))
            """
        } else {
            """
            Below are live system metrics from a macOS machine. \
            The user's complaint: the fan keeps spinning and the battery drains fast.

            Your task: diagnose based on the numbers.

            Rules:
            - Rely ONLY on the data below. Do not invent anything not in the data.
            - No generic advice ("close some apps", "restart") — tie every \
            suggestion to a specific number.
            - At most 5 items. Each item: WHY (which metric) → WHAT TO DO.
            - Order by impact, highest first.
            - Say "not certain" when you are not. No false confidence.
            - You have tools: call get_system_status or list_processes whenever \
            you need current numbers; never reason from stale data.
            - Write in English. Be brief and direct. Skip the intro, go straight to items.

            ---
            \(build(s, alerts: alerts))
            """
        }
    }

    /// Sohbet ortasında gönderilen taze raporun başlığı ("Güncel durumu
    /// gönder" butonu). İlk istem gibi teşhis talimatı taşımaz — bağlam
    /// sohbette zaten var.
    static func promptUpdate(_ s: AlertEngine.Snapshot, alerts: [ActiveAlert]) -> String {
        let header = AILocale.isTurkish
            ? "İşte sistemin GÜNCEL durumu (önceki rapor eskidi, bunu esas al):"
            : "Here is the CURRENT system status (the previous report is stale; use this one):"
        return """
        \(header)

        \(build(s, alerts: alerts))
        """
    }
}

#endif
