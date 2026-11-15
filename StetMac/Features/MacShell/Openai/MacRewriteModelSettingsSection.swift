#if os(macOS)
    import StetAI
    import StetCore
    import SwiftUI

    struct MacRewriteModelSettingsSection: View {
        @ObservedObject var viewModel: MacOpenAISettingsViewModel

        var body: some View {
            LinearSectionGroup("Refine") {
                LinearSettingRow(
                    "Transcript improvement",
                    subtitle: "Stet can refine and improve the precision of your transcriptions using AI."
                ) {
                    Toggle("", isOn: $viewModel.isRewriteEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(MacUI.LinearBrand.accent)
                }

                if viewModel.isRewriteEnabled {
                    LinearSettingRow("Refine Model") {
                        Picker("", selection: $viewModel.unifiedProvider) {
                            ForEach(MacOpenAISettingsViewModel.UnifiedAIProvider.allCases) { provider in
                                Group {
                                    if provider.isDisabled {
                                        Text("\(Text(LocalizedStringKey(provider.displayName))) (Unavailable)")
                                    } else {
                                        Text(LocalizedStringKey(provider.displayName))
                                    }
                                }
                                .tag(provider)
                                .disabled(provider.isDisabled)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: MacUI.LinearMetrics.pickerWidth, alignment: .trailing)
                    }

                    if !viewModel.availableModels.isEmpty {
                        LinearSettingRow("Preferred Model") {
                            Picker(
                                "",
                                selection: Binding(
                                    get: { viewModel.selectedModelID },
                                    set: { viewModel.selectModel($0) }
                                )
                            ) {
                                ForEach(viewModel.availableModels) { model in
                                    Text(verbatim: model.displayName).tag(model.id)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: MacUI.LinearMetrics.pickerWidth, alignment: .trailing)
                        }
                    }

                    if !viewModel.availableThinkingLevels.isEmpty {
                        LinearSettingRow("Thinking Level") {
                            Picker("", selection: $viewModel.selectedThinkingLevel) {
                                ForEach(viewModel.availableThinkingLevels, id: \.self) { level in
                                    Text(LocalizedStringKey(level.displayName)).tag(level)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: MacUI.LinearMetrics.pickerWidth, alignment: .trailing)
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
        }
    }
#endif
