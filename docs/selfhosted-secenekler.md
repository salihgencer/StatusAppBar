# StatusAppBar için Self-Hosted Yazılım Seçenekleri

Kaynak: [awesome-selfhosted](https://github.com/awesome-selfhosted/awesome-selfhosted) listesi (master, 2026-08 itibarıyla) tarandı.

**Aktiflik doğrulaması:** Aşağıdaki tüm projelerin repo aktivitesi GitHub/GitLab API üzerinden 2026-08-03 tarihinde kontrol edildi; hepsinin son commit'i son birkaç gün–iki hafta içinde. Terk edilmiş proje yok.

Bağlam: tek geliştirici, Linux VPS, Docker/tek binary tercihi, ihtiyaçlar = landing page + gizlilik politikası, destek, analitik, dokümantasyon, e-posta, istatistik.

---

## 1. Statik Site / Landing Page

> Not: Listenin "Static Site Generators" bölümü kendi içinde madde barındırmıyor, [staticgen.com](https://staticgen.com)'a yönlendiriyor. CMS bölümündekiler (WordPress, Joomla vb.) tek geliştiricili bir ürün sayfası için gereksiz ağır. En mantıklı yol statik jeneratör + mevcut VPS'te basit bir web sunucusu.

### Hugo
- **Lisans:** Apache-2.0 · **Teknoloji:** Go, tek binary (Docker imajı da var)
- **Neden uygun:** Landing page + gizlilik politikası + changelog/blog için fazlasıyla yeterli. Binlerce tema, çok dilli destek (TR/EN) hazır. Build çıktısı düz HTML — VPS'te Caddy/nginx ile servis et, bakım derdi yok.
- **Repo:** https://github.com/gohugoio/hugo

### Zola
- **Lisans:** EUPL-1.2 · **Teknoloji:** Rust, tek binary
- **Neden uygun:** Hugo'dan daha sade; tema/shortcode sistemi küçük bir site için ideal. Alternatif olarak **Astro** (MIT) daha "pazarlama sitesi" hissi veren modern bir seçenek.
- **Repo:** https://github.com/getzola/zola

## 2. Web Analitik (gizlilik dostu)

### Umami
- **Lisans:** MIT · **Teknoloji:** Node.js, resmi Docker imajı var (Postgres/MySQL gerekir)
- **Neden uygun:** Basit, çerezsiz, GDPR/KVKK dostu; "siteye kaç kişi geldi, hangi sayfa okundu" ihtiyacını en düşük bakım maliyetiyle çözer. Custom event ile "indirme butonuna tıklama" da izlenir.
- **Repo:** https://github.com/umami-software/umami

### GoatCounter
- **Lisans:** EUPL-1.2 · **Teknoloji:** Go, tek binary (SQLite yeterli)
- **Neden uygun:** En hafif seçenek — veritabanı dahil tek process. Küçük trafikli bir ürün sitesi için Umami'den bile daha az kaynak yer.
- **Repo:** https://github.com/arp242/goatcounter

### Plausible Analytics
- **Lisans:** AGPL-3.0 · **Teknoloji:** Elixir, Docker (ClickHouse + Postgres ister)
- **Neden uygun:** Sınıfının en bilineni; arayüzü ve raporları en cilalısı. Bedeli: kaynak tüketimi Umami/GoatCounter'a göre belirgin yüksek. Matomo (GPL-3.0, PHP) ise tam Google Analytics ikamesi ama bu ölçek için ağır.
- **Repo:** https://github.com/plausible/analytics

## 3. İletişim Formu / Destek

### FreeScout
- **Lisans:** AGPL-3.0 · **Teknoloji:** PHP (Laravel), Docker imajı var
- **Neden uygun:** Zendesk/Help Scout ikamesi; destek taleplerini düz e-posta üzerinden yönetir (kullanıcı tarafında hesap/portal gerekmez — tek kişilik destek için en gerçekçi model). `destek@alanadi.com` adresini paylaşımlı gelen kutusuna çevirir.
- **Repo:** https://github.com/freescout-help-desk/freescout

### Libredesk
- **Lisans:** AGPL-3.0 · **Teknoloji:** Go + Node, tek binary, Docker
- **Neden uygun:** Daha modern, hafif bir alternatif; e-posta + canlı sohbet tek binary'de. Yeni proje ama çok aktif geliştiriliyor. (Saf form backend istersen listedeki **OpnForm** veya **HeyForm** — ikisi de AGPL-3.0, Docker — landing page'e gömülebilir iletişim formu üretir.)
- **Repo:** https://github.com/abhinavxd/libredesk

## 4. Dokümantasyon / Bilgi Tabanı

### Docmost
- **Lisans:** AGPL-3.0 · **Teknoloji:** Node.js, resmi Docker Compose
- **Neden uygun:** Notion/Confluence ikamesi, modern editör; "SSS + kullanım kılavuzu" sitesi olarak public space açılabilir. Aktiflik ve momentum bu kategoride en yüksek projelerden.
- **Repo:** https://github.com/docmost/docmost

### BookStack
- **Lisans:** MIT · **Teknoloji:** PHP, Docker (LinuxServer imajı yaygın)
- **Neden uygun:** Kitap/bölüm/sayfa hiyerarşisi kullanıcı dokümanı için birebir; 10+ yıldır olgun ve istikrarlı. (Alternatif yaklaşım: dokümanı da Hugo/MkDocs ile statik üretip aynı siteye koymak — ek servis çalıştırmazsın.)
- **Repo:** https://github.com/BookStackApp/BookStack

## 5. E-posta

> Gerçekçi not: tek kişi için kendi MX'ini işletmek deliverability (SPF/DKIM/DMARC, IP itibarı) yönetimi demek. Sadece `info@` almak istiyorsan forwarding yeterli; tam sunucu istiyorsan:

### docker-mailserver
- **Lisans:** MIT · **Teknoloji:** Tek Docker konteyneri, SQL'siz (sadece config dosyaları)
- **Neden uygun:** "Production-ready fullstack but simple" — SMTP+IMAP+antispam tek imajda; dokümantasyonu mükemmel, self-host topluluğunda standart cevap. VPS kullanan tek geliştirici için en dengeli seçim.
- **Repo:** https://github.com/docker-mailserver/docker-mailserver

### Mox
- **Lisans:** MIT · **Teknoloji:** Go, tek binary
- **Neden uygun:** SMTP+IMAP+webmail+otomatik TLS+SPF/DKIM/DMARC hepsi tek Go binary'sinde; modern protokolleri (MTA-STS, DANE) kutudan çıkar çıkmaz destekler. Alternatifler: **Maddy** (GPL-3.0, Go tek daemon) ve daha ağır ama kurumsal özellikli **Stalwart** (AGPL-3.0, Rust).
- **Repo:** https://github.com/mjl-/mox

## 6. İndirme / Sürüm İstatistiği ve Ürün Analitiği

### Aptabase
- **Lisans:** AGPL-3.0 · **Teknoloji:** .NET, resmi Docker imajı
- **Neden uygun:** Listenin Analytics bölümündeki tek "mobil + **masaüstü uygulaması**" analitiği — Swift SDK'sı var, yani StatusAppBar'ın *içinden* gizlilik dostu kullanım istatistiği (aktif kullanıcı, sürüm dağılımı, ülke) toplanabilir. App Store satış verisini vermez ama "kaç kişi gerçekten kullanıyor" sorusunu yanıtlar; ücretli bir uygulamada en değerli metrik bu.
- **Repo:** https://github.com/aptabase/aptabase

> Ayrıca (tam madde sayılmaz): **Daily Stars Explorer** (MIT, Docker) GitHub star/interest trendini izler; GitHub release indirme sayıları için ayrı servis kurmaya gerek yok — [shields.io](https://shields.io) `github/downloads` rozeti veya GitHub REST API (`/releases`) + basit bir cron/script yeterli. Satış raporları App Store Connect'ten gelir; bunları tek panelde görmek istersen listenin **Metabase**'i (AGPL-3.0, Docker) genel amaçlı dashboard olarak iş görür.

## 7. Bonus: Projeye Uyan Diğer Bulgular

### Listmonk
- **Lisans:** AGPL-3.0 · **Teknoloji:** Go, tek binary + Postgres, Docker
- **Neden uygun:** Sürüm duyuruları / "App Store'a çıktı" bülteni için kendi Mailchimp'in. Landing page'e gömülebilir abonelik formu üretir; çift opt-in ve KVKK/GDPR araçları dahili.
- **Repo:** https://github.com/knadh/listmonk

### GlitchTip
- **Lisans:** MIT · **Teknoloji:** Python (Django), Docker
- **Neden uygun:** Sentry ikamesi hata takibi; Sentry SDK'larıyla (macOS/Swift dahil) uyumlu — uygulama crash'lerini kendi sunucunda toplarsın, kullanıcı verisi dışarı çıkmaz. Ücretli bir uygulamada "bilinmeyen crash" riskini yönetmenin en ucuz yolu.
- **Repo:** https://gitlab.com/glitchtip/glitchtip

### Fider
- **Lisans:** AGPL-3.0 (listedeki MIT ibaresi güncel değil, repo AGPL'ye geçmiş) · **Teknoloji:** Go, Docker
- **Neden uygun:** Canny/UserVoice ikamesi: kullanıcılar özellik isteği gönderir ve oy verir, sen public roadmap çıkarırsın. Menü çubuğu aracı gibi küçük ama tutkulu kullanıcı kitlesi olan ürünlerde önceliklendirmeyi çok kolaylaştırır.
- **Repo:** https://github.com/getfider/fider

---

## Öncelik Önerisi (kurmaya değme sırası)

1. **Hugo/Zola** ile landing + gizlilik politikası (bugünkü iş)
2. **Umami** veya **GoatCounter** — site analitiği
3. **GlitchTip** — ücretli uygulamada crash görünürlüğü kritik
4. **Listmonk** — lansman bülteni için abone toplamaya erken başla
5. **Aptabase** — uygulama içi kullanım metriği (opsiyonel ama değerli)
6. E-posta, helpdesk (FreeScout/Libredesk), docs (Docmost) — ihtiyaç doğdukça
