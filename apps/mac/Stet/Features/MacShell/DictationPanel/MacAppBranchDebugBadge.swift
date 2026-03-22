#if os(macOS)
import SwiftUI

struct MacAppBranchDebugBadge: View {
    let appInfo: AppInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("AppBranch")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
                .textCase(.uppercase)

            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.96))
                .lineLimit(1)

            Text(subtitle)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: 176, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.black.opacity(0.34))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.10), lineWidth: 0.5)
                }
        }
    }

    private var title: String {
        appInfo?.localizedName ?? "No target app"
    }

    private var subtitle: String {
        appInfo?.bundleIdentifier ?? "Click another app to test"
    }
}
#endif
