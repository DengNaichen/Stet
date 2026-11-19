#if os(macOS)
    import AppKit
    import Testing

    @testable import Stet

    @MainActor
    @Suite("Mac Dictation Panel Layout", .serialized)
    struct MacDictationPanelLayoutTests {
        @Test func fixedLayoutUsesExpectedPanelMetrics() {
            let layout = MacDictationPanelLayout.fixed

            #expect(layout.panelSize == CGSize(width: 370, height: 106))
            #expect(layout.bottomInset == 12)
            #expect(layout.scale == 0.66)
        }
    }

    @MainActor
    @Suite("Mac Panel Controller", .serialized)
    struct MacPanelControllerTests {
        @Test func hideDetachesHostedContentAndReattachesOnNextShow() {
            let controller = MacPanelController()
            weak var weakAppModel: MacDictationPanelViewModelTests.StubPanelModel?
            var hideCount = 0
            controller.onHide = { hideCount += 1 }

            autoreleasepool {
                let appModel = MacDictationPanelViewModelTests.StubPanelModel(dictationState: .listening)
                weakAppModel = appModel
                controller.show(appModel: appModel, mode: .transient)
                #expect(controller.hasHostedContent)

                controller.hide()
                #expect(!controller.hasHostedContent)
                #expect(hideCount == 1)
            }

            #expect(weakAppModel == nil)

            let nextModel = MacDictationPanelViewModelTests.StubPanelModel(dictationState: .starting)
            controller.show(appModel: nextModel, mode: .transient)
            #expect(controller.hasHostedContent)

            controller.hide()
            #expect(!controller.hasHostedContent)
            #expect(hideCount == 2)
        }
    }
#endif
