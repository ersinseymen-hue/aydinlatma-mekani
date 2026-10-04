import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_policy.dart';

const String siteUrl = 'https://aydinlatmamekani.com';
const String oneSignalAppId = 'e1ff25e0-3d28-493a-a742-19fb9e305e87';

const Color appPrimary = Color(0xFF00A2E8);
const Color loadingOrange = Color.fromRGBO(240, 147, 43, 1);
const Color loadingTrack = Color.fromRGBO(220, 220, 220, 1);
const Color appDarkBackground = Color(0xFF12161C);
const Color appDarkCard = Color(0xFF191E25);
const Color appDarkSurface = Color(0xFF20262F);
const Color appDarkBorder = Color(0xFF1B384A);
const Color appDarkTextPrimary = Color(0xFFDDF2FC);
const MethodChannel appNativeChannel =
    MethodChannel('com.lightstore.aydinlatmamekani/browser');

enum AppErrorScreen {
  none,
  noInternet,
  serverError,
}

class _StartupThemeState {
  const _StartupThemeState({
    required this.preference,
    required this.isDarkMode,
  });

  final String preference;
  final bool isDarkMode;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final _StartupThemeState startupTheme =
      await _resolveStartupThemeBeforeRunApp();

  runApp(
    AydinlatmaMekaniApp(
      initialThemePreference: startupTheme.preference,
      initialDarkMode: startupTheme.isDarkMode,
    ),
  );
}

Future<_StartupThemeState> _resolveStartupThemeBeforeRunApp() async {
  final _StartupThemeState routeFallback = _readStartupThemeFromInitialRoute();

  if (!Platform.isAndroid && !Platform.isIOS) {
    return routeFallback;
  }

  try {
    final dynamic raw = await appNativeChannel
        .invokeMethod<dynamic>('getStartupThemeState')
        .timeout(const Duration(milliseconds: 1500));

    if (raw is Map) {
      final String preference = normalizeThemePreference(
        raw['preference']?.toString(),
      );
      final String? resolved = raw['resolved']?.toString();

      if (resolved == 'dark' || resolved == 'light') {
        return _StartupThemeState(
          preference: preference,
          isDarkMode: resolved == 'dark',
        );
      }
    }
  } catch (error) {
    debugPrint('Native başlangıç teması okunamadı: $error');
  }

  return routeFallback;
}

_StartupThemeState _readStartupThemeFromInitialRoute() {
  final bool fallbackDarkMode =
      WidgetsBinding.instance.platformDispatcher.platformBrightness ==
          Brightness.dark;

  try {
    final String route =
        WidgetsBinding.instance.platformDispatcher.defaultRouteName;
    final Uri? uri = Uri.tryParse(route);

    if (uri != null && uri.path == '/am-startup') {
      final String preference = normalizeThemePreference(
        uri.queryParameters['preference'],
      );
      final String? resolved = uri.queryParameters['theme'];

      if (resolved == 'dark' || resolved == 'light') {
        return _StartupThemeState(
          preference: preference,
          isDarkMode: resolved == 'dark',
        );
      }
    }
  } catch (error) {
    debugPrint('Başlangıç tema rotası okunamadı: $error');
  }

  return _StartupThemeState(
    preference: 'system',
    isDarkMode: fallbackDarkMode,
  );
}

Future<void> _requestOneSignalPushPermission() async {
  try {
    await OneSignal.Notifications.requestPermission(false);
  } catch (error) {
    debugPrint('OneSignal bildirim izni istenemedi: $error');
  }
}

Future<void> _initializeOneSignal() async {
  try {
    OneSignal.Debug.setLogLevel(OSLogLevel.none);

    OneSignal.initialize(oneSignalAppId);

    // Push altypisini hemen hazirla, ancak In-App Message'i
    // ilk WebView yuklemesi tamamlanana kadar ekranda gosterme.
    await OneSignal.InAppMessages.paused(true);

    unawaited(_requestOneSignalPushPermission());
  } catch (error) {
    debugPrint('OneSignal başlatılamadı: $error');
  }
}

class AydinlatmaMekaniApp extends StatelessWidget {
  const AydinlatmaMekaniApp({
    super.key,
    required this.initialThemePreference,
    required this.initialDarkMode,
  });

  final String initialThemePreference;
  final bool initialDarkMode;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Aydınlatma Mekânı',
      theme: ThemeData(useMaterial3: false),
      darkTheme: ThemeData.dark(useMaterial3: false),
      themeMode: initialDarkMode ? ThemeMode.dark : ThemeMode.light,
      initialRoute: '/',
      home: WebViewScreen(
        initialThemePreference: initialThemePreference,
        initialDarkMode: initialDarkMode,
      ),
    );
  }
}

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({
    super.key,
    required this.initialThemePreference,
    required this.initialDarkMode,
  });

  final String initialThemePreference;
  final bool initialDarkMode;

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen>
    with WidgetsBindingObserver {
  static const MethodChannel _browserChannel = appNativeChannel;

  // Keep the mobile popup's existing grid, spacing and minimum heights.
  // Avoid a zero flex basis for its grid buttons in an auto-height column
  // on iOS; the two cards should derive their height from their contents.
  static const String _smartSearchPopupIOSLayoutBridge = r'''
(function () {
  'use strict';

  function installStyle() {
    if (document.getElementById('am-ios-smart-search-layout')) {
      return;
    }

    var target = document.head || document.documentElement;
    if (!target) {
      return;
    }

    var style = document.createElement('style');
    style.id = 'am-ios-smart-search-layout';
    style.textContent =
      '@media (max-width:1023px){' +
      '#am-smart-search-popup .am-smart-search__option{' +
      'flex:0 0 auto!important;' +
      '-webkit-appearance:none;' +
      'appearance:none;' +
      '}}';
    target.appendChild(style);
  }

  installStyle();
  document.addEventListener('DOMContentLoaded', installStyle, { once: true });
})();
''';

  // Limit the site's smart-popup guard to its own visible backdrop.
  static const String _smartSearchPopupIOSCookieBridge = r'''
(function () {
  'use strict';
  if (window.__AM_IOS_POPUP_COOKIE_GUARD__) return;
  window.__AM_IOS_POPUP_COOKIE_GUARD__ = true;

  // Scope the correction to the site's named smart-popup listeners. Do not
  // change event cancellation, cookies, or the popup's suspension state.
  var originalAdd = document.addEventListener;
  var originalRemove = document.removeEventListener;
  var wrappers = new WeakMap();
  var outsideEvents = ['pointerdown', 'pointerup', 'mousedown', 'mouseup',
    'click', 'touchstart', 'touchend'];

  function visiblePopup(root, layer) {
    if (!root || !layer || !root.isConnected || !layer.isConnected) return false;
    var box = root.getBoundingClientRect();
    if (box.width <= 0 || box.height <= 0 || box.bottom <= 0 ||
        box.top >= window.innerHeight) return false;
    for (var node = root; node; node = node.parentElement) {
      var style = getComputedStyle(node);
      if (node.hidden || style.display === 'none' ||
          style.visibility === 'hidden' || style.visibility === 'collapse' ||
          style.opacity === '0' ||
          node.classList.contains('fancybox-is-closing')) return false;
    }
    return true;
  }

  document.addEventListener = function (type, listener, options) {
    var outside = typeof listener === 'function' &&
      listener.name === 'blockSmartPopupOutsideClose' &&
      outsideEvents.indexOf(type) !== -1;
    var escape = typeof listener === 'function' &&
      listener.name === 'blockSmartPopupEscape' && type === 'keydown';
    if (!outside && !escape) {
      return originalAdd.call(this, type, listener, options);
    }
    var byType = wrappers.get(listener);
    if (!byType) { byType = {}; wrappers.set(listener, byType); }
    if (!byType[type]) {
      byType[type] = function (event) {
        var root = document.getElementById('am-smart-search-popup');
        var idea = root && root.closest('#idea-popup');
        var layer = idea && idea.closest('.fancybox-container');
        if (!visiblePopup(root, layer)) return;
        // Protect only the popup's own backdrop. Header/category navigation,
        // shipping and cookie controls outside this container keep their events.
        if (outside && !layer.contains(event.target)) return;
        return listener.call(this, event);
      };
    }
    return originalAdd.call(this, type, byType[type], options);
  };

  document.removeEventListener = function (type, listener, options) {
    var byType = typeof listener === 'function' && wrappers.get(listener);
    return originalRemove.call(this, type,
      byType && byType[type] ? byType[type] : listener, options);
  };

  function installStyle() {
    var html = document.documentElement;
    if (!html || document.getElementById('am-ios-smart-popup-cookie-guard')) return;
    var style = document.createElement('style');
    style.id = 'am-ios-smart-popup-cookie-guard';
    // Preserve the cookie library's own visibility and pointer-event rules,
    // including cc-invisible after the user's dismissal.
    style.textContent = '.cc-window{z-index:2147483647!important;}';
    (document.head || html).appendChild(style);
  }
  installStyle();
  document.addEventListener('DOMContentLoaded', installStyle, { once: true });
})();
''';

  static const String _smartSearchPopupIOSScrollbarBridge = r'''
(function () {
  'use strict';

  // Require both the shipped iOS version and CSS support. Older WebKit builds
  // may parse a property before implementing its rendering behavior.
  var os = navigator.userAgent.match(/\bOS (\d+)[_.](\d+)/);
  if (!os || Number(os[1]) < 18 ||
      (Number(os[1]) === 18 && Number(os[2]) < 2) ||
      !window.CSS || !CSS.supports('scrollbar-width', 'none') ||
      window.__AM_IOS_POPUP_SCROLLBAR__) {
    return;
  }
  window.__AM_IOS_POPUP_SCROLLBAR__ = true;

  var popup = null;
  var track = null;
  var thumb = null;
  var resizeObserver = null;
  var pending = false;
  var previousWidth = '';
  var previousPriority = '';

  function schedule() {
    if (pending) { return; }
    pending = true;
    requestAnimationFrame(function () {
      pending = false;
      update();
    });
  }

  function bind(next) {
    if (popup === next) { return; }
    if (popup) {
      popup.removeEventListener('scroll', schedule);
      if (popup.style.getPropertyValue('scrollbar-width') === 'none') {
        if (previousWidth) {
          popup.style.setProperty('scrollbar-width', previousWidth, previousPriority);
        } else {
          popup.style.removeProperty('scrollbar-width');
        }
      }
    }
    if (resizeObserver) { resizeObserver.disconnect(); }
    popup = next;
    if (!popup) { return; }
    previousWidth = popup.style.getPropertyValue('scrollbar-width');
    previousPriority = popup.style.getPropertyPriority('scrollbar-width');
    popup.style.setProperty('scrollbar-width', 'none', 'important');
    popup.addEventListener('scroll', schedule, { passive: true });
    if (window.ResizeObserver) {
      resizeObserver = new ResizeObserver(schedule);
      resizeObserver.observe(popup);
      var grid = popup.querySelector('.am-smart-search__grid');
      if (grid) { resizeObserver.observe(grid); }
    }
  }

  function update() {
    bind(document.getElementById('am-smart-search-popup'));
    if (!track || !popup) {
      if (track) { track.style.display = 'none'; }
      return;
    }
    // The indicator lives at page level so Fancybox transforms/overflow
    // cannot displace or clip it. Place it just above its popup, below KVKK.
    var layerPriority = 0;
    for (var node = popup; node; node = node.parentElement) {
      var value = parseInt(getComputedStyle(node).zIndex, 10);
      if (isFinite(value)) { layerPriority = Math.max(layerPriority, value); }
    }
    track.style.zIndex = String(Math.min(2147483646, layerPriority + 1));
    var style = getComputedStyle(popup);
    var box = popup.getBoundingClientRect();
    var maxScroll = popup.scrollHeight - popup.clientHeight;
    var visible = box.width > 0 && box.height > 0 &&
      box.bottom > 0 && box.top < window.innerHeight &&
      style.display !== 'none' && style.visibility !== 'hidden' &&
      (style.overflowY === 'auto' || style.overflowY === 'scroll') &&
      maxScroll > 1 && style.getPropertyValue('scrollbar-width') === 'none';
    for (var parent = popup; visible && parent; parent = parent.parentElement) {
      var ancestorStyle = getComputedStyle(parent);
      if (ancestorStyle.display === 'none' ||
          ancestorStyle.visibility === 'hidden' || Number(ancestorStyle.opacity) === 0) {
        visible = false;
      }
    }
    if (!visible) {
      track.style.display = 'none';
      return;
    }

    // Overlay the existing scrolling element without resizing it or adding
    // another scroll container. Pointer events continue to reach the popup.
    var top = Math.max(0, box.top) + 12;
    var close = popup.querySelector('.am-smart-search__close');
    if (close) {
      var closeBox = close.getBoundingClientRect();
      if (closeBox.width > 0 && closeBox.right >= box.right - 14) {
        top = Math.max(top, closeBox.bottom + 6);
      }
    }
    var hit = document.elementFromPoint &&
      document.elementFromPoint(box.right - 10, top + 1);
    if (hit && !popup.contains(hit) &&
        !(hit.closest && hit.closest('.cc-window'))) {
      track.style.display = 'none';
      return;
    }
    var bottom = Math.min(window.innerHeight, box.bottom) - 12;
    var height = bottom - top;
    if (height <= 0) { track.style.display = 'none'; return; }
    var size = Math.min(height, Math.max(24,
      height * popup.clientHeight / popup.scrollHeight));
    var progress = Math.max(0, Math.min(1, popup.scrollTop / maxScroll));
    var color = style.getPropertyValue('--am-scrollbar-color').trim() ||
      style.getPropertyValue('--am-blue').trim() ||
      style.getPropertyValue('--am-accent-dark').trim() || '#00A2E8';
    track.style.top = top + 'px';
    track.style.left = (box.right - 12) + 'px';
    track.style.height = height + 'px';
    track.style.backgroundColor = 'color-mix(in srgb, ' + color + ' 18%, transparent)';
    thumb.style.backgroundColor = color;
    thumb.style.height = size + 'px';
    thumb.style.transform = 'translateY(' + ((height - size) * progress) + 'px)';
    track.style.display = 'block';
  }

  function start() {
    if (track || !document.body) { return; }
    track = document.createElement('div');
    track.id = 'am-ios-popup-scrollbar';
    track.setAttribute('aria-hidden', 'true');
    track.style.cssText = 'position:fixed;display:none;width:4px;pointer-events:none;' +
      'z-index:1;border-radius:3px;overflow:hidden;';
    thumb = document.createElement('div');
    thumb.style.cssText = 'position:absolute;top:0;left:0;width:100%;' +
      'border-radius:3px;pointer-events:none;';
    track.appendChild(thumb);
    document.body.appendChild(track);
    new MutationObserver(function (records) {
      if (records.some(function (record) {
        return record.target !== track && record.target !== thumb;
      })) { schedule(); }
    }).observe(document.documentElement, {
      childList: true, subtree: true, attributes: true,
      attributeFilter: ['class', 'style', 'hidden']
    });
    document.addEventListener('scroll', schedule, true);
    document.addEventListener('load', schedule, true);
    document.addEventListener('transitionend', schedule, true);
    document.addEventListener('animationend', schedule, true);
    window.addEventListener('resize', schedule);
    window.addEventListener('orientationchange', schedule);
    window.addEventListener('pageshow', schedule);
    if (window.visualViewport) {
      window.visualViewport.addEventListener('resize', schedule);
      window.visualViewport.addEventListener('scroll', schedule);
    }
    update();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start, { once: true });
  } else {
    start();
  }
})();
''';

  static const String _nativeVoiceRecognitionBridge = r'''
(function () {
  'use strict';

  var isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent);
  if ((!isIOS && (window.SpeechRecognition || window.webkitSpeechRecognition)) ||
      window.__AYDINLATMA_NATIVE_SPEECH__) {
    return;
  }

  window.__AYDINLATMA_NATIVE_SPEECH__ = true;

  function NativeSpeechRecognition() {
    this.continuous = false;
    this.interimResults = false;
    this.lang = 'tr-TR';
    this._running = false;
    this._listeners = {};
  }

  NativeSpeechRecognition.prototype.addEventListener = function (type, callback) {
    if (typeof callback !== 'function') {
      return;
    }

    if (!this._listeners[type]) {
      this._listeners[type] = [];
    }

    this._listeners[type].push(callback);
  };

  NativeSpeechRecognition.prototype.removeEventListener = function (type, callback) {
    var listeners = this._listeners[type] || [];
    this._listeners[type] = listeners.filter(function (item) {
      return item !== callback;
    });
  };

  NativeSpeechRecognition.prototype._dispatch = function (type, event) {
    event = event || {};
    event.type = type;

    var listeners = (this._listeners[type] || []).slice();
    listeners.forEach(function (callback) {
      try { callback.call(this, event); } catch (error) {}
    }, this);

    var propertyHandler = this['on' + type];
    if (typeof propertyHandler === 'function') {
      try { propertyHandler.call(this, event); } catch (error) {}
    }
  };

  NativeSpeechRecognition.prototype._finish = function () {
    if (!this._running) {
      return;
    }

    this._running = false;
    this._dispatch('end', {});
  };

  NativeSpeechRecognition.prototype.start = function () {
    if (this._running) {
      throw new Error('InvalidStateError');
    }

    this._running = true;
    this._dispatch('start', {});

    var self = this;
    var bridge = window.flutter_inappwebview;

    if (!bridge || typeof bridge.callHandler !== 'function') {
      self._dispatch('error', { error: 'service-not-allowed' });
      self._finish();
      return;
    }

    bridge.callHandler('nativeVoiceSearch', this.lang || 'tr-TR').then(
      function (text) {
        if (!self._running) {
          return;
        }

        var transcript = (text || '').toString().trim();

        if (!transcript) {
          self._dispatch('error', { error: 'no-speech' });
          self._finish();
          return;
        }

        var alternative = {
          transcript: transcript,
          confidence: 1
        };
        var result = [alternative];
        result.isFinal = true;
        var results = [result];

        self._dispatch('result', {
          resultIndex: 0,
          results: results
        });
        self._finish();
      },
      function () {
        if (!self._running) {
          return;
        }

        self._dispatch('error', { error: 'network' });
        self._finish();
      }
    );
  };

  NativeSpeechRecognition.prototype.stop = function () {
    if (!this._running) {
      return;
    }

    try {
      if (window.flutter_inappwebview &&
          typeof window.flutter_inappwebview.callHandler === 'function') {
        window.flutter_inappwebview.callHandler('nativeVoiceSearchStop');
      }
    } catch (error) {}

    this._finish();
  };

  NativeSpeechRecognition.prototype.abort =
      NativeSpeechRecognition.prototype.stop;

  window.webkitSpeechRecognition = NativeSpeechRecognition;
  window.SpeechRecognition = NativeSpeechRecognition;
})();
''';

  InAppWebViewController? _webViewController;
  Uri? _pendingOneSignalUrl;
  Future<void>? _oneSignalInitializationFuture;
  Timer? _oneSignalInAppResumeTimer;
  int _oneSignalInAppResumeGeneration = 0;
  bool _oneSignalInAppMessagesResumed = false;
  Uri _lastSiteUrl = Uri.parse(siteUrl);
  late final PullToRefreshController _pullToRefreshController;

  bool _showSplash = true;
  bool _initialRealPageLoadStarted = false;
  bool _pageLoading = false;
  bool _showWelcomeTooltip = false;
  bool _welcomeTooltipShown = false;
  bool _retryInProgress = false;
  bool _currentLoadFailed = false;
  bool _googleLoginNoticeOpen = false;
  bool _backNavigationInProgress = false;
  bool _simulatorTestsAvailable = false;
  bool _simulatorNoInternetPreview = false;
  int _recoveryGeneration = 0;
  int _pageLoadGeneration = 0;
  int _finalizingLoadGeneration = -1;

  late String _themePreference;
  late bool _isDarkMode;
  late final bool _splashDarkMode;

  AppErrorScreen _errorScreen = AppErrorScreen.none;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  double _splashProgress = 0.0;
  double _siteProgress = 0.0;

  Timer? _finishTimer;
  Timer? _pageReadyStabilityTimer;
  Timer? _welcomeTooltipTimer;
  late final DateTime _splashStartedAt = DateTime.now();
  static const int _minimumSplashVisibleMs = 700;
  static const int _pageReadyStabilityMs = 250;

  final InAppWebViewSettings _webViewSettings = InAppWebViewSettings(
    javaScriptEnabled: true,
    useShouldOverrideUrlLoading: true,
    cacheEnabled: true,
    mediaPlaybackRequiresUserGesture: false,
    supportZoom: false,
    verticalScrollBarEnabled: true,
    horizontalScrollBarEnabled: false,
    transparentBackground: false,
    domStorageEnabled: true,
    thirdPartyCookiesEnabled: true,
    builtInZoomControls: false,
    displayZoomControls: false,
    allowsInlineMediaPlayback: true,
    allowsBackForwardNavigationGestures: true,
    javaScriptCanOpenWindowsAutomatically: true,
    sharedCookiesEnabled: true,
  );

  Future<void> _configureSimulatorTests() async {
    if (!kDebugMode || !Platform.isIOS) {
      return;
    }
    try {
      final bool available = await _browserChannel
              .invokeMethod<bool>('isSimulatorTestEnvironment') ??
          false;
      if (mounted && available) {
        setState(() => _simulatorTestsAvailable = true);
      }
    } catch (_) {
      // Missing/failed native confirmation always leaves test controls hidden.
    }
  }

  void _showSimulatorNoInternet() {
    if (!kDebugMode || !Platform.isIOS || !_simulatorTestsAvailable ||
        _showSplash || !mounted) {
      return;
    }
    _recoveryGeneration++;
    _simulatorNoInternetPreview = true;
    _showErrorScreen(AppErrorScreen.noInternet);
  }

  Future<void> _endSimulatorNoInternet() async {
    if (!kDebugMode || !Platform.isIOS || !_simulatorTestsAvailable ||
        !_simulatorNoInternetPreview || !mounted) {
      return;
    }
    setState(() => _simulatorNoInternetPreview = false);
    _clearErrorScreen();
    await _retryCurrentPage();
  }

  Future<bool> _requestMicrophonePermission() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return true;
    }

    try {
      final bool? granted = await _browserChannel.invokeMethod<bool>(
        'requestMicrophonePermission',
      );
      return granted == true;
    } catch (error) {
      debugPrint('Mikrofon izni alınamadı: $error');
      return false;
    }
  }

  Future<String?> _startNativeVoiceRecognition(String language) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return null;
    }

    try {
      return await _browserChannel.invokeMethod<String>(
        'startVoiceRecognition',
        <String, dynamic>{
          'language': language.isEmpty ? 'tr-TR' : language,
        },
      );
    } catch (error) {
      debugPrint('Sesli arama başlatılamadı: $error');
      return null;
    }
  }

  Future<void> _stopNativeVoiceRecognition() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }

    try {
      await _browserChannel.invokeMethod<bool>('stopVoiceRecognition');
    } catch (error) {
      debugPrint('Sesli arama durdurulamadı: $error');
    }
  }

  String get _nativeThemeBridge {
    final String preference = jsonEncode(_themePreference);
    final String resolvedTheme = jsonEncode(_isDarkMode ? 'dark' : 'light');

    return '''
(function () {
  'use strict';

  var STORAGE_KEY = 'am-theme-preference-v1';
  var SESSION_KEY = 'am-native-theme-seeded-v2';
  var nativePreference = $preference;
  var nativeResolvedTheme = $resolvedTheme;

  function normalizeTheme(value) {
    return value === 'dark' ? 'dark' : 'light';
  }

  function readStoredTheme() {
    try {
      var stored = window.localStorage.getItem(STORAGE_KEY);
      if (stored === 'light' || stored === 'dark') {
        return stored;
      }
    } catch (ignore) {}

    return null;
  }

  function resolveDesiredTheme() {
    var seeded = false;

    try {
      seeded = window.sessionStorage.getItem(SESSION_KEY) === '1';
    } catch (ignore) {}

    if (!seeded) {
      var firstTheme = nativePreference === 'light' || nativePreference === 'dark'
        ? nativePreference
        : nativeResolvedTheme;

      try {
        window.localStorage.setItem(STORAGE_KEY, firstTheme);
        window.sessionStorage.setItem(SESSION_KEY, '1');
      } catch (ignore) {}

      return normalizeTheme(firstTheme);
    }

    return normalizeTheme(readStoredTheme() || nativeResolvedTheme);
  }

  function applyRootTheme(theme) {
    var root = document.documentElement;
    if (!root) return;

    root.classList.toggle('am-theme-dark', theme === 'dark');
    root.setAttribute('data-am-theme', theme);
    root.setAttribute('data-am-theme-preference', theme);

    var meta = document.getElementById('am-theme-color');
    if (meta) {
      meta.setAttribute('content', theme === 'dark' ? '#0E1217' : '#F0932B');
    }
  }

  function applyNativeTheme() {
    var desiredTheme = resolveDesiredTheme();
    applyRootTheme(desiredTheme);

    if (!window.AMTheme ||
        typeof window.AMTheme.setPreference !== 'function') {
      return false;
    }

    try {
      window.__AM_NATIVE_THEME_SYNC_ACTIVE__ = true;
      window.AMTheme.setPreference(desiredTheme);
      return true;
    } catch (ignore) {
      return false;
    } finally {
      window.setTimeout(function () {
        window.__AM_NATIVE_THEME_SYNC_ACTIVE__ = false;
      }, 0);
    }
  }

  window.__AM_APPLY_NATIVE_THEME__ = applyNativeTheme;

  function reportManualThemeChange() {
    var preference = 'system';
    var resolved = document.documentElement.classList.contains('am-theme-dark')
      ? 'dark'
      : 'light';

    try {
      if (window.AMTheme &&
          typeof window.AMTheme.getPreference === 'function') {
        preference = window.AMTheme.getPreference() || preference;
      }
      if (window.AMTheme &&
          typeof window.AMTheme.getResolvedTheme === 'function') {
        resolved = window.AMTheme.getResolvedTheme() || resolved;
      }
    } catch (ignore) {}

    try {
      var bridge = window.flutter_inappwebview;
      if (bridge && typeof bridge.callHandler === 'function') {
        bridge.callHandler(
          'nativeThemeChanged',
          preference,
          resolved,
          true
        );
      }
    } catch (ignore) {}
  }

  window.addEventListener('am:themechange', function (event) {
    if (window.__AM_NATIVE_THEME_SYNC_ACTIVE__ === true) {
      return;
    }

    var source = event && event.detail ? event.detail.source : null;
    if (source === 'manual') {
      reportManualThemeChange();
    }
  });

  applyRootTheme(resolveDesiredTheme());

  var attempts = 0;
  function retryThemeApiSync() {
    if (applyNativeTheme()) {
      return;
    }

    attempts += 1;
    if (attempts < 100) {
      window.setTimeout(retryThemeApiSync, 20);
    }
  }

  retryThemeApiSync();

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () {
      applyNativeTheme();
    }, { once: true });
  } else {
    applyNativeTheme();
  }
})();
''';
  }

  static const String _webPushSuppressionBridge = r'''
(function () {
  'use strict';

  if (window.__AM_NATIVE_APP_WEB_PUSH_BLOCKER__) {
    return;
  }

  window.__AM_NATIVE_APP_WEB_PUSH_BLOCKER__ = true;

  var PROMPT_SELECTORS = [
    '#onesignal-slidedown-container',
    '.onesignal-slidedown-container',
    '#onesignal-popover-container',
    '.onesignal-popover-container',
    '#onesignal-bell-container',
    '.onesignal-bell-container',
    '.onesignal-customlink-container',
    '.slidedown-prompt',
    '[class*="onesignal-slidedown"]',
    '[id*="onesignal-slidedown"]'
  ];

  function installStyle() {
    if (!document.documentElement || document.getElementById('am-native-app-hide-web-push')) {
      return;
    }

    var style = document.createElement('style');
    style.id = 'am-native-app-hide-web-push';
    style.textContent = PROMPT_SELECTORS.join(',') +
      '{display:none!important;visibility:hidden!important;opacity:0!important;pointer-events:none!important;}';
    document.documentElement.appendChild(style);
  }

  function removePromptNodes(root) {
    if (!root || !root.querySelectorAll) {
      return;
    }

    for (var i = 0; i < PROMPT_SELECTORS.length; i++) {
      var nodes = root.querySelectorAll(PROMPT_SELECTORS[i]);
      for (var j = 0; j < nodes.length; j++) {
        try {
          nodes[j].style.setProperty('display', 'none', 'important');
          nodes[j].remove();
        } catch (ignore) {}
      }
    }
  }

  function resolvedFalse() {
    return Promise.resolve(false);
  }

  function patchOneSignal(api) {
    if (!api) {
      return;
    }

    try {
      if (api.Slidedown) {
        api.Slidedown.promptPush = resolvedFalse;
        api.Slidedown.promptPushCategories = resolvedFalse;
      }
    } catch (ignore) {}

    try {
      if (api.Notifications) {
        api.Notifications.requestPermission = resolvedFalse;
      }
    } catch (ignore) {}

    var legacyMethods = [
      'showSlidedownPrompt',
      'showCategorySlidedown',
      'showNativePrompt',
      'registerForPushNotifications'
    ];

    for (var i = 0; i < legacyMethods.length; i++) {
      try {
        if (typeof api[legacyMethods[i]] === 'function') {
          api[legacyMethods[i]] = resolvedFalse;
        }
      } catch (ignore) {}
    }
  }

  try {
    if (window.Notification &&
        typeof window.Notification.requestPermission === 'function') {
      window.Notification.requestPermission = function () {
        return Promise.resolve('denied');
      };
    }
  } catch (ignore) {}

  var deferred = window.OneSignalDeferred;
  if (!Array.isArray(deferred)) {
    deferred = [];
  }

  var originalPush = deferred.push.bind(deferred);
  deferred.push = function () {
    var wrapped = [];

    for (var i = 0; i < arguments.length; i++) {
      var callback = arguments[i];

      if (typeof callback !== 'function') {
        wrapped.push(callback);
        continue;
      }

      wrapped.push((function (originalCallback) {
        return function (api) {
          patchOneSignal(api);
          var result = originalCallback(api);
          patchOneSignal(api);
          removePromptNodes(document);
          return result;
        };
      })(callback));
    }

    return originalPush.apply(deferred, wrapped);
  };

  window.OneSignalDeferred = deferred;

  function sweep() {
    installStyle();
    removePromptNodes(document);

    try {
      patchOneSignal(window.OneSignal);
    } catch (ignore) {}
  }

  var sweepQueued = false;

  function scheduleSweep() {
    if (sweepQueued) {
      return;
    }

    sweepQueued = true;

    var run = function () {
      sweepQueued = false;
      sweep();
    };

    if (typeof window.requestAnimationFrame === 'function') {
      window.requestAnimationFrame(run);
    } else {
      window.setTimeout(run, 16);
    }
  }

  sweep();

  if (document.documentElement && window.MutationObserver) {
    var observer = new MutationObserver(function () {
      scheduleSweep();
    });

    observer.observe(document.documentElement, {
      childList: true,
      subtree: true
    });
  } else if (document.addEventListener) {
    document.addEventListener('DOMContentLoaded', function () {
      sweep();

      if (window.MutationObserver && document.documentElement) {
        var observer = new MutationObserver(function () {
          scheduleSweep();
        });

        observer.observe(document.documentElement, {
          childList: true,
          subtree: true
        });
      }
    }, { once: true });
  }

  var checks = 0;
  var timer = window.setInterval(function () {
    sweep();
    checks += 1;
    if (checks >= 30) {
      window.clearInterval(timer);
    }
  }, 500);
})();
''';

  Future<void> _persistThemePreference(
    String preference, {
    required bool explicitChange,
  }) async {
    try {
      await _browserChannel.invokeMethod<bool>(
        'setThemePreference',
        <String, dynamic>{
          'preference': preference,
          'explicit': explicitChange,
        },
      );
    } catch (error) {
      debugPrint('Tema tercihi kaydedilemedi: $error');
    }
  }

  Future<void> _applyThemePreference({
    required String preference,
    required String resolvedTheme,
    required bool explicitChange,
  }) async {
    final String normalizedPreference = normalizeThemePreference(preference);
    final String nextPreference =
        explicitChange ? normalizedPreference : _themePreference;
    final bool nextDarkMode = resolvedTheme == 'dark';

    if (mounted &&
        (_themePreference != nextPreference || _isDarkMode != nextDarkMode)) {
      setState(() {
        _themePreference = nextPreference;
        _isDarkMode = nextDarkMode;
      });
    } else {
      _themePreference = nextPreference;
      _isDarkMode = nextDarkMode;
    }

    if (explicitChange) {
      await _persistThemePreference(
        normalizedPreference,
        explicitChange: true,
      );
    }
  }

  Future<void> _syncThemeToWebView(
    InAppWebViewController? controller,
  ) async {
    if (controller == null) {
      return;
    }

    try {
      await controller.evaluateJavascript(
        source: r'''
(function () {
  if (typeof window.__AM_APPLY_NATIVE_THEME__ === 'function') {
    window.__AM_APPLY_NATIVE_THEME__();
    return true;
  }
  return false;
})();
''',
      );
    } catch (error) {
      debugPrint('Native tema web görünümüne uygulanamadı: $error');
    }
  }

  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();

    if (_themePreference != 'system' || !mounted) {
      return;
    }

    final bool nextDarkMode =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark;

    if (_isDarkMode == nextDarkMode) {
      return;
    }

    setState(() {
      _isDarkMode = nextDarkMode;
    });

    _syncThemeToWebView(_webViewController);
  }

  static const String _openInAppProtection = r'''
(function () {
  'use strict';

  if (window.__AYDINLATMA_MEKANI_APP_PROTECTION__) {
    return;
  }

  window.__AYDINLATMA_MEKANI_APP_PROTECTION__ = true;
  window.__AYDINLATMA_MEKANI_APP__ = true;

  function setDismissCookie() {
    document.cookie =
      'durum=false; path=/; max-age=31536000; SameSite=Lax';
  }

  function installBlockingStyle() {
    if (document.getElementById('aydinlatma-app-block-style')) {
      return;
    }

    var style = document.createElement('style');
    style.id = 'aydinlatma-app-block-style';
    style.textContent =
      '#mobarka,#mobiluygdiv{' +
      'display:none!important;' +
      'visibility:hidden!important;' +
      'opacity:0!important;' +
      'pointer-events:none!important;' +
      '}';

    var target =
      document.head ||
      document.documentElement;

    if (target) {
      target.appendChild(style);
    }
  }

  function removeOpenInAppElements() {
    var backdrop = document.getElementById('mobarka');
    var popup = document.getElementById('mobiluygdiv');

    if (backdrop && backdrop.parentNode) {
      backdrop.parentNode.removeChild(backdrop);
    }

    if (popup && popup.parentNode) {
      popup.parentNode.removeChild(popup);
    }

    if (document.documentElement) {
      document.documentElement.style.removeProperty('overflow');
      document.documentElement.style.removeProperty('overflow-x');
      document.documentElement.style.removeProperty('overflow-y');
      document.documentElement.style.removeProperty('position');
      document.documentElement.style.removeProperty('height');
      document.documentElement.style.removeProperty('touch-action');
      document.documentElement.style.removeProperty('pointer-events');
      document.documentElement.style.setProperty(
        'opacity',
        '1',
        'important'
      );
      document.documentElement.style.setProperty(
        'filter',
        'none',
        'important'
      );
    }

    if (document.body) {
      document.body.style.removeProperty('overflow');
      document.body.style.removeProperty('overflow-x');
      document.body.style.removeProperty('overflow-y');
      document.body.style.removeProperty('position');
      document.body.style.removeProperty('height');
      document.body.style.removeProperty('touch-action');
      document.body.style.removeProperty('pointer-events');
      document.body.style.setProperty('opacity', '1', 'important');
      document.body.style.setProperty('filter', 'none', 'important');

      document.body.classList.remove(
        'modal-open',
        'overflow-hidden',
        'no-scroll',
        'noscroll',
        'scroll-lock',
        'locked',
        'is-locked'
      );
    }
  }

  function preparePage() {
    setDismissCookie();
    installBlockingStyle();
    removeOpenInAppElements();
    return true;
  }

  setDismissCookie();
  installBlockingStyle();

  function installObserver() {
    if (!document.documentElement) {
      window.setTimeout(installObserver, 0);
      return;
    }

    installBlockingStyle();
    removeOpenInAppElements();

    var observer = new MutationObserver(function (mutations) {
      var shouldClean = false;

      for (var i = 0; i < mutations.length; i++) {
        var mutation = mutations[i];

        for (var j = 0; j < mutation.addedNodes.length; j++) {
          var node = mutation.addedNodes[j];

          if (node.nodeType !== 1) {
            continue;
          }

          if (
            node.id === 'mobarka' ||
            node.id === 'mobiluygdiv' ||
            (
              node.querySelector &&
              (
                node.querySelector('#mobarka') ||
                node.querySelector('#mobiluygdiv')
              )
            )
          ) {
            shouldClean = true;
            break;
          }
        }

        if (shouldClean) {
          break;
        }
      }

      if (shouldClean) {
        removeOpenInAppElements();
      }
    });

    observer.observe(document.documentElement, {
      childList: true,
      subtree: true
    });

    window.__AYDINLATMA_MEKANI_APP_OBSERVER__ = observer;
    window.__AYDINLATMA_PREPARE_PAGE__ = preparePage;
  }

  installObserver();
})();
''';

  static const String _emailRememberHandler = r'''
(function () {
  'use strict';

  if (window.__AYDINLATMA_EMAIL_REMEMBER__) {
    return;
  }

  window.__AYDINLATMA_EMAIL_REMEMBER__ = true;

  var storageKey = 'aydinlatma_remembered_email';

  function normalizeText(value) {
    return String(value || '')
      .toLocaleLowerCase('tr-TR')
      .replace(/\s+/g, ' ')
      .trim();
  }

  function isEmailInput(element) {
    if (!element || element.tagName !== 'INPUT') {
      return false;
    }

    var type = String(element.type || '').toLowerCase();
    var name = String(element.name || '').toLowerCase();
    var id = String(element.id || '').toLowerCase();
    var placeholder = String(element.placeholder || '')
      .toLocaleLowerCase('tr-TR');

    return type === 'email' ||
      name.indexOf('email') !== -1 ||
      name.indexOf('mail') !== -1 ||
      id.indexOf('email') !== -1 ||
      id.indexOf('mail') !== -1 ||
      placeholder.indexOf('e-mail') !== -1 ||
      placeholder.indexOf('email') !== -1;
  }

  function findEmailInput(root) {
    var inputs = (root || document).querySelectorAll('input');

    for (var i = 0; i < inputs.length; i++) {
      if (isEmailInput(inputs[i])) {
        return inputs[i];
      }
    }

    return null;
  }

  function isRememberCheckbox(element) {
    if (!element || element.tagName !== 'INPUT') {
      return false;
    }

    if (String(element.type || '').toLowerCase() !== 'checkbox') {
      return false;
    }

    var name = String(element.name || '').toLocaleLowerCase('tr-TR');
    var id = String(element.id || '').toLocaleLowerCase('tr-TR');
    var value = String(element.value || '').toLocaleLowerCase('tr-TR');
    var labelText = '';

    if (element.labels && element.labels.length > 0) {
      for (var i = 0; i < element.labels.length; i++) {
        labelText += ' ' + String(
          element.labels[i].innerText ||
          element.labels[i].textContent ||
          ''
        );
      }
    }

    var parent = element.parentElement;

    for (var depth = 0; parent && depth < 3; depth++) {
      labelText += ' ' + String(
        parent.innerText ||
        parent.textContent ||
        ''
      );
      parent = parent.parentElement;
    }

    labelText = labelText.toLocaleLowerCase('tr-TR');

    return name.indexOf('remember') !== -1 ||
      id.indexOf('remember') !== -1 ||
      value.indexOf('remember') !== -1 ||
      labelText.indexOf('beni hatırla') !== -1 ||
      labelText.indexOf('beni hatirla') !== -1;
  }

  function findRememberCheckbox(root) {
    var checkboxes = (root || document)
      .querySelectorAll('input[type="checkbox"]');

    for (var i = 0; i < checkboxes.length; i++) {
      if (isRememberCheckbox(checkboxes[i])) {
        return checkboxes[i];
      }
    }

    return null;
  }

  function hideNode(node) {
    if (!node || !node.style) {
      return;
    }

    node.style.setProperty('display', 'none', 'important');
    node.style.setProperty('visibility', 'hidden', 'important');
    node.style.setProperty('opacity', '0', 'important');
    node.style.setProperty('pointer-events', 'none', 'important');
    node.setAttribute('aria-hidden', 'true');
  }

  function hideRememberUi() {
    var checkbox = findRememberCheckbox(document);

    if (!checkbox) {
      return;
    }

    checkbox.checked = true;
    hideNode(checkbox);

    if (checkbox.labels && checkbox.labels.length > 0) {
      for (var i = 0; i < checkbox.labels.length; i++) {
        hideNode(checkbox.labels[i]);
      }
    }

    var current = checkbox.parentElement;

    for (var depth = 0; current && depth < 4; depth++) {
      var text = normalizeText(
        current.innerText || current.textContent || ''
      );
      var interactiveCount = current.querySelectorAll(
        'input,button,a,select,textarea'
      ).length;
      var containsForgotPassword =
        text.indexOf('şifremi unuttum') !== -1 ||
        text.indexOf('sifremi unuttum') !== -1 ||
        text.indexOf('forgot password') !== -1;

      if (
        (text === 'beni hatırla' || text === 'beni hatirla' ||
         text.indexOf('beni hatırla') !== -1 ||
         text.indexOf('beni hatirla') !== -1) &&
        !containsForgotPassword &&
        interactiveCount <= 1
      ) {
        hideNode(current);
        return;
      }

      current = current.parentElement;
    }

    var searchRoot = checkbox.parentElement;

    for (var level = 0; searchRoot && level < 3; level++) {
      var candidates = searchRoot.querySelectorAll('label,span,div,p');

      for (var j = 0; j < candidates.length; j++) {
        var candidateText = normalizeText(
          candidates[j].innerText || candidates[j].textContent || ''
        );

        if (
          candidateText === 'beni hatırla' ||
          candidateText === 'beni hatirla'
        ) {
          hideNode(candidates[j]);
        }
      }

      searchRoot = searchRoot.parentElement;
    }
  }

  function findLoginEmailInput() {
    var rememberCheckbox = findRememberCheckbox(document);

    if (rememberCheckbox) {
      var scope = rememberCheckbox.parentElement;

      for (var depth = 0; scope && depth < 8; depth++) {
        var scopedEmail = findEmailInput(scope);

        if (scopedEmail) {
          return scopedEmail;
        }

        scope = scope.parentElement;
      }
    }

    return findEmailInput(document);
  }

  function setNativeValue(input, value) {
    if (!input || !value) {
      return;
    }

    var descriptor = Object.getOwnPropertyDescriptor(
      window.HTMLInputElement.prototype,
      'value'
    );

    if (descriptor && descriptor.set) {
      descriptor.set.call(input, value);
    } else {
      input.value = value;
    }

    input.dispatchEvent(
      new Event('input', { bubbles: true })
    );
    input.dispatchEvent(
      new Event('change', { bubbles: true })
    );
  }

  function fillRememberedEmail() {
    var savedEmail = '';

    try {
      savedEmail = localStorage.getItem(storageKey) || '';
    } catch (_) {
      return;
    }

    if (!savedEmail) {
      return;
    }

    var emailInput = findLoginEmailInput();

    if (
      emailInput &&
      !String(emailInput.value || '').trim()
    ) {
      setNativeValue(emailInput, savedEmail);
    }
  }

  function saveEmailAutomatically() {
    var emailInput = findLoginEmailInput();

    if (!emailInput) {
      return;
    }

    var email = String(emailInput.value || '').trim();

    if (!email) {
      return;
    }

    try {
      localStorage.setItem(storageKey, email);
    } catch (_) {
    }
  }

  document.addEventListener(
    'submit',
    function () {
      saveEmailAutomatically();
    },
    true
  );

  document.addEventListener(
    'click',
    function (event) {
      var element = event.target;

      while (
        element &&
        element !== document.documentElement
      ) {
        if (
          element.tagName === 'BUTTON' ||
          (
            element.tagName === 'INPUT' &&
            (
              String(element.type || '').toLowerCase() === 'submit' ||
              String(element.type || '').toLowerCase() === 'button'
            )
          )
        ) {
          window.setTimeout(saveEmailAutomatically, 0);
          break;
        }

        element = element.parentElement;
      }
    },
    true
  );

  function prepare() {
    hideRememberUi();
    fillRememberedEmail();
  }

  var prepareQueued = false;

  function schedulePrepare() {
    if (prepareQueued) {
      return;
    }

    prepareQueued = true;

    var run = function () {
      prepareQueued = false;
      prepare();
    };

    if (typeof window.requestAnimationFrame === 'function') {
      window.requestAnimationFrame(run);
    } else {
      window.setTimeout(run, 16);
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener(
      'DOMContentLoaded',
      prepare,
      { once: true }
    );
  } else {
    prepare();
  }

  var observer = new MutationObserver(function () {
    schedulePrepare();
  });

  function startObserver() {
    if (!document.documentElement) {
      window.setTimeout(startObserver, 0);
      return;
    }

    observer.observe(document.documentElement, {
      childList: true,
      subtree: true
    });
  }

  startObserver();
})();
''';

  static const String _googleLoginClickHandler = r'''
(function () {
  'use strict';

  if (window.__AYDINLATMA_GOOGLE_LOGIN_NOTICE__) {
    return;
  }

  window.__AYDINLATMA_GOOGLE_LOGIN_NOTICE__ = true;

  function normalize(value) {
    return String(value || '')
      .toLocaleLowerCase('tr-TR')
      .replace(/\s+/g, ' ')
      .trim();
  }

  function findClickable(start) {
    var element = start;

    while (element && element !== document.documentElement) {
      if (
        element.tagName === 'A' ||
        element.tagName === 'BUTTON' ||
        element.getAttribute('role') === 'button'
      ) {
        return element;
      }

      element = element.parentElement;
    }

    return null;
  }

  function isGoogleLoginElement(element) {
    if (!element) {
      return false;
    }

    var text = normalize(
      (element.innerText || element.textContent || '') + ' ' +
      (element.getAttribute('aria-label') || '') + ' ' +
      (element.getAttribute('title') || '')
    );

    var href = normalize(element.getAttribute('href'));
    var id = normalize(element.id);
    var className = normalize(element.className);

    var googleIdentity =
      text.indexOf('google') !== -1 ||
      href.indexOf('accounts.google.com') !== -1 ||
      href.indexOf('socialconnector.eticaret.com/google/') !== -1 ||
      href.indexOf('/google/login') !== -1 ||
      id.indexOf('google') !== -1 ||
      className.indexOf('google') !== -1;

    var loginIdentity =
      text.indexOf('bağlan') !== -1 ||
      text.indexOf('giriş') !== -1 ||
      text.indexOf('login') !== -1 ||
      text.indexOf('sign in') !== -1 ||
      href.indexOf('login') !== -1 ||
      href.indexOf('socialconnector') !== -1;

    return googleIdentity && loginIdentity;
  }

  document.addEventListener(
    'click',
    function (event) {
      var element = findClickable(event.target);

      if (!isGoogleLoginElement(element)) {
        return;
      }

      event.preventDefault();
      event.stopPropagation();
      event.stopImmediatePropagation();

      if (
        window.flutter_inappwebview &&
        window.flutter_inappwebview.callHandler
      ) {
        window.flutter_inappwebview.callHandler(
          'showGoogleLoginNotice'
        );
      }

      return false;
    },
    true
  );
})();
''';

  static const String _whatsAppShareHandler = r'''
(function () {
  'use strict';

  if (window.__AYDINLATMA_WHATSAPP_SHARE_HANDLER__) {
    return;
  }

  window.__AYDINLATMA_WHATSAPP_SHARE_HANDLER__ = true;

  function isWhatsAppShareUrl(value) {
    try {
      var url = new URL(String(value || ''), window.location.href);

      return (
        url.hostname.toLowerCase() === 'web.whatsapp.com' &&
        url.pathname.toLowerCase() === '/send'
      );
    } catch (_) {
      return false;
    }
  }

  function sendToFlutter(value) {
    if (
      window.flutter_inappwebview &&
      window.flutter_inappwebview.callHandler
    ) {
      window.flutter_inappwebview.callHandler(
        'openWhatsAppShare',
        String(value || '')
      );
    }
  }

  function findAnchor(start) {
    var element = start;

    while (element && element !== document.documentElement) {
      if (element.tagName === 'A' && element.href) {
        return element;
      }

      element = element.parentElement;
    }

    return null;
  }

  document.addEventListener(
    'click',
    function (event) {
      var anchor = findAnchor(event.target);

      if (!anchor || !isWhatsAppShareUrl(anchor.href)) {
        return;
      }

      event.preventDefault();
      event.stopPropagation();
      event.stopImmediatePropagation();

      sendToFlutter(anchor.href);
      return false;
    },
    true
  );

  var originalWindowOpen = window.open;

  window.open = function (url, target, features) {
    if (isWhatsAppShareUrl(url)) {
      sendToFlutter(url);
      return null;
    }

    return originalWindowOpen.call(
      window,
      url,
      target,
      features
    );
  };
})();
''';

  static const String _externalLinkClickHandler = r'''
(function () {
  'use strict';

  if (window.__AYDINLATMA_EXTERNAL_LINK_HANDLER__) {
    return;
  }

  window.__AYDINLATMA_EXTERNAL_LINK_HANDLER__ = true;

  function findAnchor(start) {
    var element = start;

    while (element && element !== document.documentElement) {
      if (element.tagName === 'A' && element.href) {
        return element;
      }

      element = element.parentElement;
    }

    return null;
  }

  function lower(value) {
    return String(value || '').toLowerCase();
  }

  function isFacebookLoginHref(href) {
    return (
      href.indexOf('socialconnector.eticaret.com/facebook/') !== -1 ||
      href.indexOf('facebook.com/dialog/oauth') !== -1 ||
      href.indexOf('facebook.com/login') !== -1 ||
      href.indexOf('facebook.com/checkpoint') !== -1 ||
      href.indexOf('client_id=') !== -1 ||
      href.indexOf('redirect_uri=') !== -1
    );
  }

  function isCatalogHref(href) {
    try {
      var url = new URL(href, window.location.href);
      return (
        url.protocol === 'https:' &&
        url.hostname.toLowerCase() ===
          'katalog.aydinlatmamekani.com'
      );
    } catch (_) {
      return false;
    }
  }

  function externalType(href) {
    var value = lower(href);

    if (isFacebookLoginHref(value)) {
      return '';
    }

    if (
      value.indexOf('mailto:') === 0 ||
      value.indexOf('tel:') === 0 ||
      value.indexOf('sms:') === 0 ||
      value.indexOf('whatsapp:') === 0 ||
      value.indexOf('https://wa.me/') === 0 ||
      value.indexOf('https://api.whatsapp.com/') === 0
    ) {
      return 'external';
    }

    if (
      value.indexOf('geo:') === 0 ||
      value.indexOf('intent://') === 0 ||
      value.indexOf('maps.google.') !== -1 ||
      value.indexOf('google.com/maps') !== -1 ||
      value.indexOf('google.com.tr/maps') !== -1 ||
      value.indexOf('maps.app.goo.gl') !== -1
    ) {
      return 'map';
    }

    if (
      isCatalogHref(href) ||
      value.indexOf('facebook.com') !== -1 ||
      value.indexOf('fb.com') !== -1 ||
      value.indexOf('instagram.com') !== -1 ||
      value.indexOf('youtube.com') !== -1 ||
      value.indexOf('youtu.be') !== -1 ||
      value.indexOf('pinterest.com') !== -1 ||
      value.indexOf('pin.it') !== -1
    ) {
      return 'browser';
    }

    return '';
  }

  document.addEventListener(
    'click',
    function (event) {
      var anchor = findAnchor(event.target);

      if (!anchor) {
        return;
      }

      var type = externalType(anchor.href);

      if (!type) {
        return;
      }

      event.preventDefault();
      event.stopPropagation();
      event.stopImmediatePropagation();

      if (
        window.flutter_inappwebview &&
        window.flutter_inappwebview.callHandler
      ) {
        window.flutter_inappwebview.callHandler(
          'openExternalLink',
          type,
          anchor.href
        );
      }

      return false;
    },
    true
  );
})();
''';

  Uri _normalizeExternalLink(Uri uri) {
    final String scheme = uri.scheme.toLowerCase();
    final String host = uri.host.toLowerCase();
    final String path = uri.path.toLowerCase();

    final bool googleMapsUrl = scheme == 'geo' ||
        host == 'maps.google.com' ||
        host.endsWith('.maps.google.com') ||
        ((host == 'google.com' || host.endsWith('.google.com')) &&
            path.startsWith('/maps')) ||
        host == 'maps.app.goo.gl';

    if (!googleMapsUrl) {
      return uri;
    }

    String? latitude;
    String? longitude;

    final String? queryValue = uri.queryParameters['q'];

    if (queryValue != null && queryValue.isNotEmpty) {
      final Uri? nestedUri = Uri.tryParse(queryValue);

      if (nestedUri != null) {
        final String? nestedLl = nestedUri.queryParameters['ll'];

        if (nestedLl != null && nestedLl.contains(',')) {
          final List<String> parts = nestedLl.split(',');

          if (parts.length >= 2) {
            latitude = parts[0].trim();
            longitude = parts[1].trim();
          }
        }
      }

      if (latitude == null && longitude == null && queryValue.contains(',')) {
        final List<String> parts = queryValue.split(',');

        if (parts.length >= 2) {
          latitude = parts[0].trim();
          longitude = parts[1].trim();
        }
      }
    }

    final String? directLl = uri.queryParameters['ll'];

    if ((latitude == null || longitude == null) &&
        directLl != null &&
        directLl.contains(',')) {
      final List<String> parts = directLl.split(',');

      if (parts.length >= 2) {
        latitude = parts[0].trim();
        longitude = parts[1].trim();
      }
    }

    if (latitude != null &&
        longitude != null &&
        latitude.isNotEmpty &&
        longitude.isNotEmpty) {
      return Uri.parse(
        'geo:$latitude,$longitude?q=$latitude,$longitude',
      );
    }

    return uri;
  }

  bool _isFacebookAuthUrl(Uri? uri) {
    if (uri == null) {
      return false;
    }

    final String host = uri.host.toLowerCase();
    final String path = uri.path.toLowerCase();

    final bool facebookHost = host == 'facebook.com' ||
        host.endsWith('.facebook.com') ||
        host == 'fb.com' ||
        host.endsWith('.fb.com');

    final bool socialConnector =
        host == 'socialconnector.eticaret.com' && path.contains('facebook');

    return facebookHost || socialConnector;
  }

  void _rememberSiteUrl(Uri? uri) {
    if (isMainSiteUrl(uri)) {
      _lastSiteUrl = uri!;
    }
  }

  bool _isWhatsAppUrl(Uri? uri) {
    if (uri == null) {
      return false;
    }

    final String scheme = uri.scheme.toLowerCase();
    final String host = uri.host.toLowerCase();
    final String value = uri.toString().toLowerCase();

    return scheme == 'whatsapp' ||
        host == 'web.whatsapp.com' ||
        host == 'api.whatsapp.com' ||
        host == 'wa.me' ||
        (scheme == 'intent' &&
            (value.contains('whatsapp') || value.contains('com.whatsapp')));
  }

  Uri _normalizeWhatsAppShareUrl(Uri uri) {
    if (!_isWhatsAppUrl(uri)) {
      return uri;
    }

    if (uri.scheme.toLowerCase() == 'whatsapp') {
      return uri;
    }

    final String text = uri.queryParameters['text'] ?? '';
    final String phone = uri.queryParameters['phone'] ?? '';

    final Map<String, String> queryParameters = <String, String>{};

    if (text.isNotEmpty) {
      queryParameters['text'] = text;
    }

    if (phone.isNotEmpty) {
      queryParameters['phone'] = phone;
    }

    return Uri(
      scheme: 'whatsapp',
      host: 'send',
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
  }

  Future<bool> _openExistingExternalLink(Uri uri) async {
    final Uri whatsappUri = _normalizeWhatsAppShareUrl(uri);
    final Uri normalizedUri = _normalizeExternalLink(whatsappUri);

    try {
      return await launchUrl(
        normalizedUri,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }

  Future<bool> _openInDefaultBrowser(Uri uri) async {
    try {
      final bool? opened = await _browserChannel.invokeMethod<bool>(
        'openInDefaultBrowser',
        <String, String>{
          'url': uri.toString(),
        },
      );

      return opened == true;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> _openMapNatively(Uri uri) async {
    final Uri normalizedUri = _normalizeExternalLink(uri);

    try {
      final bool? opened = await _browserChannel.invokeMethod<bool>(
        'openMap',
        <String, String>{
          'url': normalizedUri.toString(),
        },
      );

      return opened == true;
    } on PlatformException {
      return false;
    }
  }

  Uri? _parseOneSignalUrl(String? value) {
    if (value == null) {
      return null;
    }

    final String trimmed = value.trim();

    if (trimmed.isEmpty) {
      return null;
    }

    final Uri? uri = Uri.tryParse(trimmed);

    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }

    return uri;
  }

  Uri? _notificationTargetUrl(OSNotification notification) {
    final Uri? launchUrl = _parseOneSignalUrl(
      notification.launchUrl,
    );

    if (launchUrl != null) {
      return launchUrl;
    }

    final Map<String, dynamic>? additionalData = notification.additionalData;

    if (additionalData == null) {
      return null;
    }

    for (final String key in <String>[
      'webview_url',
      'url',
      'launch_url',
    ]) {
      final dynamic value = additionalData[key];
      final Uri? uri = _parseOneSignalUrl(value?.toString());

      if (uri != null) {
        return uri;
      }
    }

    return null;
  }

  Future<void> _openOneSignalUrlInsideApp(Uri uri) async {
    final InAppWebViewController? controller = _webViewController;

    if (controller == null) {
      _pendingOneSignalUrl = uri;
      return;
    }

    _pendingOneSignalUrl = null;
    if (isCatalogUrl(uri)) {
      await _openInDefaultBrowser(uri);
      return;
    }
    if (!isMainSiteUrl(uri)) {
      await _openExistingExternalLink(uri);
      return;
    }

    await controller.loadUrl(
      urlRequest: URLRequest(url: WebUri.uri(uri)),
    );
  }

  Future<void> _openPendingOneSignalUrl() async {
    final Uri? pendingUrl = _pendingOneSignalUrl;

    if (pendingUrl == null || _webViewController == null) {
      return;
    }

    await _openOneSignalUrlInsideApp(pendingUrl);
  }

  void _cancelPendingOneSignalInAppResume() {
    if (_oneSignalInAppMessagesResumed) {
      return;
    }

    _oneSignalInAppResumeGeneration++;
    _oneSignalInAppResumeTimer?.cancel();
    _oneSignalInAppResumeTimer = null;
  }

  void _scheduleOneSignalInAppResume() {
    if (_oneSignalInAppMessagesResumed ||
        !mounted ||
        _showSplash ||
        _pageLoading ||
        _errorScreen != AppErrorScreen.none) {
      return;
    }

    _oneSignalInAppResumeTimer?.cancel();
    final int generation = ++_oneSignalInAppResumeGeneration;

    _oneSignalInAppResumeTimer = Timer(
      const Duration(milliseconds: 600),
      () {
        unawaited(_resumeOneSignalInAppMessages(generation));
      },
    );
  }

  Future<void> _resumeOneSignalInAppMessages(
    int generation,
  ) async {
    final Future<void>? initialization = _oneSignalInitializationFuture;

    if (initialization != null) {
      await initialization;
    }

    if (!mounted ||
        generation != _oneSignalInAppResumeGeneration ||
        _oneSignalInAppMessagesResumed ||
        _showSplash ||
        _pageLoading ||
        _errorScreen != AppErrorScreen.none) {
      return;
    }

    try {
      await OneSignal.InAppMessages.paused(false);

      if (!mounted ||
          generation != _oneSignalInAppResumeGeneration ||
          _showSplash ||
          _pageLoading ||
          _errorScreen != AppErrorScreen.none) {
        await OneSignal.InAppMessages.paused(true);
        return;
      }

      _oneSignalInAppMessagesResumed = true;
      _oneSignalInAppResumeTimer = null;
    } catch (error) {
      debugPrint(
        'OneSignal In-App Message devam ettirilemedi: $error',
      );
    }
  }

  void _onNotificationClick(OSNotificationClickEvent event) {
    final Uri? uri = _notificationTargetUrl(event.notification);
    if (uri != null && mounted) {
      unawaited(_openOneSignalUrlInsideApp(uri));
    }
  }

  void _onInAppMessageClick(OSInAppMessageClickEvent event) {
    final Uri? uri = _parseOneSignalUrl(event.result.url) ??
        _parseOneSignalUrl(event.result.actionId);
    if (uri != null && mounted) {
      unawaited(_openOneSignalUrlInsideApp(uri));
    }
  }

  void _configureOneSignalClickHandlers() {
    OneSignal.Notifications.addClickListener(_onNotificationClick);
    OneSignal.InAppMessages.addClickListener(_onInAppMessageClick);
  }

  @override
  void initState() {
    super.initState();

    _themePreference = normalizeThemePreference(widget.initialThemePreference);
    _isDarkMode = widget.initialDarkMode;
    _splashDarkMode = widget.initialDarkMode;
    WidgetsBinding.instance.addObserver(this);
    if (kDebugMode && Platform.isIOS) {
      unawaited(_configureSimulatorTests());
    }

    _configureOneSignalClickHandlers();
    _oneSignalInitializationFuture = _initializeOneSignal();

    _pullToRefreshController = PullToRefreshController(
      settings: PullToRefreshSettings(
        enabled: true,
        color: const Color(0xFFF0932B),
        backgroundColor: Colors.transparent,
        distanceToTriggerSync: 90,
      ),
      onRefresh: () async {
        if (_errorScreen != AppErrorScreen.none || _retryInProgress) {
          await _pullToRefreshController.endRefreshing();
          return;
        }

        final InAppWebViewController? controller = _webViewController;

        if (controller == null) {
          await _pullToRefreshController.endRefreshing();
          return;
        }

        await controller.reload();
      },
    );

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
          _handleConnectivityChanged,
        );

    _checkInitialConnectivity();
  }

  Future<void> _checkInitialConnectivity() async {
    final List<ConnectivityResult> result =
        await Connectivity().checkConnectivity();

    if (!mounted) {
      return;
    }

    if (result.isEmpty ||
        result.every((item) => item == ConnectivityResult.none)) {
      _showErrorScreen(AppErrorScreen.noInternet);
    }
  }

  Future<void> _handleConnectivityChanged(
    List<ConnectivityResult> result,
  ) async {
    if (kDebugMode && _simulatorNoInternetPreview) {
      return;
    }
    if (!mounted) {
      return;
    }

    if (result.isEmpty ||
        result.every((item) => item == ConnectivityResult.none)) {
      _recoveryGeneration++;
      _showErrorScreen(AppErrorScreen.noInternet);
      return;
    }

    if (_errorScreen != AppErrorScreen.none) {
      await _attemptRecovery(automatic: true);
    }
  }

  void _showErrorScreen(AppErrorScreen errorScreen) {
    if (kDebugMode && _simulatorNoInternetPreview) {
      errorScreen = AppErrorScreen.noInternet;
    }
    _finishTimer?.cancel();

    if (!mounted) {
      return;
    }

    setState(() {
      _errorScreen = errorScreen;
      _retryInProgress = false;
      _pageLoading = false;
      _showWelcomeTooltip = false;

      if (_showSplash) {
        _showSplash = false;
      }
    });
  }

  void _clearErrorScreen() {
    if (kDebugMode && _simulatorNoInternetPreview) {
      return;
    }
    if (!mounted || _errorScreen == AppErrorScreen.none) {
      return;
    }

    setState(() {
      _errorScreen = AppErrorScreen.none;
      _retryInProgress = false;
    });
  }

  Future<bool> _isMainDocumentUrl(
    InAppWebViewController controller,
    Uri? failedUrl,
  ) async {
    if (failedUrl == null) {
      return true;
    }

    final Uri? currentUrl = await controller.getUrl();

    if (currentUrl == null) {
      return true;
    }

    return currentUrl.scheme == failedUrl.scheme &&
        currentUrl.host == failedUrl.host &&
        currentUrl.path == failedUrl.path;
  }

  Future<void> _handleWebViewError(
    InAppWebViewController controller,
    Uri? url,
  ) async {
    if (!await _isMainDocumentUrl(controller, url)) {
      return;
    }

    _currentLoadFailed = true;

    final List<ConnectivityResult> connectivity =
        await Connectivity().checkConnectivity();

    if (!mounted) {
      return;
    }

    if (connectivity.isEmpty ||
        connectivity.every((item) => item == ConnectivityResult.none)) {
      _showErrorScreen(AppErrorScreen.noInternet);
    } else {
      _showErrorScreen(AppErrorScreen.serverError);
    }
  }

  Future<AppErrorScreen> _probeSite() async {
    final List<ConnectivityResult> connectivity =
        await Connectivity().checkConnectivity();

    if (connectivity.isEmpty ||
        connectivity.every((item) => item == ConnectivityResult.none)) {
      return AppErrorScreen.noInternet;
    }

    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);

    try {
      final HttpClientRequest request =
          await client.getUrl(Uri.parse(siteUrl)).timeout(
                const Duration(seconds: 6),
              );

      request.followRedirects = true;

      final HttpClientResponse response = await request.close().timeout(
            const Duration(seconds: 6),
          );

      await response.drain<void>();

      if (response.statusCode >= 500) {
        return AppErrorScreen.serverError;
      }

      return AppErrorScreen.none;
    } on SocketException {
      return AppErrorScreen.serverError;
    } on TimeoutException {
      return AppErrorScreen.serverError;
    } on HandshakeException {
      return AppErrorScreen.serverError;
    } catch (_) {
      return AppErrorScreen.serverError;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _attemptRecovery({
    required bool automatic,
  }) async {
    if (kDebugMode && _simulatorNoInternetPreview) {
      return;
    }
    final int generation = ++_recoveryGeneration;

    if (mounted) {
      setState(() {
        _retryInProgress = true;
      });
    }

    final List<Duration> delays = automatic
        ? const <Duration>[
            Duration(milliseconds: 700),
            Duration(milliseconds: 1200),
            Duration(milliseconds: 2000),
          ]
        : const <Duration>[
            Duration.zero,
            Duration(milliseconds: 900),
          ];

    AppErrorScreen result = AppErrorScreen.serverError;

    for (final Duration delay in delays) {
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }

      if (!mounted || generation != _recoveryGeneration) {
        return;
      }

      result = await _probeSite();

      if (result == AppErrorScreen.none) {
        break;
      }

      if (result == AppErrorScreen.noInternet) {
        break;
      }
    }

    if (!mounted || generation != _recoveryGeneration) {
      return;
    }

    if (result != AppErrorScreen.none) {
      setState(() {
        _retryInProgress = false;
        _errorScreen = result;
      });
      return;
    }

    final InAppWebViewController? controller = _webViewController;

    if (controller == null) {
      setState(() {
        _retryInProgress = false;
      });
      return;
    }

    _currentLoadFailed = false;

    try {
      await controller.loadUrl(
        urlRequest: URLRequest(
          url: WebUri(siteUrl),
        ),
      );
    } catch (_) {
      if (!mounted || generation != _recoveryGeneration) {
        return;
      }

      final AppErrorScreen failure = await _probeSite();

      if (!mounted || generation != _recoveryGeneration) {
        return;
      }

      setState(() {
        _retryInProgress = false;
        _errorScreen = failure == AppErrorScreen.none
            ? AppErrorScreen.serverError
            : failure;
      });
    }
  }

  Future<void> _retryCurrentPage() async {
    if (kDebugMode && _simulatorNoInternetPreview) {
      await _endSimulatorNoInternet();
      return;
    }
    if (_retryInProgress) {
      return;
    }

    await _attemptRecovery(automatic: false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _finishTimer?.cancel();
    _pageReadyStabilityTimer?.cancel();
    _welcomeTooltipTimer?.cancel();
    _oneSignalInAppResumeTimer?.cancel();
    _connectivitySubscription?.cancel();
    OneSignal.Notifications.removeClickListener(_onNotificationClick);
    OneSignal.InAppMessages.removeClickListener(_onInAppMessageClick);
    unawaited(_stopNativeVoiceRecognition());
    super.dispose();
  }

  void _showWelcomeTooltipOnce() {
    if (_welcomeTooltipShown || !mounted) {
      return;
    }

    _welcomeTooltipShown = true;

    setState(() {
      _showWelcomeTooltip = true;
    });

    _welcomeTooltipTimer?.cancel();
    _welcomeTooltipTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) {
        return;
      }

      setState(() {
        _showWelcomeTooltip = false;
      });
    });
  }

  void _updateMonotonicProgress({
    required int rawProgress,
    required bool splash,
  }) {
    final double target = rawProgress.clamp(0, 95).toDouble() / 100.0;

    if (!mounted) {
      return;
    }

    final double current = splash ? _splashProgress : _siteProgress;

    if (target <= current) {
      return;
    }

    setState(() {
      if (splash) {
        _splashProgress = target;
      } else {
        _siteProgress = target;
      }
    });
  }

  void _scheduleFinalizeAfterStableProgress100(
    InAppWebViewController controller,
    int loadGeneration,
  ) {
    _pageReadyStabilityTimer?.cancel();
    _pageReadyStabilityTimer = Timer(
      const Duration(milliseconds: _pageReadyStabilityMs),
      () {
        _pageReadyStabilityTimer = null;

        if (!mounted ||
            loadGeneration != _pageLoadGeneration ||
            _currentLoadFailed) {
          return;
        }

        unawaited(
          _finalizePageAtWebViewProgress100(
            controller,
            loadGeneration,
          ),
        );
      },
    );
  }

  Future<void> _finalizePageAtWebViewProgress100(
    InAppWebViewController controller,
    int loadGeneration,
  ) async {
    if (!mounted ||
        loadGeneration != _pageLoadGeneration ||
        _currentLoadFailed ||
        _finalizingLoadGeneration == loadGeneration) {
      return;
    }

    _finalizingLoadGeneration = loadGeneration;

    try {
      await _pullToRefreshController.endRefreshing();

      if (!mounted ||
          loadGeneration != _pageLoadGeneration ||
          _currentLoadFailed) {
        return;
      }

      await _syncThemeToWebView(controller);

      if (!mounted ||
          loadGeneration != _pageLoadGeneration ||
          _currentLoadFailed) {
        return;
      }

      await _cleanAndRevealPage(loadGeneration);
    } finally {
      if (_finalizingLoadGeneration == loadGeneration) {
        _finalizingLoadGeneration = -1;
      }
    }
  }

  Future<void> _cleanAndRevealPage(
    int expectedLoadGeneration,
  ) async {
    final InAppWebViewController? controller = _webViewController;

    if (controller == null || expectedLoadGeneration != _pageLoadGeneration) {
      return;
    }

    await controller.evaluateJavascript(
      source: _openInAppProtection,
    );

    if (expectedLoadGeneration != _pageLoadGeneration) {
      return;
    }

    await controller.evaluateJavascript(
      source: '''
        (function () {
          if (typeof window.__AYDINLATMA_PREPARE_PAGE__ === 'function') {
            return window.__AYDINLATMA_PREPARE_PAGE__();
          }

          return true;
        })();
      ''',
    );

    if (!mounted || expectedLoadGeneration != _pageLoadGeneration) {
      return;
    }

    _clearErrorScreen();

    if (_showSplash) {
      setState(() {
        _splashProgress = 1.0;
      });

      final int elapsedMs =
          DateTime.now().difference(_splashStartedAt).inMilliseconds;
      final int remainingMs = _minimumSplashVisibleMs - elapsedMs;
      final int hideDelayMs = remainingMs > 0 ? remainingMs : 0;

      _finishTimer?.cancel();
      _finishTimer = Timer(Duration(milliseconds: hideDelayMs), () {
        if (!mounted || expectedLoadGeneration != _pageLoadGeneration) {
          return;
        }

        setState(() {
          _showSplash = false;
          _pageLoading = false;
        });

        _showWelcomeTooltipOnce();
        _scheduleOneSignalInAppResume();
      });
    } else {
      setState(() {
        _siteProgress = 1.0;
      });

      _finishTimer?.cancel();
      _finishTimer = Timer(const Duration(milliseconds: 180), () {
        if (!mounted || expectedLoadGeneration != _pageLoadGeneration) {
          return;
        }

        setState(() {
          _pageLoading = false;
          _siteProgress = 0.0;
        });

        _scheduleOneSignalInAppResume();
      });
    }
  }

  Future<void> _showGoogleLoginNotice() async {
    if (_googleLoginNoticeOpen || !mounted) {
      return;
    }

    _googleLoginNoticeOpen = true;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text(
            'Google ile Giriş',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color.fromRGBO(16, 28, 44, 1),
            ),
          ),
          content: const Text(
            'Google ile giriş özelliği mobil uygulamamızda hazırlık aşamasındadır. '
            'Şimdilik Facebook ile giriş yapabilirsiniz.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 16,
              height: 1.45,
              fontWeight: FontWeight.w600,
              color: Color.fromRGBO(100, 105, 118, 1),
            ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            SizedBox(
              width: 140,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: appPrimary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
                child: const Text(
                  'Tamam',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    _googleLoginNoticeOpen = false;
  }

  Future<bool> _handleBackButton() async {
    if (_backNavigationInProgress || (Platform.isIOS && _showSplash)) {
      return false;
    }
    _backNavigationInProgress = true;
    try {
      return await _navigateBackOrConfirmExit();
    } finally {
      _backNavigationInProgress = false;
    }
  }

  Future<bool> _navigateBackOrConfirmExit() async {
    final InAppWebViewController? controller = _webViewController;

    if (controller != null) {
      final Uri? currentUrl = await controller.getUrl();

      if (_isFacebookAuthUrl(currentUrl)) {
        await controller.loadUrl(
          urlRequest: URLRequest(url: WebUri.uri(_lastSiteUrl)),
        );
        return false;
      }

      if (await controller.canGoBack()) {
        await controller.goBack();
        return false;
      }
    }

    if (!mounted) {
      return false;
    }

    // iOS users leave with the system Home gesture, without app confirmation.
    if (Platform.isIOS) {
      return false;
    }

    await _syncThemeToWebView(controller);

    if (!mounted) {
      return false;
    }

    final bool? shouldExit = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return ExitDialog(
          isDarkMode: _isDarkMode,
        );
      },
    );

    if (shouldExit == true && Platform.isAndroid) {
      SystemNavigator.pop();
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final double fixedPrimaryAreaHeight =
        MediaQuery.of(context).padding.top + 4;
    final Color nativeBackground =
        _isDarkMode ? appDarkBackground : Colors.white;
    final Color nativeStatusBarColor =
        _isDarkMode ? const Color(0xFF0E1217) : appPrimary;
    final Color splashBackground =
        _splashDarkMode ? appDarkBackground : Colors.white;
    final Color splashLoadingTrack =
        _splashDarkMode ? appDarkSurface : loadingTrack;
    final String splashImagePath = _splashDarkMode
        ? 'assets/images/splash_logo_dark.webp'
        : 'assets/images/splash_logo_light.webp';

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: nativeStatusBarColor,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor:
            _isDarkMode ? const Color(0xFF0E1217) : Colors.white,
        systemNavigationBarIconBrightness:
            _isDarkMode ? Brightness.light : Brightness.dark,
      ),
      child: PopScope<Object?>(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) {
            unawaited(_handleBackButton());
          }
        },
        child: Scaffold(
          backgroundColor: nativeBackground,
          body: SafeArea(
            top: false,
            bottom: Platform.isIOS,
            child: Column(
              children: [
                Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Column(
                      children: [
                        SizedBox(
                          height: fixedPrimaryAreaHeight,
                          width: double.infinity,
                          child: ColoredBox(
                            color: nativeStatusBarColor,
                          ),
                        ),
                        Expanded(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              IgnorePointer(
                                ignoring: _errorScreen != AppErrorScreen.none,
                                child: Opacity(
                                  opacity: _errorScreen == AppErrorScreen.none
                                      ? 1.0
                                      : 0.0,
                                  child: InAppWebView(
                                    pullToRefreshController:
                                        _pullToRefreshController,
                                    initialUrlRequest: URLRequest(
                                      url: WebUri(siteUrl),
                                    ),
                                    initialSettings: _webViewSettings,
                                    initialUserScripts:
                                        UnmodifiableListView<UserScript>([
                                      if (Platform.isIOS)
                                        UserScript(
                                          source: _smartSearchPopupIOSCookieBridge,
                                          injectionTime: UserScriptInjectionTime
                                              .AT_DOCUMENT_START,
                                        ),
                                      if (Platform.isIOS)
                                        UserScript(
                                          source: _smartSearchPopupIOSScrollbarBridge,
                                          injectionTime: UserScriptInjectionTime
                                              .AT_DOCUMENT_START,
                                        ),
                                      if (Platform.isIOS)
                                        UserScript(
                                          source: _smartSearchPopupIOSLayoutBridge,
                                          injectionTime: UserScriptInjectionTime
                                              .AT_DOCUMENT_START,
                                        ),
                                      UserScript(
                                        source: _nativeThemeBridge,
                                        injectionTime: UserScriptInjectionTime
                                            .AT_DOCUMENT_START,
                                      ),
                                      UserScript(
                                        source: _nativeVoiceRecognitionBridge,
                                        injectionTime: UserScriptInjectionTime
                                            .AT_DOCUMENT_START,
                                      ),
                                      UserScript(
                                        source: _webPushSuppressionBridge,
                                        injectionTime: UserScriptInjectionTime
                                            .AT_DOCUMENT_START,
                                      ),
                                      UserScript(
                                        source: _openInAppProtection,
                                        injectionTime: UserScriptInjectionTime
                                            .AT_DOCUMENT_START,
                                      ),
                                      UserScript(
                                        source: _whatsAppShareHandler,
                                        injectionTime: UserScriptInjectionTime
                                            .AT_DOCUMENT_START,
                                      ),
                                      UserScript(
                                        source: _externalLinkClickHandler,
                                        injectionTime: UserScriptInjectionTime
                                            .AT_DOCUMENT_START,
                                      ),
                                      UserScript(
                                        source: _googleLoginClickHandler,
                                        injectionTime: UserScriptInjectionTime
                                            .AT_DOCUMENT_START,
                                      ),
                                      UserScript(
                                        source: _emailRememberHandler,
                                        injectionTime: UserScriptInjectionTime
                                            .AT_DOCUMENT_START,
                                      ),
                                    ]),
                                    onWebViewCreated: (controller) {
                                      _webViewController = controller;
                                      _openPendingOneSignalUrl();
    
                                      controller.addJavaScriptHandler(
                                        handlerName: 'nativeThemeChanged',
                                        callback: (List<dynamic> arguments) async {
                                          if (!isMainSiteUrl(
                                              await controller.getUrl())) {
                                            return null;
                                          }
                                          final String preference =
                                              arguments.isNotEmpty
                                                  ? arguments[0].toString()
                                                  : 'system';
                                          final String resolvedTheme =
                                              arguments.length > 1
                                                  ? arguments[1].toString()
                                                  : 'light';
                                          final bool explicitChange =
                                              arguments.length > 2 &&
                                                  arguments[2] == true;
    
                                          await _applyThemePreference(
                                            preference: preference,
                                            resolvedTheme: resolvedTheme,
                                            explicitChange: explicitChange,
                                          );
                                          return true;
                                        },
                                      );
    
                                      controller.addJavaScriptHandler(
                                        handlerName: 'openWhatsAppShare',
                                        callback: (List<dynamic> arguments) async {
                                          if (arguments.isEmpty) {
                                            return false;
                                          }
    
                                          final Uri? uri = Uri.tryParse(
                                            arguments.first.toString(),
                                          );
    
                                          if (uri == null) {
                                            return false;
                                          }
    
                                          return _openExistingExternalLink(uri);
                                        },
                                      );
    
                                      controller.addJavaScriptHandler(
                                        handlerName: 'showGoogleLoginNotice',
                                        callback: (List<dynamic> arguments) {
                                          _showGoogleLoginNotice();
                                          return null;
                                        },
                                      );
    
                                      controller.addJavaScriptHandler(
                                        handlerName: 'nativeVoiceSearch',
                                        callback: (List<dynamic> arguments) async {
                                          if (!isMainSiteUrl(
                                              await controller.getUrl())) {
                                            return null;
                                          }
                                          final String language =
                                              arguments.isNotEmpty
                                                  ? arguments.first.toString()
                                                  : 'tr-TR';
                                          return _startNativeVoiceRecognition(
                                              language);
                                        },
                                      );
    
                                      controller.addJavaScriptHandler(
                                        handlerName: 'nativeVoiceSearchStop',
                                        callback: (List<dynamic> arguments) async {
                                          if (!isMainSiteUrl(
                                              await controller.getUrl())) {
                                            return null;
                                          }
                                          await _stopNativeVoiceRecognition();
                                          return true;
                                        },
                                      );
    
                                      controller.addJavaScriptHandler(
                                        handlerName: 'openExternalLink',
                                        callback: (List<dynamic> arguments) async {
                                          if (arguments.length < 2) {
                                            return false;
                                          }
    
                                          final String type =
                                              arguments[0].toString();
                                          final Uri? uri = Uri.tryParse(
                                            arguments[1].toString(),
                                          );
    
                                          if (uri == null) {
                                            return false;
                                          }
    
                                          if (type == 'map') {
                                            return _openMapNatively(uri);
                                          }
    
                                          if (type == 'external') {
                                            return _openExistingExternalLink(uri);
                                          }
    
                                          if (type == 'browser') {
                                            return _openInDefaultBrowser(uri);
                                          }
    
                                          return false;
                                        },
                                      );
                                    },
                                    onPermissionRequest:
                                        (controller, request) async {
                                      if (!isMainSiteUrl(request.origin)) {
                                        return PermissionResponse(
                                          resources: [],
                                          action: PermissionResponseAction.DENY,
                                        );
                                      }
                                      final audio = request.resources
                                          .where((resource) =>
                                              resource ==
                                              PermissionResourceType.MICROPHONE)
                                          .toList();
                                      final granted = audio.isNotEmpty &&
                                          await _requestMicrophonePermission();
                                      return PermissionResponse(
                                        resources: granted ? audio : [],
                                        action: granted
                                            ? PermissionResponseAction.GRANT
                                            : PermissionResponseAction.DENY,
                                      );
                                    },
                                    onCreateWindow: (controller, action) async {
                                      final uri = action.request.url;
                                      if (uri == null ||
                                          uri.toString() == 'about:blank') {
                                        return false;
                                      }
                                      if (_isFacebookAuthUrl(uri) ||
                                          isMainSiteUrl(uri)) {
                                        _rememberSiteUrl(await controller.getUrl());
                                        await controller.loadUrl(
                                            urlRequest: URLRequest(url: uri));
                                      } else if (isCatalogUrl(uri)) {
                                        await _openInDefaultBrowser(uri);
                                      } else {
                                        await _openExistingExternalLink(uri);
                                      }
                                      return false;
                                    },
                                    shouldOverrideUrlLoading: (
                                      controller,
                                      navigationAction,
                                    ) async {
                                      final Uri? uri = navigationAction.request.url;
    
                                      if (_isFacebookAuthUrl(uri)) {
                                        final Uri? currentUrl =
                                            await controller.getUrl();
                                        _rememberSiteUrl(currentUrl);
                                        return NavigationActionPolicy.ALLOW;
                                      }
    
                                      _rememberSiteUrl(uri);
    
                                      if (_isWhatsAppUrl(uri)) {
                                        await _openExistingExternalLink(uri!);
                                        return NavigationActionPolicy.CANCEL;
                                      }
    
                                      if (isCatalogUrl(uri)) {
                                        await _openInDefaultBrowser(uri!);
                                        return NavigationActionPolicy.CANCEL;
                                      }
    
                                      return NavigationActionPolicy.ALLOW;
                                    },
                                    onLoadStart: (controller, url) {
                                      _rememberSiteUrl(url);
    
                                      if (_showSplash && isMainSiteUrl(url)) {
                                        _initialRealPageLoadStarted = true;
                                      }
    
                                      _pageLoadGeneration++;
                                      _finishTimer?.cancel();
                                      _pageReadyStabilityTimer?.cancel();
                                      _cancelPendingOneSignalInAppResume();
    
                                      if (_errorScreen == AppErrorScreen.none) {
                                        _currentLoadFailed = false;
                                      }
    
                                      if (!mounted) {
                                        return;
                                      }
    
                                      setState(() {
                                        _pageLoading = true;
    
                                        if (!_showSplash) {
                                          _siteProgress = 0.0;
                                        }
                                      });
                                    },
                                    onProgressChanged: (controller, progress) {
                                      final int loadGeneration =
                                          _pageLoadGeneration;
    
                                      // flutter_inappwebview ilk acilista once about:blank
                                      // bootstrap dokumanini tamamlayip %100 bildirebilir.
                                      // Gercek site onLoadStart almadan bu sahte %100'u
                                      // splash bitisi olarak kabul etmiyoruz.
                                      final bool waitingForInitialRealPage =
                                          _showSplash &&
                                              !_initialRealPageLoadStarted;
                                      final int effectiveProgress =
                                          waitingForInitialRealPage
                                              ? progress.clamp(0, 10).toInt()
                                              : progress;
    
                                      _updateMonotonicProgress(
                                        rawProgress: effectiveProgress,
                                        splash: _showSplash,
                                      );
    
                                      if (progress >= 100 &&
                                          !waitingForInitialRealPage) {
                                        _scheduleFinalizeAfterStableProgress100(
                                          controller,
                                          loadGeneration,
                                        );
                                      }
                                    },
                                    onLoadStop: (controller, url) async {
                                      _rememberSiteUrl(url);
                                      await _pullToRefreshController
                                          .endRefreshing();
                                    },
                                    onReceivedError:
                                        (controller, request, error) async {
                                      if (request.isForMainFrame == false ||
                                          error.type ==
                                              WebResourceErrorType.CANCELLED) {
                                        return;
                                      }
                                      final url = request.url;
                                      await _pullToRefreshController
                                          .endRefreshing();
    
                                      if (_isWhatsAppUrl(url)) {
                                        _currentLoadFailed = false;
    
                                        if (mounted) {
                                          setState(() {
                                            _pageLoading = false;
                                            _siteProgress = 0.0;
                                          });
                                        }
    
                                        return;
                                      }
    
                                      await _handleWebViewError(
                                        controller,
                                        url,
                                      );
                                    },
                                    onReceivedHttpError:
                                        (controller, request, response) async {
                                      if (request.isForMainFrame == false) {
                                        return;
                                      }
                                      final url = request.url;
                                      final statusCode = response.statusCode ?? 0;
                                      await _pullToRefreshController
                                          .endRefreshing();
    
                                      if (_isWhatsAppUrl(url)) {
                                        _currentLoadFailed = false;
    
                                        if (mounted) {
                                          setState(() {
                                            _pageLoading = false;
                                            _siteProgress = 0.0;
                                          });
                                        }
    
                                        return;
                                      }
    
                                      if (statusCode >= 500) {
                                        await _handleWebViewError(
                                          controller,
                                          url,
                                        );
                                      }
                                    },
                                  ),
                                ),
                              ),
                              if (!_showSplash &&
                                  _pageLoading &&
                                  _errorScreen == AppErrorScreen.none)
                                Positioned(
                                  top: 0,
                                  left: 0,
                                  right: 0,
                                  height: 4,
                                  child: IgnorePointer(
                                    child: LinearProgressIndicator(
                                      value: _siteProgress,
                                      backgroundColor: loadingTrack,
                                      valueColor:
                                          const AlwaysStoppedAnimation<Color>(
                                        loadingOrange,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_errorScreen != AppErrorScreen.none)
                      Positioned.fill(
                        child: AppConnectionErrorScreen(
                          type: _errorScreen,
                          retryInProgress: _retryInProgress,
                          onRetry: _retryCurrentPage,
                          isDarkMode: _isDarkMode,
                        ),
                      ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 142,
                      child: IgnorePointer(
                        child: Center(
                          child: AnimatedOpacity(
                            opacity: _showWelcomeTooltip &&
                                    _errorScreen == AppErrorScreen.none
                                ? 1.0
                                : 0.0,
                            duration: const Duration(milliseconds: 350),
                            curve: Curves.easeInOut,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 22,
                                vertical: 11,
                              ),
                              decoration: BoxDecoration(
                                color: const Color.fromRGBO(13, 13, 13, 1),
                                borderRadius: BorderRadius.circular(999),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.28),
                                    blurRadius: 20,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: const Text(
                                'Hoş geldiniz. 🤗',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'Nunito',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                  letterSpacing: 1.0,
                                  height: 1.15,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_showSplash)
                      Positioned.fill(
                        child: Container(
                          color: splashBackground,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              _CroppedSplashLogo(assetPath: splashImagePath),
                              Align(
                                alignment: Alignment.bottomCenter,
                                child: SizedBox(
                                  height: 4,
                                  child: LinearProgressIndicator(
                                    value: _splashProgress,
                                    backgroundColor: splashLoadingTrack,
                                    valueColor: const AlwaysStoppedAnimation<Color>(
                                      loadingOrange,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                ),
                if (kDebugMode &&
                    Platform.isIOS &&
                    _simulatorTestsAvailable &&
                    !_showSplash)
                  Material(
                    color: nativeBackground,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: _isDarkMode
                                ? appDarkBorder
                                : const Color(0xFFE5E7EB),
                          ),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _simulatorNoInternetPreview
                                ? () => unawaited(_endSimulatorNoInternet())
                                : _showSimulatorNoInternet,
                            style: TextButton.styleFrom(
                              foregroundColor: appPrimary,
                              minimumSize: const Size(0, 40),
                            ),
                            icon: const Icon(Icons.science_outlined, size: 18),
                            label: Text(_simulatorNoInternetPreview
                                ? 'Testi bitir'
                                : 'No-internet testi'),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Cropped assets are sized independently of the screen's height. Short
// viewports can scroll instead of shrinking a complete portrait composition.
class _CroppedSplashLogo extends StatelessWidget {
  const _CroppedSplashLogo({super.key, required this.assetPath});

  final String assetPath;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double availableWidth =
              (constraints.maxWidth - 48).clamp(0.0, 420.0).toDouble();
          final double availableHeight =
              (constraints.maxHeight - 48).clamp(0.0, double.infinity).toDouble();
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: availableHeight),
              child: Center(
                child: Image.asset(
                  assetPath,
                  width: availableWidth,
                  height: 168,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  semanticLabel: 'Uygulama logosu',
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CroppedErrorArtwork extends StatelessWidget {
  const _CroppedErrorArtwork({
    super.key,
    required this.logoPath,
    required this.illustrationPath,
    required this.illustrationLabel,
    required this.retryButton,
  });

  final String logoPath;
  final String illustrationPath;
  final String illustrationLabel;
  final Widget retryButton;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool horizontalLayout = constraints.maxWidth >= 600 &&
            constraints.maxWidth > constraints.maxHeight;
        final double verticalPadding = horizontalLayout ? 16.0 : 24.0;
        final double contentWidth =
            (constraints.maxWidth - 48).clamp(0.0, 760.0).toDouble();
        final double contentHeight = (constraints.maxHeight -
                verticalPadding * 2)
            .clamp(0.0, double.infinity)
            .toDouble();
        final double logoSize =
            contentWidth.clamp(0.0, horizontalLayout ? 144.0 : 168.0).toDouble();
        final double illustrationWidth =
            contentWidth.clamp(0.0, 240.0).toDouble();
        final Widget logo = Image.asset(
          logoPath,
          width: logoSize,
          height: logoSize,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          semanticLabel: 'Uygulama logosu',
        );
        final Widget illustration = Image.asset(
          illustrationPath,
          width: illustrationWidth,
          height: horizontalLayout ? 164 : 240,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          semanticLabel: illustrationLabel,
        );
        // Keep the logo above the illustration in every orientation.
        final Widget content = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            logo,
            SizedBox(height: horizontalLayout ? 12 : 28),
            illustration,
            SizedBox(height: horizontalLayout ? 14 : 24),
            retryButton,
          ],
        );
        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: 24,
            vertical: verticalPadding,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: contentHeight),
            child: Center(
              child: SizedBox(width: contentWidth, child: content),
            ),
          ),
        );
      },
    );
  }
}

class AppConnectionErrorScreen extends StatelessWidget {
  const AppConnectionErrorScreen({
    super.key,
    required this.type,
    required this.retryInProgress,
    required this.onRetry,
    required this.isDarkMode,
  });

  final AppErrorScreen type;
  final bool retryInProgress;
  final Future<void> Function() onRetry;
  final bool isDarkMode;

  @override
  Widget build(BuildContext context) {
    final String logoPath = isDarkMode
        ? 'assets/images/error_logo_dark.webp'
        : 'assets/images/error_logo_light.webp';
    final String imagePath = type == AppErrorScreen.noInternet
        ? (isDarkMode
            ? 'assets/images/no_internet_dark.webp'
            : 'assets/images/no_internet_light.webp')
        : (isDarkMode
            ? 'assets/images/server_error_dark.webp'
            : 'assets/images/server_error_light.webp');
    final Color backgroundColor =
        isDarkMode ? appDarkBackground : Colors.white;

    return Material(
      color: backgroundColor,
      child: SafeArea(
        top: false,
        child: _CroppedErrorArtwork(
          logoPath: logoPath,
          illustrationPath: imagePath,
          illustrationLabel: type == AppErrorScreen.noInternet
              ? 'İnternet Bağlantısı Bulunamadı!'
              : 'Sunucuya ulaşılamadı',
          retryButton: SizedBox(
            width: 190,
            height: 52,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: appPrimary,
                side: const BorderSide(color: appPrimary, width: 2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              onPressed: retryInProgress ? null : () { onRetry(); },
              child: Text(
                retryInProgress ? 'Kontrol Ediliyor...' : 'Tekrar Dene',
                style: const TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: appPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ExitDialog extends StatelessWidget {
  const ExitDialog({
    super.key,
    required this.isDarkMode,
  });

  final bool isDarkMode;

  @override
  Widget build(BuildContext context) {
    final Color modalBackground = isDarkMode ? appDarkCard : Colors.white;
    final Color titleColor =
        isDarkMode ? appDarkTextPrimary : const Color.fromRGBO(16, 28, 44, 1);
    final Color descriptionColor = isDarkMode
        ? appDarkTextPrimary
        : const Color.fromRGBO(100, 105, 118, 1);
    final Color ringColor =
        isDarkMode ? appDarkBorder : const Color.fromRGBO(221, 242, 252, 1);
    final Color dividerColor = isDarkMode
        ? const Color(0xFF2A3440)
        : const Color.fromRGBO(229, 231, 235, 1);
    final Color cancelBackground =
        isDarkMode ? appDarkSurface : const Color.fromRGBO(247, 247, 247, 1);
    final Color cancelForeground = isDarkMode
        ? appDarkTextPrimary
        : const Color.fromRGBO(100, 105, 118, 1);
    final Color exitForeground = isDarkMode ? appDarkTextPrimary : Colors.white;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 58),
            padding: const EdgeInsets.fromLTRB(26, 88, 26, 28),
            decoration: BoxDecoration(
              color: modalBackground,
              borderRadius: BorderRadius.circular(34),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: isDarkMode ? 0.34 : 0.18,
                  ),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: modalBackground,
                        border: Border.all(
                          color: ringColor,
                          width: 4,
                        ),
                      ),
                      child: const Icon(
                        Icons.logout_rounded,
                        color: appPrimary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Uygulamayı kapatmak üzeresiniz.',
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 28,
                            height: 1.45,
                            fontWeight: FontWeight.w700,
                            color: titleColor,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  width: 92,
                  height: 7,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: const LinearGradient(
                      colors: [
                        Color.fromRGBO(126, 221, 241, 1),
                        appPrimary,
                        Color.fromRGBO(2, 139, 216, 1),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                Text(
                  'Uygulamadan çıkmak istediğinize emin misiniz?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 21,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                    color: descriptionColor,
                  ),
                ),
                const SizedBox(height: 32),
                Container(
                  height: 1,
                  color: dividerColor,
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 66,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: cancelBackground,
                            foregroundColor: cancelForeground,
                            elevation: isDarkMode ? 0 : 2,
                            shadowColor: Colors.black.withValues(alpha: 0.12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () => Navigator.of(context).pop(false),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.close_rounded,
                                size: 24,
                                color: cancelForeground,
                              ),
                              const SizedBox(width: 7),
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    'Vazgeç',
                                    maxLines: 1,
                                    style: TextStyle(
                                      fontFamily: 'Nunito',
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      color: cancelForeground,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: SizedBox(
                        height: 66,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: appPrimary,
                            foregroundColor: exitForeground,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () => Navigator.of(context).pop(true),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.logout_rounded,
                                size: 24,
                                color: exitForeground,
                              ),
                              const SizedBox(width: 7),
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    'Çık',
                                    maxLines: 1,
                                    style: TextStyle(
                                      fontFamily: 'Nunito',
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      color: exitForeground,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            width: 116,
            height: 116,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: modalBackground,
              border: Border.all(
                color: ringColor,
                width: 12,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: isDarkMode ? 0.26 : 0.10,
                  ),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Image.asset(
                isDarkMode
                    ? 'assets/images/exit_modal_logo_dark.png'
                    : 'assets/images/exit_modal_logo.png',
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                gaplessPlayback: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
