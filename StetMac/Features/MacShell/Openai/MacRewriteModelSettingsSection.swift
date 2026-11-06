#if os(macOS)
    import StetAI
    import StetCore
    import SwiftUI

    struct MacRewriteModelSettingsSection: View {
        @ObservedObject var viewModel: MacOpenAISettingsViewModel
        private let controlWidth: CGFloat = 240

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
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                    if viewModel.isRewriteEnabled {
                        Divider().padding(.vertical, 4)

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
                            .frame(width: controlWidth, alignment: .trailing)
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
                                .frame(width: controlWidth, alignment: .trailing)
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
                                .frame(width: controlWidth, alignment: .trailing)
                            }
                        }

                        MacModelCatalogUpdateControls(store: viewModel.catalogStore) {
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
