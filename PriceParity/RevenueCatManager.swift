import Combine
import Foundation
import RevenueCat

@MainActor
final class RevenueCatManager: ObservableObject {
    @Published var isPremium = false
    @Published var isShowingPaywall = false
    @Published var isRefreshingCustomerInfo = false

    private var didLoadCustomerInfo = false
    private let premiumEntitlementID = "Premium"

    func refreshCustomerInfoIfNeeded() async {
        guard !didLoadCustomerInfo else { return }
        didLoadCustomerInfo = true
        await refreshCustomerInfo()
    }

    func refreshCustomerInfo() async {
        guard !isRefreshingCustomerInfo else { return }
        isRefreshingCustomerInfo = true
        defer { isRefreshingCustomerInfo = false }

        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            isPremium = customerInfo.entitlements.all[premiumEntitlementID]?.isActive == true
        } catch {
            isPremium = false
        }
    }

    func restorePurchases() async {
        guard !isRefreshingCustomerInfo else { return }
        isRefreshingCustomerInfo = true
        defer { isRefreshingCustomerInfo = false }

        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            isPremium = customerInfo.entitlements.all[premiumEntitlementID]?.isActive == true
        } catch {
            isPremium = false
        }
    }

    func presentPaywall() {
        isShowingPaywall = true
    }
}
