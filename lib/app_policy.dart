String normalizeThemePreference(String? value) {
  return value == 'light' || value == 'dark' || value == 'system'
      ? value!
      : 'system';
}

bool isMainSiteUrl(Uri? uri) {
  if (uri == null) return false;
  final scheme = uri.scheme.toLowerCase();
  final host = uri.host.toLowerCase();
  return (scheme == 'http' || scheme == 'https') &&
      (host == 'aydinlatmamekani.com' || host == 'www.aydinlatmamekani.com');
}

bool isCatalogUrl(Uri? uri) {
  return uri != null &&
      uri.scheme.toLowerCase() == 'https' &&
      uri.host.toLowerCase() == 'katalog.aydinlatmamekani.com';
}

bool isCategoryPageUrl(Uri? uri) {
  return isMainSiteUrl(uri) &&
      uri!.userInfo.isEmpty &&
      uri.path.startsWith('/kategori/') &&
      uri.path.length > '/kategori/'.length;
}
