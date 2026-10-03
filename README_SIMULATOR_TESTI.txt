Aydınlatma Mekânı — yalnız iOS simülatöründe no-internet testi

Bu ZIP mevcut iOS projesine uygulanacak güncelleme paketidir.

1. ZIP'i Windows'ta klasöre çıkartın.
2. Kendi GitHub deponuzun kökünde Add file > Upload files seçin.
3. Paket içindeki lib ve ios klasörlerini, codemagic.yaml ve .gitignore dosyalarını yükleyin. Dosyalar mevcut yolların üzerine yazılmalıdır. README dosyası yalnız talimattır.
4. Commit changes ile kaydedin.
5. Codemagic'te ios-simulator iş akışını çalıştırın.
6. Yeni aydinlatmamekani-ios-simulator.zip dosyasını indirip Appetize'a yükleyin. Kaynak kod ZIP'ini Appetize'a yüklemeyin.

TEST
Uygulama açılınca sağ üstte No-internet testi düğmesine dokunun.
Bu düğme interneti kesmeden mevcut no-internet ekranını gösterir.
Tekrar Dene veya Testi bitir ile testten çıkıp gerçek bağlantıyı yeniden kontrol edebilirsiniz.

GÖRÜNÜRLÜK
Düğme yalnız debug modundaki iOS simülatöründe görünür.
Yerel iOS kodu simülatörde çalışıldığını doğrulamadıkça test etkinleşmez.
Gerçek iPhone/iPad'de debug derleme dahil görünmez. Release/App Store derlemesinde görünmez.
App Store için kaynak koddan test düğmesini ayrıca silmek gerekmez.

Normal no-internet ve server-error ekranları gerçek cihazlarda etkin kalır.
iOS'ta görünür geri düğmesi ve çıkış onayı bulunmaz. Önceki popup ve scrollbar düzeltmeleri korunmuştur.

KONTROL
Dart ve Swift sözdizimi, dosya yolları, simülatör koşulları ve önceki hata ekranlarının korunması kontrol edildi.
Bu ortamda Flutter/Xcode derlemesi veya simülatör çalıştırması yapılmadı. Codemagic derlemesi Dart analizini ve iOS derlemesini çalıştırır.
