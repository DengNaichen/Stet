#if os(macOS)
    import Foundation
    import Testing

    @testable import Stet

    @MainActor
    @Suite("Mac Settings Navigation", .serialized)
    struct MacSettingsNavigationTests {
        @Test func mainSidebarHasExactlyFourWorkspaceTabsWithoutAppearance() {
            #expect(MacMainTab.allCases == [.overview, .history, .dictionary, .meetings])
            #expect(!MacMainTab.allCases.map(\.rawValue).contains("appearance"))
        }

        @Test func settingsSectionsAndTabsMatchConvergedArchitecture() {
            #expect(MacSettingsSection.allCases == [.app, .dictation, .advanced])

            let appTabs = MacSettingsTab.allCases.filter { $0.section == .app }
            let dictationTabs = MacSettingsTab.allCases.filter { $0.section == .dictation }
            let advancedTabs = MacSettingsTab.allCases.filter { $0.section == .advanced }

            #expect(appTabs == [.general, .appearance])
            #expect(dictationTabs == [.dictation, .microphone, .speechAndRefine])
            #if DEBUG
                #expect(advancedTabs == [.mcp, .shaderDebug])
            #else
                #expect(advancedTabs == [.mcp])
            #endif
        }

        @Test func settingsFilterMatchesLegacyTabNamesAndTaskWordsWithSectionHints() {
            let state = MacSettingsNavigationState()

            state.searchQuery = "paste"
            #expect(state.filteredTabs == [.dictation])
            #expect(state.activeTab == .dictation)
            #expect(MacSettingsTab.dictation.matchedSectionHint(for: "paste") == "Pasting & App Compatibility")
            #expect(state.effectiveTargetSection == .pastingCompatibility)

            state.searchQuery = "clipboard"
            #expect(state.filteredTabs == [.dictation])
            #expect(state.effectiveTargetSection == .pastingCompatibility)

            state.searchQuery = "shortcut"
            #expect(state.filteredTabs == [.dictation])
            #expect(MacSettingsTab.dictation.matchedSectionHint(for: "shortcut") == "Shortcuts")
            #expect(state.effectiveTargetSection == .shortcuts)

            state.searchQuery = "capsule"
            #expect(state.filteredTabs == [.appearance])
            #expect(state.activeTab == .appearance)
            #expect(MacSettingsTab.appearance.matchedSectionHint(for: "capsule") == "Dictation Indicator")
            #expect(state.effectiveTargetSection == .dictationIndicator)

            state.searchQuery = "transcription"
            #expect(state.filteredTabs == [.speechAndRefine])
            #expect(state.activeTab == .speechAndRefine)
            #expect(
                MacSettingsTab.speechAndRefine.matchedSectionHint(for: "transcription") == "On-Device Transcription"
            )
            #expect(state.effectiveTargetSection == .onDeviceTranscription)

            state.searchQuery = "refine"
            #expect(state.filteredTabs == [.speechAndRefine])
            #expect(MacSettingsTab.speechAndRefine.matchedSectionHint(for: "refine") == "AI Refine")
            #expect(state.effectiveTargetSection == .aiRefine)

            state.searchQuery = "deepseek"
            #expect(state.filteredTabs == [.speechAndRefine])
            #expect(state.effectiveTargetSection == .aiRefine)
        }

        @Test func settingsFilterSupportsMultiWordAndMatching() {
            let state = MacSettingsNavigationState()

            state.searchQuery = "paste compatibility"
            #expect(state.filteredTabs == [.dictation])
            #expect(state.effectiveTargetSection == .pastingCompatibility)

            state.searchQuery = "cloud refine"
            #expect(state.filteredTabs == [.speechAndRefine])
            #expect(state.effectiveTargetSection == .aiRefine)

            state.searchQuery = "meeting shortcut"
            #expect(state.filteredTabs == [.dictation])
            #expect(state.effectiveTargetSection == .shortcuts)
        }

        @Test func zeroMatchFilterPreservesCurrentSelectedTabAndClearsCleanly() {
            let state = MacSettingsNavigationState()
            state.selectTab(.microphone)
            #expect(state.activeTab == .microphone)

            state.searchQuery = "stetuxnomatch"
            #expect(state.filteredTabs.isEmpty)
            #expect(state.activeTab == .microphone)

            state.clearFilter()
            #expect(state.searchQuery.isEmpty)
            #expect(state.filteredTabs == state.visibleTabs)
            #expect(state.activeTab == .microphone)
        }

        @Test func zeroMatchAfterFilteredAutoSwitchRetainsLastVisibleTabAndClearRestoresSelection() {
            let state = MacSettingsNavigationState()
            #expect(state.selectedTab == .general)
            #expect(state.activeTab == .general)

            // Filtering from General to "paste" automatically displays Dictation.
            state.searchQuery = "paste"
            #expect(state.filteredTabs == [.dictation])
            #expect(state.activeTab == .dictation)
            #expect(state.selectedTab == .general)

            // Continuing to type into a zero-match query must keep Dictation visible instead of jumping to General.
            state.searchQuery = "pastexyz"
            #expect(state.filteredTabs.isEmpty)
            #expect(state.activeTab == .dictation)

            // Clearing an uncommitted filter deterministically restores the last explicitly selected tab (General).
            state.clearFilter()
            #expect(state.searchQuery.isEmpty)
            #expect(state.activeTab == .general)

            // If the user explicitly selects the filtered tab before hitting zero results, clearing keeps it.
            state.searchQuery = "paste"
            state.selectTab(.dictation)
            state.searchQuery = "pastexyz"
            #expect(state.filteredTabs.isEmpty)
            #expect(state.activeTab == .dictation)

            state.clearFilter()
            #expect(state.activeTab == .dictation)
        }

        @Test func mainNavigationPreservesLastSettingsTabAndSupportsMeetingsShortcutDeepLink() {
            let nav = MacMainNavigationState()
            #expect(nav.selectedTab == .overview)
            #expect(!nav.showingSettings)

            // Cmd+, opens Settings on General initially.
            nav.openSettings()
            #expect(nav.showingSettings)
            #expect(nav.settingsNavState.activeTab == .general)

            // Switch to Appearance, return to app, reopen Settings -> stays on Appearance.
            nav.settingsNavState.selectTab(.appearance)
            nav.backToApp()
            #expect(!nav.showingSettings)
            #expect(nav.selectedTab == .overview)

            nav.openSettings()
            #expect(nav.showingSettings)
            #expect(nav.settingsNavState.activeTab == .appearance)
            nav.backToApp()

            // Navigate to Meetings, trigger Change Shortcut… deep link even with stale filter.
            nav.selectedTab = .meetings
            nav.settingsNavState.searchQuery = "stetuxnomatch"
            nav.openSettings(to: .dictation, section: .shortcuts)
            #expect(nav.showingSettings)
            #expect(nav.settingsNavState.searchQuery.isEmpty)
            #expect(nav.settingsNavState.activeTab == .dictation)
            #expect(nav.settingsNavState.effectiveTargetSection == .shortcuts)

            // Back to app returns to Meetings.
            nav.backToApp()
            #expect(!nav.showingSettings)
            #expect(nav.selectedTab == .meetings)
        }

        @Test func speechAndRefineDataFlowNoticeReflectsActualModeWithoutOverclaiming() {
            let offNotice = MacSpeechRefineDataFlowNotice.make(
                isRewriteEnabled: false,
                provider: .openAI,
                selectedModelDisplayName: "GPT-4.1 Mini",
                customBaseURL: "",
                connectionNeedsAttention: true
            )
            #expect(offNotice.systemImage == "lock.shield")
            #expect(offNotice.tone == .neutral)
            #expect(offNotice.missingConfigWarning == nil)
            #expect(offNotice.message.contains("does not send transcripts"))

            let appleNotice = MacSpeechRefineDataFlowNotice.make(
                isRewriteEnabled: true,
                provider: .appleIntelligence,
                selectedModelDisplayName: nil,
                customBaseURL: "",
                connectionNeedsAttention: false
            )
            #expect(appleNotice.systemImage == "apple.intelligence")
            #expect(appleNotice.tone == .neutral)
            #expect(appleNotice.missingConfigWarning == nil)

            let cloudUnconfigured = MacSpeechRefineDataFlowNotice.make(
                isRewriteEnabled: true,
                provider: .deepSeek,
                selectedModelDisplayName: "DeepSeek V3",
                customBaseURL: "",
                connectionNeedsAttention: true
            )
            #expect(cloudUnconfigured.systemImage == "network")
            #expect(cloudUnconfigured.tone == .network)
            #expect(cloudUnconfigured.message.contains("DeepSeek (DeepSeek V3)"))
            #expect(cloudUnconfigured.message.contains("can include Personal Dictionary terms"))
            #expect(cloudUnconfigured.missingConfigWarning?.contains("DeepSeek API key isn't set") == true)

            let customConfigured = MacSpeechRefineDataFlowNotice.make(
                isRewriteEnabled: true,
                provider: .custom,
                selectedModelDisplayName: nil,
                customBaseURL: "https://llm.example.com/v1",
                connectionNeedsAttention: false
            )
            #expect(customConfigured.message.contains("llm.example.com"))
            #expect(customConfigured.missingConfigWarning == nil)

            let customIncomplete = MacSpeechRefineDataFlowNotice.make(
                isRewriteEnabled: true,
                provider: .custom,
                selectedModelDisplayName: nil,
                customBaseURL: "",
                connectionNeedsAttention: true
            )
            #expect(customIncomplete.message.contains("your configured server"))
            #expect(customIncomplete.missingConfigWarning != nil)
        }
    }
#endif
