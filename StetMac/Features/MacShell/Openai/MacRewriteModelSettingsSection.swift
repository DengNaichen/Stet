#if os(macOS)
    import StetAI
    import StetCore
    import SwiftUI

    struct MacRewriteModelSettingsSection: View {
        @ObservedObject var viewModel: MacOpenAISettingsViewModel

        var body: some View {
            Section {
                VStack(alignment: .leading, spacing: MacUI.SettingsViewMetrics.cardContentSpacing) {
                    Toggle(
                        NSLocalizedString("Transcript improvement", comment: ""), isOn: $viewModel.isRewriteEnabled)

                    Text(
                        NSLocalizedString(
                            "Stet can refine and improve the precision of your transcriptions using AI.",
                            comment: "")
                    )
                    .font(MacUI.Typography.detail)
                    .foregroundStyle(MacUI.Foreground.secondary)

                    if viewModel.isRewriteEnabled {
                        Divider().padding(.vertical, MacUI.SettingsViewMetrics.dividerVerticalPadding)

                        MacSettingsValueRow(title: NSLocalizedString("Refine Model", comment: "")) {
                            Picker("", selection: $viewModel.unifiedProvider) {
                                ForEach(MacOpenAISettingsViewModel.UnifiedAIProvider.allCases) { provider in
                                    Text(
                                        provider.isDisabled
                                            ? "\(provider.displayName) (Unavailable)" : provider.displayName
                                    )
                                    .tag(provider)
                                    .disabled(provider.isDisabled)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: MacUI.SettingsViewMetrics.controlWidth, alignment: .trailing)
                        }

                        if !viewModel.availableModels.isEmpty {
                            MacSettingsValueRow(title: NSLocalizedString("Preferred Model", comment: "")) {
                                Picker(
                                    "",
                                    selection: Binding(
                                        get: { viewModel.selectedModelID },
                                        set: { viewModel.selectModel($0) }
                                    )
                                ) {
                                    ForEach(viewModel.availableModels) { model in
                                        Text(model.displayName).tag(model.id)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(width: MacUI.SettingsViewMetrics.controlWidth, alignment: .trailing)
                            }
                        }

                        if !viewModel.availableThinkingLevels.isEmpty {
                            MacSettingsValueRow(title: "Thinking Level") {
                                Picker("", selection: $viewModel.selectedThinkingLevel) {
                                    ForEach(viewModel.availableThinkingLevels, id: \.self) { level in
                                        Text(level.displayName).tag(level)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(width: MacUI.SettingsViewMetrics.controlWidth, alignment: .trailing)
                            }
                        }

                        MacModelCatalogUpdateControls(
                            refreshState: viewModel.catalogRefreshState,
                            revision: viewModel.catalogRevision
                        ) {
                            Task { await viewModel.refreshModelCatalog() }
                        }
                    }
                }
            } header: {
                Text(NSLocalizedString("Refine", comment: ""))
            }
        }
    }
#endif
