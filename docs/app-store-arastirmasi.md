# StatusAppBar — Mac App Store'da Satış Araştırması

> Tarih: 2026-08-03. Durum: araştırma notu — uygulama henüz sandbox'lı test build'i ile doğrulanmadı.
> "⚠️ Doğrulanmalı" işareti: birincil kaynakta net cevap bulunamadı; sandbox açık bir test build'i ile cihazda denenmeli.

## 0. TL;DR

- App Store mümkün ama mevcut mimaride **iki özellik sandbox altında bozulur**: `ps` subprocess'i ile proses listesi ve `osascript` bildirim yedeği. İkisi de değiştirilebilir alternatiflere sahip.
- CPU/RAM/disk/ağ/pil metriklerinin çekirdeği (Mach host API'leri, `getifaddrs`, `IOPowerSources`) sandbox'ta çalışır — kanıt: iStat Menus 7 dahil birçok sistem monitörü Mac App Store'da satılıyor.
- **Notarization ve Hardened Runtime Mac App Store için gerekli değil**; zorunlu olan tek şey App Sandbox + Apple Distribution imzası + Xcode araç zinciriyle paketleme.
- SwiftPM executable doğrudan arşivlenemez; ince bir Xcode projesi sarmalayıcı gerekir (kaynaklar olduğu gibi kalabilir).
- Önerilen model: **paid-upfront $4.99–$9.99** (Keka modeli: GitHub ücretsiz kalır, App Store "destekle satın al" kanalı olur) veya freemium tek-seferlik IAP. Abonelik bu kategori için önerilmez.

---

## 1. App Store teknik gereksinimleri

| Gereksinim | Durum | Kaynak |
|---|---|---|
| Paid Apple Developer Program ($99/yıl) | Gerekli (App Store dağıtımı için) | [developer.apple.com/programs](https://developer.apple.com/programs/) |
| App Sandbox | **Zorunlu** — Review Guidelines 2.4.5(i): "They must be appropriately sandboxed" | [App Review Guidelines 2.4.5](https://developer.apple.com/app-store/review/guidelines/#2.4) |
| Hardened Runtime | MAS için **zorunlu değil**; notarization için zorunludur. MAS'ta sandbox yeterli. | [Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime) |
| Notarization | MAS için **gerekli değil**. Gatekeeper yalnızca "App Store dışından indirilen" yazılımda notarization ister; App Store review kendi tarama hattıdır. | [Apple Platform Security — Gatekeeper](https://support.apple.com/guide/security/welcome/web) |
| İmza | Apple Distribution sertifikası + provisioning profile (ad-hoc imza MAS'a yüklenemez) | [App Store Connect Help](https://developer.apple.com/help/app-store-connect/) |
| Paketleme | Xcode teknolojileriyle paketlenmeli; üçüncü taraf installer yasak; kendi kendini güncelleme yasak (2.4.5(ii), 2.4.5(vii)) | [App Review Guidelines 2.4.5](https://developer.apple.com/app-store/review/guidelines/#2.4) |

Not: Mevcut ad-hoc imzalı GitHub dağıtımı korunabilir — o kanal için Developer ID + notarization istersen Hardened Runtime o zaman gerekir. İki kanal ayrı build hatlarıdır.

---

## 2. Sandbox uyumluluğu (KRİTİK BÖLÜM)

App Sandbox kuralı: child process **parent'ın sandbox'ını miras alır** ve ek yetki verilemez. Kaynak: [Entitlement Key Reference — Enabling App Sandbox (inherit)](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html) ve Apple DTS (Quinn) forum yanıtları, örn. [forums.developer.apple.com/forums/thread/685544](https://forums.developer.apple.com/forums/thread/685544).

### 2.1 Çalışanlar (yüksek güven)

- **Mach `host_processor_info` / `host_statistics64` / `getloadavg`**: sandbox'ta kısıtlı değil. Kanıt: Mac App Store'daki iStat Menus 7 çekirdek bazlı CPU, load average, bellek basıncı, memory pressure gösteriyor ([App Store listesi](https://apps.apple.com/us/app/istat-menus-7/id6499559693)). Bu API'ler için Apple'ın sandbox kısıtı belgelemediğini de ekleyelim.
- **`getifaddrs` ağ sayaçları**: sandbox ağ *erişimini* değil arayüz istatistiklerini okumayı engellemez; MAS'taki monitörler ağ hızı gösteriyor. Gemini çağrısı için `com.apple.security.network.client` entitlement'ı yeterli ([doküman](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.client)).
- **`ProcessInfo.thermalState`**: public Foundation API, sandbox kısıtı yok.
- **Pil — `IOPowerSources` (`IOPSCopyPowerSourcesInfo`)**: public IOKit API'si, sandbox'ta çalışır; MAS'taki pil uygulamaları böyle çalışıyor. Bkz. [SO: Using IOKit in macOS app (battery)](https://stackoverflow.com/questions/48584991/using-iokit-in-macos-app) — "IOKit.framework is a reasonably well documented, public API on macOS… entitlements restrictions apply".
- **`SMAppService` (launch at login)**: sandbox ile tam uyumlu; `mainApp` login item MAS için tasarlanmış yol. Sandbox'lı uygulamanın kurduğu launchd agent'ların da sandbox'lı olması gerekir ([Apple Forums — Service Management](https://developer.apple.com/forums/tags/servicemanagement), Quinn'in tablosu). Guidelines 2.4.5(iii) kullanıcı onayı şartı koyar — ayarlardaki toggle bu onayı sağlar.
- **`UNUserNotificationCenter`**: sandbox'ta sorunsuz, MAS için doğru bildirim yolu.

### 2.2 Bozulanlar (yüksek güven)

- **`ps` subprocess'i → çalışmaz / işe yaramaz.**
  İki katmanlı sorun:
  1. Sandbox'lı uygulamadan sistem binary'si spawn etmek pratikte `deny(1) process-exec` / "Operation not permitted" duvarına çarpar; güvenilir çalışan tek yol kendi bundle'ındaki imzalı helper'ları çalıştırmaktır (raporlar: [SO — shell script with App Sandbox](https://stackoverflow.com/questions/19937966/how-to-run-a-shell-script-with-mac-app-sandbox-enabled), [HackTricks macOS Sandbox](https://book.hacktricks.wiki/en/macos-hardening/macos-security-and-privilege-escalation/macos-security-protections/macos-sandbox.html)).
  2. Spawn edilse bile child sandbox'ı miras alır; sandbox'lı `ps` diğer prosesleri göremez.
  
  **Çözüm önerisi**: `ps`'i tamamen bırak. Proses listesi için:
  - `NSWorkspace.shared.runningApplications` / `NSRunningApplication` — sandbox uyumlu, isim/ikon/PID verir.
  - Aynı kullanıcıya ait proseslerin CPU/RAM'i için libproc `proc_pid_rusage` sandbox'ta kullanılabiliyor (⚠️ doğrulanmalı — [SO: proc_pid_rusage in sandboxed app](https://stackoverflow.com/questions/47020502/using-proc-pid-rusage-in-sandboxed-app) sorusu bunun denendiğini gösteriyor; iStat Menus MAS sürümü "apps using the most CPU" listesini helper'sız sunduğuna göre bir yol mevcut).
  - **Başka kullanıcıların prosesleri MAS kapsamında fiilen imkânsız** — kabul edilebilir bir sınırlama olarak App Store açıklamasına yazılmalı. (iStat Menus MAS sürümünün bazı istatistikler için ayrı bir "Helper" indirtmesi tam da bu yüzden — bkz. §3.)

- **`osascript display notification` yedeği → kaldırılmalı.**
  Sandbox'ta Apple Events gönderimi `com.apple.security.automation.apple-events` entitlement'ı + Info.plist açıklaması + kullanıcı onayı ister; spawn edilen `osascript` child'ı sandbox'ı miras aldığı için event gönderimi reddedilir (hata -1743 sınıfı). Ayrıca dış script çalıştırmak App Review'da gereksiz soru doğurur. `UNUserNotificationCenter` tek başına yeterli; fallback'i silmek hem sandbox hem review açısından daha temiz.

### 2.3 Belirsiz / cihazda doğrulanmalı

- **IOKit `IOBlockStorageDriver` (disk I/O sayaçları)**: iStat Menus MAS disk aktivitesi gösteriyor, yani IORegistry'den *okuma* genel olarak sandbox'ta mümkün. Ama `IOServiceOpen` tabanlı erişim bazı sürücü sınıflarında sandbox'a takılıyor ([SO: IOKit not permitted in Sandbox?](https://stackoverflow.com/questions/23244349/iokit-not-permitted-in-sandbox)). ⚠️ **Doğrulanmalı**: yalnızca `IORegistryEntryCreateCFProperty` ile property okunuyorsa çalışma ihtimali yüksek; kext/connection gerektiren yollar riskli.
- **`AppleSmartBattery` IORegistry detayları (cycle count, sağlık)**: MAS'taki pil uygulamaları (ör. Battery Health serisi) cycle count gösteriyor, yani büyük ihtimalle çalışır. ⚠️ Doğrulanmalı — temel yüzde/durum zaten `IOPowerSources` ile garanti.
- **S.M.A.R.T. durumu**: sandbox'ta mümkün değil gibi; iStat Menus MAS'ta S.M.A.R.T. dahil bazı veriler helper'a taşınmış durumda. StatusAppBar bunu kullanmıyorsa sorun yok.

### 2.4 Gemini "derin analiz" özelliği ve App Review

- Kullanıcının **kendi API key'iyle** üçüncü taraf API çağrısı kurallara aykırı değil: 3.1.1 yalnızca uygulama içi dijital içerik *satışını* IAP'a bağlar; burada satış yok, kullanıcı Google ile kendi hesabını kullanıyor.
- Yapılması gerekenler: `network.client` entitlement'ı; App Review notlarına "opsiyonel özellik, kullanıcı kendi Gemini API key'ini girer, key'siz uygulama tam işlevsel" açıklaması (reviewer key olmadan test edemez, 2.1 "demo account" maddesine takılmamak için bu net yazılmalı); App Privacy beyanında "kullanıcı talebiyle sistem metrikleri üçüncü taraf servise gönderilir" ifadesi.
- ⚠️ Doğrulanmalı: Google'ın Gemini API şartlarının üçüncü taraf istemcilere izin kapsamı ayrıca kontrol edilmeli (App Store değil, Google ToS konusu).

---

## 3. Benzer uygulamalar ne yapıyor?

| Uygulama | Dağıtım | Fiyat | Sandbox yaklaşımı |
|---|---|---|---|
| **iStat Menus 7** (Bjango) | Mac App Store + doğrudan satış + Setapp | MAS: **$11.99** paid-upfront + hava durumu aboneliği IAP ($4.99/yıl veya $0.99/ay) ([App Store](https://apps.apple.com/us/app/istat-menus-7/id6499559693)) | MAS sürümü sandbox'lı; fan kontrolü, CPU frekansı ve bazı sensör/S.M.A.R.T. verileri için ayrı "iStat Menus Helper" indirtiliyor — Bjango bunun "App Store kurallarının tam işlevselliğe izin vermemesinden" kaynaklandığını belirtiyor ([MacRumors derlemesi](https://forums.macrumors.com/threads/istat-menus-6-from-app-store-vs-directly-from-devs.2345825/), [AAPL Ch.](https://applech2.com/archives/20240821-istat-menus-7-mac-app-store-version.html)) |
| **Stats** (exelban, MIT) | **App Store'da YOK** — yalnızca DMG + Homebrew ([README](https://github.com/exelban/stats/blob/master/README.md)) | Ücretsiz | Sandbox'suz dağıtılıyor; SMC sensörleri için root LaunchDaemon helper (`/Library/PrivilegedHelperTools/...`) kuruyor — bu mimari 2.4.5(v) (root escalation yasağı) nedeniyle MAS'a taşınamaz. Stats'in MAS'ta olmamasının teknik nedeni büyük ihtimalle bu. |
| **iStatistica Pro** | Mac App Store | Freemium; tam kilit açma ~$5.99 ([derleme](https://thesweetbits.com/istat-menus-vs-istatistica-pro/)) | Freemium/IAP modelinin bu kategoride çalıştığına örnek. |
| **Keka** (açık kaynak örneği) | Web sitesi ücretsiz + MAS ücretli | MAS: $4.99 civarı "destek" satışı ([MacSources](https://macsources.com/keka-macos-file-archiver-2022-review/)) | Açık kaynak projeyi MAS'ta satmanın kanıtlanmış modeli: kaynak ve site sürümü ücretsiz kalır, MAS kolaylık + destek kanalı olur. |

Sonuç: kategori lideri (iStat) bile MAS sürümünde bazı verilerden feragat ediyor. StatusAppBar'ın çekirdek metrikleri bu feragat listesinde değil; yalnızca proses listesi kısıtlanıyor.

---

## 4. SwiftPM'den App Store'a geçiş

- SwiftPM executable target'tan doğrudan MAS arşivi üretilemez: provisioning, entitlement imzalama ve `.app` hedefi Xcode proje modeli gerektirir. Guidelines 2.4.5(ii) "Xcode ile paketlenmiş" şartı da bunu fiilen zorunlu kılar.
- **Önerilen yol (minimal invaziv)**:
  1. `Sources/StatusAppBar`'ı olduğu gibi bırak.
  2. Repo köküne ince bir Xcode projesi ekle: tek macOS App target, SwiftUI, deployment target macOS 14. Kaynak dosyaları doğrudan hedefe referansla ekle (veya mevcut paketi local SwiftPM dependency olarak bağla).
  3. Signing & Capabilities: App Sandbox aç, `Outgoing Connections (Client)` işaretle.
  4. `Product > Archive` → Organizer → App Store Connect'e yükle; veya CI için `xcodebuild archive -scheme ... && xcodebuild -exportArchive -exportMethod app-store-connect`.
- Kategori: **Utilities** (iStat Menus da bu kategoride). Yaş derecelendirmesi: **4+** (iStat Menus referansıyla).
- `LSUIElement = true` (Dock'suz menü çubuğu ajanı) MAS ile uyumlu; Info.plist'te kalır.

---

## 5. Monetizasyon — bu kategori için

### Modeller

| Model | Artı | Eksi | Bu uygulamaya uyum |
|---|---|---|---|
| **Paid-upfront** ($4.99–$9.99) | Basit, IAP altyapısı yok, 2.4.5(vi) lisans ekranı yasağıyla çelişmez | Deneme yok (yalnızca App Store içi trial mekanikleri) | ✅ Önerilen (Keka modeli) |
| **Freemium + tek seferlik IAP** | Deneme doğal; 3.1.1 "XX-day Trial" tier-0 non-consumable ile süreli deneme resmi olarak destekleniyor | StoreKit entegrasyonu gerekir | ✅ İkinci seçenek (iStatistica modeli) |
| **Abonelik** | Sürekli gelir | Utility'de sürekli değer kanıtı zor (3.1.2(a) "ongoing value" şartı); kullanıcı tepkisi yüksek | ❌ Önerilmez — Gemini bile kullanıcının kendi key'i, sunucu maliyeti yok |

### Fiyat referansları (güncel, Ağustos 2026 civarı)

- iStat Menus 7 MAS: **$11.99** ([App Store](https://apps.apple.com/us/app/istat-menus-7/id6499559693))
- iStatistica Pro tam kilit: **~$5.99** ([derleme](https://thesweetbits.com/istat-menus-vs-istatistica-pro/))
- Keka MAS: **~$4.99** ([MacSources](https://macsources.com/keka-macos-file-archiver-2022-review/))
- Stats: ücretsiz (MAS'ta yok)

**Öneri**: GitHub sürümü ücretsiz kalmaya devam edeceği için MAS fiyatı "destek + kolaylık" primi taşımalı: **$4.99 veya $6.99**. iStat'ın yarısı civarı, Keka ile aynı lig.

### Komisyon

- Standart %30; **Small Business Program** ile %15 — yıllık 1M USD altı gelir şartı, başvuru gerekli ([Apple — Small Business Program](https://developer.apple.com/app-store/small-business-program/)). Bu ölçekte neredeyse kesin %15 uygulanır; hesap açılır açılmaz kaydolunmalı (onaydan sonraki ayın 15'inde yürürlüğe girer).

### MIT açık kaynak riskleri

- MIT lisansı herkese fork + kendi adıyla MAS'a yükleme hakkı verir. Gerçek risk: **kopya uygulamalar**. Koruma: (1) uygulama adını/markayı tescil ettir ve metadata'da marka ihlali bildirimi hakkını kullan (Guidelines 4.1 "Copycats" ve 5.2 fikri mülkiyet maddeleri şikâyet zemini); (2) "resmi sürüm" anlatısı kur — Keka bunu yıllardır başarıyla yapıyor; (3) Gemini analizi gibi sunucu tarafı değeri olan özellikler kopyalarda aynı cazibeyi taşımaz.
- 2.4.5(vi): MAS sürümü lisans ekranı/anahtarı gösteremez, kendi kopya korumasını yapamaz — ücretlendirme tamamen App Store fiyatına veya IAP'a dayanmalı.
- 2.4.5(vii): kendi güncelleme mekanizması yasak — varsa GitHub release kontrolü MAS build'inde kapatılmalı veya MAS sayfasına yönlendirmeli.

---

## 6. App Review Guidelines — bu uygulamayı ilgilendiren maddeler

Kaynak: [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

- **2.4.5 (Mac'e özel kurallar)**: (i) sandbox zorunlu; (ii) Xcode paketleme, kendi kendine kurulan tek bundle; (iii) **onaysız otomatik başlatma/arka plan prosesi yok** — `SMAppService` toggle'ı onaylı sayılır; (iv) ek kod indirme yok; (v) root/setuid yok (Stats'in SMC helper modeli bu yüzden MAS dışı); (vi) lisans ekranı/anahtarı yok; (vii) güncellemeler yalnızca MAS üzerinden; (viii) deprecated teknoloji yok.
- **2.5.1 public API zorunluluğu**: Mach host API'leri, IOKit, `getifaddrs` public. ⚠️ Dokümante edilmemiş IORegistry property anahtarları (bazı pil/SMC değerleri) "private API" sayılabilir — review'da sorulursa savunması zor; kritik olmayan detay verileri fallback'li yazılmalı.
- **2.1 App Completeness**: Gemini özelliği reviewer'ın test edemeyeceği bir dış bağımlılık → Review Notes'ta açıkça anlat, key'siz tam işlevsellik vurgulanmalı.
- **2.3 Accurate Metadata**: "proses listesi yalnızca kendi kullanıcının prosesleri" gibi sandbox kaynaklı sınırlar App Store açıklamasında dürüstçe belirtilmeli (yanıltıcı pazarlama 2.3.1 ihlali sayılır).
- **1.1.6 doğruluk**: sistem metriği uygulaması olarak yanlış veri göstermek red nedeni olabilir — hesaplama doğruluğu review notlarında vurgulanabilir.
- **Menü çubuğuna özel ayrı bir kural yok**; `LSUIElement` ajan uygulamalar MAS'ta standart kabul görüyor.

---

## 7. Gizlilik ve uyumluluk (gözden kaçması kolay iki madde)

- **Privacy manifest (`PrivacyInfo.xcprivacy`)**: Mayıs 2024'ten beri App Store Connect yüklemelerinde "required reason API" beyanı zorunlu; beyansız kullanım `ITMS-91053` ile reddedilir. StatusAppBar'ın kullandığı muhtemel kategoriler: **disk alanı** (`statfs`/`volumeAvailableCapacity` → `NSPrivacyAccessedAPICategoryDiskSpace`), **UserDefaults** (ayarlar → `NSPrivacyAccessedAPICategoryUserDefaults`), varsa **sistem açılış zamanı/uptime** (`NSPrivacyAccessedAPICategorySystemBootTime`) ve **dosya zaman damgası**. Kaynak: [Apple — Describing use of required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) (⚠️ macOS-only uygulamalarda kapsam ayrıntısını Xcode 15+ ile doğrula).
- **App Privacy (besin etiketi)**: Gemini çağrısı nedeniyle "veri toplanmıyor ama kullanıcı isteğiyle üçüncü tarafa sistem metriği gönderiliyor" beyanı gerekir; iStat Menus "Data Not Collected" beyan ediyor ([App Store](https://apps.apple.com/us/app/istat-menus-7/id6499559693)) — StatusAppBar Gemini'siz de aynısını diyebilir ama Gemini akışı açıklamada yer almalı. Gizlilik politikası URL'si zorunlu (GitHub Pages yeterli).
- **Şifreleme ihracat beyanı**: HTTPS kullanımı standart muafiyet kapsamında — App Store Connect'te "exempt" işaretle veya `ITSAppUsesNonExemptEncryption = false`. Kaynak: [Apple — Complying with encryption export regulations](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations).

---

## 8. Pratik checklist (adım adım)

1. **Hesap**: Apple Developer Program'a kaydol ($99/yıl) → [developer.apple.com/programs](https://developer.apple.com/programs/). Ardından **Small Business Program**'a başvur (%15 komisyon).
2. **Kod değişiklikleri (sandbox hazırlığı)**:
   - `ps` subprocess'ini kaldır → `NSWorkspace.runningApplications` + (aynı kullanıcı için) `proc_pid_rusage`'e geç; başka kullanıcıların prosesleri "App Store sürümünde yok" olarak belgelensin.
   - `osascript` bildirim yedeğini kaldır → yalnızca `UNUserNotificationCenter`.
   - Varsa kendi güncelleme kontrolünü MAS build'inde devre dışı bırak (2.4.5(vii)).
3. **Xcode projesi**: ince App target oluştur, mevcut kaynakları bağla; `LSUIElement`, deployment target macOS 14.
4. **Entitlements**: `com.apple.security.app-sandbox` + `com.apple.security.network.client`. Başka bir şey ekleme (gereksiz entitlement review sorusu doğurur).
5. **Privacy manifest**: `PrivacyInfo.xcprivacy` — disk space + user defaults (+ gerekirse boot time) reason kodlarıyla.
6. **Sandbox doğrulama build'i**: Sandbox açık build'de her metriği tek tek cihazda test et — özellikle `IOBlockStorageDriver` ve `AppleSmartBattery` IORegistry okumaları (§2.3). Console.app'te `sandboxd` deny loglarını izle.
7. **App Store Connect**: yeni uygulama → kategori Utilities → yaş 4+ → fiyat ($4.99–$6.99 öneri) → şifreleme beyanı (exempt) → App Privacy formu → gizlilik politikası URL'si.
8. **Metadata**: açıklamada sandbox sınırlarını dürüstçe yaz (2.3); screenshot'lar gerçek kullanımı göstersin (2.3.3); isim/marka uygunluğu kontrolü (4.1).
9. **Review Notes**: "Gemini derin analiz opsiyoneldir, kullanıcı kendi API key'ini girer; key'siz tüm özellikler çalışır. Demo hesap gerekmez." + launch-at-login toggle'ının onay mekanizması olduğu notu.
10. **İki kanal stratejisi**: GitHub sürümü (ad-hoc veya ileride Developer ID + notarize) ücretsiz kalır; MAS sürümü ayrı build config ile üretilir. `release.sh`'e MAS varyantı eklenebilir.

---

## 9. En büyük riskler (özet)

1. **Proses listesi özelliği kısıtlanacak** — başka kullanıcıların prosesleri MAS'ta mümkün değil; bu, uygulamanın fark yaratan bir özelliğiyse değer önerisi yeniden yazılmalı.
2. **IOKit detay okumaları (disk I/O, pil detayları)** sandbox'ta doğrulanmadı — §2.3; en kötü senaryoda bazı alt metrikler MAS sürümünden çıkarılır.
3. **Kopya uygulama riski** (MIT) — marka koruması ve "resmi sürüm" konumlandırması şart.
4. **Review belirsizliği** — menü çubuğu monitörleri MAS'ta yaygın olduğundan kategori riski düşük; asıl belirsizlik Gemini özelliğinin review'da nasıl karşılanacağı (notlarla yönetilebilir).

## Kaynaklar (birincil ağırlıklı)

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) — özellikle 2.4.5, 2.5.1, 2.3, 3.1.1
- [App Store Small Business Program](https://developer.apple.com/app-store/small-business-program/)
- [Apple Developer Program](https://developer.apple.com/programs/)
- [Apple Platform Security — Gatekeeper & notarization](https://support.apple.com/guide/security/welcome/web)
- [Entitlement Key Reference — App Sandbox inheritance](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html)
- [com.apple.security.network.client](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.client)
- [Apple — Required reason API / privacy manifest](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
- [Apple Forums — Service Management (SMAppService + sandbox)](https://developer.apple.com/forums/tags/servicemanagement)
- [iStat Menus 7 — App Store](https://apps.apple.com/us/app/istat-menus-7/id6499559693) · [Bjango](https://bjango.com/mac/istatmenus/) · [MAS sürüm farkları (MacRumors)](https://forums.macrumors.com/threads/istat-menus-6-from-app-store-vs-directly-from-devs.2345825/)
- [Stats (exelban) README](https://github.com/exelban/stats/blob/master/README.md)
- [SO — IOKit in macOS app (battery)](https://stackoverflow.com/questions/48584991/using-iokit-in-macos-app) · [SO — IOKit not permitted in Sandbox?](https://stackoverflow.com/questions/23244349/iokit-not-permitted-in-sandbox) · [SO — proc_pid_rusage in sandboxed app](https://stackoverflow.com/questions/47020502/using-proc-pid-rusage-in-sandboxed-app)
- [Keka MAS modeli (MacSources)](https://macsources.com/keka-macos-file-archiver-2022-review/)
