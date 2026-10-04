Aydınlatma Mekânı — KVKK ve kaydırma çubuğu düzeltmesi

BU SON PAKET ÖNCEKİ DÜZELTMELERİ DE İÇERİR.

1. ZIP'i çıkartın.
2. İçindeki lib ve ios klasörlerini, codemagic.yaml ve .gitignore dosyalarını ilgili GitHub deposunun köküne yükleyin. Dosyalar mevcut yolların üzerine yazılmalıdır.
3. Commit changes ile kaydedin.
4. Codemagic'te ios-simulator iş akışını çalıştırın.
5. Oluşan aydinlatmamekani-ios-simulator.zip dosyasını Appetize'a yükleyin. Bu kaynak kod ZIP'ini Appetize'a yüklemeyin.

SON DAVRANIŞ
KVKK/çerez bildirimi popup açıkken gizlenmez. Site katmanlarında en üstte tutulur.
Popup açıkken Kapat ve gizlilik bağlantısı sitenin kendi işlemini kullanır. Bildirim otomatik kabul edilmez veya kapatılmış sayılmaz.
Popup'ın diğer dış dokunma kuralları korunur.
Kaydırma çubuğu, popup kapsayıcısının kırpma ve dönüşümlerinden etkilenmeyen önceki çizim yerine döndürüldü. Önceliği popup'ın hemen üstünde, KVKK bildiriminin altında hesaplanır.
Popup'ın X düğmesine ait alan çubuğun çiziminden ayrılır. Çubuk dokunmaları engellemez.
Özel çubuk iOS 18.2 ve üzeri, gerekli CSS desteği olduğunda kullanılır.

DİĞER ÖZELLİKLER
No-internet testi yalnız debug iOS simülatöründe, web içeriğinin altında ayrı satırda görünür.
Gerçek cihazlarda normal no-internet ve server-error ekranları korunmuştur.
iOS'ta görünür geri düğmesi ve çıkış onayı yoktur.

KONTROL
Dart sözdizimi ve DOM olay/kaydırma testleri geçti.
KVKK görünürlüğü, Kapat/gizlilik işlemleri, dokunma olayları, popup kilidinin geri yüklenmesi, kaydırma konumu, taşma, eski iOS koşulları ve sonradan eklenen popup kontrol edildi.
Bu ortamda Flutter/Xcode derlemesi ve gerçek iOS çalıştırması yapılmadı. Yeni derlemeyle Appetize'da görsel kontrol gerekir.

TEST SIRASI
1. Yatay modda popup ve KVKK birlikte görünürken KVKK üstte kalmalıdır.
2. KVKK Kapat'a dokunun; bildirim kapanmalı, popup açık kalmalıdır.
3. Popup'ı kaydırın; tek ince çubuk konumu izlemelidir.
4. Dikey/yatay geçişi ve popup'ın X düğmesini kontrol edin.
