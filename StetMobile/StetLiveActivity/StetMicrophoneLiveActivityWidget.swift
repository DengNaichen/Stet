import ActivityKit
import SwiftUI
import WidgetKit

struct StetMicrophoneLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StetMicrophoneActivityAttributes.self) { context in
            StetMicrophoneMarkView(isActive: context.state.isMicrophoneActive, size: CGSize(width: 44, height: 32))
                .frame(maxWidth: .infinity, minHeight: 52)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    StetMicrophoneMarkView(
                        isActive: context.state.isMicrophoneActive,
                        size: CGSize(width: 44, height: 32)
                    )
                }
            } compactLeading: {
                StetMicrophoneMarkView(
                    isActive: context.state.isMicrophoneActive,
                    size: CGSize(width: 22, height: 16)
                )
            } compactTrailing: {
                EmptyView()
            } minimal: {
                StetMicrophoneMarkView(
                    isActive: context.state.isMicrophoneActive,
                    size: CGSize(width: 22, height: 16)
                )
            }
        }
    }
}

private struct StetMicrophoneMarkView: View {
    let isActive: Bool
    let size: CGSize

    var body: some View {
        Image("StetMark")
            .resizable()
            .scaledToFit()
            .frame(width: size.width, height: size.height)
            .opacity(isActive ? 1 : 0.45)
            .accessibilityLabel("Stet microphone active")
    }
}

#if DEBUG
    private let previewAttributes = StetMicrophoneActivityAttributes()
    private let previewState = StetMicrophoneActivityAttributes.ContentState(isMicrophoneActive: true)

    #Preview("Lock Screen", as: .content, using: previewAttributes) {
        StetMicrophoneLiveActivityWidget()
    } contentStates: {
        previewState
    }

    #Preview("Dynamic Island Compact", as: .dynamicIsland(.compact), using: previewAttributes) {
        StetMicrophoneLiveActivityWidget()
    } contentStates: {
        previewState
    }

    #Preview("Dynamic Island Minimal", as: .dynamicIsland(.minimal), using: previewAttributes) {
        StetMicrophoneLiveActivityWidget()
    } contentStates: {
        previewState
    }

    #Preview("Dynamic Island Expanded", as: .dynamicIsland(.expanded), using: previewAttributes) {
        StetMicrophoneLiveActivityWidget()
    } contentStates: {
        previewState
    }
#endif
