Aydınlatma Mekânı — popup etkileşim düzeltmesi

Bu paket önceki düzeltmeleri içerir. Yalnız bu turdaki değişiklik lib/main.dart içindeki iOS popup köprüsündedir.

GITHUB / CODEMAGIC
1. ZIP'i çıkartın. lib ve ios klasörlerini, codemagic.yaml ve .gitignore dosyalarını mevcut deponuzun kökünde aynı yolların üzerine yükleyin.
2. Commit changes ile kaydedin.
3. Codemagic ios-simulator iş akışını yeniden çalıştırın.
4. Oluşan aydinlatmamekani-ios-simulator.zip dosyasını Appetize'a yükleyin. Bu kaynak ZIP'ini Appetize'a yüklemeyin.

DÜZELTME
Önceki genel KVKK pointer-events kuralı ve geçici popup askıya alma işlemi kaldırıldı.
Yalnız sitenin adı bilinen popup olay dinleyicileri daraltılır. Görünür popup'ın kendi arka plan koruması korunur; dışındaki kargo/KVKK/kategori kontrollerinin kendi olayları çalışır. Gizlenen veya kapanan popup sayfayı kilitlemez.
KVKK'nın en üstteki önceliği korunur. Görünürlüğünü çerez kütüphanesi belirler; kapatılmış bildirim görünmezken dokunmaları yakalamaz. Kapat seçimi silinmez ve otomatik onay verilmez.
KVKK'nın eksik görünmesinin simülatördeki kesin nedeni gözlemlenemedi. Önceki Kapat seçimi veya sitedeki yükleme koşulları etkili olabilir.
Kaydırma çubuğu, normal hata ekranları, simülatör test satırı ve uygulama kimliği korunmuştur. iOS geri düğmesi/çıkış onayı yoktur.

NORMAL TARAYICI
Flutter değişikliği normal tarayıcıya etki etmez. Site popup içeriği için SITE_POPUP_TIKLAMA_DUZELTMESI.txt içindeki ayrı değişiklik hazırlanmıştır. Bu TXT dosyasını GitHub'a yüklemeniz gerekmez.
F5/Ctrl+F5 sorununun nedeni henüz doğrulanmadı; bu fonksiyonlar yalnız Escape tuşunu engeller.

DOĞRULAMA
Dart sözdizimi, JavaScript sözdizimi ve DOM olay testleri geçti. Kargo X, KVKK Kapat/gizlilik bağlantısı, kategori olayı, yenileme tuşlarının iptal edilmemesi, popup arka planı, gizlenen popup ve eski scrollbar testleri kontrol edildi.
Bu ortamda Flutter/Xcode derlemesi veya gerçek iOS çalıştırması yapılmadı. Menü testleri gerçek simülatör navigasyonunun yerine geçmez.
Yeni derlemede popup açıkken kargo X/KVKK, popup kapandıktan sonra kategori bağlantısı ve yatay kaydırma kontrol edilmelidir.
