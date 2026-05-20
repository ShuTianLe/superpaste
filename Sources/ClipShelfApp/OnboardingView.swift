import SwiftUI

struct OnboardingView: View {
    let requestAccessibility: () -> Void
    let finish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("onboarding.title"))
                        .font(.largeTitle.weight(.bold))
                    Text(L10n.text("onboarding.subtitle"))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                OnboardingRow(icon: "keyboard", title: L10n.text("onboarding.hotkey.title"), detail: L10n.text("onboarding.hotkey.detail"))
                OnboardingRow(icon: "lock", title: L10n.text("onboarding.lock.title"), detail: L10n.text("onboarding.lock.detail"))
                OnboardingRow(icon: "wifi.slash", title: L10n.text("onboarding.offline.title"), detail: L10n.text("onboarding.offline.detail"))
            }

            HStack {
                Button(L10n.text("onboarding.enableDirectPaste")) {
                    requestAccessibility()
                }
                Spacer()
                Button(L10n.text("onboarding.start")) {
                    finish()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct OnboardingRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 28)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
