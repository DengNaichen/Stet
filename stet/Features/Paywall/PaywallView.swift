#if os(macOS)
    import SwiftUI

    struct PaywallView: View {
        @ObservedObject private var purchaseStore = PurchaseStore.shared
        var onDismiss: () -> Void

        var body: some View {
            VStack(spacing: 32) {
                VStack(spacing: 8) {
                    Text("Your free trial is complete")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))

                    Text(
                        "You've used all \(TrialStore.freeLimit) free transcriptions.\nUnlock Stet to keep going."
                    )
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    #if APP_STORE
                        if let error = purchaseStore.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        Button {
                            Task { await purchaseStore.purchase() }
                        } label: {
                            Text(purchaseStore.isPurchasing ? "Processing..." : "Unlock Stet")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(purchaseStore.isPurchasing)

                        Button("Restore Purchase") {
                            Task { await purchaseStore.restore() }
                        }
                        .buttonStyle(.plain)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .disabled(purchaseStore.isPurchasing)
                    #endif
                }
            }
            .padding(44)
            .frame(width: 380)
            .onChange(of: purchaseStore.isUnlocked) { _, unlocked in
                if unlocked { onDismiss() }
            }
        }
    }
#endif
