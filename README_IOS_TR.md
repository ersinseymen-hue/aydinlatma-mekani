# Aydınlatma Mekânı — iOS

Uygulama: Aydınlatma Mekânı
Bundle ID: com.lightstore.aydinlatmamekani
Adres: https://aydinlatmamekani.com
Sürüm: 2.0.0+23

## Şimdi tarayıcıda test

1. ZIP dosyasını çıkarın. GitHub'da aydinlatmamekani-ios adlı ayrı, private depo oluşturun.
2. ZIP içindeki assets, ios, lib, test klasörlerini ve kökteki dosyaları deponun ana dizinine yükleyin. Üstteki aydinlatmamekani_ios klasörünü ayrıca yüklemeyin. codemagic.yaml ve pubspec.yaml kökte görünmelidir.
3. Codemagic'te Add application ile bu depoyu ekleyin. Configuration: codemagic.yaml; branch: main; workflow: ios-simulator. Start new build.
4. Başarılı build'in Artifacts bölümünden aydinlatmamekani-ios-simulator.zip dosyasını indirin.
5. Appetize'da yeni uygulama yüklemesi açın ve bu ZIP'i doğrudan yükleyin.
6. Açılış, ürün arama, ürün detayları, sepet ve açık/koyu temayı test edin. Test bitince simülatör oturumunu kapatın.

## Daha sonra

Apple Developer üyeliği ve imzalama ayarları hazır olduğunda cihaz/mağaza için imzalı build hazırlanır. ios-unsigned iş akışı imzasız cihaz derlemesini kontrol eder; mağazaya yüklenebilen imzalı IPA üretmez.

OneSignal App ID, yüklenen Android kaynaklarındaki mevcut değeri korur. Apple bildirim kimlik bilgileri ve ayrı uygulama tercihleri yayın aşamasında düzenlenir. Simülatör testi gerçek iPhone bildirimi doğrulamasının yerini tutmaz.

Orijinal Android kaynakları değiştirilmemiştir. Bu paket ayrı iOS projesidir.
