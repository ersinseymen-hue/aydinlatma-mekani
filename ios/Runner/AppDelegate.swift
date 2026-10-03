import UIKit
import Flutter
import AVFoundation
import Speech

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let themeKey = "aydinlatmamekani_theme_preference"
  private var browserChannel: FlutterMethodChannel?
  private let audioEngine = AVAudioEngine()
  private var speechRecognizer: SFSpeechRecognizer?
  private var speechRequest: SFSpeechAudioBufferRecognitionRequest?
  private var speechTask: SFSpeechRecognitionTask?
  private var speechResult: FlutterResult?
  private var speechGeneration: UUID?
  private var speechTimeout: Timer?
  private var silenceTimeout: Timer?
  private var lastTranscript = ""
  private var hasAudioTap = false

  override func application(_ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    applyStoredTheme()
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "com.lightstore.aydinlatmamekani/browser",
        binaryMessenger: controller.binaryMessenger)
      browserChannel = channel
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else {
          result(FlutterError(code: "APP_UNAVAILABLE", message: nil, details: nil)); return
        }
        self.handle(call, result: result)
      }
      showStartupCover(on: controller)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args: [String: Any] = (call.arguments as? [String: Any]) ?? [:]
    switch call.method {
    case "getThemePreference": result(themePreference)
    case "getSystemDarkMode": result(systemDarkMode)
    case "getStartupTheme": result(resolvedTheme)
    case "getStartupThemeState": result(["preference": themePreference, "resolved": resolvedTheme])
    case "setThemePreference":
      if (args["explicit"] as? Bool) == true {
        let preference = (args["preference"] as? String) ?? "system"
        if preference == "dark" || preference == "light" {
          UserDefaults.standard.set(preference, forKey: themeKey)
        } else { UserDefaults.standard.removeObject(forKey: themeKey) }
        applyStoredTheme()
      }
      result(true)
    case "requestMicrophonePermission": requestMicrophone { result($0) }
    case "startVoiceRecognition":
      startVoiceRecognition(language: (args["language"] as? String) ?? "tr-TR", result: result)
    case "stopVoiceRecognition": finishVoiceRecognition(nil); result(true)
    case "openInDefaultBrowser": openExternal(args["url"] as? String, result: result)
    case "openMap": openMap(args["url"] as? String, result: result)
    default: result(FlutterMethodNotImplemented)
    }
  }

  private var themePreference: String {
    let stored = UserDefaults.standard.string(forKey: themeKey)
    return stored == "dark" || stored == "light" ? stored! : "system"
  }
  private var systemDarkMode: Bool {
    UIScreen.main.traitCollection.userInterfaceStyle == .dark
  }
  private var resolvedTheme: String {
    if themePreference == "system" { return systemDarkMode ? "dark" : "light" }
    return themePreference
  }
  private func applyStoredTheme() {
    switch themePreference {
    case "dark": window?.overrideUserInterfaceStyle = .dark
    case "light": window?.overrideUserInterfaceStyle = .light
    default: window?.overrideUserInterfaceStyle = .unspecified
    }
  }
  private func showStartupCover(on controller: FlutterViewController) {
    let dark = resolvedTheme == "dark"
    let cover = UIView(frame: controller.view.bounds)
    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    cover.backgroundColor = dark
      ? UIColor(red: 18/255, green: 22/255, blue: 28/255, alpha: 1) : .white
    let image = UIImageView(image: UIImage(named: dark ? "LaunchDark" : "LaunchLight"))
    image.frame = cover.bounds
    image.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    image.contentMode = .scaleAspectFit
    cover.addSubview(image)
    controller.view.addSubview(cover)
    controller.setFlutterViewDidRenderCallback { [weak cover] in cover?.removeFromSuperview() }
  }
  private func requestMicrophone(_ completion: @escaping (Bool) -> Void) {
    AVAudioSession.sharedInstance().requestRecordPermission { granted in
      DispatchQueue.main.async { completion(granted) }
    }
  }
  private func startVoiceRecognition(language: String, result: @escaping FlutterResult) {
    guard speechResult == nil else {
      result(FlutterError(code: "VOICE_RECOGNITION_BUSY", message: "Sesli arama zaten çalışıyor.", details: nil)); return
    }
    let generation = UUID()
    speechGeneration = generation
    speechResult = result
    requestMicrophone { [weak self] granted in
      guard let self = self, self.speechGeneration == generation else { return }
      guard granted else { self.finishVoiceRecognition(nil); return }
      SFSpeechRecognizer.requestAuthorization { [weak self] status in
        DispatchQueue.main.async {
          guard let self = self, self.speechGeneration == generation else { return }
          guard status == .authorized else { self.finishVoiceRecognition(nil); return }
          self.beginVoiceRecognition(language: language, generation: generation)
        }
      }
    }
  }
  private func beginVoiceRecognition(language: String, generation: UUID) {
    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language)), recognizer.isAvailable else {
      finishVoiceRecognition(nil); return
    }
    speechRecognizer = recognizer
    lastTranscript = ""
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    speechRequest = request
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.record, mode: .measurement, options: [])
      try session.setActive(true)
      let input = audioEngine.inputNode
      let format = input.outputFormat(forBus: 0)
      guard format.sampleRate > 0 && format.channelCount > 0 else { finishVoiceRecognition(nil); return }
      input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
      hasAudioTap = true
      audioEngine.prepare()
      try audioEngine.start()
      speechTask = recognizer.recognitionTask(with: request) { [weak self] response, error in
        DispatchQueue.main.async {
          guard let self = self, self.speechGeneration == generation else { return }
          if let response = response {
            self.lastTranscript = response.bestTranscription.formattedString
            self.silenceTimeout?.invalidate()
            if response.isFinal { self.finishVoiceRecognition(self.lastTranscript); return }
            self.silenceTimeout = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
              guard let self = self, self.speechGeneration == generation else { return }
              self.finishVoiceRecognition(self.lastTranscript)
            }
          }
          if error != nil { self.finishVoiceRecognition(self.lastTranscript) }
        }
      }
      speechTimeout = Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { [weak self] _ in
        guard let self = self, self.speechGeneration == generation else { return }
        self.finishVoiceRecognition(self.lastTranscript)
      }
    } catch { finishVoiceRecognition(nil) }
  }
  private func finishVoiceRecognition(_ transcript: String?) {
    let callback = speechResult
    let hadSession = speechRequest != nil
    speechResult = nil
    speechGeneration = nil
    speechTimeout?.invalidate(); speechTimeout = nil
    silenceTimeout?.invalidate(); silenceTimeout = nil
    audioEngine.stop()
    if hasAudioTap { audioEngine.inputNode.removeTap(onBus: 0); hasAudioTap = false }
    speechRequest?.endAudio()
    speechTask?.cancel()
    speechTask = nil; speechRequest = nil; speechRecognizer = nil
    if hadSession { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    let trimmed = transcript?.trimmingCharacters(in: .whitespacesAndNewlines)
    callback?(trimmed?.isEmpty == false ? trimmed : nil)
  }
  private func openExternal(_ raw: String?, result: @escaping FlutterResult) {
    guard let raw = raw, let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
          ["http", "https", "tel", "mailto", "whatsapp", "maps", "comgooglemaps"].contains(scheme) else {
      result(false); return
    }
    UIApplication.shared.open(url, options: [:]) { opened in result(opened) }
  }
  private func openMap(_ raw: String?, result: @escaping FlutterResult) {
    guard let raw = raw, let url = URL(string: raw) else { result(false); return }
    if url.scheme == "geo" {
      let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
        .queryItems?.first(where: { $0.name == "q" })?.value
      let coordinates = String(raw.dropFirst(4)).components(separatedBy: "?").first ?? ""
      var components = URLComponents(string: "https://maps.apple.com/")!
      components.queryItems = [URLQueryItem(name: "q", value: query ?? coordinates)]
      openExternal(components.url?.absoluteString, result: result)
    } else { openExternal(raw, result: result) }
  }
  override func applicationDidEnterBackground(_ application: UIApplication) {
    finishVoiceRecognition(nil)
    super.applicationDidEnterBackground(application)
  }
}
