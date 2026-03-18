#if os(macOS)
import SwiftUI
import AppKit

enum MacUI {
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
        static let preferencesWidthFactor: CGFloat = 0.36
        static let preferencesHeightFactor: CGFloat = 0.48

        // Minimum size to keep layout comfortable
        static let preferencesMinSize = CGSize(width: 500, height: 400)

        // Fallback size when screen info isn't available
        static let preferencesFallbackSize = CGSize(width: 724, height: 500)

        /// Compute an adaptive default size for the Preferences window based on the given screen.
        static func preferencesDefaultSize(for screen: NSScreen?) -> CGSize {
            let visibleSize = screen?.visibleFrame.size ?? preferencesFallbackSize
            let width = max(preferencesMinSize.width, visibleSize.width * preferencesWidthFactor)
            let height = max(preferencesMinSize.height, visibleSize.height * preferencesHeightFactor)
            return CGSize(width: width, height: height)
        }
    }
}
#endif


