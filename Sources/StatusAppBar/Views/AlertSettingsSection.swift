import AppKit
import SwiftUI

/// Uyarı eşikleri ve derin analiz ayarları.
struct AlertSettingsSection: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Uyarıları aç", isOn: $settings.alertsEnabled)
                .toggleStyle(.checkbox)
                .font(.system(size: 11, weight: .semibold))

            if settings.alertsEnabled {
                Group {
                    Toggle("Bellek baskısı (swap)", isOn: $settings.alertSwap)
                    Toggle("CPU canavarı", isOn: $settings.alertCPUHog)
                    Toggle("Termal / kernel_task", isOn: $settings.alertThermal)
                    Toggle("Uzun uptime", isOn: $settings.alertUptime)
                    Toggle("Pil tüketimi", isOn: $settings.alertBattery)
                }
                .toggleStyle(.checkbox)
                .font(.system(size: 11))

                Divider().padding(.vertical, 2)

                ThresholdRow(label: String(localized: "Swap eşiği"), unit: "%",
                             value: $settings.swapWarnPercent,
                             range: 50...95, step: 5)
                ThresholdRow(label: String(localized: "CPU eşiği"), unit: "%",
                             value: $settings.cpuHogPercent,
                             range: 100...600, step: 50)
                ThresholdRow(label: "Uptime", unit: String(localized: "gün"),
                             value: $settings.uptimeWarnDays,
                             range: 1...30, step: 1)
                ThresholdRow(label: String(localized: "Pil çekişi"), unit: "W",
                             value: $settings.batteryDrainWatts,
                             range: 10...50, step: 5)
                ThresholdRow(label: String(localized: "Bekleme"), unit: String(localized: "dk"),
                             value: $settings.alertCooldownMinutes,
                             range: 5...180, step: 5)

                Toggle("Kritik uyarılarda ses", isOn: $settings.alertSound)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))

                // Ad-hoc imzalı bir uygulamada bildirim izni sessizce
                // düşebiliyor. Bu buton olmadan sistemin çalışmadığını fark
                // etmenin tek yolu bir uyarıyı kaçırmak olurdu.
                // Bildirim zinciri iki yoldan gidebiliyor ve hangisinin aktif
                // olduğu kullanıcı için önemli: yedek yolda bildirimler
                // "Script Editor" adına görünür.
                HStack(spacing: 5) {
                    Image(systemName: Notifier.shared.isHealthy
                          ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(Notifier.shared.isHealthy ? Theme.power : Theme.disk)
                    Text(Notifier.shared.statusText)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 10))

                HStack(spacing: 8) {
                    Button {
                        Notifier.shared.sendTest()
                    } label: {
                        Label("Test bildirimi gönder", systemImage: "bell.badge")
                            .font(.system(size: 11))
                    }
                    Button("Bildirim ayarları") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(.tint)
                }

                #if MAS
                // Derin analiz ayarları yalnızca ücretli MAS sürümünde var.
                Divider().padding(.vertical, 2)

                AISettingsSection()
                #endif
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Etiket + stepper + değer. Slider yerine stepper: eşik ayarı hassas bir iş,
/// kullanıcı tam sayıyı görmeli.
private struct ThresholdRow: View {
    var label: String
    var unit: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(width: 78, alignment: .leading)
                .foregroundStyle(.secondary)
            Stepper(value: $value, in: range, step: step) {
                Text("\(Int(value)) \(unit)")
                    .monospacedDigit()
            }
            .controlSize(.small)
        }
        .font(.system(size: 11))
    }
}

#if MAS
/// Derin analiz AI sağlayıcı ayarları (yalnızca ücretli MAS sürümü).
///
/// "Doğrula" butonu model listesini çeker: çağrı başarılıysa anahtar/bağlantı
/// geçerlidir — ayrı bir doğrulama uç noktası gerektirmez ve kullanıcı
/// modelini hazır listeden seçer.
private struct AISettingsSection: View {
    @EnvironmentObject var settings: AppSettings

    @State private var isValidating = false
    @State private var validationMessage: String?
    @State private var validationOK = false
    @State private var fetchedModels: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Derin analiz (AI)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Picker("", selection: $settings.aiProviderRaw) {
                ForEach(AIProvider.allCases) { provider in
                    Text(provider.label).tag(provider.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if settings.aiProvider.needsAPIKey {
                SecureField("API anahtarı", text: keyBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
            }

            if settings.aiProvider.isLocal {
                TextField("Sunucu adresi", text: urlBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
            }

            if !settings.aiProvider.isDemo {
                HStack(spacing: 8) {
                    Button {
                        validate()
                    } label: {
                        Label("Doğrula ve modelleri getir", systemImage: "checkmark.shield")
                            .font(.system(size: 10))
                    }
                    .disabled(isValidating)

                    if isValidating {
                        ProgressView().controlSize(.small)
                    }
                }

                if let message = validationMessage {
                    Text(message)
                        .font(.system(size: 9))
                        .foregroundStyle(validationOK ? Theme.power : Theme.cpu)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if fetchedModels.isEmpty {
                    TextField("Model", text: modelBinding)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                } else {
                    Picker("Model", selection: modelBinding) {
                        ForEach(fetchedModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.system(size: 11))
                }
            }

            // Dürüst uyarı: anahtar düz metin olarak UserDefaults'ta durur.
            // Keychain daha doğru olurdu; kişisel bir araç için bu bilinçli
            // bir basitleştirme, ama kullanıcı bunu bilmeli.
            Text(privacyNote)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        // Sağlayıcı değişince eski doğrulama sonucu yanıltıcı olur.
        .onChange(of: settings.aiProviderRaw) { _, _ in
            fetchedModels = []
            validationMessage = nil
        }
    }

    // MARK: - Sağlayıcıya göre alan bağlantıları

    private var keyBinding: Binding<String> {
        switch settings.aiProvider {
        case .gemini:    return $settings.geminiAPIKey
        case .anthropic: return $settings.anthropicAPIKey
        case .openai:    return $settings.openaiAPIKey
        default:         return .constant("")
        }
    }

    private var urlBinding: Binding<String> {
        switch settings.aiProvider {
        case .ollama:    return $settings.ollamaURL
        case .lmstudio:  return $settings.lmstudioURL
        default:         return .constant("")
        }
    }

    private var modelBinding: Binding<String> {
        switch settings.aiProvider {
        case .gemini:    return $settings.geminiModel
        case .anthropic: return $settings.anthropicModel
        case .openai:    return $settings.openaiModel
        case .ollama:    return $settings.ollamaModel
        case .lmstudio:  return $settings.lmstudioModel
        case .demo:      return .constant("")
        }
    }

    private var privacyNote: String {
        if settings.aiProvider.isDemo {
            return String(localized: "Demo modu: analiz cihaz üzerinde canlı ölçümden üretilir; anahtar veya bağlantı gerektirmez.")
        }
        if settings.aiProvider.isLocal {
            return String(localized: "Yerel sunucu: sistem verisi bu Mac'ten çıkmaz. Analiz yalnızca butona bastığında gönderilir.")
        }
        return String(localized: "Anahtar bu Mac'te UserDefaults içinde saklanır (şifrelenmez). Analiz yalnızca butona bastığında gönderilir.")
    }

    // MARK: - Doğrulama

    private func validate() {
        isValidating = true
        validationMessage = nil
        let current = AdvisorStore.makeClient(settings)
        Task { @MainActor in
            do {
                let models = try await current.listModels()
                fetchedModels = models
                validationOK = !models.isEmpty
                validationMessage = models.isEmpty
                    ? String(localized: "Bağlantı kuruldu ama model listesi boş.")
                    : String(format: String(localized: "✓ %ld model bulundu"), models.count)
                // Model seçilmemişse ilkini öner.
                if modelBinding.wrappedValue.isEmpty, let first = models.first {
                    modelBinding.wrappedValue = first
                }
            } catch {
                fetchedModels = []
                validationOK = false
                validationMessage = error.localizedDescription
            }
            isValidating = false
        }
    }
}
#endif
