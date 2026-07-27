# DogonFiles — Native Android Kurulum Rehberi

## ⚠️ Önemli: Bu paket ne içeriyor, ne içermiyor

Ben (Claude) bu ortamda **internete çıkamıyorum**, bu yüzden `npx cap add android`
komutunun normalde ürettiği devasa native Android proje iskeletini (gradle-wrapper.jar,
Capacitor'ün Android kütüphaneleri vb. — yüzlerce dosya, internetten indirilir) elle
üretemedim. Onun yerine size **her şeyi otomatik kuran bir sistem** hazırladım:

- `www/` → gerçek uygulamanızın arayüzü (sizin HTML'iniz + kök erişim köprüsü)
- `android-patch/` → Shizuku/libsu kök erişim kodu (Java) + gerekli manifest/gradle ekleri
- `apply-patch.sh` → `cap add android` çalıştıktan SONRA yukarıdaki yamayı otomatik uygular
- `.github/workflows/build.yml` → GitHub Actions ile **Android Studio kurmadan** APK üretir
- `capacitor.config.json`, `package.json` → proje tanımları

Yani akış şu: `npm install` → `npx cap add android` (bu adım internet ister, native
iskeleti indirir) → `bash apply-patch.sh` (Shizuku/libsu kodunu enjekte eder) → derle.
Bu akışı hem Termux'ta hem de GitHub Actions'ta (otomatik) çalıştırabilirsiniz.

---

## 1) En kolay yol: Sadece GitHub Actions kullanın (Android Studio GEREKMEZ)

1. Bu zip'i açıp içeriğini yeni bir GitHub reposuna push edin (aşağıdaki Termux
   bölümüne bakın).
2. Repo → **Actions** sekmesi → "Build DogonFiles APK" workflow'unu bulun →
   **Run workflow** butonuna basın (debug veya release seçin).
3. Build bitince aynı sayfada **Artifacts** altında `DogonFiles-apk` dosyasını
   indirin, içinden `app-debug.apk`'yı telefonunuza kurun.
4. Workflow otomatik olarak: bağımlılıkları kurar → ikonları üretir (varsa) →
   `npx cap add android` çalıştırır → `apply-patch.sh` ile Shizuku/libsu kodunu
   ekler → Gradle ile APK derler.

> Not: `release` seçimi imzasız APK üretir (Google Play için değil, kendi
> cihazınıza kurmak için "bilinmeyen kaynaklardan yükleme"yi açmanız yeterli).
> Gerçek imzalı release için ayrıca bir keystore ve imzalama adımı gerekir —
> isterseniz bunu da ayrı bir workflow adımı olarak ekleyebilirim.

---

## 2) Termux ile GitHub'a push etme

```bash
pkg install git -y
cd ~/storage/downloads   # veya zip'i açtığınız klasör
unzip DogonFiles.zip
cd DogonFiles

git init
git add .
git commit -m "DogonFiles ilk sürüm"
git branch -M main

# GitHub'da önce boş bir repo oluşturun (github.com üzerinden), sonra:
git remote add origin https://github.com/KULLANICI_ADIN/DogonFiles.git
git push -u origin main
```

İlk push'ta kullanıcı adı/şifre yerine **Personal Access Token (PAT)** isteyecektir
(GitHub artık şifreyle push'a izin vermiyor). Token oluşturmak için:
GitHub → Settings → Developer settings → Personal access tokens → Generate new
token (repo yetkisiyle) → push sırasında şifre alanına bu token'ı yapıştırın.

---

## 3) Yerelde (bilgisayarda / Termux'ta) manuel build

```bash
npm install
npx cap add android          # internet gerekir, native iskeleti indirir
bash apply-patch.sh          # Shizuku/libsu kodunu android/ içine enjekte eder
cd android
chmod +x gradlew
./gradlew assembleDebug      # çıktı: android/app/build/outputs/apk/debug/app-debug.apk
```

Termux'ta tam Android SDK/Gradle kurmak zahmetlidir — bu yüzden asıl önerilen
yol GitHub Actions'tır (madde 1).

---

## 4) İkon Sorunu — Neden Beyaz Arka Plan Çıkıyor ve Nasıl Çözülür

**Sebep:** Android'in adaptive icon sistemi iki katman ister: bir **foreground**
(şeffaf arka planlı logo) ve bir **background** (düz renk). Kaynak PNG'niz
şeffaf değilse (veya `@capacitor/assets` şeffaf olmayan bir PNG'den otomatik
adaptive icon üretmeye çalışırsa) launcher bunu beyaza boyayarak "tamamlar".

### Otomatik çözüm (önerilen)

1. `resources/icon.png` konumuna **1024×1024, PADDINGSİZ, gerçek alfa
   şeffaflığı olan** logonuzu koyun (örn. Figma/Photoshop'tan PNG olarak,
   arka planı transparan bırakarak export edin — beyaz dikdörtgen DEĞİL,
   gerçek alpha kanalı olmalı).
2. Aşağıdaki komutu çalıştırın (bu proje `package.json`'da zaten script
   olarak tanımlı):
   ```bash
   npm install -D @capacitor/assets
   npx capacitor-assets generate --android
   ```
3. Bu komut `android/app/src/main/res/mipmap-*` altına foreground/background
   katmanlarını ve `ic_launcher.xml` (adaptive icon) dosyalarını **otomatik
   ve doğru** şekilde üretir.
4. GitHub Actions workflow'u `resources/icon.png` varsa bu komutu build
   sırasında zaten otomatik çalıştırıyor.

### Manuel yol (otomatik üretim işe yaramazsa)

`android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
```

`android/app/src/main/res/values/colors.xml` içine (BEYAZ DEĞİL, koyu tema rengi):
```xml
<color name="ic_launcher_background">#08090b</color>
```

`ic_launcher_foreground`: 108×108dp tuval, gerçek logo **66dp güvenli alan**
içine ortalanmış, geri kalanı tamamen **şeffaf** (alpha=0) bir PNG/vektör
olmalı — logo kenarları launcher maskesi tarafından kırpılıyorsa 66dp
kuralına uymamış demektir.

### Doğrulama

Kurulum sonrası launcher'da uygulama ikonuna basılı tutup "Uygulama Bilgisi"
yerine doğrudan ana ekrandaki ikonun köşelerine bakın: arka plan beyazsa
foreground PNG hâlâ opak bir zemin içeriyordur (alfa kanalı export sırasında
kaybolmuş olabilir — export ayarlarında "transparency/alpha" açık olduğundan
emin olun).

---

## 5) Logo/İkon Dosyalarını Nereye Koymalısınız (isimlendirme)

| Dosya | Konum | Amaç |
|---|---|---|
| `icon.png` (1024×1024, şeffaf) | `resources/icon.png` | Uygulama ikonu — `@capacitor/assets` bundan tüm mipmap boyutlarını üretir |
| `splash.png` (2732×2732, ortalanmış logo) | `resources/splash.png` | Açılış ekranı — aynı komutla üretilir |
| Uygulama içi logo (ör. üst bar `.logo` SVG'si) | zaten `www/index.html` içinde inline SVG olarak var, değiştirmek isterseniz `www/assets/logo.png` oluşturup HTML'de `<img src="assets/logo.png">` ile değiştirebilirsiniz |
| Diğer uygulama içi PNG ikonlar | `www/assets/icons/` klasörü açıp oradan `<img src="assets/icons/isim.png">` ile referans verin |

`resources/` klasörünü zip içine boş bir `resources/README.txt` ile
bıraktım — `icon.png` ve `splash.png` dosyalarınızı oraya koymanız yeterli.

---

## 6) Root/Shizuku Nasıl Çalışıyor (özet)

- `www/dogon-root-bridge.js`: arayüzdeki "Kök Erişimi" toggle'ını gerçek
  native plugin'e bağlar. Plugin yoksa (örn. tarayıcıda test), eski
  simülasyona otomatik düşer — davranış bozulmaz.
- `DogonRootPlugin.java`: önce Shizuku, yoksa libsu (Magisk root) dener.
  **Sadece salt-okunur `ls` komutu** çalıştırır — dosya yazma/silme bu
  plugin üzerinden yapılmaz (bilinçli güvenlik sınırı; mevcut kopyala/taşı/sil
  işlemleri hâlâ uygulama içi sanal katmanda kalır).
- Shizuku hiç kurulu değilse kullanıcıya kurulum ekranı (Play Store, GitHub,
  ADB komutu, Kablosuz hata ayıklama) otomatik gösterilir — bunu tetiklemek
  için ekstra bir şey yapmanıza gerek yok, `dogon-root-bridge.js` hallediyor.

⚠️ Shizuku API'sinin bazı iç metodları (`newProcess`) sürümden sürüme
değişebiliyor. `DogonRootPlugin.java` içinde reflection ile çağrılıyor;
`dev.rikka.shizuku:api` sürümünü güncellerseniz bu metodun hâlâ mevcut
olduğunu (veya Shizuku'nun önerdiği güncel `UserService` AIDL yöntemine
geçmeniz gerekip gerekmediğini) Shizuku'nun resmi dokümantasyonundan
kontrol edin.

---

## 7) 120Hz / Performans

- `MainActivity.java`: donanım hızlandırma, `offscreenPreRaster`, overscroll
  kapatma, edge-to-edge.
- `capacitor.config.json`: `androidScheme: https`, `allowMixedContent: false`.
- Test için: Geliştirici Seçenekleri → "Zorla 120Hz" (destekleyen cihazlarda)
  açıp uygulamayı gerçek cihazda deneyin — WebView refresh rate'i otomatik
  cihazdan alır, ekstra kod gerekmez.
