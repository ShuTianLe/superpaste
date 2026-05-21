import AppKit
import ClipShelfCore
import SwiftUI

struct OverlayView: View {
    @ObservedObject var controller: ClipShelfController
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            LiquidDivider()
            mainContent
            LiquidDivider()
            footer
        }
        .frame(minWidth: 724, maxWidth: .infinity, minHeight: 344, maxHeight: .infinity)
        .background(LiquidGlassPanelBackground(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear {
            searchFocused = false
            controller.accessibilityTrusted = AccessibilityPermission.isTrusted
            controller.reload()
        }
        .onChange(of: controller.overlayFocusResetRequest) { _, _ in
            searchFocused = false
        }
        .onChange(of: controller.searchFocusRequest) { _, request in
            guard request > 0 else {
                searchFocused = false
                return
            }
            searchFocused = true
        }
        .onChange(of: controller.query) { _, _ in
            controller.reload(resetSelection: true, scrollToSelection: true)
        }
        .onChange(of: controller.typeFilter) { _, _ in
            controller.reload(resetSelection: true, scrollToSelection: true)
        }
        .onExitCommand {
            controller.hideOverlay()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            AppGlyph(size: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text("overlay.title"))
                    .font(.system(size: 15, weight: .semibold))
                Text(L10n.text("overlay.subtitle"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 176, alignment: .leading)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(L10n.text("overlay.search"), text: $controller.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .medium))
                    .focused($searchFocused)
                    .onSubmit { controller.pasteSelected() }
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.62), in: RoundedRectangle(cornerRadius: 10))
            .background(GlassSearchFieldBackground(isFocused: searchFocused))
            .animation(OverlayMotion.quick, value: searchFocused)

            Picker("", selection: $controller.typeFilter) {
                ForEach(ClipboardTypeFilter.allCases) { filter in
                    Text(filter.displayName).tag(filter)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 108)

            Button {
                controller.hideOverlay()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 1))
            .contentShape(Circle())
            .help(L10n.text("overlay.close"))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var mainContent: some View {
        HStack(spacing: 0) {
            pinboardRail
            LiquidDivider(vertical: true)
            timeline
        }
        .frame(height: 236)
        .background(GlassTimelineBackground())
    }

    private var pinboardRail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PINBOARDS")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 2)

            PinboardButton(
                title: L10n.text("overlay.recent"),
                systemImage: "clock",
                color: .secondary,
                isSelected: controller.selectedPinboardId == nil
            ) {
                controller.selectedPinboardId = nil
                controller.reload(resetSelection: true, scrollToSelection: true)
            }

            ForEach(controller.pinboards) { pinboard in
                PinboardButton(
                    title: pinboard.name,
                    systemImage: "pin.fill",
                    color: Color(hex: pinboard.color),
                    isSelected: controller.selectedPinboardId == pinboard.id
                ) {
                    controller.selectedPinboardId = pinboard.id
                    controller.reload(resetSelection: true, scrollToSelection: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: 148)
    }

    private var timeline: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    if controller.items.isEmpty {
                        EmptyClipsView()
                            .frame(width: 440, height: 196)
                    } else {
                        ForEach(Array(controller.items.enumerated()), id: \.element.id) { index, item in
                            ClipCard(
                                index: index,
                                item: item,
                                isSelected: controller.selectedIndex == index,
                                thumbnailProvider: thumbnail(for:)
                            )
                            .id(item.id)
                            .zIndex(controller.selectedIndex == index ? 10 : 0)
                            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .overlay {
                                CardClickSurface(
                                    onHover: {
                                        guard controller.selectedIndex != index else { return }
                                        controller.selectItem(at: index)
                                    },
                                    onSingleClick: {
                                        withAnimation(OverlayMotion.selectionFast) {
                                            controller.selectItem(at: index)
                                        }
                                    },
                                    onDoubleClick: {
                                        controller.selectItem(at: index)
                                        controller.paste(item)
                                    }
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                            }
                            .contextMenu {
                                Button(L10n.text("context.paste")) { controller.paste(item) }
                                Button(L10n.text("context.pastePlain")) { controller.paste(item, asPlainText: true) }
                                Button(L10n.text("context.copyPlain")) { controller.copyPlainText(item) }
                                Button(item.isPinned ? L10n.text("context.unpin") : L10n.text("context.pin")) { controller.togglePin(item) }
                                Button(L10n.text("context.addPinboard")) { controller.assignToFirstPinboard(item) }
                                Divider()
                                Button(L10n.text("context.delete"), role: .destructive) { controller.delete(item) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.035),
                        .init(color: .black, location: 0.965),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .background(HorizontalWheelScrollSurface())
            .onChange(of: controller.selectionScrollRequest) { _, _ in
                let index = controller.selectedIndex
                guard controller.items.indices.contains(index) else { return }
                withAnimation(OverlayMotion.scroll) {
                    proxy.scrollTo(controller.items[index].id, anchor: .center)
                }
            }
            .overlay(alignment: .bottom) {
                if let message = controller.transientMessage {
                    Text(message)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.28), lineWidth: 1))
                        .shadow(color: .black.opacity(0.16), radius: 14, y: 8)
                        .padding(.bottom, 8)
                        .transition(.opacity.combined(with: .move(edge: .bottom)).combined(with: .scale(scale: 0.98)))
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            KeycapHint(symbol: "↩", text: L10n.text("overlay.returnPaste"))
            KeycapHint(symbol: "← →", text: L10n.text("overlay.arrowsBrowse"))
            KeycapHint(symbol: "1-9", text: L10n.text("overlay.numberPaste"))
            Spacer()
            permissionIndicator
            Text(L10n.format("overlay.clips.count", controller.items.count))
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private var permissionIndicator: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(controller.accessibilityTrusted ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
            Text(controller.accessibilityTrusted ? L10n.text("settings.accessibilityAllowed") : L10n.text("settings.accessibilityDenied"))
                .lineLimit(1)
        }
    }

    private func thumbnail(for item: ClipboardItem) -> NSImage? {
        guard let blob = item.blobRefs.first(where: { $0.thumbnailPath != nil }),
              let data = try? controller.store.thumbnailData(for: blob)
        else {
            return nil
        }
        return NSImage(data: data)
    }
}

struct AppGlyph: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                .fill(Color.accentColor)
            RoundedRectangle(cornerRadius: size * 0.12, style: .continuous)
                .fill(Color.white.opacity(0.92))
                .frame(width: size * 0.46, height: size * 0.58)
                .offset(x: size * 0.04, y: size * 0.02)
            RoundedRectangle(cornerRadius: size * 0.10, style: .continuous)
                .stroke(Color.white.opacity(0.72), lineWidth: max(size * 0.055, 1))
                .frame(width: size * 0.46, height: size * 0.58)
                .offset(x: -size * 0.08, y: -size * 0.06)
        }
        .frame(width: size, height: size)
    }
}

struct ShortcutHint: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
    }
}

private enum OverlayMotion {
    static let selection = Animation.spring(response: 0.28, dampingFraction: 0.78, blendDuration: 0.08)
    static let selectionFast = Animation.easeOut(duration: 0.10)
    static let hover = Animation.easeOut(duration: 0.08)
    static let scroll = Animation.smooth(duration: 0.24)
    static let quick = Animation.smooth(duration: 0.16)
}

private struct LiquidGlassPanelBackground: View {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(panelTint)
            )
            .overlay(alignment: .topLeading) {
                LinearGradient(
                    colors: [
                        Color.white.opacity(colorScheme == .dark ? 0.22 : 0.50),
                        Color.white.opacity(0.08),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: 128)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .overlay(alignment: .top) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.0),
                                Color.white.opacity(colorScheme == .dark ? 0.34 : 0.72),
                                Color.accentColor.opacity(0.30),
                                Color.white.opacity(0.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 420, height: 2)
                    .padding(.top, 1)
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(borderGradient, lineWidth: 1)
            )
    }

    private var panelTint: Color {
        colorScheme == .dark ? Color.black.opacity(0.18) : Color.white.opacity(0.24)
    }

    private var borderGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .dark ? 0.30 : 0.70),
                Color.primary.opacity(0.06),
                Color.accentColor.opacity(0.20)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct GlassTimelineBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.025) : Color.white.opacity(0.10))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.28), lineWidth: 1)
                    )
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
    }
}

private struct GlassSearchFieldBackground: View {
    let isFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.white.opacity(0.34))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(isFocused ? Color.accentColor.opacity(0.62) : Color.white.opacity(0.22), lineWidth: isFocused ? 1.4 : 1)
            )
            .shadow(color: isFocused ? Color.accentColor.opacity(0.20) : Color.clear, radius: 12, y: 4)
    }
}

private struct LiquidDivider: View {
    var vertical = false

    var body: some View {
        LinearGradient(
            colors: [
                Color.white.opacity(0.0),
                Color.white.opacity(0.24),
                Color.primary.opacity(0.08),
                Color.white.opacity(0.0)
            ],
            startPoint: vertical ? .top : .leading,
            endPoint: vertical ? .bottom : .trailing
        )
        .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}

private struct KeycapHint: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Text(symbol)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .frame(height: 18)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Color.white.opacity(0.24), lineWidth: 1)
                )
            Text(text)
                .lineLimit(1)
        }
    }
}

struct EmptyClipsView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.secondary)
            Text(L10n.text("overlay.empty.title"))
                .font(.system(size: 16, weight: .semibold))
            Text(L10n.text("overlay.empty.subtitle"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PinboardButton: View {
    let title: String
    let systemImage: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : color)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.10))
                            )
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.22) : Color.clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(OverlayMotion.quick, value: isSelected)
    }
}

struct ClipCard: View {
    let index: Int
    let item: ClipboardItem
    let isSelected: Bool
    let thumbnailProvider: (ClipboardItem) -> NSImage?
    @State private var isHovering = false
    private var typeStyle: ClipboardTypeStyle {
        ClipboardTypeStyle(type: ClipboardTypeFilter(rawValue: item.primaryType))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                ClipboardTypeIcon(style: typeStyle, size: 31, isSelected: isSelected)
                VStack(alignment: .leading, spacing: 2) {
                    Text(typeLabel)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(typeStyle.accent)
                        .textCase(.uppercase)
                        .lineLimit(1)
                    Text(typeSubtitle)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text("\(index + 1)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .frame(width: 21, height: 21)
                    .background(isSelected ? typeStyle.accent : Color.primary.opacity(0.08), in: Circle())
                    .shadow(color: isSelected ? typeStyle.accent.opacity(0.28) : Color.clear, radius: 8, y: 2)
            }

            preview
                .frame(maxWidth: .infinity, minHeight: 92, maxHeight: 92, alignment: .leading)

            HStack(spacing: 6) {
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .foregroundStyle(typeStyle.accent)
                }
                Text(item.sourceName ?? L10n.text("overlay.unknown"))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(item.createdAt, style: .time)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 214, height: 196)
        .background(cardBackground)
        .overlay(cardHighlight, alignment: .top)
        .overlay(cardBorder)
        .scaleEffect(isSelected ? 1.018 : (isHovering ? 1.006 : 1.0))
        .offset(y: isSelected ? -2 : (isHovering ? -1 : 0))
        .shadow(color: Color.black.opacity(isSelected ? 0.16 : (isHovering ? 0.10 : 0.07)), radius: isSelected ? 12 : 8, x: 0, y: isSelected ? 7 : 4)
        .shadow(color: typeStyle.accent.opacity(isSelected ? 0.10 : 0), radius: 8, x: 0, y: 4)
        .animation(OverlayMotion.hover, value: isSelected)
        .animation(OverlayMotion.hover, value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let thumbnail = thumbnailProvider(item) {
            ThumbnailPreview(thumbnail: thumbnail, style: typeStyle, typeLabel: typeLabel)
        } else {
            switch ClipboardTypeFilter(rawValue: item.primaryType) {
            case .url:
                LinkCardPreview(text: item.previewText, style: typeStyle)
            case .file:
                FileCardPreview(text: item.previewText, style: typeStyle)
            case .color:
                ColorCardPreview(text: item.previewText, style: typeStyle)
            case .code:
                CodeCardPreview(text: item.previewText, style: typeStyle)
            default:
                TextCardPreview(text: item.previewText, style: typeStyle, isCode: item.primaryType == ClipboardTypeFilter.code.rawValue)
            }
        }
    }

    private var typeLabel: String {
        ClipboardTypeFilter(rawValue: item.primaryType)?.displayName ?? item.primaryType.capitalized
    }

    private var typeSubtitle: String {
        switch ClipboardTypeFilter(rawValue: item.primaryType) {
        case .url:
            return ClipboardPreviewMetadata.host(from: item.previewText) ?? "Web link"
        case .file:
            return ClipboardPreviewMetadata.fileExtension(from: item.previewText).map { "\($0.uppercased()) file" } ?? "Local file"
        case .pdf:
            return "Document"
        case .image:
            return "Visual item"
        case .code:
            return "Snippet"
        case .richText:
            return "Formatted text"
        case .color:
            return ClipboardPreviewMetadata.colorHex(from: item.previewText) ?? "Color value"
        default:
            return "\(max(item.previewText.count, 1)) chars"
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                typeStyle.accent.opacity(isSelected ? 0.17 : (isHovering ? 0.11 : 0.075)),
                                Color(nsColor: .controlBackgroundColor).opacity(isHovering ? 0.44 : 0.30)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(isSelected ? 0.62 : 0.30),
                        typeStyle.accent.opacity(isSelected ? 0.78 : 0.18),
                        Color.primary.opacity(isSelected ? 0.10 : 0.07)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: isSelected ? 1.5 : 1
            )
    }

    private var cardHighlight: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(isSelected ? 0.32 : 0.16),
                        typeStyle.accent.opacity(isSelected ? 0.12 : 0.055),
                        Color.white.opacity(0.04),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(height: 74)
            .allowsHitTesting(false)
    }
}

private struct ClipboardTypeStyle {
    let type: ClipboardTypeFilter?

    var accent: Color {
        switch type {
        case .url:
            return Color(red: 0.00, green: 0.55, blue: 0.78)
        case .file:
            return Color(red: 0.38, green: 0.35, blue: 0.86)
        case .pdf:
            return Color(red: 0.88, green: 0.18, blue: 0.22)
        case .image:
            return Color(red: 0.10, green: 0.60, blue: 0.42)
        case .code:
            return Color(red: 0.72, green: 0.42, blue: 0.10)
        case .richText:
            return Color(red: 0.65, green: 0.28, blue: 0.70)
        case .color:
            return Color(red: 0.95, green: 0.46, blue: 0.12)
        default:
            return Color(red: 0.28, green: 0.48, blue: 0.78)
        }
    }

    var secondary: Color {
        switch type {
        case .url:
            return Color(red: 0.32, green: 0.86, blue: 0.82)
        case .file:
            return Color(red: 0.50, green: 0.64, blue: 0.98)
        case .pdf:
            return Color(red: 1.00, green: 0.54, blue: 0.40)
        case .image:
            return Color(red: 0.52, green: 0.80, blue: 0.36)
        case .code:
            return Color(red: 0.98, green: 0.74, blue: 0.22)
        case .richText:
            return Color(red: 0.88, green: 0.56, blue: 0.92)
        case .color:
            return Color(red: 1.00, green: 0.72, blue: 0.22)
        default:
            return Color(red: 0.55, green: 0.68, blue: 0.84)
        }
    }
}

private struct ClipboardTypeIcon: View {
    let style: ClipboardTypeStyle
    let size: CGFloat
    let isSelected: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            style.secondary.opacity(isSelected ? 0.95 : 0.78),
                            style.accent.opacity(isSelected ? 0.98 : 0.72)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .stroke(Color.white.opacity(0.44), lineWidth: 1)
            icon
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        }
        .frame(width: size, height: size)
        .shadow(color: style.accent.opacity(isSelected ? 0.28 : 0.10), radius: isSelected ? 9 : 5, y: 3)
    }

    @ViewBuilder
    private var icon: some View {
        switch style.type {
        case .url:
            LinkGlyph()
        case .file:
            FileGlyph()
        case .pdf:
            PDFGlyph()
        case .image:
            ImageGlyph()
        case .code:
            CodeGlyph()
        case .richText:
            RichTextGlyph()
        case .color:
            ColorGlyph()
        default:
            TextGlyph()
        }
    }
}

private struct LinkGlyph: View {
    var body: some View {
        ZStack {
            Capsule()
                .stroke(lineWidth: 2.2)
                .frame(width: 15, height: 8)
                .rotationEffect(.degrees(-35))
                .offset(x: -3, y: 2)
            Capsule()
                .stroke(lineWidth: 2.2)
                .frame(width: 15, height: 8)
                .rotationEffect(.degrees(-35))
                .offset(x: 4, y: -3)
        }
    }
}

private struct FileGlyph: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 2.8, style: .continuous)
                .fill(Color.white.opacity(0.95))
                .frame(width: 16, height: 19)
            Path { path in
                path.move(to: CGPoint(x: 10, y: 0))
                path.addLine(to: CGPoint(x: 16, y: 6))
                path.addLine(to: CGPoint(x: 10, y: 6))
                path.closeSubpath()
            }
            .fill(Color.black.opacity(0.16))
            .frame(width: 16, height: 19)
            VStack(spacing: 2.2) {
                Capsule().frame(width: 8, height: 1.4)
                Capsule().frame(width: 10, height: 1.4)
                Capsule().frame(width: 7, height: 1.4)
            }
            .foregroundStyle(Color.black.opacity(0.32))
            .offset(x: -3.2, y: 9)
        }
    }
}

private struct PDFGlyph: View {
    var body: some View {
        ZStack {
            FileGlyph()
            Text("PDF")
                .font(.system(size: 5.5, weight: .black))
                .foregroundStyle(.red)
                .offset(y: 4.4)
        }
    }
}

private struct ImageGlyph: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(lineWidth: 2)
                .frame(width: 18, height: 15)
            Circle()
                .frame(width: 3.5, height: 3.5)
                .offset(x: 4.8, y: -3.6)
            Path { path in
                path.move(to: CGPoint(x: -8, y: 5))
                path.addLine(to: CGPoint(x: -2, y: -1))
                path.addLine(to: CGPoint(x: 2, y: 3))
                path.addLine(to: CGPoint(x: 6.5, y: -2))
                path.addLine(to: CGPoint(x: 9, y: 5))
            }
            .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct CodeGlyph: View {
    var body: some View {
        HStack(spacing: 2.5) {
            Text("<")
            Text("/")
            Text(">")
        }
        .font(.system(size: 12, weight: .black, design: .monospaced))
    }
}

private struct RichTextGlyph: View {
    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 1.5) {
            Text("A")
                .font(.system(size: 15, weight: .black, design: .serif))
            Text("a")
                .font(.system(size: 10, weight: .bold, design: .serif))
        }
    }
}

private struct ColorGlyph: View {
    var body: some View {
        ZStack {
            Circle().frame(width: 10, height: 10).offset(x: -4, y: 3)
            Circle().frame(width: 10, height: 10).offset(x: 4, y: 3)
            Circle().frame(width: 10, height: 10).offset(y: -4)
        }
    }
}

private struct TextGlyph: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Capsule().frame(width: 15, height: 2)
            Capsule().frame(width: 18, height: 2)
            Capsule().frame(width: 11, height: 2)
        }
    }
}

private struct ThumbnailPreview: View {
    let thumbnail: NSImage
    let style: ClipboardTypeStyle
    let typeLabel: String

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: thumbnail)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 92)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.24), lineWidth: 1)
                )
            Text(typeLabel)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .frame(height: 18)
                .background(style.accent.opacity(0.88), in: Capsule())
                .padding(6)
        }
        .frame(maxWidth: .infinity, maxHeight: 92)
    }
}

private struct LinkCardPreview: View {
    let text: String
    let style: ClipboardTypeStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "globe")
                    .font(.system(size: 11, weight: .semibold))
                Text(ClipboardPreviewMetadata.host(from: text) ?? "Link")
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(style.accent)

            Text(ClipboardPreviewMetadata.urlPathSummary(from: text))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text(PreviewTextFormatter.displayText(text, maxCharacters: 150, breakEvery: 18))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.secondary.opacity(0.85))
                .lineLimit(2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: 92, alignment: .topLeading)
        .background(typePreviewBackground(style))
        .allowsHitTesting(false)
    }
}

private struct FileCardPreview: View {
    let text: String
    let style: ClipboardTypeStyle

    var body: some View {
        HStack(spacing: 10) {
            ClipboardTypeIcon(style: style, size: 46, isSelected: false)

            VStack(alignment: .leading, spacing: 6) {
                Text(ClipboardPreviewMetadata.fileName(from: text))
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(2)
                Text(ClipboardPreviewMetadata.filePathSummary(from: text))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let ext = ClipboardPreviewMetadata.fileExtension(from: text) {
                    Text(ext.uppercased())
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(style.accent)
                        .padding(.horizontal, 6)
                        .frame(height: 17)
                        .background(style.accent.opacity(0.12), in: Capsule())
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: 92, alignment: .leading)
        .background(typePreviewBackground(style))
        .allowsHitTesting(false)
    }
}

private struct ColorCardPreview: View {
    let text: String
    let style: ClipboardTypeStyle

    var body: some View {
        let color = ClipboardPreviewMetadata.color(from: text) ?? style.accent
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color)
                .frame(width: 54, height: 58)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.42), lineWidth: 1)
                )
                .shadow(color: color.opacity(0.24), radius: 10, y: 4)

            VStack(alignment: .leading, spacing: 7) {
                Text(ClipboardPreviewMetadata.colorHex(from: text) ?? "Color")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .lineLimit(1)
                Text(PreviewTextFormatter.displayText(text, maxCharacters: 88))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: 92, alignment: .leading)
        .background(typePreviewBackground(style))
        .allowsHitTesting(false)
    }
}

private struct CodeCardPreview: View {
    let text: String
    let style: ClipboardTypeStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Circle().fill(Color.red.opacity(0.72)).frame(width: 6, height: 6)
                Circle().fill(Color.yellow.opacity(0.72)).frame(width: 6, height: 6)
                Circle().fill(Color.green.opacity(0.72)).frame(width: 6, height: 6)
                Spacer(minLength: 0)
            }
            Text(PreviewTextFormatter.displayText(text, maxCharacters: 260, breakEvery: 24))
                .font(.system(size: 11.3, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(5)
                .truncationMode(.tail)
        }
        .padding(9)
        .frame(maxWidth: .infinity, maxHeight: 92, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.09))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(style.accent.opacity(0.28), lineWidth: 1)
                )
        )
        .clipped()
        .allowsHitTesting(false)
    }
}

private struct TextCardPreview: View {
    let text: String
    let style: ClipboardTypeStyle
    let isCode: Bool

    var body: some View {
        Text(PreviewTextFormatter.displayText(text))
            .font(.system(size: 13, design: isCode ? .monospaced : .default))
            .foregroundStyle(.primary)
            .lineLimit(6)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, maxHeight: 92, alignment: .topLeading)
            .padding(1)
            .clipped()
            .allowsHitTesting(false)
    }
}

private func typePreviewBackground(_ style: ClipboardTypeStyle) -> some View {
    RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(style.accent.opacity(0.065))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(style.accent.opacity(0.16), lineWidth: 1)
        )
}

private enum ClipboardPreviewMetadata {
    static func host(from text: String) -> String? {
        normalizedURL(from: text)?.host(percentEncoded: false)
    }

    static func urlPathSummary(from text: String) -> String {
        guard let url = normalizedURL(from: text) else {
            return PreviewTextFormatter.displayText(text, maxCharacters: 90, breakEvery: 20)
        }
        let path = url.path(percentEncoded: false)
        if path.isEmpty || path == "/" {
            return url.scheme.map { "\($0.uppercased()) link" } ?? "Web link"
        }
        return PreviewTextFormatter.displayText(path, maxCharacters: 90, breakEvery: 18)
    }

    static func fileName(from text: String) -> String {
        let first = firstLine(from: text)
        let url = URL(string: first)
        let path = url?.isFileURL == true ? (url?.path(percentEncoded: false) ?? first) : first
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? "File" : name
    }

    static func filePathSummary(from text: String) -> String {
        let first = firstLine(from: text)
        let url = URL(string: first)
        let path = url?.isFileURL == true ? (url?.path(percentEncoded: false) ?? first) : first
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
        return parent.isEmpty || parent == "/" ? "Local file" : parent
    }

    static func fileExtension(from text: String) -> String? {
        let ext = URL(fileURLWithPath: fileName(from: text)).pathExtension
        return ext.isEmpty ? nil : ext
    }

    static func colorHex(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = trimmed.range(of: #"#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?"#, options: .regularExpression) {
            return String(trimmed[match]).uppercased()
        }
        return nil
    }

    static func color(from text: String) -> Color? {
        guard let hex = colorHex(from: text) else { return nil }
        let clean = hex.dropFirst()
        guard clean.count == 6 || clean.count == 8,
              let int = UInt64(clean, radix: 16)
        else {
            return nil
        }
        let r: UInt64
        let g: UInt64
        let b: UInt64
        if clean.count == 8 {
            r = (int >> 24) & 0xff
            g = (int >> 16) & 0xff
            b = (int >> 8) & 0xff
        } else {
            r = (int >> 16) & 0xff
            g = (int >> 8) & 0xff
            b = int & 0xff
        }
        return Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: 1)
    }

    private static func normalizedURL(from text: String) -> URL? {
        let trimmed = firstLine(from: text)
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        return URL(string: "https://\(trimmed)")
    }

    private static func firstLine(from text: String) -> String {
        text
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct CardClickSurface: NSViewRepresentable {
    let onHover: () -> Void
    let onSingleClick: () -> Void
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> CardClickView {
        let view = CardClickView()
        view.onHover = onHover
        view.onSingleClick = onSingleClick
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: CardClickView, context: Context) {
        nsView.onHover = onHover
        nsView.onSingleClick = onSingleClick
        nsView.onDoubleClick = onDoubleClick
    }
}

private final class CardClickView: NSView {
    var onHover: (() -> Void)?
    var onSingleClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?

    private var trackingAreaRef: NSTrackingArea?
    private var isMouseInside = false

    override var acceptsFirstResponder: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        guard !isMouseInside else { return }
        isMouseInside = true
        onHover?()
    }

    override func mouseMoved(with event: NSEvent) {
        guard !isMouseInside else { return }
        isMouseInside = true
        onHover?()
    }

    override func mouseExited(with event: NSEvent) {
        isMouseInside = false
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            onDoubleClick?()
        } else {
            onSingleClick?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        super.rightMouseDown(with: event)
    }
}

private struct HorizontalWheelScrollSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> HorizontalWheelScrollView {
        HorizontalWheelScrollView()
    }

    func updateNSView(_ nsView: HorizontalWheelScrollView, context: Context) {}
}

private final class HorizontalWheelScrollView: NSView {
    private var eventMonitor: Any?
    private weak var cachedScrollView: NSScrollView?

    override var acceptsFirstResponder: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        cachedScrollView = nil
        updateEventMonitor()
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        scrollHorizontally(with: event)
    }

    private func updateEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }

        guard window != nil else { return }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self,
                  self.shouldHandle(event)
            else {
                return event
            }
            self.scrollHorizontally(with: event)
            return nil
        }
    }

    private func shouldHandle(_ event: NSEvent) -> Bool {
        guard event.window === window else { return false }
        let point = convert(event.locationInWindow, from: nil)
        return bounds.contains(point)
    }

    private func scrollHorizontally(with event: NSEvent) {
        guard let scrollView = targetScrollView() else {
            super.scrollWheel(with: event)
            return
        }

        let rawDelta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            ? event.scrollingDeltaX
            : -event.scrollingDeltaY
        let horizontalDelta = scaledWheelDelta(rawDelta, event: event)
        guard horizontalDelta != 0 else { return }

        let documentWidth = scrollView.documentView?.bounds.width ?? 0
        let visibleWidth = scrollView.contentView.bounds.width
        let maxX = max(documentWidth - visibleWidth, 0)
        var origin = scrollView.contentView.bounds.origin
        origin.x = min(max(origin.x + horizontalDelta, 0), maxX)
        scrollView.contentView.setBoundsOrigin(origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func scaledWheelDelta(_ delta: CGFloat, event: NSEvent) -> CGFloat {
        guard delta != 0 else { return 0 }

        if event.hasPreciseScrollingDeltas {
            return delta * 1.4
        }

        let direction: CGFloat = delta > 0 ? 1 : -1
        let magnitude = min(max(abs(delta) * 10, 120), 260)
        return direction * magnitude
    }

    private func targetScrollView() -> NSScrollView? {
        if let cachedScrollView,
           cachedScrollView.window === window,
           isUsableTarget(cachedScrollView) {
            return cachedScrollView
        }

        if let enclosingScrollView,
           isUsableTarget(enclosingScrollView) {
            cachedScrollView = enclosingScrollView
            return enclosingScrollView
        }

        if let nearest = nearestScrollView(),
           isUsableTarget(nearest) {
            cachedScrollView = nearest
            return nearest
        }

        let matched = matchingScrollViewInWindow()
        cachedScrollView = matched
        return matched
    }

    private func nearestScrollView() -> NSScrollView? {
        var current: NSView? = superview
        while let view = current {
            if let scrollView = view as? NSScrollView {
                return scrollView
            }
            current = view.superview
        }
        return nil
    }

    private func matchingScrollViewInWindow() -> NSScrollView? {
        guard let contentView = window?.contentView else { return nil }
        let surfaceFrame = convert(bounds, to: nil)
        let scrollViews = contentView.descendants.compactMap { $0 as? NSScrollView }
        return scrollViews
            .filter { scrollView in
                guard isUsableTarget(scrollView) else { return false }
                let frame = scrollView.convert(scrollView.bounds, to: nil)
                return frame.intersects(surfaceFrame)
            }
            .max { lhs, rhs in
                lhs.convert(lhs.bounds, to: nil).intersection(surfaceFrame).width
                    < rhs.convert(rhs.bounds, to: nil).intersection(surfaceFrame).width
            }
    }

    private func isUsableTarget(_ scrollView: NSScrollView) -> Bool {
        let documentWidth = scrollView.documentView?.bounds.width ?? 0
        let visibleWidth = scrollView.contentView.bounds.width
        return documentWidth > visibleWidth
    }
}

private extension NSView {
    var descendants: [NSView] {
        subviews + subviews.flatMap(\.descendants)
    }
}

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xff, (int >> 8) & 0xff, int & 0xff)
        default:
            (r, g, b) = (45, 116, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}
