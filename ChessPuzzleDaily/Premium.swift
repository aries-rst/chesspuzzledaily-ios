import Foundation
import StoreKit

// iOS equivalent of Premium.kt — one-time non-consumable purchase ("premium") that removes ads
// (once ads are enabled — see Ads.swift) and unlocks nearby Bluetooth/Wi-Fi multiplayer (see
// NetPlay.swift). Same contract as the Android BillingClient one-time-product flow, built on
// StoreKit 2 instead.
//
// App Store Connect setup required before shipping: Monetize → In-App Purchases → create a
// Non-Consumable product with product id "premium", price tier matching $1.99 — same id as the
// Play Console "premium" one-time product used by all 5 Android games.

enum PremiumProduct {
      static let id = "premium"
}

@MainActor
final class PremiumStore: ObservableObject {
      /// Shared instance so code without a GameController reference (Ads.swift) can read the
      /// entitlement without threading it through every call site.
      static let shared = PremiumStore()

      @Published private(set) var isPremium: Bool
      @Published private(set) var product: Product?
      @Published private(set) var isLoading = false
      @Published private(set) var lastError: String?

      private let d = UserDefaults.standard
      private let key = "cpd_premium"
      private var updatesTask: Task<Void, Never>?

      private init() {
                isPremium = d.bool(forKey: key)
      }

      /// Call once at app launch: starts listening for transaction updates (Ask to Buy approvals,
      /// restores initiated elsewhere) and loads the product + current entitlement.
      func start() {
                guard updatesTask == nil else { return }
                updatesTask = Task {
                              for await update in Transaction.updates {
                                                await self.handle(update)
                              }
                }
                Task {
                              await self.loadProduct()
                              await self.refreshEntitlement()
                }
      }

      private func loadProduct() async {
                isLoading = true
                defer { isLoading = false }
                do {
                              let products = try await Product.products(for: [PremiumProduct.id])
                              product = products.first
                } catch {
                              lastError = error.localizedDescription
                }
      }

      /// Re-checks StoreKit's own current-entitlements list (the source of truth) and syncs the
      /// cached flag used for the instant `isPremium` reads elsewhere in the app.
      func refreshEntitlement() async {
                var owned = false
                for await result in Transaction.currentEntitlements {
                              if case .verified(let t) = result, t.productID == PremiumProduct.id, t.revocationDate == nil {
                                                owned = true
                              }
                }
                setPremium(owned)
      }

      func purchase() async {
                guard let product else { await loadProduct(); return }
                isLoading = true
                defer { isLoading = false }
                do {
                              let result = try await product.purchase()
                              switch result {
                                            case .success(let verification):
                                                await handle(verification)
                                            case .userCancelled, .pending:
                                                break
                                            @unknown default:
                                                break
                              }
                } catch {
                              lastError = error.localizedDescription
                }
      }

      /// "Restore Purchases" — required by App Review for any non-consumable IAP.
      func restore() async {
                isLoading = true
                defer { isLoading = false }
                try? await AppStore.sync()
                await refreshEntitlement()
      }

      private func handle(_ result: VerificationResult<Transaction>) async {
                guard case .verified(let transaction) = result, transaction.productID == PremiumProduct.id else { return }
                setPremium(transaction.revocationDate == nil)
                await transaction.finish()
      }

      private func setPremium(_ v: Bool) {
                isPremium = v
                d.set(v, forKey: key)
      }

      var priceText: String { product?.displayPrice ?? "$1.99" }
}
