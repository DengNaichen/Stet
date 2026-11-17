#if os(macOS)
    import AppKit
    import SwiftUI

    extension MacUI {
        enum LinearBrand {
            /// Restrained Stet warm amber accent for active toggles and subtle data accents.
            static let accentFill = Palette.adaptive(
                light: NSColor(srgbRed: 214 / 255, green: 118 / 255, blue: 10 / 255, alpha: 1),
                dark: NSColor(srgbRed: 230 / 255, green: 152 / 255, blue: 52 / 255, alpha: 1)
            )
            static let accent = Color(nsColor: accentFill)
        }

        enum LinearSurfaces {
            static let detailCanvas = Color(nsColor: .windowBackgroundColor)

            static let cardFill = Palette.adaptive(
                light: NSColor.white,
                dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.055)
            )
            static let card = Color(nsColor: cardFill)

            static let elevatedFill = Palette.adaptive(
                light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.045),
                dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.08)
            )
            static let elevated = Color(nsColor: elevatedFill)

            static let glassInset = Color(
                nsColor: Palette.adaptive(
                    light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.055),
                    dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.085)
                )
            )

            static let hairlineColor = Palette.adaptive(
                light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.065),
                dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.075)
            )
            static let hairline = Color(nsColor: hairlineColor)

            static let hairlineStrongColor = Palette.adaptive(
                light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.14),
                dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.14)
            )
            static let hairlineStrong = Color(nsColor: hairlineStrongColor)

            static let sidebarActiveFill = Palette.adaptive(
                light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.08),
                dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.13)
            )
            static let sidebarActive = Color(nsColor: sidebarActiveFill)

            static let sidebarHoverFill = Palette.adaptive(
                light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.045),
                dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.045)
            )
            static let sidebarHover = Color(nsColor: sidebarHoverFill)

            static let subtleHover = Color(
                nsColor: Palette.adaptive(
                    light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.025),
                    dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.025)
                )
            )

            static let mutedInk = Color(
                nsColor: Palette.adaptive(
                    light: NSColor(srgbRed: 130 / 255, green: 136 / 255, blue: 148 / 255, alpha: 1),
                    dark: NSColor(srgbRed: 110 / 255, green: 116 / 255, blue: 130 / 255, alpha: 1)
                )
            )
        }

        enum LinearTypography {
            static let pageTitle = Font.system(size: 16, weight: .semibold)
            static let sectionLabel = Font.system(size: 12, weight: .semibold)
            static let rowTitle = Font.system(size: 13, weight: .regular)
            static let rowSubtitle = Font.system(size: 11.5, weight: .regular)
            static let body = Font.system(size: 12.5, weight: .regular)
            static let sidebarItem = Font.system(size: 12.5, weight: .regular)
            static let sidebarSelected = Font.system(size: 12.5, weight: .medium)
            static let sidebarGroup = Font.system(size: 11, weight: .semibold)
            static let badge = Font.system(size: 11, weight: .medium)
            static let kbd = Font.system(size: 10, weight: .medium)
            static let statValue = Font.system(size: 18, weight: .semibold)
            static let statLabel = Font.system(size: 11, weight: .medium)
            static let code = Font.system(size: 11.5, design: .monospaced)
        }

        enum LinearMetrics {
            static let windowMinWidth: CGFloat = 780
            static let windowMinHeight: CGFloat = 540
            static let sidebarWidth: CGFloat = 204
            static let sidebarTopClearance: CGFloat = 38
            static let sidebarHorizontalPadding: CGFloat = 8
            /// Explicit gap between sidebar items so hover and active selection never touch.
            static let sidebarRowGap: CGFloat = 2
            static let sidebarRowHeight: CGFloat = 28
            static let sidebarRowCornerRadius: CGFloat = 6
            static let sidebarSectionGap: CGFloat = 14
            static let insetMargin: CGFloat = 7
            static let insetCornerRadius: CGFloat = 10
            static let contentHorizontalPadding: CGFloat = 24
            static let contentTopPadding: CGFloat = 12
            static let contentBottomPadding: CGFloat = 24
            static let contentSectionSpacing: CGFloat = 18
            static let contentMaxWidth: CGFloat = 720
            static let cardCornerRadius: CGFloat = 10
            static let rowHorizontalPadding: CGFloat = 14
            static let rowVerticalPadding: CGFloat = 9
            static let rowMinHeight: CGFloat = 42
            static let pickerWidth: CGFloat = 200
        }
    }

    // MARK: - Shell Containers & Navigation

    /// Sidebar navigation item with physical gap separation between hover and active states.
    struct LinearSidebarNavRow: View {
        let title: LocalizedStringKey
        let systemImage: String
        let isSelected: Bool
        var shortcutHint: String?
        let action: () -> Void

        @State private var isHovered = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(
                            isSelected || isHovered ? MacUI.Foreground.primary : MacUI.Foreground.secondaryColor
                        )
                        .frame(width: 16, alignment: .center)

                    Text(title)
                        .font(isSelected ? MacUI.LinearTypography.sidebarSelected : MacUI.LinearTypography.sidebarItem)
                        .foregroundStyle(
                            isSelected || isHovered ? MacUI.Foreground.primary : MacUI.Foreground.secondaryColor
                        )
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if let shortcutHint {
                        LinearKbdHint(
                            text: shortcutHint,
                            fillColor: MacUI.LinearSurfaces.glassInset
                        )
                    }
                }
                .padding(.horizontal, 9)
                .frame(height: MacUI.LinearMetrics.sidebarRowHeight)
                .background(backgroundView)
                .overlay(borderOverlay)
                .contentShape(
                    RoundedRectangle(
                        cornerRadius: MacUI.LinearMetrics.sidebarRowCornerRadius,
                        style: .continuous
                    )
                )
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) {
                    isHovered = hovering
                }
            }
        }

        @ViewBuilder
        private var backgroundView: some View {
            if isSelected {
                RoundedRectangle(cornerRadius: MacUI.LinearMetrics.sidebarRowCornerRadius, style: .continuous)
                    .fill(MacUI.LinearSurfaces.sidebarActive)
            } else if isHovered {
                RoundedRectangle(cornerRadius: MacUI.LinearMetrics.sidebarRowCornerRadius, style: .continuous)
                    .fill(MacUI.LinearSurfaces.sidebarHover)
            }
        }

        @ViewBuilder
        private var borderOverlay: some View {
            if isSelected {
                RoundedRectangle(cornerRadius: MacUI.LinearMetrics.sidebarRowCornerRadius, style: .continuous)
                    .strokeBorder(MacUI.LinearSurfaces.hairline, lineWidth: 1)
            }
        }
    }

    /// Small keycap badge used for shortcut hints inside sidebar and action rows.
    struct LinearKbdHint: View {
        let text: String
        var fillColor: Color = MacUI.LinearSurfaces.elevated

        var body: some View {
            Text(text)
                .font(MacUI.LinearTypography.kbd)
                .foregroundStyle(MacUI.LinearSurfaces.mutedInk)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(fillColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(MacUI.LinearSurfaces.hairline, lineWidth: 1)
                )
        }
    }

    // MARK: - Page & Card Structure

    extension View {
        /// Propagate detail title into the native macOS unified toolbar.
        @ViewBuilder
        func macNativeNavigationChrome(
            title: LocalizedStringKey,
            preservesExpandedToolbar: Bool = true
        ) -> some View {
            let base = navigationTitle(title)
            if preservesExpandedToolbar, #available(macOS 26.0, *) {
                base.toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Color.clear
                            .frame(width: 1, height: 1)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
            } else {
                base
            }
        }
    }

    /// Standard scrollable detail container with native unified toolbar title.
    struct LinearPageContainer<Content: View>: View {
        let title: LocalizedStringKey
        var maxWidth: CGFloat = MacUI.LinearMetrics.contentMaxWidth
        var preservesExpandedToolbar: Bool = true
        @ViewBuilder let content: () -> Content

        init(
            title: LocalizedStringKey,
            maxWidth: CGFloat = MacUI.LinearMetrics.contentMaxWidth,
            preservesExpandedToolbar: Bool = true,
            @ViewBuilder content: @escaping () -> Content
        ) {
            self.title = title
            self.maxWidth = maxWidth
            self.preservesExpandedToolbar = preservesExpandedToolbar
            self.content = content
        }

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: MacUI.LinearMetrics.contentSectionSpacing) {
                    content()
                }
                .frame(maxWidth: maxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, MacUI.LinearMetrics.contentHorizontalPadding)
                .padding(.top, MacUI.LinearMetrics.contentTopPadding)
                .padding(.bottom, MacUI.LinearMetrics.contentBottomPadding)
            }
            .macSettingsScrollIndicator()
            .macNativeNavigationChrome(
                title: title,
                preservesExpandedToolbar: preservesExpandedToolbar
            )
        }
    }

    /// Compact search box for sidebars and inline list filters.
    struct LinearSearchField: View {
        let placeholder: LocalizedStringKey
        @Binding var text: String
        var height: CGFloat = 28
        var fillColor: Color = MacUI.LinearSurfaces.elevated
        var isBorderless: Bool = false

        var body: some View {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: isBorderless ? 11.5 : 11, weight: .medium))
                    .foregroundStyle(MacUI.LinearSurfaces.mutedInk)

                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(MacUI.LinearTypography.body)
                    .foregroundStyle(MacUI.Foreground.primary)

                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(MacUI.LinearSurfaces.mutedInk)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, isBorderless ? 10 : 8)
            .frame(height: height)
            .background {
                if isBorderless {
                    Capsule()
                        .fill(fillColor)
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(fillColor)
                }
            }
            .overlay {
                if !isBorderless {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(MacUI.LinearSurfaces.hairline, lineWidth: 1)
                }
            }
        }
    }

    struct LinearHairlineDivider: View {
        var insetLeading: CGFloat = 0

        var body: some View {
            Rectangle()
                .fill(MacUI.LinearSurfaces.hairline)
                .frame(height: 1)
                .padding(.leading, insetLeading)
        }
    }

    /// Hairline-bordered card grouping related Linear setting rows.
    struct LinearSectionGroup<Content: View>: View {
        private let titleLabel: Text?
        var footer: LocalizedStringKey?
        @ViewBuilder let content: () -> Content

        init(
            _ title: LocalizedStringKey? = nil,
            footer: LocalizedStringKey? = nil,
            @ViewBuilder content: @escaping () -> Content
        ) {
            self.titleLabel = title.map { Text($0) }
            self.footer = footer
            self.content = content
        }

        init(
            titleLabel: Text,
            footer: LocalizedStringKey? = nil,
            @ViewBuilder content: @escaping () -> Content
        ) {
            self.titleLabel = titleLabel
            self.footer = footer
            self.content = content
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                if let titleLabel {
                    titleLabel
                        .font(MacUI.LinearTypography.sectionLabel)
                        .foregroundStyle(MacUI.Foreground.secondary)
                        .padding(.leading, 2)
                }

                VStack(alignment: .leading, spacing: 0) {
                    content()
                }
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: MacUI.LinearMetrics.cardCornerRadius, style: .continuous)
                        .fill(MacUI.LinearSurfaces.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: MacUI.LinearMetrics.cardCornerRadius, style: .continuous)
                        .strokeBorder(MacUI.LinearSurfaces.hairline, lineWidth: 1)
                )

                if let footer {
                    Text(footer)
                        .font(MacUI.LinearTypography.rowSubtitle)
                        .foregroundStyle(MacUI.LinearSurfaces.mutedInk)
                        .padding(.leading, 2)
                }
            }
        }
    }

    /// Two-line preference row with left title + subtitle and right compact control.
    struct LinearSettingRow<Control: View>: View {
        let title: LocalizedStringKey?
        var titleText: String?
        var subtitle: LocalizedStringKey?
        var subtitleText: String?
        @ViewBuilder let control: () -> Control

        init(
            _ title: LocalizedStringKey,
            subtitle: LocalizedStringKey? = nil,
            @ViewBuilder control: @escaping () -> Control
        ) {
            self.title = title
            self.titleText = nil
            self.subtitle = subtitle
            self.subtitleText = nil
            self.control = control
        }

        init(
            _ title: LocalizedStringKey,
            subtitleText: String?,
            @ViewBuilder control: @escaping () -> Control
        ) {
            self.title = title
            self.titleText = nil
            self.subtitle = nil
            self.subtitleText = subtitleText
            self.control = control
        }

        init(
            titleText: String,
            subtitle: LocalizedStringKey? = nil,
            @ViewBuilder control: @escaping () -> Control
        ) {
            self.title = nil
            self.titleText = titleText
            self.subtitle = subtitle
            self.subtitleText = nil
            self.control = control
        }

        var body: some View {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    if let titleText {
                        Text(verbatim: titleText)
                            .font(MacUI.LinearTypography.rowTitle)
                            .foregroundStyle(MacUI.Foreground.primary)
                    } else if let title {
                        Text(title)
                            .font(MacUI.LinearTypography.rowTitle)
                            .foregroundStyle(MacUI.Foreground.primary)
                    }

                    if let subtitle {
                        Text(subtitle)
                            .font(MacUI.LinearTypography.rowSubtitle)
                            .foregroundStyle(MacUI.Foreground.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if let subtitleText {
                        Text(verbatim: subtitleText)
                            .font(MacUI.LinearTypography.rowSubtitle)
                            .foregroundStyle(MacUI.Foreground.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 12)

                control()
            }
            .padding(.horizontal, MacUI.LinearMetrics.rowHorizontalPadding)
            .padding(.vertical, MacUI.LinearMetrics.rowVerticalPadding)
            .frame(minHeight: MacUI.LinearMetrics.rowMinHeight, alignment: .leading)
        }
    }

    /// Compact inline alert banner used inside Linear panels (warnings, errors, callouts).
    struct LinearInlineBanner: View {
        let systemImage: String
        let tint: Color
        let message: LocalizedStringKey
        var detail: String?

        init(systemImage: String, tint: Color, message: LocalizedStringKey) {
            self.systemImage = systemImage
            self.tint = tint
            self.message = message
            self.detail = nil
        }

        init(systemImage: String, tint: Color, text: String) {
            self.systemImage = systemImage
            self.tint = tint
            self.message = LocalizedStringKey(text)
            self.detail = text
        }

        var body: some View {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .padding(.top, 1)

                if let detail {
                    Text(detail)
                        .font(MacUI.LinearTypography.rowSubtitle)
                        .foregroundStyle(MacUI.Foreground.primary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(message)
                        .font(MacUI.LinearTypography.rowSubtitle)
                        .foregroundStyle(MacUI.Foreground.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tint.opacity(0.09))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(tint.opacity(0.24), lineWidth: 1)
            )
        }
    }

    // MARK: - Interactive Styles (Stet Warm Orange)

    struct LinearBadge: View {
        private let label: Text
        var tint: Color
        var showDot: Bool

        init(
            text: LocalizedStringKey,
            tint: Color = MacUI.Foreground.secondaryColor,
            showDot: Bool = false
        ) {
            self.label = Text(text)
            self.tint = tint
            self.showDot = showDot
        }

        init(
            verbatim text: String,
            tint: Color = MacUI.Foreground.secondaryColor,
            showDot: Bool = false
        ) {
            self.label = Text(verbatim: text)
            self.tint = tint
            self.showDot = showDot
        }

        var body: some View {
            HStack(spacing: 5) {
                if showDot {
                    Circle()
                        .fill(tint)
                        .frame(width: 5, height: 5)
                }
                label
                    .font(MacUI.LinearTypography.badge)
                    .foregroundStyle(tint)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(tint.opacity(0.11))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(tint.opacity(0.22), lineWidth: 1)
            )
        }
    }
#endif
