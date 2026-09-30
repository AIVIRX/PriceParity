import Foundation

enum DemoModeData {
    static let apps: [ASCAppSummary] = [
        ASCAppSummary(
            id: "demo.priceparity",
            name: "Price Parity Demo",
            bundleID: "com.demo.priceparity.demo",
            iconURL: nil,
            subscriptionCount: 2,
            iapCount: 1
        ),
        ASCAppSummary(
            id: "demo.stringcat",
            name: "String Catalog - Translate",
            bundleID: "com.demo.stringcat",
            iconURL: nil,
            subscriptionCount: 1,
            iapCount: 1
        ),
        ASCAppSummary(
            id: "demo.dockui",
            name: "DockUI - Design For SwiftUI",
            bundleID: "com.demo.dockui",
            iconURL: nil,
            subscriptionCount: 1,
            iapCount: 0
        )
    ]

    static func catalog(for appID: String) -> AppMonetizationCatalog {
        switch appID {
        case "demo.priceparity":
            return AppMonetizationCatalog(
                subscriptions: [
                    AppMonetizationProduct(
                        id: "demo.priceparity.monthly",
                        referenceName: "Pro Monthly",
                        productID: "com.demo.priceparity.pro.monthly",
                        kind: .subscription,
                        state: .approved
                    ),
                    AppMonetizationProduct(
                        id: "demo.priceparity.yearly",
                        referenceName: "Pro Yearly",
                        productID: "com.demo.priceparity.pro.yearly",
                        kind: .subscription,
                        state: .approved
                    )
                ],
                inAppPurchases: [
                    AppMonetizationProduct(
                        id: "demo.priceparity.lifetime",
                        referenceName: "Lifetime Unlock",
                        productID: "com.demo.priceparity.lifetime",
                        kind: .inAppPurchase,
                        state: .approved
                    )
                ]
            )
        case "demo.stringcat":
            return AppMonetizationCatalog(
                subscriptions: [
                    AppMonetizationProduct(
                        id: "demo.stringcat.plus",
                        referenceName: "StringCat Plus",
                        productID: "com.demo.stringcat.plus",
                        kind: .subscription,
                        state: .approved
                    )
                ],
                inAppPurchases: [
                    AppMonetizationProduct(
                        id: "demo.stringcat.tokens",
                        referenceName: "Translation Pack",
                        productID: "com.demo.stringcat.tokens",
                        kind: .inAppPurchase,
                        state: .approved
                    )
                ]
            )
        case "demo.dockui":
            return AppMonetizationCatalog(
                subscriptions: [
                    AppMonetizationProduct(
                        id: "demo.dockui.pro",
                        referenceName: "DockUI Pro",
                        productID: "com.demo.dockui.pro",
                        kind: .subscription,
                        state: .approved
                    )
                ],
                inAppPurchases: []
            )
        default:
            return AppMonetizationCatalog(subscriptions: [], inAppPurchases: [])
        }
    }
}
