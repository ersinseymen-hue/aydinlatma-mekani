IOS POPUP KAYDIRMA GÖSTERGESİ — aydinlatma-mekani

Bu paket önceki popup ve Geri/çıkış onayı düzenlemelerini de içerir.

1. ZIP'i çıkarın.
2. aydinlatma-mekani GitHub deposunun ana dizininde Add file > Upload files seçin.
3. lib klasörünü, codemagic.yaml ve .gitignore dosyasını yükleyin.
4. Commit changes yapın. README dosyasını yüklemeniz gerekmez.
5. Codemagic'te main / ios-simulator derlemesini başlatın.
6. Yeni aydinlatmamekani-ios-simulator.zip dosyasını Appetize'da Upload a new build ile yükleyin.

- Yalnız iOS 18.2 ve sonrası ve scrollbar-width: none desteği olan WebView'larda etkinleşir.
- Eski veya sürümü tanımlanamayan iOS ortamlarında mevcut davranış korunur.
- Yalnız #am-smart-search-popup içindeki yerleşik gösterge gizlenir.
- Yeni bir kaydırma alanı oluşturulmaz. Aynı popup'ın kaydırma konumunu gösteren 5px çubuk eklenir.
- Gösterge popup'ın mevcut --am-blue rengini kullanır; dokunmaları engellemez ve sürüklenebilir ayrı bir kontrol değildir.
- İçerik ekrana sığdığında veya popup kapandığında çubuk görünmez.
- Yatay/dikey yön değiştirme, boyut ve içerik değişimleri izlenir.

Kontroller:
Dart sözdizimi, JavaScript sözdizimi, DOM davranış testleri geçti. Önceki köprüler ve Geri/çıkış onayı kodu değişmeden korundu. Flutter analizi ve gerçek iOS çalışma testi burada yapılamadı; Codemagic derlemesi ve Appetize kontrolü gerekir.

Appetize kontrolü:
Popup açıkken cihazı yatay çevirin. Çubuk taşan içerik varsa görünmeli. Popup'ı kaydırırken çubuk da ilerlemeli; ikinci kart ve Kapat düğmesi çalışmalı. Popup kapanınca çubuk kaybolmalı. Dikey modda içerik tamamen sığıyorsa çubuk görünmemeli.
