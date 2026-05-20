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
                    Text("ClipShelf")
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
        .frame(minWidth: 188, idealWidth: 188, maxWidth: 188, maxHeight: .infinity, alignment: .topLeading)
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
                            onSave: saveGeneral
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
        applyLaunchAtLogin(controller.settings.launchAtLogin)
        controller.saveSettings()
        onHotKeyChanged(controller.settings)
        onLocalizationChanged()
    }

    private func saveSettings() {
        controller.saveSettings()
        onLocalizationChanged()
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
            Label(section.title, systemImage: section.systemImage)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.accentColor.opacity(0.16))
                    }
                }
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
    let onSave: () -> Void

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
                    .onChange(of: settings.language) { _, _ in
                        onSave()
                    }
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
                    .frame(width: 150)
                }

                SettingsRow(title: L10n.format("settings.largeLimit", largeItemLimitMB), detail: L10n.text("settings.largeLimitHelp")) {
                    Stepper("", value: $largeItemLimitMB, in: 1...1024, step: 16)
                        .labelsHidden()
                }
            }

            HStack {
                Spacer()
                Button(L10n.text("settings.save")) {
                    onSave()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard(title: L10n.text("settings.localStore"), subtitle: L10n.text("settings.localStoreHelp")) {
                PathPill(text: controller.store.baseURL.path)

                HStack {
                    Button(L10n.text("settings.runCleanup")) {
                        do {
                            try controller.store.cleanup(retentionPolicy: controller.settings.retentionPolicy)
                            controller.reload()
                        } catch {
                            controller.showTransientMessage(error.localizedDescription)
                        }
                    }
                    Button(L10n.text("settings.refreshDiagnostics")) {
                        diagnostics = (try? controller.store.diagnosticsSummary()) ?? ""
                    }
                    Spacer()
                }
            }

            SettingsCard(title: L10n.text("settings.diagnostics")) {
                TextEditor(text: $diagnostics)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 250)
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                    .onAppear {
                        diagnostics = (try? controller.store.diagnosticsSummary()) ?? ""
                    }
            }
        }
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
