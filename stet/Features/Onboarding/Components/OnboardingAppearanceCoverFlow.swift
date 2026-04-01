#if os(macOS)
    import SwiftUI

    struct OnboardingAppearanceCoverFlowPanel: View {
        private struct CardSpec: Identifiable {
            let id = UUID()
            let theme: MacDictationVisualTheme
            let badge: String
            let color: Color
            let imageName: String?
            let swatches: [Color]?
        }

        private struct LayoutSpec {
            let size: CGSize
            let xOffset: CGFloat
            let yOffset: CGFloat
            let yRotation: Double
            let scale: CGFloat
            let opacity: Double
            let zIndex: Double
            let isInteractive: Bool
        }

        private struct SwatchSpec {
            let color: Color
        }

        @State private var focusedIndex = 0
        let selectedTheme: MacDictationVisualTheme
        let isSelectedThemeApplied: Bool
        private let onFocusedThemeChange: (MacDictationVisualTheme) -> Void
        private let onApplyTheme: (MacDictationVisualTheme) -> Void

        init(
            selectedTheme: MacDictationVisualTheme,
            isSelectedThemeApplied: Bool,
            onFocusedThemeChange: @escaping (MacDictationVisualTheme) -> Void = { _ in },
            onApplyTheme: @escaping (MacDictationVisualTheme) -> Void = { _ in }
        ) {
            self.selectedTheme = selectedTheme
            self.isSelectedThemeApplied = isSelectedThemeApplied
            self.onFocusedThemeChange = onFocusedThemeChange
            self.onApplyTheme = onApplyTheme
        }

        private let cards: [CardSpec] = [
            .init(
                theme: .blossom,
                badge: "01",
                color: Color(red: 0.95, green: 0.78, blue: 0.84),
                imageName: "flower",
                swatches: [Color(hex: "#87b3e2"), Color(hex: "#b7cb5c"), Color(hex: "#e78e92")]
            ),
            .init(
                theme: .egg,
                badge: "02",
                color: Color(red: 0.20, green: 0.64, blue: 0.45),
                imageName: "onboardingEgg",
                swatches: [Color(hex: "#5e8da7"), Color(hex: "#dc9803"), Color(hex: "#cacabf")]
            ),
            .init(
                theme: .harbor,
                badge: "03",
                color: Color(red: 0.93, green: 0.50, blue: 0.24),
                imageName: "onboardingArch",
                swatches: [Color(hex: "#014c69"), Color(hex: "#3a2520"), Color(hex: "#b05e5b")]
            ),
            .init(
                theme: .cat,
                badge: "04",
                color: Color(red: 0.70, green: 0.38, blue: 0.90),
                imageName: "onboardingFloat",
                swatches: [Color(hex: "#a22e2e"), Color(hex: "#191718"), Color(hex: "#eeeced")]
            ),
            .init(
                theme: .beacon,
                badge: "05",
                color: Color(red: 0.95, green: 0.73, blue: 0.20),
                imageName: "onboardingPanel5",
                swatches: [Color(hex: "#053447"), Color(hex: "#0451ad"), Color(hex: "#efa50f")]
            ),
            .init(
                theme: .autumn,
                badge: "06",
                color: Color(red: 0.29, green: 0.78, blue: 0.76),
                imageName: "autumn",
                swatches: [Color(hex: "#fdc24e"), Color(hex: "#fe4c45"), Color(hex: "#187789")]
            ),
        ]

        var body: some View {
            VStack(spacing: 16) {
                Spacer(minLength: 0)

                HStack(spacing: 12) {
                    ForEach(swatchSpecs(for: focusedIndex).indices, id: \.self) { index in
                        let swatch = swatchSpecs(for: focusedIndex)[index]

                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(swatch.color)
                            .frame(width: 46, height: 46)
                            .shadow(color: Color.black.opacity(0.22), radius: 10, x: 0, y: 6)
                    }
                }
                .animation(.spring(response: 0.45, dampingFraction: 0.82), value: focusedIndex)

                ZStack {
                    ForEach(cards.indices, id: \.self) { index in
                        let card = cards[index]
                        let relativeOffset = relativeOffset(for: index)
                        let layout = layout(for: relativeOffset)

                        OnboardingCoverFlowCard(
                            badge: card.badge,
                            color: card.color,
                            imageName: card.imageName
                        )
                        .frame(width: layout.size.width, height: layout.size.height)
                        .scaleEffect(layout.scale)
                        .rotation3DEffect(
                            .degrees(layout.yRotation),
                            axis: (x: 0, y: 1, z: 0),
                            perspective: 0.78
                        )
                        .offset(x: layout.xOffset, y: layout.yOffset)
                        .opacity(layout.opacity)
                        .zIndex(layout.zIndex)
                        .allowsHitTesting(layout.isInteractive)
                        .onTapGesture {
                            guard relativeOffset == -1 || relativeOffset == 1 else { return }
                            rotateFocus(by: relativeOffset)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .animation(.spring(response: 0.45, dampingFraction: 0.82), value: focusedIndex)

                Spacer(minLength: 0)

                OnboardingActionButton(
                    title: isSelectedThemeApplied ? "Applied" : "Apply Theme",
                    systemImage: "paintbrush",
                    isEnabled: !isSelectedThemeApplied,
                    background: isSelectedThemeApplied ? Color.accentColor : Color.white.opacity(0.12),
                    foreground: isSelectedThemeApplied ? .white : .primary,
                    strokeColor: Color.white.opacity(0.12),
                    minHeight: 44
                ) {
                    onApplyTheme(currentFocusedTheme)
                }
                .frame(width: 190)
            }
            .padding(.vertical, 8)
            .onAppear {
                focusedIndex = normalizedIndex(index(for: selectedTheme))
                onFocusedThemeChange(currentFocusedTheme)
            }
            .onChange(of: selectedTheme) { _, newTheme in
                let nextIndex = normalizedIndex(index(for: newTheme))
                guard nextIndex != focusedIndex else { return }
                focusedIndex = nextIndex
            }
        }

        private func swatchSpecs(for focusedIndex: Int) -> [SwatchSpec] {
            let card = cards[normalizedIndex(focusedIndex)]
            if let swatches = card.swatches, swatches.count == 3 {
                return swatches.map { SwatchSpec(color: $0) }
            }

            return [
                SwatchSpec(color: card.color.opacity(0.96)),
                SwatchSpec(color: card.color.opacity(0.72)),
                SwatchSpec(color: card.color.opacity(0.54)),
            ]
        }

        private func relativeOffset(for index: Int) -> Int {
            guard !cards.isEmpty else { return 0 }

            let count = cards.count
            var offset = index - focusedIndex
            if offset > count / 2 { offset -= count }
            if offset < -(count / 2) { offset += count }
            return offset
        }

        private func layout(for offset: Int) -> LayoutSpec {
            switch offset {
            case 0:
                return LayoutSpec(
                    size: CGSize(width: 210, height: 294),
                    xOffset: 0, yOffset: 0, yRotation: 0, scale: 1.0,
                    opacity: 1.0, zIndex: 3, isInteractive: false
                )
            case -1:
                return LayoutSpec(
                    size: CGSize(width: 150, height: 224),
                    xOffset: -148, yOffset: 18, yRotation: 28, scale: 0.92,
                    opacity: 1.0, zIndex: 2, isInteractive: true
                )
            case 1:
                return LayoutSpec(
                    size: CGSize(width: 150, height: 224),
                    xOffset: 148, yOffset: 18, yRotation: -28, scale: 0.92,
                    opacity: 1.0, zIndex: 1, isInteractive: true
                )
            default:
                let hiddenIsLeft = offset < 0
                return LayoutSpec(
                    size: CGSize(width: 150, height: 224),
                    xOffset: hiddenIsLeft ? -280 : 280,
                    yOffset: 28,
                    yRotation: hiddenIsLeft ? 34 : -34,
                    scale: 0.8,
                    opacity: 0.0,
                    zIndex: 0,
                    isInteractive: false
                )
            }
        }

        private func rotateFocus(by delta: Int) {
            guard delta != 0 else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                focusedIndex = normalizedIndex(focusedIndex + delta)
            }
            onFocusedThemeChange(currentFocusedTheme)
        }

        private func normalizedIndex(_ index: Int) -> Int {
            guard !cards.isEmpty else { return 0 }
            let modulo = index % cards.count
            return modulo >= 0 ? modulo : modulo + cards.count
        }

        private func index(for theme: MacDictationVisualTheme) -> Int {
            cards.firstIndex(where: { $0.theme == theme }) ?? 0
        }

        private var currentFocusedTheme: MacDictationVisualTheme {
            cards[normalizedIndex(focusedIndex)].theme
        }
    }

    private struct OnboardingCoverFlowCard: View {
        let badge: String
        let color: Color
        let imageName: String?

        var body: some View {
            ZStack(alignment: .topTrailing) {
                if let imageName {
                    Image(imageName)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                } else {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(color)
                }

                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(imageName == nil ? 0.12 : 0.18),
                                Color.white.opacity(imageName == nil ? 0.04 : 0.08),
                                .clear,
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                if imageName != nil {
                    LinearGradient(
                        colors: [Color.black.opacity(0.02), Color.black.opacity(0.12)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.black.opacity(0.30), radius: 18, x: 0, y: 12)
        }
    }
#endif
