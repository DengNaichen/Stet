#if os(macOS)
    import KeyboardShortcuts
    import SwiftUI

    struct OnboardingFirstSuccessStep: View {
        @ObservedObject var viewModel: OnboardingViewModel
        @State private var draftText = ""
        @State private var currentShortcut: KeyboardShortcuts.Shortcut? = KeyboardShortcuts.getShortcut(
            for: HotkeyBinding.dictation.name
        )
        @FocusState private var isDraftFocused: Bool

        private var sampleSentence: String {
            switch viewModel.transcriptionPrimaryLanguage {
            case "zh-Hans":
                return "明天上午十点我们开个会，把这次的设计方案过一遍。"
            case "zh-Hant":
                return "明天上午十點我們開個會，把這次的設計方案過一遍。"
            case "ja":
                return "明日の朝十時から、新しいデザインについて打ち合わせをしましょう。"
            case "ko":
                return "내일 오전 열 시에 만나서 디자인 초안을 같이 확인해 봅시다."
            case "fr":
                return "Retrouvons-nous demain matin pour revoir les notes du projet."
            case "de":
                return "Lass uns morgen früh kurz die Notizen zum Projekt durchgehen."
            case "es":
                return "Reunámonos mañana por la mañana para revisar las notas del proyecto."
            case "pt":
                return "Vamos nos reunir amanhã de manhã para revisar as notas do projeto."
            case "it":
                return "Incontriamoci domani mattina per rivedere le note del progetto."
            default:
                return "Let's meet tomorrow morning to review the project notes."
            }
        }

        var body: some View {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    OnboardingStepHeader(
                        eyebrow: "Step 4 of 5",
                        title: "Try saying something",
                        subtitle: "Press your shortcut to dictate into the box below and confirm everything works."
                    )

                    notepadCard

                    if let firstSuccessPreviewText = viewModel.firstSuccessPreviewText {
                        LinearInlineBanner(
                            systemImage: "checkmark.circle.fill",
                            tint: MacUI.Foreground.success,
                            message: "It worked: \(firstSuccessPreviewText)"
                        )
                    } else if let firstSuccessFailureMessage = viewModel.firstSuccessFailureMessage {
                        LinearInlineBanner(
                            systemImage: "exclamationmark.circle.fill",
                            tint: MacUI.Foreground.error,
                            text: firstSuccessFailureMessage
                        )
                    }
                }
                .padding(.horizontal, OnboardingMetrics.contentHorizontalPadding)
                .padding(.top, 4)
                .padding(.bottom, 16)

                OnboardingFooterBar {
                    OnboardingBackButton {
                        viewModel.retreatOnboarding()
                    }
                } trailing: {
                    if viewModel.canSkipFirstSuccessOnboarding && !viewModel.canContinueFirstSuccessOnboarding {
                        OnboardingSecondaryButton("Skip for now") {
                            viewModel.continueOnboarding()
                        }
                    }

                    OnboardingPrimaryButton(
                        "Continue",
                        isEnabled: viewModel.canContinueFirstSuccessOnboarding
                            || viewModel.canSkipFirstSuccessOnboarding
                    ) {
                        viewModel.continueOnboarding()
                    }
                }
            }
            .onAppear {
                currentShortcut = KeyboardShortcuts.getShortcut(for: HotkeyBinding.dictation.name)
                if draftText.isEmpty, let preview = viewModel.firstSuccessPreviewText {
                    draftText = preview
                }
                DispatchQueue.main.async {
                    isDraftFocused = true
                }
            }
            .onChange(of: viewModel.firstSuccessPreviewText) { _, newValue in
                if let newValue, !newValue.isEmpty, draftText.isEmpty {
                    draftText = newValue
                }
            }
        }

        private var notepadCard: some View {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Try reading aloud")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.4)
                        .textCase(.uppercase)
                        .foregroundStyle(MacUI.LinearSurfaces.mutedInk)

                    Text(verbatim: "“\(sampleSentence)”")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(MacUI.Foreground.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 15)
                .padding(.vertical, 11)
                .background(MacUI.LinearSurfaces.subtleHover)

                LinearHairlineDivider()

                ZStack(alignment: .topLeading) {
                    if draftText.isEmpty {
                        Text("Your spoken words will appear here…")
                            .font(.system(size: 14))
                            .foregroundStyle(MacUI.LinearSurfaces.mutedInk)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .allowsHitTesting(false)
                    }

                    TextField("", text: $draftText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundStyle(MacUI.Foreground.primary)
                        .focused($isDraftFocused)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    isDraftFocused = true
                }

                LinearHairlineDivider()

                HStack(spacing: 8) {
                    Text("Press")
                        .font(.system(size: 12))
                        .foregroundStyle(MacUI.Foreground.secondary)

                    OnboardingCompactHotkeyBadge(shortcut: currentShortcut)

                    Text("and speak naturally")
                        .font(.system(size: 12))
                        .foregroundStyle(MacUI.Foreground.secondary)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(MacUI.LinearSurfaces.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(
                        isDraftFocused ? OnboardingPalette.accentBorder : MacUI.LinearSurfaces.hairline,
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
    }

    #if DEBUG
        #Preview {
            OnboardingFirstSuccessStep(
                viewModel: OnboardingViewModel(coordinator: MockOnboardingCoordinator(step: .firstSuccess))
            )
            .frame(width: OnboardingMetrics.windowWidth, height: 500)
        }
    #endif
#endif
