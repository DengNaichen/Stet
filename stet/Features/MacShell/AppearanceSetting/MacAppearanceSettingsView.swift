#if os(macOS)
    import StetVisuals
    import SwiftUI

    struct MacAppearanceSettingsView: View {
        @StateObject private var viewModel: MacAppearanceSettingsViewModel

        init() {
            _viewModel = StateObject(wrappedValue: .shared)
        }

        init(viewModel: MacAppearanceSettingsViewModel) {
            _viewModel = StateObject(wrappedValue: viewModel)
        }

        private struct ThemeCard {
            let theme: MacDictationVisualTheme
            let imageName: String
        }

        private let themeCards: [ThemeCard] = [
            .init(theme: .blossom, imageName: "flower"),
            .init(theme: .egg, imageName: "onboardingEgg"),
            .init(theme: .harbor, imageName: "onboardingArch"),
            .init(theme: .cat, imageName: "onboardingFloat"),
            .init(theme: .beacon, imageName: "onboardingPanel5"),
            .init(theme: .autumn, imageName: "autumn"),
        ]

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    capsulePreview

                    themeCardScroller

                    Text("Choose the color palette used by the dictation capsule.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, MacUI.SettingsViewMetrics.formHorizontalPadding)
                .padding(.vertical, 20)
                .padding(.bottom, MacUI.SettingsViewMetrics.formBottomPadding)
            }
            .task {
                viewModel.load()
            }
        }

        private var capsulePreview: some View {
            MacDictationCapsulePreviewView(
                theme: MacDictationShaderTheme(rawValue: viewModel.shaderTheme.rawValue) ?? .egg,
                scale: 2.0
            )
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 20)
        }

        private var themeCardScroller: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(themeCards, id: \.theme) { card in
                        themeCardButton(card)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
            }
        }

        private func themeCardButton(_ card: ThemeCard) -> some View {
            let isSelected = viewModel.shaderTheme == card.theme

            return Button {
                viewModel.updateShaderTheme(card.theme, persist: true)
            } label: {
                ZStack(alignment: .bottom) {
                    Image(card.imageName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 96, height: 134)
                        .clipped()

                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.45)],
                        startPoint: .center,
                        endPoint: .bottom
                    )

                    Text(card.theme.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.bottom, 8)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: Color.black.opacity(isSelected ? 0.30 : 0.15), radius: isSelected ? 10 : 6, x: 0, y: 4)
                .scaleEffect(isSelected ? 1.04 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
            }
            .buttonStyle(.plain)
        }
    }
#endif
