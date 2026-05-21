import Foundation

public struct ClipboardItem: Identifiable, Hashable, Codable {
    public var id: UUID
    public var createdAt: Date
    public var sourceBundleId: String?
    public var sourceName: String?
    public var primaryType: String
    public var previewText: String
    public var contentHash: String
    public var isPinned: Bool
    public var isSensitive: Bool
    public var blobRefs: [ClipboardBlob]

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        sourceBundleId: String?,
        sourceName: String?,
        primaryType: String,
        previewText: String,
        contentHash: String,
        isPinned: Bool = false,
        isSensitive: Bool = false,
        blobRefs: [ClipboardBlob] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sourceBundleId = sourceBundleId
        self.sourceName = sourceName
        self.primaryType = primaryType
        self.previewText = previewText
        self.contentHash = contentHash
        self.isPinned = isPinned
        self.isSensitive = isSensitive
        self.blobRefs = blobRefs
    }
}

public struct ClipboardBlob: Identifiable, Hashable, Codable {
    public var id: UUID
    public var itemId: UUID
    public var uti: String
    public var size: Int
    public var sha256: String
    public var encryptedPath: String
    public var thumbnailPath: String?
    public var ocrText: String?

    public init(
        id: UUID = UUID(),
        itemId: UUID,
        uti: String,
        size: Int,
        sha256: String,
        encryptedPath: String,
        thumbnailPath: String? = nil,
        ocrText: String? = nil
    ) {
        self.id = id
        self.itemId = itemId
        self.uti = uti
        self.size = size
        self.sha256 = sha256
        self.encryptedPath = encryptedPath
        self.thumbnailPath = thumbnailPath
        self.ocrText = ocrText
    }
}

public struct Pinboard: Identifiable, Hashable, Codable {
    public var id: UUID
    public var name: String
    public var color: String
    public var sortOrder: Int
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        color: String,
        sortOrder: Int,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}

public struct PinboardItem: Hashable, Codable {
    public var pinboardId: UUID
    public var itemId: UUID
    public var position: Int

    public init(pinboardId: UUID, itemId: UUID, position: Int) {
        self.pinboardId = pinboardId
        self.itemId = itemId
        self.position = position
    }
}

public enum PrivacyRuleKind: String, Codable, CaseIterable {
    case app
    case type
    case regex
    case windowTitle
}

public enum PrivacyRuleAction: String, Codable, CaseIterable {
    case skip
    case mask
}

public struct PrivacyRule: Identifiable, Hashable, Codable {
    public var id: UUID
    public var kind: PrivacyRuleKind
    public var pattern: String
    public var action: PrivacyRuleAction
    public var enabled: Bool

    public init(
        id: UUID = UUID(),
        kind: PrivacyRuleKind,
        pattern: String,
        action: PrivacyRuleAction = .skip,
        enabled: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.pattern = pattern
        self.action = action
        self.enabled = enabled
    }
}

public enum PasteMode: String, Codable, CaseIterable {
    case direct
    case copyOnly
}

public enum RetentionPolicy: String, Codable, CaseIterable {
    case hours12
    case days1
    case days7
    case days30
    case days90
    case days365
    case forever

    public var days: Int? {
        switch self {
        case .forever:
            return nil
        case .hours12:
            return nil
        case .days1:
            return 1
        case .days7:
            return 7
        case .days30:
            return 30
        case .days90:
            return 90
        case .days365:
            return 365
        }
    }

    public var expirationInterval: TimeInterval? {
        switch self {
        case .forever:
            return nil
        case .hours12:
            return 12 * 60 * 60
        case .days1:
            return 24 * 60 * 60
        case .days7:
            return 7 * 24 * 60 * 60
        case .days30:
            return 30 * 24 * 60 * 60
        case .days90:
            return 90 * 24 * 60 * 60
        case .days365:
            return 365 * 24 * 60 * 60
        }
    }

    public var displayName: String {
        switch self {
        case .forever:
            return AppLocalization.text("retention.forever", value: "Forever")
        case .hours12:
            return AppLocalization.text("retention.hours12", value: "12 hours")
        case .days1:
            return AppLocalization.text("retention.days1", value: "1 day")
        case .days7:
            return AppLocalization.text("retention.days7", value: "7 days")
        case .days30:
            return AppLocalization.text("retention.days30", value: "30 days")
        case .days90:
            return AppLocalization.text("retention.days90", value: "90 days")
        case .days365:
            return AppLocalization.text("retention.days365", value: "365 days")
        }
    }
}

public struct StorageUsage: Hashable {
    public var itemCount: Int
    public var blobCount: Int
    public var payloadBytes: Int64
    public var databaseBytes: Int64
    public var attachmentBytes: Int64
    public var totalBytes: Int64
    public var baseURL: URL

    public init(
        itemCount: Int,
        blobCount: Int,
        payloadBytes: Int64,
        databaseBytes: Int64,
        attachmentBytes: Int64,
        totalBytes: Int64,
        baseURL: URL
    ) {
        self.itemCount = itemCount
        self.blobCount = blobCount
        self.payloadBytes = payloadBytes
        self.databaseBytes = databaseBytes
        self.attachmentBytes = attachmentBytes
        self.totalBytes = totalBytes
        self.baseURL = baseURL
    }
}

public enum AppAppearance: String, Codable, CaseIterable {
    case system
    case light
    case dark
}

public enum AppLanguage: String, Codable, CaseIterable {
    case system
    case zhHans
    case en
}

public enum AppLocalization {
    public static let languageDefaultsKey = "ClipShelf.LanguageOverride.v1"

    public static func setLanguage(_ language: AppLanguage, defaults: UserDefaults = .standard) {
        defaults.set(language.rawValue, forKey: languageDefaultsKey)
    }

    public static func currentLanguage(defaults: UserDefaults = .standard) -> AppLanguage {
        guard let rawValue = defaults.string(forKey: languageDefaultsKey),
              let language = AppLanguage(rawValue: rawValue)
        else {
            return .system
        }
        return language
    }

    public static func text(_ key: String, value: String? = nil) -> String {
        NSLocalizedString(
            key,
            tableName: "Localizable",
            bundle: bundle(for: currentLanguage()),
            value: value ?? key,
            comment: ""
        )
    }

    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale.current, arguments: arguments)
    }

    private static func bundle(for language: AppLanguage) -> Bundle {
        switch language {
        case .system:
            return .main
        case .zhHans:
            return localizedBundle(named: "zh-Hans")
        case .en:
            return localizedBundle(named: "en")
        }
    }

    private static func localizedBundle(named name: String) -> Bundle {
        guard let path = Bundle.main.path(forResource: name, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else {
            return .main
        }
        return bundle
    }
}

public struct AppSettings: Codable, Hashable {
    public var hotkey: HotKey
    public var pasteMode: PasteMode
    public var retentionPolicy: RetentionPolicy
    public var largeItemLimit: Int
    public var launchAtLogin: Bool
    public var appearance: AppAppearance
    public var language: AppLanguage
    public var ignoredBundleIds: [String]
    public var privacyRules: [PrivacyRule]

    public init(
        hotkey: HotKey = .default,
        pasteMode: PasteMode = .direct,
        retentionPolicy: RetentionPolicy = .forever,
        largeItemLimit: Int = 256 * 1024 * 1024,
        launchAtLogin: Bool = false,
        appearance: AppAppearance = .system,
        language: AppLanguage = .system,
        ignoredBundleIds: [String] = PrivacyRuleMatcher.defaultIgnoredBundleIds,
        privacyRules: [PrivacyRule] = PrivacyRuleMatcher.defaultRules
    ) {
        self.hotkey = hotkey
        self.pasteMode = pasteMode
        self.retentionPolicy = retentionPolicy
        self.largeItemLimit = largeItemLimit
        self.launchAtLogin = launchAtLogin
        self.appearance = appearance
        self.language = language
        self.ignoredBundleIds = ignoredBundleIds
        self.privacyRules = privacyRules
    }

    private enum CodingKeys: String, CodingKey {
        case hotkey
        case pasteMode
        case retentionPolicy
        case largeItemLimit
        case launchAtLogin
        case appearance
        case language
        case ignoredBundleIds
        case privacyRules
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.hotkey = try container.decodeIfPresent(HotKey.self, forKey: .hotkey) ?? .default
        self.pasteMode = try container.decodeIfPresent(PasteMode.self, forKey: .pasteMode) ?? .direct
        self.retentionPolicy = try container.decodeIfPresent(RetentionPolicy.self, forKey: .retentionPolicy) ?? .forever
        self.largeItemLimit = try container.decodeIfPresent(Int.self, forKey: .largeItemLimit) ?? 256 * 1024 * 1024
        self.launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        self.appearance = try container.decodeIfPresent(AppAppearance.self, forKey: .appearance) ?? .system
        self.language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
        self.ignoredBundleIds = try container.decodeIfPresent([String].self, forKey: .ignoredBundleIds) ?? PrivacyRuleMatcher.defaultIgnoredBundleIds
        self.privacyRules = try container.decodeIfPresent([PrivacyRule].self, forKey: .privacyRules) ?? PrivacyRuleMatcher.defaultRules
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hotkey, forKey: .hotkey)
        try container.encode(pasteMode, forKey: .pasteMode)
        try container.encode(retentionPolicy, forKey: .retentionPolicy)
        try container.encode(largeItemLimit, forKey: .largeItemLimit)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(appearance, forKey: .appearance)
        try container.encode(language, forKey: .language)
        try container.encode(ignoredBundleIds, forKey: .ignoredBundleIds)
        try container.encode(privacyRules, forKey: .privacyRules)
    }
}

public struct HotKey: Codable, Hashable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    public var displayName: String

    public init(keyCode: UInt32, modifiers: UInt32, displayName: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.displayName = displayName
    }

    public static let `default` = HotKey(
        keyCode: 9,
        modifiers: 768,
        displayName: "Shift-Command-V"
    )
}

public struct ClipboardPayload: Hashable {
    public var uti: String
    public var data: Data

    public init(uti: String, data: Data) {
        self.uti = uti
        self.data = data
    }
}

public struct PendingClipboardItem: Hashable {
    public var item: ClipboardItem
    public var payloads: [ClipboardPayload]

    public init(item: ClipboardItem, payloads: [ClipboardPayload]) {
        self.item = item
        self.payloads = payloads
    }
}

public enum ClipboardTypeFilter: String, CaseIterable, Identifiable {
    case all
    case text
    case code
    case url
    case image
    case file
    case pdf
    case richText
    case color

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .all:
            return AppLocalization.text("type.all", value: "All")
        case .text:
            return AppLocalization.text("type.text", value: "Text")
        case .code:
            return AppLocalization.text("type.code", value: "Code")
        case .url:
            return AppLocalization.text("type.url", value: "Links")
        case .image:
            return AppLocalization.text("type.image", value: "Images")
        case .file:
            return AppLocalization.text("type.file", value: "Files")
        case .pdf:
            return "PDF"
        case .richText:
            return AppLocalization.text("type.richText", value: "Rich")
        case .color:
            return AppLocalization.text("type.color", value: "Colors")
        }
    }
}

public enum ClipShelfError: LocalizedError {
    case database(String)
    case encryption(String)
    case keychain(String)
    case storage(String)
    case pasteboard(String)

    public var errorDescription: String? {
        switch self {
        case .database(let message):
            return "Database error: \(message)"
        case .encryption(let message):
            return "Encryption error: \(message)"
        case .keychain(let message):
            return "Keychain error: \(message)"
        case .storage(let message):
            return "Storage error: \(message)"
        case .pasteboard(let message):
            return "Pasteboard error: \(message)"
        }
    }
}
