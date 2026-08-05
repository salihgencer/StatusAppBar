import Foundation

/// Isınmanın olası nedenini vekil sinyallerden çıkarır.
///
/// NEDEN ÖLÇÜM DEĞİL, ÇIKARIM: macOS'ta ısıyı kaynağa atfeden resmî API yok;
/// GPU yükü ayrıcalıksız hiç ölçülemiyor. Motor tek baskın neden seçer,
/// katkı yüzdesi üretmez — sahte kesinlik `ThermalMonitor` felsefesiyle
/// çelişir ("kaç derece" değil, "neden").
///
/// ÖNCELİK SIRASI:
/// 1. Proses CPU'su eşiğin üstünde → suçlu o proses.
/// 2. Takas trafiği yoğun → bellek baskısı. DOLAYLI neden: RAM baskısı
///    takas → disk çalışması zinciri üzerinden ısıtır; kullanıcıya
///    dolaylılığı söyleyen cümle kurulur.
/// 3. Şarj oluyor → güç girişi. Nominal'de bu dala hiç gelinmez (guard),
///    yani şarj yalnızca termal baskı zaten varken neden sayılır.
/// 4. Hiçbiri → belirlenemedi (GPU'nun ölçülemediği notuyla).
///
/// Eşikler bilinçli olarak SABİT — ayar ekranı yok. Kural sayısı az kalır;
/// her yeni ayar yanlış-pozitif riskidir (AlertEngine felsefesi).
nonisolated enum ThermalAttribution {

    /// Tepe proses bu CPU yüzdesinin üstündeyse ısınmanın sorumlusu sayılır.
    static let processCPUThreshold: Double = 50

    /// Toplam takas giriş+çıkış hızı (byte/sn). Bu seviye aktif bellek
    /// darboğazı demektir; sağlıklı sistemde sıfıra yakındır.
    static let swapTrafficThreshold: Double = 20 * 1024 * 1024

    /// kernel_task bu seviyedeyse sistem kısarak soğutuyor demektir.
    /// Neden değil SONUÇTUR — UI'da ayrı rozet olarak gösterilir.
    static let kernelCoolingThreshold: Double = 50

    static func attribute(_ s: AlertEngine.Snapshot) -> ThermalVerdict {
        var v = ThermalVerdict()
        // MAS varyantında kernelTaskCPU her zaman 0 (başka kullanıcının
        // prosesleri okunamaz) — rozet orada kendiliğinden hiç görünmez.
        v.coolingActive = s.processes.kernelTaskCPU >= kernelCoolingThreshold

        // Baskı yokken neden aramak gürültü üretir.
        guard s.thermal.severity >= 1 else { return v }

        if let top = s.processes.topCPU.first, top.cpu >= processCPUThreshold {
            v.cause = .process
            v.culprit = top
            v.message = String(format: String(localized: "En olası neden: %@ (%%%ld CPU)"),
                               top.name, Int(top.cpu))
        } else if s.memory.swapInsPerSec + s.memory.swapOutsPerSec >= swapTrafficThreshold {
            v.cause = .memory
            v.message = String(localized: "En olası neden: bellek baskısı — takas trafiği yoğun (dolaylı)")
        } else if s.power.isCharging {
            v.cause = .charging
            v.message = String(localized: "En olası neden: şarj — güç girişi ısı üretir")
        } else {
            v.cause = .unknown
            v.message = String(localized: "Neden belirlenemedi — GPU yükü bu uygulamadan ölçülemiyor")
        }
        return v
    }
}
