import 'package:flutter_test/flutter_test.dart';
import 'package:aydinlatmamekani/app_policy.dart';

void main() {
  test('Both site hostnames remain inside the app', () {
    expect(
      isMainSiteUrl(Uri.parse('https://aydinlatmamekani.com/urun/123')),
      isTrue,
    );
    expect(
      isMainSiteUrl(Uri.parse('https://www.aydinlatmamekani.com/uye')),
      isTrue,
    );
  });
  test('Catalog opens externally and cannot access the microphone bridge', () {
    final catalog = Uri.parse('https://katalog.aydinlatmamekani.com/a.pdf');
    expect(isCatalogUrl(catalog), isTrue);
    expect(isMainSiteUrl(catalog), isFalse);
  });
  test('Facebook auth and lookalike hosts are outside the trusted site', () {
    for (final url in [
      'https://m.facebook.com/login',
      'https://aydinlatmamekani.com.example.org',
      'https://example.org/?url=aydinlatmamekani.com',
      'file:///aydinlatmamekani.com',
    ]) {
      expect(isMainSiteUrl(Uri.parse(url)), isFalse, reason: url);
    }
    expect(isMainSiteUrl(null), isFalse);
  });
  test('Stored light and dark choices survive normalization', () {
    expect(normalizeThemePreference('light'), 'light');
    expect(normalizeThemePreference('dark'), 'dark');
  });
  test('Missing or invalid preferences follow the system theme', () {
    expect(normalizeThemePreference(null), 'system');
    expect(normalizeThemePreference('invalid'), 'system');
    expect(normalizeThemePreference('system'), 'system');
  });
}
