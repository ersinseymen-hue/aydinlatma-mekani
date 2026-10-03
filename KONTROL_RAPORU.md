# Aydınlatma Mekânı iOS kontrolü

- Online AVM'de Codemagic ve Appetize ile çalıştığı doğrulanan iOS proje düzeni aktarıldı.
- Aydınlatma Mekânı kaynaklarından logo, açılış/hata görselleri, mavi tema ve UI şekilleri aktarıldı.
- Bundle ID, native method channel, URL scheme ve OneSignal app group uygulamaya özel güncellendi.
- Kaynak sürümü 2.0.0+23 korundu. Flutter 3.38.9 bağımlılıkları sabitlendi.
- Altı web köprüsü yüklenen Aydınlatma Mekânı kaynaklarıyla birebir karşılaştırıldı.
- OneSignal extension gömme sırası, Online AVM'deki başarılı build düzeniyle aynı tutuldu.
- Bu yeni uygulamanın gerçek Xcode derlemesi Codemagic'te yapılacaktır.
- Flutter analyze --fatal-infos: hata veya uyarı bulunmadı.
- Flutter test: 5 test geçti.
- Xcode proje yapısı, plist/entitlement dosyaları, Swift sözdizimi ve 18 iOS ikon boyutu kontrol edildi.
