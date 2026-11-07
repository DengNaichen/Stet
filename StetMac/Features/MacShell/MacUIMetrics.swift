#if os(macOS)
    import SwiftUI
    import AppKit

    enum MacUI {
        enum Brand {
            /// Luminous orange sampled from AppIconSources/AppIcon-1024.png.
            static let orange = Color(red: 252.0 / 255.0, green: 174.0 / 255.0, blue: 62.0 / 255.0)
        }

        enum Palette {
            /// Things-like hub: cool off-white, not system under-page gray.
            static let hubLight = NSColor(srgbRed: 245 / 255, green: 246 / 255, blue: 248 / 255, alpha: 1)
            static let paperLight = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
            static let inkLight = NSColor(srgbRed: 28 / 255, green: 28 / 255, blue: 30 / 255, alpha: 1)
            static let selectionLight = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.055)

            static let hubDark = NSColor(srgbRed: 44 / 255, green: 44 / 255, blue: 46 / 255, alpha: 1)
            static let paperDark = NSColor(srgbRed: 28 / 255, green: 28 / 255, blue: 30 / 255, alpha: 1)
            static let inkDark = NSColor(srgbRed: 245 / 255, green: 245 / 255, blue: 247 / 255, alpha: 1)
            static let selectionDark = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10)

            static func adaptive(light: NSColor, dark: NSColor) -> NSColor {
                NSColor(name: nil) { appearance in
                    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
                }
            }
        }

        enum Surfaces {
            static var hubFill: NSColor {
                Palette.adaptive(light: Palette.hubLight, dark: Palette.hubDark)
            }

            static var paperFill: NSColor {
                Palette.adaptive(light: Palette.paperLight, dark: Palette.paperDark)
            }

            static var hub: Color { Color(nsColor: hubFill) }
            static var paper: Color { Color(nsColor: paperFill) }
            static var ink: Color {
                Color(nsColor: Palette.adaptive(light: Palette.inkLight, dark: Palette.inkDark))
            }
            static var secondaryInk: Color { ink.opacity(0.72) }
            static var selection: Color {
                Color(nsColor: Palette.adaptive(light: Palette.selectionLight, dark: Palette.selectionDark))
            }
        }

        /// Keep native text styles and fixed-size text distinct to preserve the current Settings typography.
        enum Typography {
            static let heading: Font = .headline
            static let fieldLabel: Font = .subheadline
            static let emphasizedFieldLabel: Font = .subheadline.weight(.medium)
            static let status: Font = .callout
            static let caption: Font = .caption
            static let instructionNumber: Font = .caption.weight(.semibold)
            static let description: Font = .system(size: 12)
            static let detail: Font = .system(size: 11)
            static let footnote: Font = .system(size: 10)
            static let itemTitle: Font = .system(size: 12, weight: .medium)
            static let actionIcon: Font = .system(size: 12)
            static let credential: Font = .system(.body, design: .monospaced)
            static let backButton: Font = .system(size: 16, weight: .medium)
            static let brand: Font = .system(size: 13, weight: .semibold)
            static let sidebarSection: Font = .system(size: 12, weight: .semibold)
            static let sidebarItem: Font = .system(size: 13, weight: .regular)
            static let selectedSidebarItem: Font = .system(size: 13, weight: .medium)
            static let detailTitle: Font = .system(size: SettingsViewMetrics.detailTitleExpandedSize, weight: .semibold)
            static let statusBadge: Font = .system(size: 11, weight: .semibold, design: .rounded)
        }

        enum Foreground {
            static let primary = Color.primary
            // Hierarchical secondary follows the enclosing foreground style; Color.secondary is an explicit color.
            static let secondary = HierarchicalShapeStyle.secondary
            static let secondaryColor = Color.secondary
            static let success = Color.green
            static let warning = Color.orange
            static let error = Color.red
        }

        enum SettingsViewMetrics {
            static let minimumWidth: CGFloat = 720
            static let minimumHeight: CGFloat = 520
            static let sidebarWidth: CGFloat = 192
            static let headerHeight: CGFloat = 40
            static let backButtonSize: CGFloat = 24
            static let backButtonLeadingPadding: CGFloat = 18
            static let brandMarkHeight: CGFloat = 14
            static let sidebarHeaderHorizontalPadding: CGFloat = 24
            static let sidebarItemInset: CGFloat = 12
            static let sidebarNavHorizontalPadding: CGFloat = 12
            static let sidebarSectionSpacing: CGFloat = 28
            static let sidebarSectionItemSpacing: CGFloat = 6
            static let sidebarRowVerticalPadding: CGFloat = 8
            static let sidebarRowCornerRadius: CGFloat = 8
            static let sidebarRowSpacing: CGFloat = 2
            static let sidebarVerticalPadding: CGFloat = 20
            static let trafficLightLeading: CGFloat = 20
            static let trafficLightTop: CGFloat = 18
            static let detailHorizontalPadding: CGFloat = 36
            // Grouped Form adds 20pt section and 10pt row insets inside its content margin.
            static let groupedFormTitleHorizontalPadding: CGFloat = detailHorizontalPadding + 30
            static let formHorizontalPadding: CGFloat = 24
            static let formBottomPadding: CGFloat = 32
            static let cardContentSpacing: CGFloat = 16
            static let cardInnerPadding: CGFloat = 12
            static let valueRowSpacing: CGFloat = 16
            static let controlWidth: CGFloat = 240
            static let rowContentSpacing: CGFloat = 12
            static let controlSpacing: CGFloat = 8
            static let labelSpacing: CGFloat = 6
            static let detailSpacing: CGFloat = 4
            static let compactDetailSpacing: CGFloat = 2
            static let dividerVerticalPadding: CGFloat = 4
            static let statusIconWidth: CGFloat = 16
            static let statusRowHeight: CGFloat = 20
            static let statusDotDiameter: CGFloat = 7
            static let instructionRowSpacing: CGFloat = 10
            static let instructionBadgeDiameter: CGFloat = 22
            static let prominentActionMinimumWidth: CGFloat = 220
            static let standaloneContentPadding: CGFloat = 20
            static let microphoneTestVerticalPadding: CGFloat = 8
            static let compactProgressScale: CGFloat = 0.7
            static let audioMeterHeight: CGFloat = 5
            static let audioMeterFillOpacity: Double = 0.7
            static let sidebarAccountRowHorizontalPadding: CGFloat = 16
            static let sidebarAccountRowVerticalPadding: CGFloat = 12
            static let overlayScrollerWidth: CGFloat = 15
            static let overlayScrollerKnobWidth: CGFloat = 10
            static let overlayScrollerMinimumKnobHeight: CGFloat = 24
            static let overlayScrollerLightOpacity: Double = 0.22
            static let overlayScrollerDarkOpacity: Double = 0.32
            static let scrollOverflowTolerance: CGFloat = 1
            static let titleScrollUpdateTolerance: CGFloat = 0.5
            static let detailTitleExpandedSize: CGFloat = 24
            static let detailTitleCollapsedSize: CGFloat = 15
            static let detailTitleCollapseDistance: CGFloat = 32
            static let detailTitleBottomPadding: CGFloat = 20
            static let badgeHorizontalPadding: CGFloat = 10
            static let badgeVerticalPadding: CGFloat = 5
            static let badgeFillOpacity: Double = 0.12
            static let badgeStrokeOpacity: Double = 0.22
            static let badgeStrokeLineWidth: CGFloat = 1
        }

        enum Motion {
            static let audioMeter = Animation.easeOut(duration: 0.1)
            static let scrollIndicatorFade = Animation.easeOut(duration: 0.2)
            static let scrollIndicatorHideDelay: Duration = .milliseconds(650)
        }

        enum EditorMetrics {
            static let width: CGFloat = 440
            static let padding: CGFloat = 24
            static let spacing: CGFloat = 16
            static let cornerRadius: CGFloat = 12
        }

        enum DictionaryViewMetrics {
            // Form paddings
            static let formHorizontalPadding: CGFloat = 20
            static let formBottomPadding: CGFloat = 28

            // Grid
            static let gridMinColumnWidth: CGFloat = 180
            static let gridSpacing: CGFloat = 8

            // Entry input row
            static let entryInputSpacing: CGFloat = 10

            // Chips
            static let chipSpacing: CGFloat = 8
            static let chipTextFont: Font = .system(size: 12, weight: .medium, design: .rounded)
            static let chipButtonIconFont: Font = .system(size: 10, weight: .bold)
            static let chipHorizontalPadding: CGFloat = 10
            static let chipVerticalPadding: CGFloat = 8
            static let chipCornerRadius: CGFloat = 10
            static let chipFillOpacity: Double = 0.08
            static let chipStrokeOpacity: Double = 0.06
            static let chipStrokeLineWidth: CGFloat = 1
            static let entryLineLimit: Int = 2
        }

        enum WindowMetrics {
            static let preferencesWidthFactor: CGFloat = 0.35
            static let preferencesHeightFactor: CGFloat = 0.40
            static let preferencesMinimumWidthFactor: CGFloat = 0.20
            static let preferencesMinimumHeightFactor: CGFloat = 0.20

            // Fallback size when screen info isn't available
            static let preferencesFallbackSize = CGSize(width: 724, height: 640)

            /// Compute an adaptive default size for the Preferences window based on the given screen.
            static func preferencesDefaultSize(for screen: NSScreen?) -> CGSize {
                let visibleSize = screen?.visibleFrame.size ?? preferencesFallbackSize
                let minimumWidth = visibleSize.width * preferencesMinimumWidthFactor
                let minimumHeight = visibleSize.height * preferencesMinimumHeightFactor
                let width = max(minimumWidth, visibleSize.width * preferencesWidthFactor)
                let height = max(minimumHeight, visibleSize.height * preferencesHeightFactor)
                return CGSize(width: width, height: height)
            }
        }
    }
#endif
