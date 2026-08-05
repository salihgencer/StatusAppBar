# StatusAppBar İçin Ücretsiz Servisler

Kaynak: [ripienaar/free-for-dev](https://github.com/ripienaar/free-for-dev) listesi tarandı; şüpheli durumlarda servislerin kendi pricing sayfalarından doğrulandı (Ağustos 2026). Yalnızca kalıcı **free tier**'ı olan servisler listelendi — free trial'lar dahil edilmedi.

Bağlam: macOS menü çubuğu sistem monitörü, Mac App Store'da $4.99 paid-upfront, kaynak kod GitHub'da açık (PolyForm Noncommercial), tek geliştirici, lansman: Product Hunt / HN / Reddit.

---

## 1. Landing Page / Statik Site Hosting

### Cloudflare Pages — ÖNERİLEN
- **Ücretsiz kapsam:** Sınırsız statik istek ve bant genişliği, 500 build/ay, 100 custom domain, otomatik SSL, global CDN. Ticari kullanım kısıtlaması yok.
- **Neden uygun:** Ücretli bir ürünün landing page'i ticari kullanım sayılır; Cloudflare Pages buna izin verir. Gizlilik politikası sayfası da aynı sitede barınır. Aynı hesapta Email Routing (bkz. §5) da ücretsiz.
- **URL:** https://pages.cloudflare.com/ · https://developers.cloudflare.com/pages/

### GitHub Pages
- **Ücretsiz kapsam:** Public repodan sınırsız statik site, custom domain + HTTPS.
- **Neden uygun:** Kod zaten GitHub'da; `statusappbar.github.io` veya custom domain ile sıfır maliyet. Not: GitHub Pages şartları "online iş yürütmek için ücretsiz hosting" olarak kullanımı kısıtlar — bir ürün tanıtım sayfası pratikte yaygın ve sorunsuz, ama en temiz seçenek Cloudflare Pages.
- **URL:** https://pages.github.com/

### Netlify
- **Ücretsiz kapsam:** 300 kredi/ay (~30 GB bant genişliği), custom domain, SSL, form handling (100 submission/ay — §3'e de bak).
- **Neden uygun:** Cloudflare'e alternatif; drag-and-drop deploy ile landing page'i dakikalar içinde yayınlama.
- **URL:** https://www.netlify.com/pricing/

> **Uyarı — Vercel:** Hobby planı yalnızca **non-commercial** kullanım içindir; ücretli uygulamanın ürün sayfası için uygun değil. Listede olmasına rağmen bilinçli olarak önerilmiyor.

---

## 2. Web Analitik (landing page)

### Umami Cloud — ÖNERİLEN
- **Ücretsiz kapsam:** Hobby plan $0 — 100k event/ay, 1 site, 6 ay veri saklama (pricing sayfasından doğrulandı). Açık kaynak, çerezsiz, GDPR uyumlu, cookie banner gerektirmez.
- **Neden uygun:** Gizlilik dostu analitik, Product Hunt/HN trafiğini ölçmek için fazlasıyla yeterli. Açık kaynak duruşu projenin lisansıyla uyumlu.
- **URL:** https://umami.is/pricing

### Microsoft Clarity
- **Ücretsiz kapsam:** Tamamen ücretsiz, trafik limiti yok; session recording + heatmap dahil.
- **Neden uygun:** Lansman günü trafik patlamasında bile limit derdi yok; landing page'de kullanıcıların nereye takıldığını görmek için heatmap bedava.
- **URL:** https://clarity.microsoft.com/

### Aptabase (bonus: uygulama içi analitik)
- **Ücretsiz kapsam:** 20k event/ay; açık kaynak, gizlilik odaklı. Swift SDK'sı macOS'u destekler.
- **Neden uygun:** Web değil **uygulama** analitiği — ileride uygulama içinde (opt-in) kullanım istatistiği istersen menü çubuğu uygulamasına entegre edilebilir. Ticari kısıtlama yok.
- **URL:** https://aptabase.com/

> **Uyarı — GoatCounter:** Hosted free tier yalnızca non-commercial; bu proje ticari olduğu için elendi.

---

## 3. Form / İletişim / Bekleme Listesi

### Tally — ÖNERİLEN
- **Ücretsiz kapsam:** Sınırsız form, sınırsız submission, e-posta bildirimi, form logic, dosya yükleme, ödeme toplama bile free tier'da.
- **Neden uygun:** Destek/iletişim formu için piyasadaki en cömert free tier; landing page'e embed edilir, cevaplar e-postana düşer.
- **URL:** https://tally.so/

### Waitlio
- **Ücretsiz kapsam:** 1 waitlist, 100 abone/ay, markalı bekleme sayfası, e-posta doğrulama, API erişimi.
- **Neden uygun:** App Store onayı öncesi lansman bekleme listesi toplamak için özel olarak tasarlanmış.
- **URL:** https://waitlio.com/

### Buttondown
- **Ücretsiz kapsam:** 100 aboneye kadar newsletter.
- **Neden uygun:** Lansman duyurusu + sürüm notları bülteni için minimalist, Markdown tabanlı, geliştirici dostu.
- **URL:** https://buttondown.email/

Alternatifler: **Web3Forms** (250 submission/ay, sınırsız form), **Formspree** (50 submission/form/ay).

---

## 4. Crash Reporting / Hata Takibi (macOS uyumlu)

### Sentry — ÖNERİLEN
- **Ücretsiz kapsam:** Developer plan: 5k error/ay, 1 kullanıcı. **sentry-cocoa SDK macOS'u native destekler** (AppKit/SwiftUI dahil), dSYM symbolication var.
- **Neden uygun:** Listede macOS ile gerçekten çalışan birkaç servisten biri; çoğu (Embrace, Instabug vb.) yalnızca mobil. Ücretli uygulamada crash visibility kritik.
- **URL:** https://sentry.io/pricing/ · https://github.com/getsentry/sentry-cocoa

### GlitchTip
- **Ücretsiz kapsam:** Hosted: 1k event/ay; **self-host edilirse sınırsız**. Sentry SDK'larıyla uyumlu (sentry-cocoa doğrudan çalışır).
- **Neden uygun:** Sentry'nin 5k limiti dar gelirse veya veri kendi sunucunda kalsın istersen açık kaynak alternatif.
- **URL:** https://glitchtip.com/

### Bugsink
- **Ücretsiz kapsam:** Hosted: 5k error/ay; self-host sınırsız. Yine Sentry-SDK uyumlu.
- **Neden uygun:** GlitchTip'e benzer, tek geliştirici için sade self-host kurulumuyla dikkat çekiyor.
- **URL:** https://www.bugsink.com/

> **Not:** App Store Connect + Xcode Organizer zaten ücretsiz crash raporu veriyor; ancak yalnızca paylaşımı kabul eden kullanıcılardan ve gecikmeli gelir. Sentry anlık + tam rapor sağlar. **Bugsnag** elendi: pricing sayfasında kalıcı free tier teyit edilemedi (yalnızca trial sonrası belirsiz "2k/ay" ibaresi listede var).

---

## 5. E-posta (destek@ adresi)

### Zoho Mail — ÖNERİLEN (gerçek mailbox)
- **Ücretsiz kapsam:** Forever Free plan: 5 kullanıcı, kullanıcı başı 5 GB, **tek custom domain**, mobil uygulama. IMAP/POP/ActiveSync free planda yok (web + mobil app var). Pricing sayfasından doğrulandı.
- **Neden uygun:** `destek@statusappbar.com` gibi gerçek bir gelen kutusu; tek kişi için 5 GB yeterli.
- **URL:** https://www.zoho.com/mail/zohomail-pricing.html

### Cloudflare Email Routing
- **Ücretsiz kapsam:** Custom domainde sınırsız adres yönlendirme (örn. destek@ → Gmail'ine), ücretsiz.
- **Neden uygun:** Mailbox istemiyorsan en basit çözüm; DNS zaten Cloudflare'deyse 5 dakikalık iş. Gönderme için Gmail "Send mail as" ile kombinlenebilir.
- **URL:** https://www.cloudflare.com/developer-platform/products/email-routing/

### forwardemail.net
- **Ücretsiz kapsam:** Custom domain için sınırsız e-posta yönlendirme, açık kaynak.
- **Neden uygun:** Cloudflare kullanmıyorsan alternatif yönlendirme servisi.
- **URL:** https://forwardemail.net/

---

## 6. Statü Sayfası / Uptime Monitoring

### UptimeRobot — ÖNERİLEN
- **Ücretsiz kapsam:** 50 monitor, 5 dk kontrol aralığı, HTTP/ping/port/keyword, e-posta uyarıları, basit status page.
- **Neden uygun:** Landing page + gelecekteki herhangi bir servis (update feed, lisans API vb.) için bol bol yeter.
- **URL:** https://uptimerobot.com/

### Instatus
- **Ücretsiz kapsam:** Sonsuza dek ücretsiz status page, sınırsız abone ve takım üyesi.
- **Neden uygun:** Güzel görünümlü public status sayfası; UptimeRobot ile entegre olur (monitor düşünce sayfa otomatik güncellenir).
- **URL:** https://instatus.com/

Alternatif: **Better Stack** (10 monitor, 3 dk aralık, status page dahil).

---

## 7. Lansman / Pazarlama Araçları

### Canva
- **Ücretsiz kapsam:** Free plan ile sunum/sosyal medya grafikleri, App Store screenshot düzenleme, Product Hunt galeri görselleri.
- **Neden uygun:** Basın kiti ve Product Hunt thumbnail/gallery için tasarımcı gerektirmez.
- **URL:** https://canva.com/

### Smartmockups
- **Ücretsiz kapsam:** 200 ücretsiz mockup.
- **Neden uygun:** MacBook çerçevesi içinde uygulama ekran görüntüleri — landing page hero görseli ve App Store pazarlama materyali için.
- **URL:** https://smartmockups.com/

### Metashot
- **Ücretsiz kapsam:** 1.000 OG (Open Graph) görsel render/ay, URL parametreleriyle dinamik, edge-cache'li.
- **Neden uygun:** Landing page'in HN/Reddit/Twitter'da paylaşıldığında düzgün önizleme kartı çıkması için dinamik OG image.
- **URL:** https://metashot.io

---

## 8. Dikkat Çekici Diğer Servisler

### Iubenda
- **Ücretsiz kapsam:** Free tier ile sınırlı gizlilik politikası + cookie policy üretimi.
- **Neden uygun:** **Gizlilik politikası sayfası ihtiyacını doğrudan karşılıyor** — App Store zaten privacy nutrition label istiyor; web tarafında da hazır, hukuken düzgün şablon sağlar. (Not: uygulama hiç veri toplamıyorsa basit statik bir "veri toplamıyoruz" sayfası da yeterli — o durumda buna gerek kalmaz.)
- **URL:** https://www.iubenda.com/

### Repohistory
- **Ücretsiz kapsam:** Tek repo için GitHub trafik geçmişini 14 günün ötesinde takip eden dashboard.
- **Neden uygun:** GitHub'ın native traffic grafiği yalnızca 14 gün tutar; HN/Reddit dalgalarının uzun vadeli etkisini görmek için.
- **URL:** https://repohistory.com

### FOSSA
- **Ücretsiz kapsam:** Açık kaynak projeler için ücretsiz lisans uyumluluk ve bağımlılık taraması.
- **Neden uygun:** Kaynak kod açık olduğundan (PolyForm Noncommercial), bağımlılıkların lisanslarının App Store dağıtımıyla çelişmediğini belgelemek için kullanışlı.
- **URL:** https://fossa.com/

---

## Özet Tablo (önerilen yığın)

| İhtiyaç | Servis | Maliyet |
|---|---|---|
| Landing page + gizlilik politikası | Cloudflare Pages | $0 |
| Web analitik | Umami Cloud | $0 (100k event/ay) |
| İletişim formu | Tally | $0 (sınırsız) |
| Lansman bülteni | Buttondown veya Waitlio | $0 (100 abone) |
| Crash reporting | Sentry (sentry-cocoa) | $0 (5k error/ay) |
| destek@ e-posta | Zoho Mail veya Cloudflare Email Routing | $0 |
| Uptime + status page | UptimeRobot + Instatus | $0 |
| Pazarlama görselleri | Canva + Smartmockups | $0 |
| OG image | Metashot | $0 (1k/ay) |
| Gizlilik politikası şablonu | Iubenda | $0 (sınırlı) |

**Toplam aylık maliyet: $0.** Tek kalıcı maliyet domain kaydı (~$10-15/yıl) olur.
