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
            static let muteLight = NSColor(srgbRed: 142 / 255, green: 142 / 255, blue: 147 / 255, alpha: 1)
            static let selectionLight = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.055)

            static let hubDark = NSColor(srgbRed: 44 / 255, green: 44 / 255, blue: 46 / 255, alpha: 1)
            static let paperDark = NSColor(srgbRed: 28 / 255, green: 28 / 255, blue: 30 / 255, alpha: 1)
            static let inkDark = NSColor(srgbRed: 245 / 255, green: 245 / 255, blue: 247 / 255, alpha: 1)
            static let muteDark = NSColor(srgbRed: 142 / 255, green: 142 / 255, blue: 147 / 255, alpha: 1)
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
            static var mute: Color {
                Color(nsColor: Palette.adaptive(light: Palette.muteLight, dark: Palette.muteDark))
            }
            static var selection: Color {
                Color(nsColor: Palette.adaptive(light: Palette.selectionLight, dark: Palette.selectionDark))
            }
        }

        enum SettingsViewMetrics {
            static let sidebarWidth: CGFloat = 192
            static let headerHeight: CGFloat = 40
            static let sidebarHeaderHorizontalPadding: CGFloat = 16
            static let sidebarItemInset: CGFloat = 12
            static let sidebarNavHorizontalPadding: CGFloat = 12
            static let sidebarSectionSpacing: CGFloat = 28
            static let sidebarSectionItemSpacing: CGFloat = 6
            static let sidebarRowVerticalPadding: CGFloat = 8
            static let sidebarRowCornerRadius: CGFloat = 8
            static let trafficLightLeading: CGFloat = 20
            static let trafficLightTop: CGFloat = 18
            static let detailHorizontalPadding: CGFloat = 36
            static let formHorizontalPadding: CGFloat = 24
            static let formBottomPadding: CGFloat = 32
            static let cardContentSpacing: CGFloat = 16
            static let cardInnerPadding: CGFloat = 12
            static let valueRowSpacing: CGFloat = 16
            static let sidebarAccountRowHorizontalPadding: CGFloat = 16
            static let sidebarAccountRowVerticalPadding: CGFloat = 12
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
