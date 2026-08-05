# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Komutlar

```bash
swift build                 # debug derleme (ücretsiz GitHub varyantı)
swift run                   # bundle'sız çalıştır (Dock ikonu yok, AppDelegate accessory'e sabitler)
./build.sh                  # release + StatusAppBar.app paketi (Apple Development kimliği varsa onunla, yoksa ad-hoc imza)
./release.sh                # universal (arm64+x86_64) + .app + StatusAppBar.zip — CI'ın çalıştırdığı script
open StatusAppBar.app       # paketlenmiş uygulamayı çalıştır

# Mac App Store (MAS) varyantı — ücretli kanal:
fastlane mac build          # xcodegen + archive + StatusAppBar.pkg (build/)
fastlane mac register       # ilk kurulum: App ID + ASC kaydı (bir kez)
fastlane mac beta|release|metadata|submit
```

**Test yok.** Test target'ı tanımlı değil; `swift test` çalışmaz. Doğrulama elle yapılır (`swift run` veya `./build.sh && open`).

### İki derleme varyantı (bkz. `Sources/StatusAppBar/BuildVariant.swift`)

- **Ücretsiz (SwiftPM)**: bayraksız derleme. `ps` ile tam proses listesi, `osascript` bildirim yedeği var; **derin analiz (AI) YOK**.
- **MAS (XcodeGen + fastlane)**: `MAS` derleme koşulu tanımlı (`project.yml`). App Sandbox açık; `ps`/`osascript` yerine sandbox uyumlu yollar (`NSWorkspace` + `proc_pidinfo`, yalnız UN). **Derin analiz yalnızca bu varyantta** — ücretli sürümün ayrıcalığı. Sandbox notları ve App Store stratejisi: `docs/app-store-arastirmasi.md`.
- MAS varyantını SwiftPM ile hızlı derleme kontrolü: `swift build -Xswiftc -DMAS`.
- **`.xcodeproj` git'e girmez** — `xcodegen generate` ile üretilir (fastlane lane'leri her koşuda üretir).

### Dokümantasyon görselleri

```bash
./build.sh && ./StatusAppBar.app/Contents/MacOS/StatusAppBar --make-docs docs
```

`docs/popover.png`, `docs/menubar.png`, `docs/menubar-load.png` üretir. Bu mod **tamamen mock veri** kullanır (`MetricsManager.mock`) — gerçek makineden IP, disk adı, donanım bilgisi okumaz. Görsel üretim yolunu değiştirirken bu kısıtı koru; README görselleri herkese açık.

`ImageRenderer` bir `ScrollView`'ı **boş** çizer (içsel yüksekliği yoktur). Bu yüzden `SnapshotRenderer` `PopoverView` değil `PopoverContent` render eder — panelin gövdesi bilerek ayrı bir view'da. Panel görseli boş çıkıyorsa ilk bakılacak yer burasıdır.

### Sürüm çıkma

1. `Info.plist` → `CFBundleShortVersionString` (semver) ve `CFBundleVersion` (artan tamsayı) güncelle.
2. `git tag vX.Y.Z && git push --tags` → `.github/workflows/release.yml` `release.sh` çalıştırıp GitHub Release'e zip yükler.

Not: workflow `runs-on: macos-14` (GitHub-hosted) kullanıyor — workspace'in "self-hosted kullan" kuralına aykırı, ama macOS build gerektirdiği için mevcut self-hosted Linux runner'lar bu işi yapamaz.

## Mimari

```
Monitor.sample()  ─▶  XMetrics (nonisolated struct, değer tipi)
        │  (7 monitor, Sampler aktörünün izole deposunda)
        ▼
   actor Sampler ──▶ Sampler.Sample (Sendable) ──▶ MetricsManager (@MainActor)
                                                          │
                          ├─▶ AlertEngine.evaluate() ─▶ [ActiveAlert] ─▶ Notifier
                          │
                          └─▶ SwiftUI (MenuBarExtra label + PopoverView)
```

Yeni metrik eklemek = yeni `nonisolated` Monitor + `Models.swift`'e `nonisolated struct` + `Sampler.Sample`'a alan + `MetricsManager`'a `@Published` alan + bir section view.

### İzolasyon sözleşmesi (bozma)

Paket **Swift 6 dil modunda**, `defaultIsolation(MainActor.self)` + `NonisolatedNonsendingByDefault` ile derlenir (`Package.swift`). Yani **her şey varsayılan olarak `@MainActor`**; arka plan tek bir yerde, açıkça.

- **Tek arka plan yeri `actor Sampler`.** 7 monitor onun izole deposunda yaşar; erişim sıralı ve main thread dışıdır. Eskiden bu garanti bir serial `DispatchQueue` konvansiyonuyla sağlanıyordu — aynı davranış, artık derleyici denetiminde.
- **Monitor'ler `nonisolated final class` ve `Sendable` değil.** Kasıtlı: tek başlarına thread-safe değiller, güvenlikleri aktörün içinde olmaktan geliyor. Aktörden dışarı sızmalarını derleyici engelliyor.
- **`Sampler.sample()` `async` değil.** `ProcessMonitor` `ps` çıktısını beklerken (~30 ms, 10 sn'de bir) cooperative pool thread'ini bloklar. `await`'e çevirmek thread'i serbest bırakırdı ama aktör reentrancy'si açıp monitor'lerin delta state'ini bozabilirdi.
- **Uyarı değerlendirmesi MainActor'de** — `AppSettings` okur, bildirim tetikler.
- `MetricsManager.tick()` üst üste binen turları `samplingTask` ile engeller.
- Timer gövdesi `MainActor.assumeIsolated` kullanır (timer `RunLoop.main`'e eklenir, dolayısıyla her zaman main'de ateşler); `isolated deinit` ise `Timer`'ın Sendable olmamasını çözer.
- UN completion handler'ları izolasyonsuz thread'lerde çağrılır — içeriden state yazmak için `Task { @MainActor in ... }` şart. `Notifier.log` bilinçli olarak `nonisolated` (saf dosya IO).

### Bilinçli tasarım kararları — değiştirmeden önce oku

Kod tabanındaki uzun yorum blokları bu kararların gerekçelerini taşıyor; silme.

| Karar | Neden |
|---|---|
| `AppSettings.shared` singleton | AlertEngine arka planda eşiklere erişiyor; iki örnek olsaydı UI'dan değişen eşik motora ulaşmazdı. |
| `MetricsManager.alerts` düz dizi olarak `@Published` | İç içe `ObservableObject` (AlertEngine'i doğrudan yayınlamak) SwiftUI güncellemesini tetiklemez. |
| `MenuBarLabelRenderer` görsel önbelleği | Her turda `ImageRenderer` çağırmak uygulamayı en çok CPU yiyenler arasına sokuyordu (7.4% → 0.3%). `LabelDescriptor` değişmedikçe yeniden çizme. |
| Varsayılan `refreshInterval = 2.0` | Aynı sebep — 1 sn render maliyeti bilgi kazancını haklı çıkarmıyor. |
| Varsayılan `menuBarMode = .adaptive` | Çentikli MacBook'ta geniş etiket çentik altına itilip görünmez oluyor; macOS bunu tespit edecek API vermiyor. |
| `ProcessMonitor` `ps` çağırıyor, `libproc` değil | `proc_pidinfo` başka kullanıcının prosesleri için ayrıcalık ister — tam da izlenmek istenen `kernel_task` (root) ve `WindowServer`. `ps` sysctl'den ayrıcalıksız okur. 10 sn'de bir ~30 ms, ana döngüden ayrık. |
| `Notifier` çift yol (UN + `osascript` yedeği) | Bundle'sız çalışmada `UNUserNotificationCenter.current()` **crash eder** (`bundleIdentifier` nil) — `hasBundle` kontrolünü kaldırma. Ad-hoc imzalı build'de UN izni reddedilebiliyor; yedek yol bildirimleri Script Editor adına gönderir. |
| İzin isteği `AppDelegate.applicationDidFinishLaunching`'de | Daha erken çağrıldığında (örn. `@StateObject` kurulumunda) uygulama Launch Services'e kaydolmadığı için istek sessizce düşüyor. |
| Gemini (bulut), yerel LLM değil | Yerel model 6-10 GB RAM ister; bu uygulamanın izlediği sorun zaten RAM tükenmesi. Yalnızca butona basınca çağrılır, arka planda polling yok. **Güncelleme (MAS sürümü):** AI artık çok sağlayıcılı (Gemini/Claude/OpenAI/Ollama/LM Studio) ve yalnızca ücretli sürümde; kullanıcının KENDİ yerel sunucusu (Ollama/LM Studio) bir tercih olarak sunulur — uygulamaya gömülü model hâlâ yok. |
| Derin analiz sohbeti **ayrı `Window` scene**'de | `MenuBarExtra(.window)` odak kaybedince kapanır — sohbet ortasında konuşma yok olurdu. Accessory uygulama olduğu için pencere açarken `NSApp.activate(ignoringOtherApps:)` şart, yoksa arkada açılır. |
| `AdvisorStore` geçmişi son 20 mesaj + ilk rapor | Gemini `generateContent` durumsuz; her istekte tüm geçmiş gider. İlk mesaj (sistem raporu) sınır dışı tutulur — bağlamın çıpası odur. |
| "Yazışmayı kopyala" sistem raporunu **dışlar** | Yazışmayı paylaşan kullanıcı makinesinin IP'sini, disk adlarını ve proses listesini paylaşmış olmamalı. |

### Uyarı motoru

`AlertEngine` kural başına bir durum makinesi yürütür. Üç mekanizma birlikte yanlış-pozitifi ve spam'i çözer — birini kaldırmak diğerlerini işlevsiz bırakır:

- **Histerezis** — tetik ve temizlenme eşikleri farklı (flapping yok).
- **Bekleme (`AlertKind.dwell`)** — koşul N saniye kesintisiz sürmeli. `cpuHog` ayrıca **aynı PID** şartı arar (`Verdict.subject`); konu değişince sayaç sıfırlanır.
- **Soğuma** — aynı tür için iki bildirim arası minimum süre (`alertCooldownMinutes`, `uptimeLeak` için 24 s override). Uyarı listede kalır, sadece tekrar bildirilmez.

Durum düzelince "normale döndü" bildirimi atılır.

Yeni kural eklemek: `AlertKind`'a case + `dwell` + `title`/`icon`, `AlertRules.swift`'e `Verdict` üreten gövde, `AppSettings.isEnabled/setEnabled`'a switch kolu. Kural sayısı bilinçli olarak az tutuluyor — her ek kural yanlış-pozitif riski.

## Konvansiyonlar

- **Yorumlar ve kullanıcıya görünen tüm metinler Türkçe.** Kod tanımlayıcıları İngilizce. Kullanıcı-facing string'ler aynı zamanda katalog anahtarıdır: İngilizce çeviriler `Resources/Localizable.xcstrings`'te yaşar (kaynak dil `tr`). Yeni bir kullanıcı-facing string eklerken dinamik olanları `String(localized:)` ile işaretle ve kataloğa `en` çevirisini ekle. Katalog yalnızca MAS (XcodeGen) build'ine girer; SwiftPM build'i anahtarı (Türkçe metni) olduğu gibi gösterir.
- **Sıfır üçüncü parti bağımlılık.** Metrikler doğrudan çekirdekten okunur (Mach, IOKit, BSD socket, `getifaddrs`). Yeni bağımlılık eklemeden önce bunun README'de öne çıkarılan bir özellik olduğunu hatırla.
- Ayarlar `UserDefaults`'a `didSet` içinde yazılır; `launchAtLogin` istisna — kaynağı `SMAppService.mainApp.status`, UserDefaults değil.
- Yorumlar "ne" değil "neden" anlatıyor (özellikle Monitors/ ve Alerts/ altında). Bu üslubu sürdür.

## Agent skills

### Issue tracker

Issue'lar GitHub Issues'da (salihgencer/StatusAppBar); skill'ler `gh` CLI kullanır. Ayrıntı: `docs/agents/issue-tracker.md`.

### Triage labels

Varsayılan beş rollü etiket seti (needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix). Ayrıntı: `docs/agents/triage-labels.md`.

### Domain docs

Single-context düzen: kök `CONTEXT.md` + `docs/adr/`. Ayrıntı: `docs/agents/domain.md`.
