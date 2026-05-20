import Foundation

public final class SettingsStore {
    private let defaults: UserDefaults
    private let key = "ClipShelf.AppSettings.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> AppSettings {
        guard let data = defaults.data(forKey: key) else {
            let settings = AppSettings()
            AppLocalization.setLanguage(settings.language, defaults: defaults)
            return settings
        }

        do {
            let settings = try JSONDecoder().decode(AppSettings.self, from: data)
            AppLocalization.setLanguage(settings.language, defaults: defaults)
            return settings
        } catch {
            let settings = AppSettings()
            AppLocalization.setLanguage(settings.language, defaults: defaults)
            return settings
        }
    }

    public func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }
        AppLocalization.setLanguage(settings.language, defaults: defaults)
        defaults.set(data, forKey: key)
    }
}
