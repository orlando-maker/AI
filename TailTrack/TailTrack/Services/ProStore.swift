import Foundation
import StoreKit
import Observation

/// TailTrack Pro entitlement + purchases, built on StoreKit 2.
/// Products are configured in App Store Connect (and TailTrack.storekit
/// for local testing).
@Observable
@MainActor
final class ProStore {

    enum ProductID {
        static let monthly = "com.orlandonell.tailtrack.pro.monthly"
        static let yearly = "com.orlandonell.tailtrack.pro.yearly"
        static let lifetime = "com.orlandonell.tailtrack.pro.lifetime"
        static let all: Set<String> = [monthly, yearly, lifetime]
    }

    private(set) var products: [Product] = []
    private(set) var isPro = false
    private(set) var purchaseError: String?
    private(set) var isLoading = false

    #if DEBUG
    /// Simulator/local override so Pro screens can be exercised without
    /// a StoreKit configuration.
    var debugProOverride = false {
        didSet {
            if debugProOverride {
                isPro = true
            } else {
                Task { [weak self] in await self?.refreshEntitlement() }
            }
        }
    }
    #endif

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                    await self?.refreshEntitlement()
                }
            }
        }
        Task { [weak self] in
            await self?.loadProducts()
            await self?.refreshEntitlement()
        }
    }

    func loadProducts() async {
        guard products.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            products = try await Product.products(for: ProductID.all)
                .sorted { $0.price < $1.price }
        } catch {
            purchaseError = "Couldn't load products: \(error.localizedDescription)"
        }
    }

    func refreshEntitlement() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.revocationDate == nil,
               ProductID.all.contains(transaction.productID) {
                entitled = true
            }
        }
        #if DEBUG
        if debugProOverride { entitled = true }
        #endif
        isPro = entitled
    }

    func purchase(_ product: Product) async {
        purchaseError = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refreshEntitlement()
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func restorePurchases() async {
        purchaseError = nil
        do {
            try await AppStore.sync()
        } catch {
            purchaseError = error.localizedDescription
        }
        await refreshEntitlement()
    }
}
