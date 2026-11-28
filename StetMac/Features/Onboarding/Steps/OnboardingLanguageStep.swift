#if os(macOS)
    import StetCore
    import SwiftUI

    struct OnboardingLanguageStep: View {
        private enum EditingSlot {
            case primary
            case secondary
        }

        private struct LanguageOption: Identifiable {
            let code: String
            let nativeName: String
            let englishName: LocalizedStringKey
            var id: String { code }
        }

        @ObservedObject var viewModel: OnboardingViewModel
        var onBackToWelcome: (() -> Void)? = nil

        @State private var activeSlot: EditingSlot = .primary

        private let languages: [LanguageOption] = [
            .init(code: "en", nativeName: "English", englishName: "English"),
            .init(code: "zh-Hans", nativeName: "简体中文", englishName: "Chinese (Simp.)"),
            .init(code: "zh-Hant", nativeName: "繁體中文", englishName: "Chinese (Trad.)"),
            .init(code: "ja", nativeName: "日本語", englishName: "Japanese"),
            .init(code: "ko", nativeName: "한국어", englishName: "Korean"),
            .init(code: "fr", nativeName: "Français", englishName: "French"),
            .init(code: "de", nativeName: "Deutsch", englishName: "German"),
            .init(code: "es", nativeName: "Español", englishName: "Spanish"),
            .init(code: "pt", nativeName: "Português", englishName: "Portuguese"),
            .init(code: "it", nativeName: "Italiano", englishName: "Italian"),
        ]

        private var primaryOption: LanguageOption {
            languages.first { $0.code == viewModel.transcriptionPrimaryLanguage } ?? languages[0]
        }

        private var secondaryOption: LanguageOption? {
            guard let code = viewModel.transcriptionSecondaryLanguage else { return nil }
            return languages.first { $0.code == code }
        }

        var body: some View {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    OnboardingStepHeader(
                        eyebrow: "Step 1 of 5",
                        title: "Choose your speaking languages",
                        subtitle: "Pick a primary language, and optionally add a second for bilingual speech."
                    )

                    slotSelectorRow

                    VStack(alignment: .leading, spacing: 7) {
                        Text(
                            activeSlot == .primary
                                ? "Click a language below to set your Primary language"
                                : "Click a language below to set your Second language"
                        )
                        .font(.system(size: 11.5))
                        .foregroundStyle(MacUI.LinearSurfaces.mutedInk)
                        .padding(.leading, 2)

                        languageGrid
                    }

                    engineStatusCard

                    if case .failed(let message) = viewModel.engineDownloadState {
                        LinearInlineBanner(
                            systemImage: "exclamationmark.circle",
                            tint: MacUI.Foreground.error,
                            text: message
                        )
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, OnboardingMetrics.contentHorizontalPadding)
                .padding(.top, 4)
                .padding(.bottom, 16)

                OnboardingFooterBar {
                    if let onBackToWelcome {
                        OnboardingBackButton(action: onBackToWelcome)
                    }
                } trailing: {
                    OnboardingPrimaryButton(
                        verbatim: viewModel.engineDownloadPrimaryButtonTitle,
                        isEnabled: !viewModel.isEngineDownloadRunning,
                        isLoading: viewModel.isEngineDownloadRunning
                    ) {
                        Task {
                            await viewModel.handleEngineDownloadPrimaryAction()
                        }
                    }
                }
            }
        }

        private var slotSelectorRow: some View {
            HStack(spacing: 8) {
                primarySlotCard

                Button {
                    swapLanguages()
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MacUI.Foreground.secondary)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(MacUI.LinearSurfaces.card)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(MacUI.LinearSurfaces.hairline, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(secondaryOption == nil)
                .opacity(secondaryOption == nil ? 0.30 : 1)
                .help("Swap primary and second language")

                secondarySlotCard
            }
        }

        private var primarySlotCard: some View {
            let isActive = activeSlot == .primary
            return Button {
                activeSlot = .primary
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Primary")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.4)
                            .textCase(.uppercase)
                            .foregroundStyle(isActive ? MacUI.LinearBrand.accent : MacUI.LinearSurfaces.mutedInk)

                        Spacer(minLength: 4)

                        if isActive {
                            Text("Selecting")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(MacUI.LinearBrand.accent)
                        }
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: primaryOption.nativeName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(MacUI.Foreground.primary)
                            .lineLimit(1)

                        if primaryOption.code != "en" {
                            Text(primaryOption.englishName)
                                .font(.system(size: 11))
                                .foregroundStyle(MacUI.LinearSurfaces.mutedInk)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isActive ? OnboardingPalette.accentSoft : MacUI.LinearSurfaces.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            isActive ? MacUI.LinearBrand.accent : MacUI.LinearSurfaces.hairline,
                            lineWidth: isActive ? 1.5 : 1
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }

        private var secondarySlotCard: some View {
            let isActive = activeSlot == .secondary
            let hasSecondary = secondaryOption != nil

            return ZStack(alignment: .topTrailing) {
                Button {
                    activeSlot = .secondary
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Second · Optional")
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(0.4)
                                .textCase(.uppercase)
                                .foregroundStyle(isActive ? MacUI.LinearBrand.accent : MacUI.LinearSurfaces.mutedInk)

                            Spacer(minLength: 4)

                            if isActive && !hasSecondary {
                                Text("Selecting")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(MacUI.LinearBrand.accent)
                            }
                        }

                        if let secondary = secondaryOption {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(verbatim: secondary.nativeName)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(MacUI.Foreground.primary)
                                    .lineLimit(1)

                                if secondary.code != "en" {
                                    Text(secondary.englishName)
                                        .font(.system(size: 11))
                                        .foregroundStyle(MacUI.LinearSurfaces.mutedInk)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.trailing, 22)
                        } else {
                            Text(isActive ? "Pick a language below…" : "+ Add second language")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(MacUI.Foreground.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                isActive
                                    ? OnboardingPalette.accentSoft
                                    : (hasSecondary ? MacUI.LinearSurfaces.card : Color.clear)
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                isActive
                                    ? MacUI.LinearBrand.accent
                                    : (hasSecondary
                                        ? MacUI.LinearSurfaces.hairline : MacUI.LinearSurfaces.hairlineStrong),
                                style: hasSecondary || isActive
                                    ? StrokeStyle(lineWidth: isActive ? 1.5 : 1)
                                    : StrokeStyle(lineWidth: 1, dash: [4, 3])
                            )
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)

                if hasSecondary {
                    Button {
                        viewModel.transcriptionSecondaryLanguage = nil
                        activeSlot = .primary
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(MacUI.Foreground.secondary)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(MacUI.LinearSurfaces.elevated))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 7)
                    .padding(.trailing, 8)
                    .help("Remove second language")
                }
            }
        }

        private var languageGrid: some View {
            let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 5)
            return LazyVGrid(columns: columns, spacing: 6) {
                ForEach(languages) { option in
                    let isPrimary = viewModel.transcriptionPrimaryLanguage == option.code
                    let isSecondary = viewModel.transcriptionSecondaryLanguage == option.code
                    let isActiveMatch =
                        (activeSlot == .primary && isPrimary) || (activeSlot == .secondary && isSecondary)

                    Button {
                        selectLanguage(option.code)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(verbatim: option.nativeName)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(MacUI.Foreground.primary)
                                    .lineLimit(1)

                                Spacer(minLength: 0)

                                if isPrimary {
                                    Text("1st")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(
                                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                                .fill(MacUI.LinearBrand.accent)
                                        )
                                } else if isSecondary {
                                    Text("2nd")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(OnboardingPalette.primaryButtonForeground)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(
                                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                                .fill(OnboardingPalette.primaryButtonBackground)
                                        )
                                }
                            }

                            Text(option.englishName)
                                .font(.system(size: 10))
                                .foregroundStyle(MacUI.LinearSurfaces.mutedInk)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(
                                    isPrimary
                                        ? OnboardingPalette.accentSoft
                                        : (isSecondary ? MacUI.LinearSurfaces.elevated : MacUI.LinearSurfaces.card)
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(
                                    isActiveMatch
                                        ? MacUI.LinearBrand.accent
                                        : (isPrimary
                                            ? OnboardingPalette.accentBorder
                                            : (isSecondary
                                                ? MacUI.LinearSurfaces.hairlineStrong
                                                : MacUI.LinearSurfaces.hairline)),
                                    lineWidth: 1
                                )
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        private var engineStatusCard: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: viewModel.transcriptionEngine == .fluidAudio ? "bolt.fill" : "cpu")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MacUI.LinearBrand.accent)
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(OnboardingPalette.accentSoft)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(LocalizedStringKey(viewModel.transcriptionEngine.displayName))
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(MacUI.Foreground.primary)

                        Text(
                            viewModel.transcriptionEngine == .fluidAudio
                                ? "Optimized for speed and accuracy in these languages."
                                : "Fast on-device local transcription engine."
                        )
                        .font(.system(size: 11.5))
                        .foregroundStyle(MacUI.Foreground.secondary)
                        .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    if viewModel.canContinueEngineDownload {
                        OnboardingStatusPill("Ready")
                    }
                }

                if viewModel.isEngineDownloadRunning {
                    VStack(alignment: .leading, spacing: 5) {
                        ProgressView(value: viewModel.engineDownloadProgress)
                            .progressViewStyle(.linear)
                            .tint(MacUI.LinearBrand.accent)

                        Text(verbatim: viewModel.engineDownloadProgressLabel)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(MacUI.Foreground.secondary)
                    }
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: OnboardingMetrics.cardCornerRadius, style: .continuous)
                    .fill(MacUI.LinearSurfaces.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OnboardingMetrics.cardCornerRadius, style: .continuous)
                    .strokeBorder(MacUI.LinearSurfaces.hairline, lineWidth: 1)
            )
        }

        private func selectLanguage(_ code: String) {
            switch activeSlot {
            case .primary:
                if code == viewModel.transcriptionSecondaryLanguage {
                    let previousPrimary = viewModel.transcriptionPrimaryLanguage
                    viewModel.transcriptionPrimaryLanguage = code
                    viewModel.transcriptionSecondaryLanguage = previousPrimary
                } else {
                    viewModel.transcriptionPrimaryLanguage = code
                }
            case .secondary:
                if code == viewModel.transcriptionPrimaryLanguage {
                    if let previousSecondary = viewModel.transcriptionSecondaryLanguage {
                        viewModel.transcriptionPrimaryLanguage = previousSecondary
                        viewModel.transcriptionSecondaryLanguage = code
                    }
                } else {
                    viewModel.transcriptionSecondaryLanguage = code
                }
            }
        }

        private func swapLanguages() {
            guard let secondary = viewModel.transcriptionSecondaryLanguage else { return }
            let primary = viewModel.transcriptionPrimaryLanguage
            viewModel.transcriptionPrimaryLanguage = secondary
            viewModel.transcriptionSecondaryLanguage = primary
        }
    }

    #if DEBUG
        #Preview {
            OnboardingLanguageStep(
                viewModel: OnboardingViewModel(coordinator: MockOnboardingCoordinator(step: .language))
            )
            .frame(width: OnboardingMetrics.windowWidth, height: 500)
        }
    #endif
#endif
