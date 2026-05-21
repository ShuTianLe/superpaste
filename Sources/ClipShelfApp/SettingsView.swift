import AppKit
import ClipShelfCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: ClipShelfController
    let onHotKeyChanged: (AppSettings) -> Void
    let onLocalizationChanged: () -> Void

    @State private var selectedSection: SettingsSection = .general
    @State private var ignoredBundleId = ""
    @State private var regexRule = ""
    @State private var largeItemLimitMB = 256

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            content
        }
        .id(controller.localizationVersion)
        .frame(width: 760, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            largeItemLimitMB = max(controller.settings.largeItemLimit / 1_048_576, 1)
            controller.accessibilityTrusted = AccessibilityPermission.isTrusted
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                AppGlyph(size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.text("app.name"))
                        .font(.system(size: 14, weight: .semibold))
                    Text(L10n.text("settings.title"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 10)

            ForEach(SettingsSection.allCases) { section in
                SettingsSidebarButton(
                    section: section,
                    isSelected: selectedSection == section
                ) {
                    selectedSection = section
                }
            }

            Spacer()
        }
        .padding(16)
        .frame(minWidth: 204, idealWidth: 204, maxWidth: 204, maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedSection.title)
                        .font(.system(size: 22, weight: .semibold))
                    Text(selectedSection.subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch selectedSection {
                    case .general:
                        GeneralSettingsView(
                            settings: $controller.settings,
                            largeItemLimitMB: $largeItemLimitMB,
                            onChange: saveGeneral,
                            onLaunchAtLoginChange: saveGeneralAndApplyLaunchAtLogin,
                            onLanguageChange: saveGeneralAndRefreshLocalization
                        )
                    case .privacy:
                        PrivacySettingsView(
                            settings: $controller.settings,
                            ignoredBundleId: $ignoredBundleId,
                            regexRule: $regexRule,
                            onSave: saveSettings
                        )
                    case .storage:
                        StorageSettingsView(controller: controller)
                    case .permissions:
                        PermissionsSettingsView(controller: controller)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func saveGeneral() {
        controller.settings.largeItemLimit = max(largeItemLimitMB, 1) * 1_048_576
        controller.saveSettings()
        onHotKeyChanged(controller.settings)
    }

    private func saveGeneralAndApplyLaunchAtLogin() {
        saveGeneral()
        applyLaunchAtLogin(controller.settings.launchAtLogin)
    }

    private func saveGeneralAndRefreshLocalization() {
        controller.settings.largeItemLimit = max(largeItemLimitMB, 1) * 1_048_576
        controller.saveSettings(refreshLocalization: true)
        onHotKeyChanged(controller.settings)
        onLocalizationChanged()
    }

    private func saveSettings() {
        controller.saveSettings()
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            controller.showTransientMessage(error.localizedDescription)
        }
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case privacy
    case storage
    case permissions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return L10n.text("settings.general")
        case .privacy: return L10n.text("settings.privacy")
        case .storage: return L10n.text("settings.storage")
        case .permissions: return L10n.text("settings.permissions")
        }
    }

    var subtitle: String {
        switch self {
        case .general: return L10n.text("settings.generalSubtitle")
        case .privacy: return L10n.text("settings.privacySubtitle")
        case .storage: return L10n.text("settings.storageSubtitle")
        case .permissions: return L10n.text("settings.permissionsSubtitle")
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .privacy: return "hand.raised"
        case .storage: return "internaldrive"
        case .permissions: return "checkmark.shield"
        }
    }
}

private struct SettingsSidebarButton: View {
    let section: SettingsSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 22)
                Text(section.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}

private struct SettingsRow<Content: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder var trailing: Content

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 18)
            trailing
        }
        .frame(minHeight: 34)
    }
}

private struct GeneralSettingsView: View {
    @Binding var settings: AppSettings
    @Binding var largeItemLimitMB: Int
    let onChange: () -> Void
    let onLaunchAtLoginChange: () -> Void
    let onLanguageChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard(title: L10n.text("settings.hotkey")) {
                SettingsRow(title: L10n.text("settings.showHistory"), detail: L10n.text("settings.hotkeyNote")) {
                    Text(settings.hotkey.displayName)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.thinMaterial, in: Capsule())
                }
            }

            SettingsCard(title: L10n.text("settings.paste")) {
                SettingsRow(title: L10n.text("settings.mode"), detail: L10n.text("settings.modeHelp")) {
                    Picker("", selection: $settings.pasteMode) {
                        Text(L10n.text("settings.directPaste")).tag(PasteMode.direct)
                        Text(L10n.text("settings.copyOnly")).tag(PasteMode.copyOnly)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                }
            }

            SettingsCard(title: L10n.text("settings.system")) {
                SettingsRow(title: L10n.text("settings.language"), detail: L10n.text("settings.languageHelp")) {
                    Picker("", selection: $settings.language) {
                        Text(L10n.text("settings.language.system")).tag(AppLanguage.system)
                        Text(L10n.text("settings.language.zhHans")).tag(AppLanguage.zhHans)
                        Text(L10n.text("settings.language.en")).tag(AppLanguage.en)
                    }
                    .labelsHidden()
                    .frame(width: 210)
                }

                Divider()

                SettingsRow(title: L10n.text("settings.launchAtLogin")) {
                    Toggle("", isOn: $settings.launchAtLogin)
                        .labelsHidden()
                }

                SettingsRow(title: L10n.text("settings.appearance")) {
                    Picker("", selection: $settings.appearance) {
                        Text(L10n.text("settings.appearance.system")).tag(AppAppearance.system)
                        Text(L10n.text("settings.appearance.light")).tag(AppAppearance.light)
                        Text(L10n.text("settings.appearance.dark")).tag(AppAppearance.dark)
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
            }

            SettingsCard(title: L10n.text("settings.storage")) {
                SettingsRow(title: L10n.text("settings.retention")) {
                    Picker("", selection: $settings.retentionPolicy) {
                        ForEach(RetentionPolicy.allCases, id: \.self) { policy in
                            Text(policy.displayName).tag(policy)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 176)
                }

                SettingsRow(title: L10n.format("settings.largeLimit", largeItemLimitMB), detail: L10n.text("settings.largeLimitHelp")) {
                    Stepper("", value: $largeItemLimitMB, in: 1...1024, step: 16)
                        .labelsHidden()
                }
            }
        }
        .onChange(of: settings.pasteMode) { _, _ in onChange() }
        .onChange(of: settings.language) { _, _ in onLanguageChange() }
        .onChange(of: settings.launchAtLogin) { _, _ in onLaunchAtLoginChange() }
        .onChange(of: settings.appearance) { _, _ in onChange() }
        .onChange(of: settings.retentionPolicy) { _, _ in onChange() }
        .onChange(of: largeItemLimitMB) { _, _ in onChange() }
    }
}

private struct PrivacySettingsView: View {
    @Binding var settings: AppSettings
    @Binding var ignoredBundleId: String
    @Binding var regexRule: String
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard(title: L10n.text("settings.ignoredApps"), subtitle: L10n.text("settings.ignoredAppsHelp")) {
                HStack {
                    TextField("com.example.App", text: $ignoredBundleId)
                        .textFieldStyle(.roundedBorder)
                    Button(L10n.text("settings.add")) {
                        let value = ignoredBundleId.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !value.isEmpty, !settings.ignoredBundleIds.contains(value) else { return }
                        settings.ignoredBundleIds.append(value)
                        ignoredBundleId = ""
                        onSave()
                    }
                }

                VStack(spacing: 0) {
                    ForEach(settings.ignoredBundleIds, id: \.self) { bundleId in
                        HStack {
                            Text(bundleId)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                            Spacer()
                            Button {
                                settings.ignoredBundleIds.removeAll { $0 == bundleId }
                                onSave()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 7)
                        Divider()
                    }
                }
                .frame(minHeight: 72, alignment: .top)
            }

            SettingsCard(title: L10n.text("settings.sensitiveRules"), subtitle: L10n.text("settings.sensitiveRulesHelp")) {
                HStack {
                    TextField(L10n.text("settings.regexPlaceholder"), text: $regexRule)
                        .textFieldStyle(.roundedBorder)
                    Button(L10n.text("settings.add")) {
                        let value = regexRule.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !value.isEmpty else { return }
                        settings.privacyRules.append(PrivacyRule(kind: .regex, pattern: value, action: .skip))
                        regexRule = ""
                        onSave()
                    }
                }

                VStack(spacing: 0) {
                    ForEach(settings.privacyRules) { rule in
                        HStack {
                            Text(rule.kind.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 74, alignment: .leading)
                            Text(rule.pattern)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                            Spacer()
                            Button {
                                settings.privacyRules.removeAll { $0.id == rule.id }
                                onSave()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 7)
                        Divider()
                    }
                }
                .frame(minHeight: 72, alignment: .top)
            }
        }
    }
}

private struct StorageSettingsView: View {
    @ObservedObject var controller: ClipShelfController
    @State private var diagnostics = ""
    @State private var usage: StorageUsage?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard(title: L10n.text("settings.storageUsage"), subtitle: L10n.text("settings.storageUsageHelp")) {
                if let usage {
                    HStack(alignment: .center, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(formatBytes(usage.totalBytes))
                                .font(.system(size: 28, weight: .semibold, design: .rounded))
                            Text(L10n.text("settings.totalUsage"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "internaldrive.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    VStack(spacing: 8) {
                        StorageUsageRow(label: L10n.text("settings.historyItems"), value: "\(usage.itemCount)")
                        StorageUsageRow(label: L10n.text("settings.payloads"), value: "\(usage.blobCount)")
                        StorageUsageRow(label: L10n.text("settings.payloadBytes"), value: formatBytes(usage.payloadBytes))
                        StorageUsageRow(label: L10n.text("settings.databaseBytes"), value: formatBytes(usage.databaseBytes))
                        StorageUsageRow(label: L10n.text("settings.attachmentBytes"), value: formatBytes(usage.attachmentBytes))
                    }
                } else {
                    ProgressView()
                        .controlSize(.small)
                }

                Button(L10n.text("settings.refreshStorage")) {
                    refreshStorage()
                }
                .buttonStyle(.borderless)
            }

            SettingsCard(title: L10n.text("settings.localStore"), subtitle: L10n.text("settings.localStoreHelp")) {
                PathPill(text: controller.store.baseURL.path)
            }

            SettingsCard(title: L10n.text("settings.clearOptions"), subtitle: L10n.text("settings.clearOptionsHelp")) {
                StorageActionRow(
                    title: L10n.text("settings.clearExpired"),
                    detail: L10n.text("settings.clearExpiredHelp"),
                    buttonTitle: L10n.text("settings.clear")
                ) {
                    performStorageAction {
                        try controller.store.cleanup(retentionPolicy: controller.settings.retentionPolicy)
                    }
                }

                Divider()

                StorageActionRow(
                    title: L10n.text("settings.clearUnpinned"),
                    detail: L10n.text("settings.clearUnpinnedHelp"),
                    buttonTitle: L10n.text("settings.clear")
                ) {
                    performStorageAction {
                        try controller.store.deleteUnpinnedItems()
                    }
                }

                Divider()

                StorageActionRow(
                    title: L10n.text("settings.clearAll"),
                    detail: L10n.text("settings.clearAllHelp"),
                    buttonTitle: L10n.text("settings.clearAllButton"),
                    isDestructive: true
                ) {
                    confirmClearAll()
                }
            }

            SettingsCard(title: L10n.text("settings.diagnostics")) {
                HStack {
                    Button(L10n.text("settings.refreshDiagnostics")) {
                        refreshStorage()
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                }

                TextEditor(text: $diagnostics)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 170)
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .onAppear {
            refreshStorage()
        }
    }

    private func refreshStorage() {
        usage = try? controller.store.storageUsage()
        diagnostics = (try? controller.store.diagnosticsSummary()) ?? ""
    }

    private func performStorageAction(_ action: () throws -> Void) {
        do {
            try action()
            controller.reload(resetSelection: true)
            refreshStorage()
        } catch {
            controller.showTransientMessage(error.localizedDescription)
        }
    }

    private func confirmClearAll() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = L10n.text("settings.confirmClearAllTitle")
        alert.informativeText = L10n.text("settings.confirmClearAllMessage")
        alert.addButton(withTitle: L10n.text("settings.confirmClear"))
        alert.addButton(withTitle: L10n.text("settings.cancel"))

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        performStorageAction {
            try controller.store.deleteAllItems()
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct StorageUsageRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
        }
        .font(.caption)
    }
}

private struct StorageActionRow: View {
    let title: String
    let detail: String
    let buttonTitle: String
    var isDestructive = false
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            Button(buttonTitle, action: action)
                .buttonStyle(.bordered)
                .foregroundStyle(isDestructive ? Color.red : Color.primary)
        }
        .frame(minHeight: 48)
    }
}

private struct PermissionsSettingsView: View {
    @ObservedObject var controller: ClipShelfController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard(title: L10n.text("settings.accessibility"), subtitle: L10n.text("settings.accessibilityHelp")) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: controller.accessibilityTrusted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(controller.accessibilityTrusted ? .green : .orange)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(controller.accessibilityTrusted ? L10n.text("settings.accessibilityAllowed") : L10n.text("settings.accessibilityDenied"))
                            .font(.system(size: 14, weight: .semibold))
                        Text(L10n.text("settings.accessibilityRestartHint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                HStack {
                    Button(L10n.text("settings.openAccessibility")) {
                        AccessibilityPermission.requestAndOpenSettings()
                        refreshPermission(after: 0.6)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(L10n.text("settings.recheckAccessibility")) {
                        refreshPermission(after: 0)
                    }
                }
            }

            SettingsCard(title: L10n.text("settings.currentAppPath"), subtitle: L10n.text("settings.currentAppPathHelp")) {
                PathPill(text: AccessibilityPermission.currentAppPath)
                PathPill(text: AccessibilityPermission.expectedApplicationsPath, label: L10n.text("settings.expectedAppPath"))

                Label(AccessibilityPermission.pathDiagnosticMessage, systemImage: AccessibilityPermission.isRunningFromApplications ? "checkmark.circle" : "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(AccessibilityPermission.isRunningFromApplications ? Color.secondary : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            refreshPermission(after: 0)
        }
    }

    private func refreshPermission(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            controller.accessibilityTrusted = AccessibilityPermission.isTrusted
        }
    }
}

private struct PathPill: View {
    let text: String
    var label: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let label {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(3)
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}
