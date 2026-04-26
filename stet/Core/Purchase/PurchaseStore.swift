#if os(macOS)
    import Combine
    import Foundation

    #if APP_STORE
        import StoreKit
    #endif

    @MainActor
    final class PurchaseStore: ObservableObject {
        static let shared = PurchaseStore()

        #if APP_STORE
            private let productID = "com.stet.unlock"
            private var transactionListener: Task<Void, Never>?
        #endif

        @Published private(set) var isUnlocked: Bool = false
        @Published private(set) var isPurchasing: Bool = false
        @Published private(set) var errorMessage: String?

        init() {
            #if APP_STORE
                transactionListener = listenForTransactions()
                Task { await refreshStatus() }
            #endif
        }

        #if APP_STORE
            deinit {
                transactionListener?.cancel()
            }

            func purchase() async {
                isPurchasing = true
                errorMessage = nil
                defer { isPurchasing = false }
                do {
                    let products = try await Product.products(for: [productID])
                    guard let product = products.first else {
                        errorMessage = "Product unavailable."
                        return
                    }
                    let result = try await product.purchase()
                    switch result {
                    case .success(let verification):
                        let transaction = try verification.payloadValue
                        await transaction.finish()
                        isUnlocked = true
                    case .userCancelled, .pending:
                        break
                    @unknown default:
                        break
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
            }

            func restore() async {
                isPurchasing = true
                errorMessage = nil
                defer { isPurchasing = false }
                do {
                    try await AppStore.sync()
                    await refreshStatus()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }

            private func refreshStatus() async {
                for await result in Transaction.currentEntitlements {
                    if let transaction = try? result.payloadValue,
                        transaction.productID == productID
                    {
                        isUnlocked = true
                        return
                    }
                }
                isUnlocked = false
            }

            private func listenForTransactions() -> Task<Void, Never> {
                Task { [weak self] in
                    for await result in Transaction.updates {
                        guard let self else { return }
                        if let transaction = try? result.payloadValue,
                            transaction.productID == productID
                        {
                            await transaction.finish()
                            isUnlocked = true
                        }
                    }
                }
            }
        #endif
    }
#endif
