import SwiftUI

enum MobileLinearPalette {
    /// Restrained Stet warm amber matching macOS MacLinearDesignSystem.
    static let accentAmber = Color(red: 230 / 255, green: 152 / 255, blue: 52 / 255)
}

extension View {
    /// Linear-style compact inline navigation header aligned horizontally with trailing Liquid Glass buttons.
    func linearInlineHeader(_ title: LocalizedStringKey) -> some View {
        self
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .contentMargins(.top, 10, for: .scrollContent)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text(title)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.primary)
                        .fixedSize()
                }
                .sharedBackgroundVisibility(.hidden)
            }
    }
}
