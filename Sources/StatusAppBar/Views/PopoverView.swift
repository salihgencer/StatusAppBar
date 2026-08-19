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

            HStack(alignment: .top, spacing: 8) {
                GPUSection()
                // Isınma nedeni uyarı beklenmeden sürekli görünür — kullanıcı
                // "neden ısınıyor" sorusunun cevabını burada görür.
                ThermalSection()
            }

            SensorSection()

            TopProcessesSection()

            SpikeLogSection()

            HealthHistorySection()

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
    @State private var showBreakdown = false
    @State private var analyzer = DiskAnalyzer()

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

            Button {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.allowsMultipleSelection = false
                if panel.runModal() == .OK, let url = panel.url {
                    analyzer.scan(url: url)
                    showBreakdown = true
                }
            } label: {
                Label(String(localized: "Klasör Analizi"), systemImage: "folder.badge.gearshape")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.top, 2)

            if showBreakdown {
                DiskBreakdownView(analyzer: analyzer)
            }
        }
    }

    private func shortName(_ name: String) -> String {
        name.count > 7 ? String(name.prefix(7)) : name
    }
}

/// Klasör analizi sonuçlarını gösteren inline bölüm.
private struct DiskBreakdownView: View {
    var analyzer: DiskAnalyzer

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if analyzer.isScanning {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(String(localized: "Taranıyor..."))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            } else if !analyzer.entries.isEmpty {
                if let path = analyzer.scannedPath {
                    Text(path.lastPathComponent)
                        .font(.system(size: 10, weight: .medium))
                    Text(Fmt.bytes(analyzer.totalSize))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }

                ForEach(analyzer.entries.prefix(10)) { entry in
                    HStack(spacing: 6) {
                        Image(systemName: entry.isDirectory ? "folder.fill" : "doc.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(entry.isDirectory ? Theme.disk : .secondary)
                        Text(entry.name)
                            .font(.system(size: 10))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(entry.sizeText)
                            .font(.system(size: 9))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                if analyzer.entries.count > 10 {
                    Text(String(localized: "+\(analyzer.entries.count - 10) daha"))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, 4)
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

// MARK: - Sensors (Sıcaklık + Fan)

/// SMC sensörleri ve fan hızları. Sandbox'ta SMC erişimi engellenir;
/// bu durumda bölüm boş olur ve gizlenir.
private struct SensorSection: View {
    @Environment(MetricsManager.self) var metrics

    var body: some View {
        let s = metrics.sensors
        if !s.temperatures.isEmpty || !s.fans.isEmpty {
            SectionCard(icon: "thermometer.medium", title: String(localized: "Sensörler"), accent: Theme.disk) {
                if !s.temperatures.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 3) {
                        ForEach(s.temperatures) { temp in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(sensorColor(temp.celsius))
                                    .frame(width: 6, height: 6)
                                Text(temp.label)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer()
                                Text(String(format: "%.0f°C", temp.celsius))
                                    .font(.system(size: 9))
                                    .monospacedDigit()
                            }
                        }
                    }
                }
                if !s.fans.isEmpty {
                    Divider().padding(.vertical, 2)
                    ForEach(s.fans) { fan in
                        MetricRow(
                            label: "Fan \(fan.index + 1)",
                            value: "\(fan.currentRPM) RPM",
                            fraction: fan.utilizationFraction, color: Theme.disk
                        )
                    }
                }
            }
        }
    }

    private func sensorColor(_ celsius: Double) -> Color {
        switch celsius {
        case ..<50:  return Theme.power
        case ..<80:  return Theme.disk
        default:     return Theme.cpu
        }
    }
}

// MARK: - GPU

private struct GPUSection: View {
    @Environment(MetricsManager.self) var metrics

    var body: some View {
        let gpu = metrics.gpu
        SectionCard(icon: "rectangle.3.group", title: "GPU", accent: Theme.memory) {
            MetricRow(label: String(localized: "Kullanım"),
                      value: Fmt.percent(gpu.utilization),
                      fraction: gpu.utilization, color: nil)
            InfoRow(label: String(localized: "Model"), value: gpu.name)
        }
    }
}

// MARK: - Spike Log

private struct SpikeLogSection: View {
    @Environment(MetricsManager.self) var metrics

    var body: some View {
        if !metrics.spikeLog.isEmpty {
            SectionCard(icon: "chart.line.uptrend.xyaxis", title: "Spike Log", accent: Theme.cpu) {
                ForEach(metrics.spikeLog.suffix(5).reversed()) { spike in
                    HStack(spacing: 6) {
                        Image(systemName: spike.kind == .cpu ? "cpu" : "memorychip")
                            .font(.system(size: 9))
                            .foregroundStyle(spike.kind == .cpu ? Theme.cpu : Theme.memory)
                        Text(spike.culpritName)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                        Spacer()
                        Text(Fmt.percent(spike.peakValue))
                            .font(.system(size: 10))
                            .monospacedDigit()
                        Text(Fmt.relativeTime(spike.timestamp))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                if metrics.spikeLog.count > 5 {
                    Text(String(localized: "+\(metrics.spikeLog.count - 5) daha"))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Health History

private struct HealthHistorySection: View {
    @Environment(MetricsManager.self) var metrics

    var body: some View {
        if metrics.healthHistory.count > 2 {
            SectionCard(icon: "heart.text.square", title: String(localized: "Sağlık Geçmişi"), accent: Theme.power) {
                HealthSparkline(data: metrics.healthHistory.map(\.score))
                    .frame(height: 40)
                HStack {
                    Text(String(localized: "Min: \(metrics.healthHistory.map(\.score).min() ?? 0)"))
                    Spacer()
                    Text(String(localized: "Maks: \(metrics.healthHistory.map(\.score).max() ?? 100)"))
                }
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            }
        }
    }
}

/// Basit sparkline çizgisi — health score geçmişini görselleştirir.
private struct HealthSparkline: View {
    let data: [Int]

    var body: some View {
        GeometryReader { geo in
            let minVal = Double(data.min() ?? 0)
            let maxVal = Double(data.max() ?? 100)
            let range = max(1, maxVal - minVal)
            let step = geo.size.width / Double(max(1, data.count - 1))

            Path { path in
                for (i, score) in data.enumerated() {
                    let x = Double(i) * step
                    let y = geo.size.height * (1 - (Double(score) - minVal) / range)
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(Theme.power, lineWidth: 1.5)
        }
    }
}

// MARK: - Footer & Settings

private struct FooterBar: View {
    @Binding var showSettings: Bool
    @Environment(MetricsManager.self) var metrics

    var body: some View {
        HStack(spacing: 12) {
            Button {
                showSettings.toggle()
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Menu {
                Button("CSV") { Exporter.export(metrics: metrics, format: .csv) }
                Button("JSON") { Exporter.export(metrics: metrics, format: .json) }
            } label: {
                Label(String(localized: "Dışa Aktar"), systemImage: "square.and.arrow.up")
                    .font(.system(size: 11))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 90)
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
