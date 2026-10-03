package com.lightstore.aydinlatmamekani

import android.Manifest
import android.app.UiModeManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.res.Configuration
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val BROWSER_CHANNEL =
            "com.lightstore.aydinlatmamekani/browser"
        private const val MICROPHONE_PERMISSION_REQUEST_CODE = 4107
        private const val THEME_PREFERENCES_NAME =
            "aydinlatmamekani_app_preferences"
        private const val THEME_PREFERENCE_KEY = "theme_preference"
        private const val THEME_PREFERENCE_EXPLICIT_KEY =
            "theme_preference_explicit_v2"
    }

    private var speechRecognizer: SpeechRecognizer? = null
    private var pendingSpeechResult: MethodChannel.Result? = null
    private var pendingSpeechLanguage: String = "tr-TR"
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        applyStoredApplicationNightMode()
        super.onCreate(savedInstanceState)
    }

    override fun getInitialRoute(): String? {
        val preference = getThemePreference()
        val resolved = when (preference) {
            "dark" -> "dark"
            "light" -> "light"
            else -> if (isSystemDarkMode()) "dark" else "light"
        }

        return "/am-startup?preference=$preference&theme=$resolved"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BROWSER_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openInDefaultBrowser" -> {
                    val url = call.argument<String>("url")

                    if (url.isNullOrBlank()) {
                        result.error(
                            "INVALID_URL",
                            "Tarayıcıda açılacak URL boş.",
                            null
                        )
                        return@setMethodCallHandler
                    }

                    try {
                        result.success(openInDefaultBrowser(url))
                    } catch (error: Exception) {
                        result.error(
                            "BROWSER_OPEN_FAILED",
                            error.message,
                            null
                        )
                    }
                }

                "openMap" -> {
                    val url = call.argument<String>("url")

                    if (url.isNullOrBlank()) {
                        result.error(
                            "INVALID_MAP_URL",
                            "Haritada açılacak URL boş.",
                            null
                        )
                        return@setMethodCallHandler
                    }

                    try {
                        result.success(openMap(url))
                    } catch (error: Exception) {
                        result.error(
                            "MAP_OPEN_FAILED",
                            error.message,
                            null
                        )
                    }
                }

                "requestMicrophonePermission" -> {
                    requestMicrophonePermission(result)
                }

                "startVoiceRecognition" -> {
                    val language = call.argument<String>("language")
                        ?.takeIf { it.isNotBlank() }
                        ?: "tr-TR"
                    startVoiceRecognition(language, result)
                }

                "stopVoiceRecognition" -> {
                    stopVoiceRecognition()
                    result.success(true)
                }

                "getThemePreference" -> {
                    result.success(getThemePreference())
                }

                "getSystemDarkMode" -> {
                    result.success(isSystemDarkMode())
                }

                "getStartupTheme" -> {
                    result.success(resolveStartupTheme())
                }

                "getStartupThemeState" -> {
                    val preference = getThemePreference()
                    val resolved = when (preference) {
                        "dark" -> "dark"
                        "light" -> "light"
                        else -> if (isSystemDarkMode()) "dark" else "light"
                    }

                    result.success(
                        mapOf(
                            "preference" to preference,
                            "resolved" to resolved
                        )
                    )
                }

                "setThemePreference" -> {
                    val preference = call.argument<String>("preference")
                        ?: "system"
                    val explicit = call.argument<Boolean>("explicit")
                        ?: false
                    saveThemePreference(preference, explicit)
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun applyStoredApplicationNightMode() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return
        }

        when (getThemePreference()) {
            "dark" -> setApplicationNightMode(
                UiModeManager.MODE_NIGHT_YES
            )
            "light" -> setApplicationNightMode(
                UiModeManager.MODE_NIGHT_NO
            )
        }
    }

    private fun setApplicationNightMode(mode: Int) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return
        }

        val uiModeManager =
            getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
        uiModeManager?.setApplicationNightMode(mode)
    }

    private fun normalizeThemePreference(value: String?): String {
        return when (value) {
            "light", "dark", "system" -> value
            else -> "system"
        }
    }

    private fun getThemePreference(): String {
        val preferences = getSharedPreferences(
            THEME_PREFERENCES_NAME,
            Context.MODE_PRIVATE
        )

        val hasExplicitPreference = preferences.getBoolean(
            THEME_PREFERENCE_EXPLICIT_KEY,
            false
        )

        if (!hasExplicitPreference) {
            preferences.edit()
                .remove(THEME_PREFERENCE_KEY)
                .apply()
            return "system"
        }

        return normalizeThemePreference(
            preferences.getString(THEME_PREFERENCE_KEY, "system")
        )
    }

    private fun saveThemePreference(
        value: String,
        explicit: Boolean
    ) {
        if (!explicit) {
            return
        }

        val preference = normalizeThemePreference(value)
        val preferences = getSharedPreferences(
            THEME_PREFERENCES_NAME,
            Context.MODE_PRIVATE
        )

        if (preference == "system") {
            preferences.edit()
                .remove(THEME_PREFERENCE_KEY)
                .putBoolean(THEME_PREFERENCE_EXPLICIT_KEY, false)
                .apply()
        } else {
            preferences.edit()
                .putString(THEME_PREFERENCE_KEY, preference)
                .putBoolean(THEME_PREFERENCE_EXPLICIT_KEY, true)
                .apply()

            setApplicationNightMode(
                if (preference == "dark") {
                    UiModeManager.MODE_NIGHT_YES
                } else {
                    UiModeManager.MODE_NIGHT_NO
                }
            )
        }
    }

    private fun resolveStartupTheme(): String {
        return when (getThemePreference()) {
            "dark" -> "dark"
            "light" -> "light"
            else -> if (isSystemDarkMode()) "dark" else "light"
        }
    }

    private fun isSystemDarkMode(): Boolean {
        val uiModeManager =
            getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager

        if (uiModeManager != null) {
            when (uiModeManager.nightMode) {
                UiModeManager.MODE_NIGHT_YES -> return true
                UiModeManager.MODE_NIGHT_NO -> return false
            }
        }

        val applicationNightMode =
            applicationContext.resources.configuration.uiMode and
                Configuration.UI_MODE_NIGHT_MASK

        if (applicationNightMode == Configuration.UI_MODE_NIGHT_YES) {
            return true
        }

        if (applicationNightMode == Configuration.UI_MODE_NIGHT_NO) {
            return false
        }

        val activityNightMode = resources.configuration.uiMode and
            Configuration.UI_MODE_NIGHT_MASK
        return activityNightMode == Configuration.UI_MODE_NIGHT_YES
    }

    private fun hasMicrophonePermission(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun requestMicrophonePermission(result: MethodChannel.Result) {
        if (hasMicrophonePermission()) {
            result.success(true)
            return
        }

        if (pendingPermissionResult != null || pendingSpeechResult != null) {
            result.success(false)
            return
        }

        pendingPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.RECORD_AUDIO),
            MICROPHONE_PERMISSION_REQUEST_CODE
        )
    }

    private fun startVoiceRecognition(
        language: String,
        result: MethodChannel.Result
    ) {
        if (pendingSpeechResult != null) {
            result.error(
                "VOICE_RECOGNITION_BUSY",
                "Sesli arama zaten çalışıyor.",
                null
            )
            return
        }

        pendingSpeechResult = result
        pendingSpeechLanguage = language

        if (!hasMicrophonePermission()) {
            requestPermissions(
                arrayOf(Manifest.permission.RECORD_AUDIO),
                MICROPHONE_PERMISSION_REQUEST_CODE
            )
            return
        }

        beginVoiceRecognition()
    }

    private fun beginVoiceRecognition() {
        val result = pendingSpeechResult ?: return

        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            pendingSpeechResult = null
            result.success(null)
            return
        }

        speechRecognizer?.destroy()
        speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this)

        speechRecognizer?.setRecognitionListener(
            object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) {}

                override fun onBeginningOfSpeech() {}

                override fun onRmsChanged(rmsdB: Float) {}

                override fun onBufferReceived(buffer: ByteArray?) {}

                override fun onEndOfSpeech() {}

                override fun onError(error: Int) {
                    finishVoiceRecognition(null)
                }

                override fun onResults(results: Bundle?) {
                    val matches = results?.getStringArrayList(
                        SpeechRecognizer.RESULTS_RECOGNITION
                    )
                    finishVoiceRecognition(matches?.firstOrNull())
                }

                override fun onPartialResults(partialResults: Bundle?) {}

                override fun onEvent(eventType: Int, params: Bundle?) {}
            }
        )

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
            )
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, pendingSpeechLanguage)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, pendingSpeechLanguage)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        }

        try {
            speechRecognizer?.startListening(intent)
        } catch (_: Exception) {
            finishVoiceRecognition(null)
        }
    }

    private fun stopVoiceRecognition() {
        speechRecognizer?.cancel()
        finishVoiceRecognition(null)
    }

    private fun finishVoiceRecognition(transcript: String?) {
        val result = pendingSpeechResult
        pendingSpeechResult = null

        speechRecognizer?.destroy()
        speechRecognizer = null

        result?.success(transcript)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(
            requestCode,
            permissions,
            grantResults
        )

        if (requestCode != MICROPHONE_PERMISSION_REQUEST_CODE) {
            return
        }

        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED

        val permissionResult = pendingPermissionResult
        pendingPermissionResult = null
        permissionResult?.success(granted)

        if (pendingSpeechResult != null) {
            if (granted) {
                beginVoiceRecognition()
            } else {
                finishVoiceRecognition(null)
            }
        }
    }

    override fun onDestroy() {
        speechRecognizer?.destroy()
        speechRecognizer = null
        pendingSpeechResult = null
        pendingPermissionResult = null
        super.onDestroy()
    }

    private fun openMap(url: String): Boolean {
        if (url.startsWith("intent://")) {
            return openIntentMapUrl(url)
        }

        val targetUri = Uri.parse(url)

        val mapIntent = Intent(
            Intent.ACTION_VIEW,
            targetUri
        ).apply {
            addCategory(Intent.CATEGORY_BROWSABLE)
        }

        return try {
            startActivity(mapIntent)
            true
        } catch (firstError: ActivityNotFoundException) {
            val fallbackUrl = buildMapFallbackUrl(targetUri)

            try {
                startActivity(
                    Intent(
                        Intent.ACTION_VIEW,
                        Uri.parse(fallbackUrl)
                    ).apply {
                        addCategory(Intent.CATEGORY_BROWSABLE)
                    }
                )
                true
            } catch (secondError: ActivityNotFoundException) {
                false
            }
        }
    }

    private fun openIntentMapUrl(url: String): Boolean {
        return try {
            val parsedIntent = Intent.parseUri(
                url,
                Intent.URI_INTENT_SCHEME
            ).apply {
                addCategory(Intent.CATEGORY_BROWSABLE)
                component = null
                selector = null
            }

            try {
                startActivity(parsedIntent)
                true
            } catch (appMissing: ActivityNotFoundException) {
                val fallbackUrl =
                    parsedIntent.getStringExtra(
                        "browser_fallback_url"
                    )

                if (!fallbackUrl.isNullOrBlank()) {
                    startActivity(
                        Intent(
                            Intent.ACTION_VIEW,
                            Uri.parse(fallbackUrl)
                        ).apply {
                            addCategory(Intent.CATEGORY_BROWSABLE)
                        }
                    )
                    true
                } else {
                    val dataUrl = parsedIntent.dataString

                    if (!dataUrl.isNullOrBlank()) {
                        startActivity(
                            Intent(
                                Intent.ACTION_VIEW,
                                Uri.parse(dataUrl)
                            ).apply {
                                addCategory(Intent.CATEGORY_BROWSABLE)
                            }
                        )
                        true
                    } else {
                        false
                    }
                }
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun buildMapFallbackUrl(uri: Uri): String {
        if (uri.scheme == "geo") {
            val raw = uri.schemeSpecificPart
                .substringBefore("?")
                .trim()

            if (raw.contains(",")) {
                return "https://www.google.com/maps/search/?api=1&query=$raw"
            }
        }

        return uri.toString()
    }

    private fun openInDefaultBrowser(url: String): Boolean {
        val targetUri = Uri.parse(url)

        val browserProbeIntent = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("https://www.example.com")
        ).apply {
            addCategory(Intent.CATEGORY_BROWSABLE)
        }

        val resolvedBrowser = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.resolveActivity(
                browserProbeIntent,
                android.content.pm.PackageManager.ResolveInfoFlags.of(
                    android.content.pm.PackageManager.MATCH_DEFAULT_ONLY.toLong()
                )
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.resolveActivity(
                browserProbeIntent,
                android.content.pm.PackageManager.MATCH_DEFAULT_ONLY
            )
        }

        val resolvedPackage = resolvedBrowser
            ?.activityInfo
            ?.packageName
            ?.takeIf { it != "android" }

        val browserPackage = resolvedPackage ?: findInstalledBrowserPackage()

        val targetIntent = Intent(
            Intent.ACTION_VIEW,
            targetUri
        ).apply {
            addCategory(Intent.CATEGORY_BROWSABLE)

            if (browserPackage != null) {
                setPackage(browserPackage)
            }
        }

        return try {
            startActivity(targetIntent)
            true
        } catch (firstError: ActivityNotFoundException) {
            val fallbackIntent = Intent(
                Intent.ACTION_VIEW,
                targetUri
            ).apply {
                addCategory(Intent.CATEGORY_BROWSABLE)
            }

            try {
                startActivity(fallbackIntent)
                true
            } catch (secondError: ActivityNotFoundException) {
                false
            }
        }
    }

    private fun findInstalledBrowserPackage(): String? {
        val knownBrowserPackages = listOf(
            "com.android.chrome",
            "com.sec.android.app.sbrowser",
            "org.mozilla.firefox",
            "com.microsoft.emmx",
            "com.opera.browser",
            "com.brave.browser"
        )

        for (packageName in knownBrowserPackages) {
            try {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(packageName, 0)
                return packageName
            } catch (_: Exception) {
                // Sonraki bilinen tarayıcı paketini kontrol et.
            }
        }

        return null
    }
}