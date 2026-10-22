import AppKit
import SysbarCore

/// The languages Sysbar ships, named in their own language. The choice is stored as this app's
/// `AppleLanguages` preference, which macOS reads at launch, so a change applies after a relaunch.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system = ""
    case english = "en"
    case turkish = "tr"
    case german = "de"
    case french = "fr"
    case spanish = "es"
    case italian = "it"
    case portuguese = "pt-BR"
    case dutch = "nl"
    case russian = "ru"
    case japanese = "ja"
    case korean = "ko"
    case chinese = "zh-Hans"
    case arabic = "ar"

    private static let preferenceKey = "AppleLanguages"

    var id: String { rawValue }

    /// Native names are not translated: a reader looks for their own language as they write it.
    var nativeName: String {
        switch self {
        case .system: L("System language")
        case .english: "English"
        case .turkish: "Türkçe"
        case .german: "Deutsch"
        case .french: "Français"
        case .spanish: "Español"
        case .italian: "Italiano"
        case .portuguese: "Português (Brasil)"
        case .dutch: "Nederlands"
        case .russian: "Русский"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .chinese: "简体中文"
        case .arabic: "العربية"
        }
    }

    /// The language chosen in Sysbar, or `.system` when it follows macOS.
    static var current: AppLanguage {
        let stored = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?[preferenceKey]
        guard let code = (stored as? [String])?.first else { return .system }
        return AppLanguage(rawValue: code) ?? .system
    }

    static func select(_ language: AppLanguage) {
        if language == .system {
            UserDefaults.standard.removeObject(forKey: preferenceKey)
        } else {
            UserDefaults.standard.set([language.rawValue], forKey: preferenceKey)
        }
    }

    /// Opens a fresh copy of the app and quits this one, so the new language takes effect.
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
