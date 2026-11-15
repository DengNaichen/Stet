#if os(macOS)
    import SwiftUI
    import AppKit

    enum MacUI {
        enum Brand {
            /// Luminous orange sampled from AppIconSources/AppIcon-1024.png.
            static let orange = Color(red: 252.0 / 255.0, green: 174.0 / 255.0, blue: 62.0 / 255.0)
        }

        enum Palette {
            /// Linear-inspired shell backdrop vs inset content canvas.
            static let hubLight = NSColor(srgbRed: 243 / 255, green: 244 / 255, blue: 246 / 255, alpha: 1)
            static let paperLight = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
            static let inkLight = NSColor(srgbRed: 22 / 255, green: 24 / 255, blue: 29 / 255, alpha: 1)
            static let selectionLight = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.05)

            static let hubDark = NSColor(srgbRed: 12 / 255, green: 13 / 255, blue: 16 / 255, alpha: 1)
            static let paperDark = NSColor(srgbRed: 19 / 255, green: 21 / 255, blue: 26 / 255, alpha: 1)
            static let inkDark = NSColor(srgbRed: 236 / 255, green: 238 / 255, blue: 242 / 255, alpha: 1)
            static let selectionDark = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.08)

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
            static let minimumWidth: CGFloat = 780
            static let minimumHeight: CGFloat = 540
            static let sidebarWidth: CGFloat = 204
            static let headerHeight: CGFloat = 38
            static let backButtonSize: CGFloat = 24
            static let backButtonLeadingPadding: CGFloat = 14
            static let brandMarkHeight: CGFloat = 14
            static let sidebarHeaderHorizontalPadding: CGFloat = 12
            static let sidebarItemInset: CGFloat = 8
            static let sidebarNavHorizontalPadding: CGFloat = 8
            static let sidebarSectionSpacing: CGFloat = 16
            static let sidebarSectionItemSpacing: CGFloat = 2
            static let sidebarRowVerticalPadding: CGFloat = 6
            static let sidebarRowCornerRadius: CGFloat = 6
            static let sidebarRowSpacing: CGFloat = 2
            static let sidebarVerticalPadding: CGFloat = 14
            static let trafficLightLeading: CGFloat = 14
            static let trafficLightTop: CGFloat = 14
            static let detailHorizontalPadding: CGFloat = 24
            static let groupedFormTitleHorizontalPadding: CGFloat = 24
            static let formHorizontalPadding: CGFloat = 24
            static let formBottomPadding: CGFloat = 24
            static let cardContentSpacing: CGFloat = 12
            static let cardInnerPadding: CGFloat = 14
            static let valueRowSpacing: CGFloat = 16
            static let controlWidth: CGFloat = 210
            static let rowContentSpacing: CGFloat = 10
            static let controlSpacing: CGFloat = 8
            static let labelSpacing: CGFloat = 6
            static let detailSpacing: CGFloat = 4
            static let compactDetailSpacing: CGFloat = 2
            static let dividerVerticalPadding: CGFloat = 2
            static let statusIconWidth: CGFloat = 14
            static let statusRowHeight: CGFloat = 18
            static let statusDotDiameter: CGFloat = 6
            static let instructionRowSpacing: CGFloat = 8
            static let instructionBadgeDiameter: CGFloat = 20
            static let prominentActionMinimumWidth: CGFloat = 200
            static let standaloneContentPadding: CGFloat = 20
            static let microphoneTestVerticalPadding: CGFloat = 4
            static let compactProgressScale: CGFloat = 0.68
            static let audioMeterHeight: CGFloat = 5
            static let audioMeterFillOpacity: Double = 0.78
            static let sidebarAccountRowHorizontalPadding: CGFloat = 12
            static let sidebarAccountRowVerticalPadding: CGFloat = 10
            static let overlayScrollerWidth: CGFloat = 12
            static let overlayScrollerKnobWidth: CGFloat = 7
            static let overlayScrollerMinimumKnobHeight: CGFloat = 24
            static let overlayScrollerLightOpacity: Double = 0.20
            static let overlayScrollerDarkOpacity: Double = 0.28
            static let scrollOverflowTolerance: CGFloat = 1
            static let titleScrollUpdateTolerance: CGFloat = 0.5
            static let detailTitleExpandedSize: CGFloat = 15
            static let detailTitleCollapsedSize: CGFloat = 14
            static let detailTitleCollapseDistance: CGFloat = 24
            static let detailTitleBottomPadding: CGFloat = 12
            static let badgeHorizontalPadding: CGFloat = 8
            static let badgeVerticalPadding: CGFloat = 3
            static let badgeFillOpacity: Double = 0.11
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
            static let formBottomPadding: CGFloat = 24

            // Grid
            static let gridMinColumnWidth: CGFloat = 160
            static let gridSpacing: CGFloat = 6

            // Entry input row
            static let entryInputSpacing: CGFloat = 8

            // Chips
            static let chipSpacing: CGFloat = 6
            static let chipTextFont: Font = .system(size: 12, weight: .medium)
            static let chipButtonIconFont: Font = .system(size: 9.5, weight: .semibold)
            static let chipHorizontalPadding: CGFloat = 9
            static let chipVerticalPadding: CGFloat = 6
            static let chipCornerRadius: CGFloat = 6
            static let chipFillOpacity: Double = 0.08
            static let chipStrokeOpacity: Double = 0.10
            static let chipStrokeLineWidth: CGFloat = 1
            static let entryLineLimit: Int = 2
        }

        enum WindowMetrics {
            static let preferencesWidthFactor: CGFloat = 0.56
            static let preferencesHeightFactor: CGFloat = 0.64
            static let preferencesMinimumWidth: CGFloat = 880
            static let preferencesMaximumWidth: CGFloat = 1040
            static let preferencesMinimumHeight: CGFloat = 600
            static let preferencesMaximumHeight: CGFloat = 740

            // Fallback size when screen info isn't available
            static let preferencesFallbackSize = CGSize(width: 940, height: 620)

            /// Compute an adaptive default size for the Preferences window based on the given screen.
            static func preferencesDefaultSize(for screen: NSScreen?) -> CGSize {
                guard let visibleSize = screen?.visibleFrame.size else {
                    return preferencesFallbackSize
                }
                let rawWidth = visibleSize.width * preferencesWidthFactor
                let rawHeight = visibleSize.height * preferencesHeightFactor
                let width = min(
                    visibleSize.width * 0.9,
                    min(preferencesMaximumWidth, max(preferencesMinimumWidth, rawWidth))
                )
                let height = min(
                    visibleSize.height * 0.9,
                    min(preferencesMaximumHeight, max(preferencesMinimumHeight, rawHeight))
                )
                return CGSize(width: width, height: height)
            }
        }
    }
#endif
