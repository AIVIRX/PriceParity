//
//  PriceParityApp.swift
//  PriceParity
//
//  Created by Maicol Cabreja on 6/20/26.
//

import RevenueCat
import SwiftUI

@main
struct PriceParityApp: App {
    @StateObject private var revenueCat = RevenueCatManager()

    init() {
        Purchases.configure(withAPIKey: "appl_xovoGNnTksBwksLZxdCPImYKJXF")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(revenueCat)
        }
    }
}
