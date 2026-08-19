import SwiftUI

/// Menu bar etiketine tıklayınca açılan ana panel. Görseldeki tüm bölümleri
/// (CPU, Memory, Disk, Power, Network, Thermal) native kartlar halinde gösterir.
struct PopoverView: View {

    /// Panelin ekranı taşmaması için üst sınır. Uyarılar ve derin analiz
    /// sonucu içeriği epey uzatabiliyor.
    private static let maxHeight: CGFloat = 700

    /// Ölçüm gelmeden önceki başlangıç yüksekliği. Sıfırdan başlamak paneli
    /// bir kare boyunca şerit gibi gösterirdi.
    @State private var contentHeight: CGFloat = 460

    var body: some View {
        ScrollView {
            PopoverContent()
                .background(
                    // İçeriğin gerçek yüksekliğini ölçüp yukarı taşır.
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ContentHeightKey.self,
                            value: geo.size.height
                        )
                    }
                )
        }
        // NEDEN AÇIK YÜKSEKLİK: `MenuBarExtra(.window)` pencereyi içeriğin
        // ideal boyutuna göre açar. `ScrollView`'ın İÇSEL YÜKSEKLİĞİ YOKTUR —
        // ölçüsüz bırakılırsa pencere sıfır yüksekliğe çöker ve panel menu
        // bar'ın altında ince bir şerit olarak görünür. Bu yüzden içeriği
        // ölçüp sınırlıyoruz: kısa içerikte pencere tam oturur, uzun içerikte
        // 700'de durup kaydırılır.
        .frame(width: 460, height: min(contentHeight, Self.maxHeight))
        .onPreferenceChange(ContentHeightKey.self) { height in
            guard height > 0 else { return }
            contentHeight = height
        }
    }
}

/// `PopoverContent`'in ölçülen yüksekliğini `PopoverView`'a taşır.
private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Panelin asıl gövdesi, `ScrollView`'dan ayrı.
///
/// AYRIM NEDEN VAR: `ImageRenderer` bir `ScrollView`'ı BOŞ render eder —
/// kaydırma görünümünün içsel bir yüksekliği yoktur, `fixedSize()` altında
/// sıfır ölçülür. README görsellerini üreten `--make-docs` bu yüzden doğrudan
/// `PopoverContent`'i render eder.
struct PopoverContent: View {
    @Environment(MetricsManager.self) var metrics
    @Environment(AppSettings.self) var settings
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 8) {
            HeaderSection()

            // Uyarı varsa en üstte — panel açıldığında ilk görülen şey
            // "her şey yolunda mı" sorusunun cevabı olmalı.
            AlertsSection()

            CPUSection()

            HStack(alignment: .top, spacing: 8) {
                MemorySection()
                DiskSection()
            }

            HStack(alignment: .top, spacing: 8) {
                PowerSection()
                NetworkSection()
            }

            // Isınma nedeni uyarı beklenmeden sürekli görünür — kullanıcı
            // "neden ısınıyor" sorusunun cevabını burada görür.
            ThermalSection()

            TopProcessesSection()

            #if MAS
            // Derin analiz yalnızca ücretli App Store sürümünde (BuildVariant).
            DeepAnalysisSection()
            #endif

            Divider().padding(.vertical, 2)

            FooterBar(showSettings: $showSettings)

            if showSettings {
                SettingsSection()
                AlertSettingsSection()
            }
        }
        .padding(12)
        .frame(width: 460)
    }
}

// MARK: - Header

private struct HeaderSection: View {
    @Environment(MetricsManager.self) var metrics

    var body: some View {
        let m = metrics.machine
        let h = HealthScore.color(for: metrics.health)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Status")
                    .fontWeight(.bold)
                Circle()
                    .fill(h.isGood ? Theme.power : Theme.cpu)
                    .frame(width: 7, height: 7)
                Text("\(h.label) · \(metrics.health)")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("up \(Fmt.uptime(metrics.uptime))")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12))

            Text(machineLine(m))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func machineLine(_ m: MachineInfo) -> String {
        var parts: [String] = []
        if m.chip != "—" { parts.append(m.chip) }
        parts.append("\(m.coreCount) cores")
        parts.append(Fmt.bytes(m.totalRAMBytes))
        if m.refreshRateHz > 0 { parts.append("\(m.refreshRateHz)Hz") }
        parts.append(m.osVersion)
        return parts.joined(separator: " · ")
    }
}

// MARK: - CPU

private struct CPUSection: View {
    @Environment(MetricsManager.self) var metrics

    var body: some View {
        let cpu = metrics.cpu
        SectionCard(icon: "cpu", title: "CPU", accent: Theme.cpu) {
            MetricRow(label: "Total", value: Fmt.percent(cpu.total), fraction: cpu.total, color: nil)

            if !cpu.cores.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 3) {
                    ForEach(Array(cpu.cores.enumerated()), id: \.offset) { idx, value in
                        HStack(spacing: 5) {
                            Text("C\(idx + 1)")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .frame(width: 22, alignment: .leading)
                            MetricBar(fraction: value, color: nil)
                            Text(Fmt.percent(value, decimals: 0))
                                .font(.system(size: 9))
                                .monospacedDigit()
                                .frame(width: 32, alignment: .trailing)
                        }
                    }
                }
                .padding(.top, 2)
            }

            InfoRow(
                label: "Load",
                value: String(format: "%.2f / %.2f / %.2f · %dP+%dE",
                              cpu.load[0], cpu.load[1], cpu.load[2], cpu.pCores, cpu.eCores)
            )
        }
    }
}

// MARK: - Memory

private struct MemorySection: View {
    @Environment(MetricsManager.self) var metrics

    var body: some View {
        let mem = metrics.memory
        SectionCard(icon: "memorychip", title: "Memory", accent: Theme.memory) {
            MetricRow(label: "Used", value: Fmt.percent(mem.usedFraction),
                      fraction: mem.usedFraction, color: nil)
            MetricRow(label: "Swap", value: Fmt.percent(mem.swapFraction),
                      fraction: mem.swapFraction, color: nil)
            InfoRow(label: "Total", value: "\(Fmt.bytes(mem.used)) / \(Fmt.bytes(mem.total))")
            InfoRow(label: "Free", value: Fmt.bytes(mem.free))
            InfoRow(label: String(localized: "Sıkışık"), value: Fmt.bytes(mem.compressed))
            // Swap trafiği yalnızca gerçekten akış varken gösterilir; sıfır
            // satırı her zaman durmak paneli gereksiz doldurur.
            if mem.swapInsPerSec + mem.swapOutsPerSec > 0 {
                InfoRow(
                    label: String(localized: "Takas"),
                    value: "↓\(Fmt.rate(mem.swapInsPerSec)) ↑\(Fmt.rate(mem.swapOutsPerSec))",
                    valueColor: mem.isThrashing ? Theme.cpu : .primary
                )
            }
        }
    }
}

// MARK: - Disk

private struct DiskSection: View {
    @Environment(MetricsManager.self) var metrics

    var body: some View {
        let disk = metrics.disk
        SectionCard(icon: "internaldrive", title: "Disk", accent: Theme.disk) {
            if disk.volumes.isEmpty {
                Text("No data").font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                ForEach(disk.volumes.prefix(3)) { vol in
                    MetricRow(label: shortName(vol.name),
                              value: "\(Fmt.bytes(vol.free)) free",
                              fraction: vol.fraction, color: nil)
                }
            }
            InfoRow(label: "Read", value: Fmt.rate(disk.readPerSec))
            InfoRow(label: "Write", value: Fmt.rate(disk.writePerSec))
        }
    }

    private func shortName(_ name: String) -> String {
        name.count > 7 ? String(name.prefix(7)) : name
    }
}

// MARK: - Power

private struct PowerSection: View {
    @Environment(MetricsManager.self) var metrics

    var body: some View {
        let p = metrics.power
        SectionCard(icon: "bolt.fill", title: "Power", accent: Theme.power) {
            if p.hasBattery {
                MetricRow(label: "Level", value: Fmt.percent(p.level, decimals: 0),
                          fraction: p.level, color: Theme.power)
                InfoRow(label: "Input", value: p.adapterWatts > 0 ? "\(p.adapterWatts)W max" : "—")
                // Anlık güç: "pil hızlı bitiyor" hissini doğrulayan tek sayı.
                // Boştaki bir MacBook 3-8 W çeker; 20 W üstü arka planda ağır
                // bir iş var demektir.
                if p.voltageMV > 0 {
                    InfoRow(
                        label: String(localized: "Çekiş"),
                        value: String(format: "%.1f W · %@", p.watts,
                                      p.amperageMA >= 0
                                        ? String(localized: "şarj")
                                        : String(localized: "deşarj")),
                        valueColor: (p.isDischarging && p.watts >= 20) ? Theme.cpu : .primary
                    )
                }
                InfoRow(label: "Status", value: statusText(p))
                InfoRow(
                    label: "Battery",
                    value: String(format: "%@ · %d cycles · %.1f°C",
                                  healthLabel(p), p.cycleCount, p.temperature),
                    valueColor: .secondary
                )
            } else {
                Text("No battery").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private func statusText(_ p: PowerMetrics) -> String {
        if p.isCharged { return "Charged" }
        if p.isCharging { return "Charging · \(Fmt.timeRemaining(p.timeRemainingMinutes))" }
        if p.onAC { return "On AC" }
        return "On battery · \(Fmt.timeRemaining(p.timeRemainingMinutes))"
    }

    private func healthLabel(_ p: PowerMetrics) -> String {
        p.healthPercent >= 80 ? "Healthy" : (p.healthPercent > 0 ? "\(Int(p.healthPercent))%" : "—")
    }
}

// MARK: - Network

private struct NetworkSection: View {
    @Environment(MetricsManager.self) var metrics

    // Bar dolulukları için yumuşak referans tavan (12.5 MB/s ~ 100 Mbit).
    private let cap: Double = 12.5 * 1024 * 1024

    var body: some View {
        let net = metrics.network
        SectionCard(icon: "antenna.radiowaves.left.and.right", title: "Network", accent: Theme.network) {
            MetricRow(label: "Down", value: Fmt.rate(net.downPerSec),
                      fraction: min(1, net.downPerSec / cap), color: Theme.network)
            MetricRow(label: "Up", value: Fmt.rate(net.upPerSec),
                      fraction: min(1, net.upPerSec / cap), color: Theme.network)
            InfoRow(label: "IP", value: net.ipAddress ?? "—")
        }
    }
}

// MARK: - Thermal

/// Termal durum + ısınmanın olası nedeni. Karar cümlesi `ThermalAttribution`
/// motorundan gelir; nominal durumdayken neden aranmaz, "baskı yok" denir.
private struct ThermalSection: View {
    @Environment(MetricsManager.self) var metrics

    var body: some View {
        let t = metrics.thermal
        let a = metrics.thermalAttribution
        SectionCard(icon: "thermometer.high", title: "Thermal", accent: accent(for: t.severity)) {
            InfoRow(label: String(localized: "Durum"), value: t.label,
                    valueColor: accent(for: t.severity))
            InfoRow(
                label: String(localized: "Neden"),
                value: a.message.isEmpty ? String(localized: "Termal baskı yok") : a.message,
                valueColor: a.cause == .none ? .secondary : .primary
            )
            // kernel_task kısarak soğutuyor: neden değil sonuç, ayrı rozet.
            if a.coolingActive {
                InfoRow(
                    label: String(localized: "Soğutma"),
                    value: String(format: String(localized: "Aktif (kernel_task %%%.0f)"),
                                  metrics.processes.kernelTaskCPU),
                    valueColor: Theme.disk
                )
            }
        }
    }

    private func accent(for severity: Int) -> Color {
        switch severity {
        case 0:  return Theme.power
        case 1:  return Theme.disk
        default: return Theme.cpu
        }
    }
}

// MARK: - Footer & Settings

private struct FooterBar: View {
    @Binding var showSettings: Bool

    var body: some View {
        HStack {
            Button {
                showSettings.toggle()
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }
}

private struct SettingsSection: View {
    @Environment(AppSettings.self) var settings
    @Environment(MetricsManager.self) var metrics

    var body: some View {
        @Bindable var settings = settings
        VStack(alignment: .leading, spacing: 4) {
            Text("Menu bar'da göster")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            HStack {
                Toggle("CPU", isOn: $settings.showCPU)
                Toggle("RAM", isOn: $settings.showRAM)
                Toggle("Disk", isOn: $settings.showDisk)
                Toggle("Net", isOn: $settings.showNetwork)
            }
            .toggleStyle(.checkbox)
            .font(.system(size: 11))

            Toggle("İkonları göster", isOn: $settings.showIcons)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))

            HStack(spacing: 6) {
                Text("Genişlik")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Picker("", selection: $settings.menuBarMode) {
                    ForEach(MenuBarMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
            }

            Toggle("Açılışta başlat", isOn: $settings.launchAtLogin)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))

            HStack(spacing: 6) {
                Text("Yenileme")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Picker("", selection: $settings.refreshInterval) {
                    Text("1s").tag(1.0)
                    Text("2s").tag(2.0)
                    Text("5s").tag(5.0)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
                .onChange(of: settings.refreshInterval) { _, newValue in
                    metrics.start(interval: newValue)
                }
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }
}
