# Not Hesaplama

Lisans öğrencileri için tarayıcıda çalışan, bağımlılık gerektirmeyen kredi ağırlıklı dönem notu ve harf notu takip uygulaması.

| Alan | Değer |
|---|---|
| **Kategori** | Statik Web Uygulaması |
| **Teknoloji** | Saf HTML / CSS / Vanilla JS (`localStorage`) |
| **Port / URL** | `3003` · `http://localhost:3003` |
| **Başlatıcı** | `BASLAT.bat` (`start.ps1`) |
| **Doğrulama** | `node --check app.js` |

## Özellikler

- Ders ekleme, kredi belirleme (`0.5–30`), yeniden adlandırma ve silme.
- Her derse sınav ekleme, düzenleme, not (`0–100`) ve ağırlık (`%0–100`) güncelleme.
- Ders ortalamasını, kredi ağırlıklı dönem ortalamasını ve 100'lük sisteme göre harf notunu otomatik hesaplama.
- Final notu girilmeden harf notu ve genel ortalama üretmeme; ağırlık toplamı için görsel durum uyarısı.
- Normal / kompakt ızgara görünümü geçişi ve mobil/masaüstü uyumlu arayüz.
- Hazır lisans dersleri (Vize `%37,5`, Kısa Sınav `%12,5`, Final `%50`) ve tarayıcıda otomatik kayıt.

## Klasör Yapısı

```text
not-hesaplama/
├── index.html              # Ana uygulama arayüzü ve modal şablonları
├── app.js                  # Durum yönetimi, hesaplama ve doğrulama mantığı
├── styles.css              # Sayfa ve kart stilleri
├── BASLAT.bat & start.ps1  # Tek tık yerel sunucu başlatıcısı (port 3003)
├── AGENTS.md               # Mühendislik kuralları
├── .gitignore              # Git yoksayma kuralları
└── README.md
```

## Kurulum ve Çalıştırma

- **Windows Tek Tık Başlatıcı (Önerilen):** `BASLAT.bat` dosyasına çift tıklayın (`http://localhost:3003` adresinde Python `http.server` veya Node.js statik sunucu ile açılır).
- **Doğrudan Dosyadan:** İsterseniz `index.html` dosyasını doğrudan tarayıcıda da açabilirsiniz.

## Testler ve Doğrulama

```sh
node --check app.js
```
