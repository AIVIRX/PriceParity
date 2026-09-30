import SwiftUI

struct StoredASCKeyCredentials: Codable {
    let issuerID: String
    let keyID: String
    let privateKeyData: Data
    let privateKeyFileName: String?
}

enum AppListPhase {
    case idle
    case loading
    case loaded
    case failed(String)
}

struct ASCAppSummary: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let bundleID: String?
    let iconURL: URL?
    let subscriptionCount: Int?
    let iapCount: Int?
}

enum PurchaseCatalogPhase {
    case loading
    case loaded
    case failed(String)
}

struct AppMonetizationCatalog {
    let subscriptions: [AppMonetizationProduct]
    let inAppPurchases: [AppMonetizationProduct]
}

struct AppMonetizationProduct: Identifiable, Hashable {
    let id: String
    let referenceName: String
    let productID: String
    let kind: MonetizationKind
    let state: InAppPurchaseState?
}

enum MonetizationKind: String, Hashable {
    case subscription
    case inAppPurchase

    var displayName: String {
        switch self {
        case .subscription: return "Subscription"
        case .inAppPurchase: return "In-App Purchase"
        }
    }
}

struct BigMacIndexEntry: Codable, Hashable {
    let territoryID: String
    let countryName: String
    let currencyCode: String?
    let dateString: String?
    let localPrice: Double?
    let dollarPrice: Double?
    let usdRawIndex: Double?
    let adjustedPrice: Double?
    let gdpPerCapita: Double?

    func customParityMultiplier(relativeTo baseEntry: BigMacIndexEntry) -> Double? {
        let costRatio: Double? = {
            guard let dollarPrice,
                  let baseDollarPrice = baseEntry.dollarPrice,
                  baseDollarPrice > 0 else { return nil }
            return dollarPrice / baseDollarPrice
        }()

        let incomeRatio: Double? = {
            guard let gdpPerCapita,
                  let baseGDPPerCapita = baseEntry.gdpPerCapita,
                  gdpPerCapita > 0,
                  baseGDPPerCapita > 0 else { return nil }
            let normalized = max(0.04, min(gdpPerCapita / baseGDPPerCapita, 4.0))
            if normalized >= 1 {
                return min(pow(normalized, 0.18), 1.18)
            }
            return max(pow(normalized, 0.62), 0.08)
        }()

        if let incomeRatio, let costRatio {
            if incomeRatio < 1, costRatio < 1 {
                return max((incomeRatio * 0.8) + (costRatio * 0.2), 0.08)
            }

            if incomeRatio < costRatio {
                return incomeRatio
            }
            return min((incomeRatio * 0.78) + (costRatio * 0.22), 1.18)
        }

        if let incomeRatio {
            return incomeRatio
        }

        if let costRatio {
            return costRatio
        }

        if let usdRawIndex {
            return 1 + (usdRawIndex / 100)
        }

        return nil
    }
}
