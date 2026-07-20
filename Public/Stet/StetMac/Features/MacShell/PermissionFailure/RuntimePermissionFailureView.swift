#if os(macOS)
    import Combine
    import SwiftUI

    struct RuntimePermissionFailureView: View {
        @ObservedObject var viewModel: RuntimePermissionFailureViewModel
        let onDismiss: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("Permissions Required")
                    .font(.title3.weight(.semibold))

                Text(viewModel.messageText)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 10) {
                    Button(viewModel.microphoneButtonTitle) {
                        viewModel.resolveMicrophoneAccess()
                    }

                    Button(viewModel.inputControlButtonTitle) {
                        viewModel.requestInputControlAccess()
                    }
                }
            }
            .padding(24)
            .frame(width: 420)
            .onReceive(viewModel.$shouldDismiss.removeDuplicates()) { shouldDismiss in
                if shouldDismiss {
                    onDismiss()
                }
            }
        }
    }
#endif
