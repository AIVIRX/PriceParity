//
//  ContentView.swift
//  PriceParity
//
//  Created by Maicol Cabreja on 6/20/26.
//

import CryptoKit
import RevenueCatUI
import StoreKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    private static let apiKeysURL = URL(string: "https://appstoreconnect.apple.com/access/integrations/api")!

    @AppStorage("appAppearance") private var appAppearance = AppAppearance.system.rawValue
    @StateObject private var viewModel = ContentViewModel()
    @State private var isImportingPrivateKey = false
    @State private var isShowingSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isReady {
                    appsView
                } else {
                    credentialsForm
                }
            }
            .navigationTitle(viewModel.isReady ? "My Apps" : "Price Parity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if viewModel.isDemoMode {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Credentials") {
                            viewModel.exitDemoMode()
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .navigationDestination(item: $viewModel.selectedApp) { app in
                AppDetailView(
                    app: app,
                    issuerID: viewModel.normalizedIssuerID,
                    keyID: viewModel.normalizedKeyID,
                    privateKeyData: viewModel.privateKeyData ?? Data(),
                    bigMacEntries: viewModel.bigMacEntries,
                    isDemoMode: viewModel.isDemoMode
                )
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(
                appearanceSelection: Binding(
                    get: { AppAppearance(rawValue: appAppearance) ?? .system },
                    set: { appAppearance = $0.rawValue }
                ),
                onDeleteData: {
                    viewModel.signOut()
                    isShowingSettings = false
                }
            )
        }
        .preferredColorScheme((AppAppearance(rawValue: appAppearance) ?? .system).colorScheme)
        .task {
            await viewModel.restoreSavedCredentialsIfNeeded()
            viewModel.restoreSavedBigMacDatasetIfNeeded()
        }
        .fileImporter(
            isPresented: $isImportingPrivateKey,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false,
            onCompletion: viewModel.importPrivateKey
        )
        .alert("Couldn’t Import Key", isPresented: importErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.importError ?? "Please choose a valid App Store Connect .p8 key.")
        }
        .alert("Couldn’t Save Credentials", isPresented: saveErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.saveError ?? "Price Parity could not save your App Store Connect credentials securely.")
        }
    }

    private var credentialsForm: some View {
        Form {
            Section {
                Label("Link App Store Connect", systemImage: "storefront")
                    .font(.title2.weight(.semibold))

                Text("Add your API credentials so Price Parity can read your apps, territories, and prices. Create the key with the App Manager role.")
                    .foregroundStyle(.secondary)
                
                Link(destination: Self.apiKeysURL) {
                    Label("Create an API Key", systemImage: "arrow.up.right.square")
                }
            }

            Section {
                credentialFieldRow(
                    title: "Issuer ID",
                    text: issuerIDBinding,
                    accessibilityIdentifier: "issuerIDField",
                    uppercasedPaste: false
                )

                credentialFieldRow(
                    title: "Key ID",
                    text: keyIDBinding,
                    accessibilityIdentifier: "keyIDField",
                    uppercasedPaste: true
                )

                Button {
                    isImportingPrivateKey = true
                } label: {
                    HStack {
                        Label(
                            viewModel.privateKeyFileName ?? "Choose Private Key",
                            systemImage: viewModel.privateKeyData == nil ? "key" : "checkmark.circle.fill"
                        )

                        Spacer()

                        if viewModel.privateKeyData != nil {
                            Text("Selected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityIdentifier("privateKeyPicker")
                
            } header: {
                HStack {
                    Text("API Credentials")
                    Spacer()
                    Button("Clear") {
                        viewModel.signOut()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                    .disabled(
                        viewModel.issuerID.isEmpty
                        && viewModel.keyID.isEmpty
                        && viewModel.privateKeyData == nil
                        && !viewModel.isReady
                    )
                }
            } footer: {
                Text("Choose the downloaded .p8 file here. The Key ID is filled from its filename when available.")
            }

            if !viewModel.issuerID.isEmpty && !viewModel.isValidIssuerID {
                Section {
                    Label("Enter the Issuer ID as a UUID.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button("Continue") {
                    viewModel.persistCredentialsAndContinue()
                }
                .frame(maxWidth: .infinity)
                .disabled(!viewModel.canContinue)
                .accessibilityIdentifier("continueButton")

                Button("Try Demo Mode") {
                    viewModel.enterDemoMode()
                }
                .frame(maxWidth: .infinity)
            } footer: {
                Label("Your private key remains on this device and is not transmitted by this setup screen.", systemImage: "lock.shield")
            }
        }
    }

    @ViewBuilder
    private var appsView: some View {
        switch viewModel.appPhase {
        case .idle, .loading:
            VStack(spacing: 16) {
                Spacer()
                ProgressView("Loading your apps")
                Text("Fetching App Store Connect apps for this key.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loaded:
            ScrollView {
                LazyVStack(spacing: 16) {
                    if viewModel.isDemoMode {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles.rectangle.stack.fill")
                                .foregroundStyle(.blue)

                            Text("You’re in Demo Mode. Tap Credentials to connect your App Store Connect API key.")
                                .font(.callout)
                                .foregroundStyle(.secondary)

                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.secondary.opacity(0.08))
                        )
                    }

                    if viewModel.filteredApps.isEmpty {
                        ContentUnavailableView {
                            Label("No Apps Found", systemImage: "shippingbox")
                        } description: {
                            if viewModel.apps.isEmpty {
                                Text("App Store Connect returned no apps for this team.")
                            } else {
                                Text("No apps matched “\(viewModel.searchText)”.")
                            }
                        } actions: {
                            Button("Refresh") {
                                viewModel.appPhase = .loading
                                Task { await viewModel.loadApps() }
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.top, 24)
                    } else {
                        ForEach(viewModel.filteredApps) { app in
                            Button {
                                viewModel.selectedApp = app
                            } label: {
                                AppSummaryCard(app: app)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .refreshable {
                viewModel.appPhase = .loading
                await viewModel.loadApps()
            }
            .searchable(text: $viewModel.searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search apps")
            .scrollIndicators(.hidden)

        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn’t Load Apps", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    viewModel.appPhase = .loading
                    Task { await viewModel.loadApps() }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var importErrorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.importError != nil },
            set: { if !$0 { viewModel.importError = nil } }
        )
    }

    private var saveErrorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.saveError != nil },
            set: { if !$0 { viewModel.saveError = nil } }
        )
    }

    @ViewBuilder
    private func credentialFieldRow(
        title: String,
        text: Binding<String>,
        accessibilityIdentifier: String,
        uppercasedPaste: Bool
    ) -> some View {
        HStack(spacing: 12) {
            TextField(title, text: text)
                .textInputAutocapitalization(uppercasedPaste ? .characters : .never)
                .autocorrectionDisabled()
                .textContentType(.none)
                .accessibilityIdentifier(accessibilityIdentifier)
        }
    }

    private var issuerIDBinding: Binding<String> {
        Binding(
            get: { viewModel.issuerID },
            set: { newValue in
                viewModel.issuerID = sanitizedCredentialText(newValue, uppercased: false)
            }
        )
    }

    private var keyIDBinding: Binding<String> {
        Binding(
            get: { viewModel.keyID },
            set: { newValue in
                viewModel.keyID = sanitizedCredentialText(newValue, uppercased: true)
            }
        )
    }

    private func sanitizedCredentialText(_ value: String, uppercased: Bool) -> String {
        let filteredScalars = value.unicodeScalars.filter { scalar in
            !CharacterSet.controlCharacters.contains(scalar)
        }
        let cleaned = String(String.UnicodeScalarView(filteredScalars))
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if uppercased {
            return cleaned.uppercased()
        }

        return cleaned
    }
}

private struct AppDetailView: View {
    let app: ASCAppSummary
    let issuerID: String
    let keyID: String
    let privateKeyData: Data
    let bigMacEntries: [BigMacIndexEntry]
    let isDemoMode: Bool
    @State private var catalogPhase: PurchaseCatalogPhase = .loading
    @State private var catalog: AppMonetizationCatalog?
    @State private var selectedSubscription: AppMonetizationProduct?
    @State private var selectedInAppPurchase: AppMonetizationProduct?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                switch catalogPhase {
                case .loading:
                    ProgressView("Loading monetization")
                        .frame(maxWidth: .infinity)

                case .failed(let message):
                    ContentUnavailableView {
                        Label("Couldn’t Load Monetization", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    }

                case .loaded:
                    VStack(spacing: 16) {
                        breakdownSection(
                            title: "Subscriptions",
                            count: catalog?.subscriptions.count ?? app.subscriptionCount ?? 0,
                            items: catalog?.subscriptions ?? []
                        )

                        breakdownSection(
                            title: "In-App Purchases",
                            count: catalog?.inAppPurchases.count ?? app.iapCount ?? 0,
                            items: catalog?.inAppPurchases ?? []
                        )
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle(app.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedSubscription) { subscription in
            SubscriptionPriceParityView(
                appName: app.name,
                appIconURL: app.iconURL,
                subscription: subscription,
                issuerID: issuerID,
                keyID: keyID,
                privateKeyData: privateKeyData,
                bigMacEntries: bigMacEntries,
                isDemoMode: isDemoMode
            )
        }
        .navigationDestination(item: $selectedInAppPurchase) { inAppPurchase in
            SubscriptionPriceParityView(
                appName: app.name,
                appIconURL: app.iconURL,
                subscription: inAppPurchase,
                issuerID: issuerID,
                keyID: keyID,
                privateKeyData: privateKeyData,
                bigMacEntries: bigMacEntries,
                isDemoMode: isDemoMode
            )
        }
        .task(id: app.id) {
            await loadCatalog()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Group {
                if let iconURL = app.iconURL {
                    AsyncImage(url: iconURL) { phase in
                        switch phase {
                        case .empty:
                            placeholderIcon
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            placeholderIcon
                        @unknown default:
                            placeholderIcon
                        }
                    }
                } else {
                    placeholderIcon
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 8) {
                Text(app.name)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)

                Text("App Store Connect dashboard")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.headline)
        }
    }

    @ViewBuilder
    private func breakdownSection(title: String, count: Int, items: [AppMonetizationProduct]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(count)")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            
            if items.isEmpty {
                Text("None found")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 12) {
                    ForEach(items) { item in
                        monetizationCard(for: item)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    @ViewBuilder
    private func monetizationCard(for item: AppMonetizationProduct) -> some View {
        let appearance = monetizationStateAppearance(for: item.state)
        Button {
            if item.kind == .subscription {
                selectedSubscription = item
            } else {
                selectedInAppPurchase = item
            }
        } label: {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: appearance.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(appearance.tint)

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.referenceName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    
                    Text(item.productID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 34, height: 34)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func loadCatalog() async {
        catalogPhase = .loading
        if isDemoMode {
            catalog = DemoModeData.catalog(for: app.id)
            catalogPhase = .loaded
            return
        }
        do {
            catalog = try await AppStoreConnectClient.fetchMonetizationCatalog(
                appID: app.id,
                issuerID: issuerID,
                keyID: keyID,
                privateKeyData: privateKeyData
            )
            catalogPhase = .loaded
        } catch {
            catalogPhase = .failed(error.localizedDescription)
        }
    }

    private var placeholderIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
            Image(systemName: "app.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func monetizationStateAppearance(for state: InAppPurchaseState?) -> MonetizationStateAppearance {
        switch state {
        case .approved:
            return .init(systemImage: "checkmark.circle.fill", tint: .green)
        case .rejected:
            return .init(systemImage: "xmark.square.fill", tint: .red)
        default:
            return .init(systemImage: "clock.fill", tint: .yellow)
        }
    }
}

private struct MonetizationStateAppearance {
    let systemImage: String
    let tint: Color
}

private struct SubscriptionPriceParityView: View {
    @EnvironmentObject private var revenueCat: RevenueCatManager
    let appName: String
    let appIconURL: URL?
    let subscription: AppMonetizationProduct
    let issuerID: String
    let keyID: String
    let privateKeyData: Data
    let bigMacEntries: [BigMacIndexEntry]
    let isDemoMode: Bool

    @State private var phase: SubscriptionPriceParityPhase = .loading
    @State private var pricePoints: [SubscriptionPriceParityPoint] = []
    @State private var overrideRegionID: String?
    @State private var overridePriceTier: String?
    @State private var isShowingOverrideSheet = false
    @State private var isShowingSaveReview = false
    @State private var manualPriceTierByRegion: [String: String] = [:]
    @State private var manualOverrideSelection: ManualOverrideSelection?
    @State private var saveAlertMessage: String?
    @State private var cachedSavePreparation: SubscriptionPriceSavePreparation?
    @State private var cachedFutureScheduledPriceIDsByTerritory: [String: String] = [:]
    @State private var isPreparingSavePreparation = false
    @State private var savePreparationProgress = 0.0
    @State private var savePreparationCompletedCount = 0
    @State private var savePreparationTotalCount = 0
    @State private var savePreparationErrorMessage: String?
    @State private var availableBasePriceTiersByRegion: [String: [String]] = [:]
    @State private var loadingOverridePriceTierRegionIDs = Set<String>()
    @State private var liveExchangeRatesBaseCurrencyCode: String?
    @State private var liveExchangeRatesByCurrencyCode: [String: Double] = [:]

    private var supportsPreserveCurrentPrice: Bool {
        subscription.kind == .subscription
    }

    private var productDisplayName: String {
        subscription.kind.displayName
    }

    private var minimumEffectiveDate: Date {
        switch subscription.kind {
        case .subscription:
            return AppStoreConnectClient.minimumSubscriptionPriceStartDate()
        case .inAppPurchase:
            return Calendar(identifier: .gregorian).startOfDay(for: Date())
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                switch phase {
                case .loading:
                    ProgressView("Loading price parity")
                        .frame(maxWidth: .infinity)

                case .failed(let message):
                    ContentUnavailableView {
                        Label("Couldn’t Load Prices", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    }

                case .loaded:
                    VStack(spacing: 12) {
                        if isPreparingSavePreparation || savePreparationErrorMessage != nil || cachedSavePreparation == nil {
                            savePreparationCard
                        }

                        summaryCard

                        if comparisonPricePoints.isEmpty {
                            Text("No price points found for this \(productDisplayName.lowercased()).")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            VStack(spacing: 12) {
                                ForEach(comparisonPricePoints) { point in
                                    pricePointCard(point)
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Price Parity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isPreparingSavePreparation && cachedSavePreparation == nil {
                    ProgressView()
                } else {
                    Button("Next") {
                        isShowingSaveReview = true
                    }
                    .disabled(!canSavePrices)
                }
            }
        }
        .alert(
            "Saved Prices",
            isPresented: Binding(
                get: { saveAlertMessage != nil },
                set: { if !$0 { saveAlertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                saveAlertMessage = nil
            }
        } message: {
            Text(saveAlertMessage ?? "")
        }
        .sheet(isPresented: $isShowingOverrideSheet) {
            OverridePickerSheet(
                pricePoints: pricePoints,
                availablePriceTiersByRegion: availableBasePriceTiersByRegion,
                loadingRegionIDs: loadingOverridePriceTierRegionIDs,
                selectedRegionID: $overrideRegionID,
                selectedPriceTier: $overridePriceTier,
                onRegionSelectionChanged: { regionID in
                    Task {
                        await loadAvailableBasePriceTiersIfNeeded(for: regionID)
                    }
                }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $manualOverrideSelection) { selection in
            TerritoryPriceAdjustmentSheet(
                    regionID: selection.regionID,
                    regionName: localizedTerritoryName(selection.regionID),
                    regionFlag: countryFlag(for: selection.regionID),
                    currentPriceText: pricePoints.first(where: { $0.territoryID == selection.regionID }).flatMap {
                        localizedPriceText(price: $0.customerPrice, currencyCode: $0.currencyCode)
                    } ?? "—",
                    recommendedPriceText: comparisonPricePoints.first(where: { $0.territoryID == selection.regionID }).flatMap {
                        autoRecommendedPriceText(for: $0)
                    } ?? "—",
                    currencyCode: pricePoints.first(where: { $0.territoryID == selection.regionID })?.currencyCode,
                    availablePriceTiers: regionAvailablePriceTiers(for: selection.regionID),
                    selectedPriceTier: Binding(
                        get: { manualPriceTierByRegion[selection.regionID] },
                        set: { newValue in
                            if let newValue, !newValue.isEmpty {
                                manualPriceTierByRegion[selection.regionID] = newValue
                            } else {
                                manualPriceTierByRegion.removeValue(forKey: selection.regionID)
                            }
                        }
                    ),
                    fallbackRecommendedTier: comparisonPricePoints.first(where: { $0.territoryID == selection.regionID }).flatMap {
                        recommendedPriceTier(for: $0)
                    },
                    isLoadingPriceTiers: loadingOverridePriceTierRegionIDs.contains(selection.regionID)
                )
                .presentationDetents([.height(420), .medium])
        }
        .sheet(isPresented: $revenueCat.isShowingPaywall, onDismiss: {
            Task {
                await revenueCat.refreshCustomerInfo()
            }
        }) {
            PaywallView()
        }
        .navigationDestination(isPresented: $isShowingSaveReview) {
            SubscriptionPriceSaveReviewView(
                subscriptionName: subscription.referenceName,
                subscriptionProductID: subscription.productID,
                appIconURL: appIconURL,
                basePriceText: selectedBasePriceDisplayText,
                baseSubtitle: selectedBasePriceSubtitle,
                items: saveReviewItems,
                supportsPreserveCurrentPrice: supportsPreserveCurrentPrice,
                minimumEffectiveDate: minimumEffectiveDate,
                onPrepare: {
                    try await prepareSaveIfNeeded()
                },
                onSave: { startDate, preserveCurrentPrice, progress in
                    try await savePricesToAppStoreConnect(
                        startDate: startDate,
                        preserveCurrentPrice: preserveCurrentPrice,
                        progress: progress
                    )
                }
            )
        }
        .task(id: subscription.id) {
            await loadPriceParity()
        }
        .task(id: selectedReferenceCurrencyCode) {
            await loadLiveExchangeRatesIfNeeded(for: selectedReferenceCurrencyCode)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                Group {
                    if let appIconURL {
                        AsyncImage(url: appIconURL) { phase in
                            switch phase {
                            case .empty:
                                priceParityPlaceholderIcon
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure:
                                priceParityPlaceholderIcon
                            @unknown default:
                                priceParityPlaceholderIcon
                            }
                        }
                    } else {
                        priceParityPlaceholderIcon
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    Text(subscription.referenceName)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)

                    Text(productDisplayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(subscription.productID)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.secondary.opacity(0.10))
                        )
                }

                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.secondary.opacity(0.10),
                            Color.secondary.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }

    private var priceParityPlaceholderIcon: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.blue.opacity(0.22),
                        Color.cyan.opacity(0.14)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.blue)
            }
    }

    private var summaryCard: some View {
        let basePoint = preferredBasePricePoint(from: pricePoints)
        let selectedRegionPoint = overrideRegionID.flatMap { regionID in
            pricePoints.first(where: { $0.territoryID == regionID })
        }
        let currencyCode = selectedRegionPoint?.currencyCode ?? basePoint?.currencyCode
        let selectedPriceText = formattedOverridePriceText(overridePriceTier, currencyCode: currencyCode) ?? preferredBasePricePoint(from: pricePoints).flatMap { localizedPriceText(price: $0.customerPrice, currencyCode: $0.currencyCode) } ?? "—"
        let baseSubtitle: String = {
            guard let regionID = overrideRegionID ?? basePoint?.territoryID else {
                return "No territory data"
            }
            return localizedTerritoryName(regionID) + " • " + (currencyCode ?? "—")
        }()

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.blue.opacity(0.18))
                    .overlay {
                        Image(systemName: "dollarsign.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.blue)
                    }
                    .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Base price")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(selectedPriceText)
                        .font(.headline)

                    Text(baseSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
                
                    Button {
                        if overrideRegionID == nil {
                            overrideRegionID = basePoint?.territoryID
                        }
                        if overridePriceTier == nil {
                            overridePriceTier = basePoint?.customerPrice ?? "4.99"
                        }
                        isShowingOverrideSheet = true
                        Task {
                            await loadAvailableBasePriceTiersIfNeeded(for: overrideRegionID ?? basePoint?.territoryID)
                        }
                    } label: {
                       Image(systemName: "pencil")
                            .font(.body.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.secondary.opacity(0.14))
                            )
                    }
                    .buttonStyle(.plain)
                
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private var comparisonPricePoints: [SubscriptionPriceParityPoint] {
        pricePoints
    }

    private var canSavePrices: Bool {
        if case .loaded = phase {
            return selectedOverridePriceValue != nil
                && !saveReviewItems.isEmpty
                && cachedSavePreparation != nil
                && !isPreparingSavePreparation
        }
        return false
    }

    private var isSavePreparationReady: Bool {
        cachedSavePreparation != nil && !isPreparingSavePreparation
    }

    private var savePreparationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: savePreparationErrorMessage == nil ? "arrow.triangle.2.circlepath.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(savePreparationErrorMessage == nil ? .blue : .orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text(savePreparationErrorMessage == nil ? "Loading Apple price points" : "Couldn’t load Apple price points")
                        .font(.subheadline.weight(.semibold))

                    Text(
                        savePreparationErrorMessage
                        ?? "We’re preloading App Store Connect price points here so the save screen opens faster."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if savePreparationErrorMessage == nil, savePreparationTotalCount > 0 {
                        Text("\(savePreparationCompletedCount) of \(savePreparationTotalCount) regions loaded")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                if savePreparationErrorMessage != nil {
                    Button("Retry") {
                        Task {
                            await warmSavePreparation(forceRefresh: true)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                }
            }

            ProgressView(value: savePreparationProgress, total: 1)
                .tint(savePreparationErrorMessage == nil ? .blue : .orange)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private var selectedBasePriceDisplayText: String {
        let basePoint = preferredBasePricePoint(from: pricePoints)
        let selectedRegionPoint = overrideRegionID.flatMap { regionID in
            pricePoints.first(where: { $0.territoryID == regionID })
        }
        let currencyCode = selectedRegionPoint?.currencyCode ?? basePoint?.currencyCode
        return formattedOverridePriceText(overridePriceTier, currencyCode: currencyCode)
            ?? preferredBasePricePoint(from: pricePoints).flatMap {
                localizedPriceText(price: $0.customerPrice, currencyCode: $0.currencyCode)
            }
            ?? "—"
    }

    private var selectedBasePriceSubtitle: String {
        let basePoint = preferredBasePricePoint(from: pricePoints)
        let selectedRegionPoint = overrideRegionID.flatMap { regionID in
            pricePoints.first(where: { $0.territoryID == regionID })
        }
        let currencyCode = selectedRegionPoint?.currencyCode ?? basePoint?.currencyCode
        guard let regionID = overrideRegionID ?? basePoint?.territoryID else {
            return "No territory data"
        }
        return localizedTerritoryName(regionID) + " • " + (currencyCode ?? "—")
    }

    private var pendingSaveTargets: [SubscriptionPriceSaveTarget] {
        comparisonPricePoints.compactMap { point in
            if let resolvedPricePoint = resolvedSelectablePricePoint(for: point) {
                return SubscriptionPriceSaveTarget(
                    territoryID: point.territoryID,
                    desiredPrice: resolvedPricePoint.customerPrice,
                    currentPrice: Double(point.customerPrice ?? ""),
                    subscriptionPricePointID: resolvedPricePoint.id
                )
            }

            guard let recommendedPrice = finalLocalPriceValue(for: point) else { return nil }
            return SubscriptionPriceSaveTarget(
                territoryID: point.territoryID,
                desiredPrice: recommendedPrice,
                currentPrice: Double(point.customerPrice ?? ""),
                subscriptionPricePointID: nil
            )
        }
    }

    private var saveReviewItems: [SubscriptionPriceReviewItem] {
        comparisonPricePoints.compactMap { point in
            guard let recommendedPrice = finalLocalPriceValue(for: point) else { return nil }
            let newPriceText = localizedPriceString(
                price: String(format: "%.2f", recommendedPrice),
                currencyCode: point.currencyCode
            ) ?? "—"
            let currentPriceText = localizedPriceString(
                price: point.customerPrice,
                currencyCode: point.currencyCode
            ) ?? "—"

            return SubscriptionPriceReviewItem(
                territoryID: point.territoryID,
                territoryName: localizedTerritoryName(point.territoryID),
                flag: countryFlag(for: point.territoryID),
                currentPriceText: currentPriceText,
                newPriceText: newPriceText,
                source: paritySource(for: point)
            )
        }
    }

    private func pricePointCard(_ point: SubscriptionPriceParityPoint) -> some View {
        let newPriceText = recommendedPriceText(for: point)
        let displayIndexText = displayIndexText(for: point)
        let isReady = isSavePreparationReady

        return HStack(alignment: .center, spacing: 14) {
            Text(countryFlag(for: point.territoryID))
                .font(.system(size: 28))
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(localizedTerritoryName(point.territoryID))
                        .font(.subheadline.weight(.semibold))

//                    Text(source.label)
//                        .font(.caption2.weight(.semibold))
//                        .foregroundStyle(source.foregroundColor)
//                        .padding(.horizontal, 8)
//                        .padding(.vertical, 4)
//                        .background(
//                            Capsule(style: .continuous)
//                                .fill(source.backgroundColor)
//                        )
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 8) {
                Button {
                    if isReady {
                        if revenueCat.isPremium {
                            manualOverrideSelection = .init(regionID: point.territoryID)
                            Task {
                                await loadAvailableBasePriceTiersIfNeeded(for: point.territoryID)
                            }
                        } else {
                            revenueCat.presentPaywall()
                        }
                    }
                } label: {
                    VStack(alignment: .trailing, spacing: 4) {
                        if isReady, let displayIndexText {
                            Text("\(displayIndexText)")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("-")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        Text(isReady ? (newPriceText ?? "—") : "—")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(isReady ? .primary : .secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.secondary.opacity(0.10))
                    )
                    .opacity(isReady ? 1 : 0.55)
                }
                .buttonStyle(.plain)
                .disabled(!isReady)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private func localizedPriceText(price: String?, currencyCode: String?) -> String? {
        localizedPriceString(price: price, currencyCode: currencyCode)
    }

    private func localizedTerritoryName(_ territoryID: String) -> String {
        localizedTerritoryDisplayName(territoryID)
    }

    private func countryFlag(for territoryID: String) -> String {
        countryFlagString(for: territoryID)
    }

    private func paritySource(for point: SubscriptionPriceParityPoint) -> PriceParitySource {
        let normalizedTerritoryID = point.territoryID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        if bigMacEntries.contains(where: { $0.territoryID == normalizedTerritoryID }) {
            return .bigMac
        }

        if fallbackParityMultiplier(for: normalizedTerritoryID) != nil {
            return .fallback
        }

        return .defaulted
    }

    private func formattedOverridePriceText(_ value: String?, currencyCode: String?) -> String? {
        localizedPriceString(price: value, currencyCode: currencyCode)
    }

    private func rawRecommendedPriceValue(for point: SubscriptionPriceParityPoint) -> Double? {
        guard let overridePrice = selectedOverridePriceValue,
              let indexValue = countryIndexMultiplier(for: point) else {
            return nil
        }

        return max(overridePrice * indexValue, minimumEquivalentPriceFloor)
    }

    private var minimumEquivalentPriceFloor: Double {
        0.99
    }

    private func recommendedPriceValue(for point: SubscriptionPriceParityPoint) -> Double? {
        manualEquivalentPriceValue(for: point) ?? rawRecommendedPriceValue(for: point)
    }

    private func recommendedComparablePriceValue(for point: SubscriptionPriceParityPoint) -> Double? {
        guard let baseComparablePrice = selectedOverrideComparablePriceValue,
              let indexValue = countryIndexMultiplier(for: point) else {
            return nil
        }

        return baseComparablePrice * indexValue
    }

    private func recommendedLocalPriceValue(for point: SubscriptionPriceParityPoint) -> Double? {
        if let resolvedPricePoint = resolvedSelectablePricePoint(for: point) {
            return resolvedPricePoint.customerPrice
        }

        if let manualLocalPrice = manualLocalPriceValue(for: point) {
            return manualLocalPrice
        }

        if let liveValue = recommendedLiveConvertedLocalPriceValue(for: point) {
            return liveValue
        }

        guard let comparablePrice = recommendedComparablePriceValue(for: point) else { return nil }
        return localPriceValue(
            fromComparablePrice: comparablePrice,
            territoryID: point.territoryID,
            currencyCode: point.currencyCode
        )
    }

    private func recommendedLiveConvertedLocalPriceValue(for point: SubscriptionPriceParityPoint) -> Double? {
        guard let baseEquivalentPrice = recommendedPriceValue(for: point),
              let baseCurrencyCode = selectedReferenceCurrencyCode,
              let targetCurrencyCode = point.currencyCode else {
            return nil
        }

        if baseCurrencyCode == targetCurrencyCode {
            return baseEquivalentPrice
        }

        guard liveExchangeRatesBaseCurrencyCode == baseCurrencyCode,
              let exchangeRate = liveExchangeRatesByCurrencyCode[targetCurrencyCode],
              exchangeRate > 0 else {
            return nil
        }

        return baseEquivalentPrice * exchangeRate
    }

    private func recommendedPriceText(for point: SubscriptionPriceParityPoint) -> String? {
        guard let newLocalPrice = finalLocalPriceValue(for: point) else { return nil }
        return localizedPriceString(price: String(format: "%.2f", newLocalPrice), currencyCode: point.currencyCode)
    }

    private func autoRecommendedPriceText(for point: SubscriptionPriceParityPoint) -> String? {
        guard let newLocalPrice = autoRecommendedLocalPriceValue(for: point) else { return nil }
        return localizedPriceString(price: String(format: "%.2f", newLocalPrice), currencyCode: point.currencyCode)
    }

    private func displayIndexText(for point: SubscriptionPriceParityPoint) -> String? {
        guard let basePrice = selectedOverridePriceValue,
              basePrice > 0,
              let finalPrice = recommendedPriceValue(for: point) else {
            return nil
        }

        return String(format: "%.2fx", finalPrice / basePrice)
    }

    private func finalLocalPriceValue(for point: SubscriptionPriceParityPoint) -> Double? {
        recommendedLocalPriceValue(for: point)
    }

    private func autoRecommendedLocalPriceValue(for point: SubscriptionPriceParityPoint) -> Double? {
        if let liveValue = autoRecommendedLiveConvertedLocalPriceValue(for: point) {
            return liveValue
        }

        guard let comparablePrice = recommendedComparablePriceValue(for: point) else { return nil }
        return localPriceValue(
            fromComparablePrice: comparablePrice,
            territoryID: point.territoryID,
            currencyCode: point.currencyCode
        )
    }

    private func autoRecommendedLiveConvertedLocalPriceValue(for point: SubscriptionPriceParityPoint) -> Double? {
        guard let baseEquivalentPrice = rawRecommendedPriceValue(for: point),
              let baseCurrencyCode = selectedReferenceCurrencyCode,
              let targetCurrencyCode = point.currencyCode else {
            return nil
        }

        if baseCurrencyCode == targetCurrencyCode {
            return baseEquivalentPrice
        }

        guard liveExchangeRatesBaseCurrencyCode == baseCurrencyCode,
              let exchangeRate = liveExchangeRatesByCurrencyCode[targetCurrencyCode],
              exchangeRate > 0 else {
            return nil
        }

        return baseEquivalentPrice * exchangeRate
    }

    private func manualLocalPriceValue(for point: SubscriptionPriceParityPoint) -> Double? {
        guard let manualTier = manualPriceTierByRegion[point.territoryID] else { return nil }
        return Double(manualTier.replacingOccurrences(of: ",", with: ""))
    }

    private func manualEquivalentPriceValue(for point: SubscriptionPriceParityPoint) -> Double? {
        guard let manualLocalPrice = manualLocalPriceValue(for: point),
              let targetCurrencyCode = point.currencyCode else {
            return nil
        }

        if selectedReferenceCurrencyCode == targetCurrencyCode {
            return manualLocalPrice
        }

        if let baseCurrencyCode = selectedReferenceCurrencyCode,
           liveExchangeRatesBaseCurrencyCode == baseCurrencyCode,
           let exchangeRate = liveExchangeRatesByCurrencyCode[targetCurrencyCode],
           exchangeRate > 0 {
            return manualLocalPrice / exchangeRate
        }

        return comparablePriceValue(
            fromLocalPrice: manualLocalPrice,
            territoryID: point.territoryID,
            currencyCode: point.currencyCode
        )
    }

    private func desiredLocalPriceValueBeforeSnapping(for point: SubscriptionPriceParityPoint) -> Double? {
        manualLocalPriceValue(for: point) ?? autoRecommendedLocalPriceValue(for: point)
    }

    private func resolvedSelectablePricePoint(for point: SubscriptionPriceParityPoint) -> ASCSelectableSubscriptionPricePoint? {
        guard let desiredLocalPrice = desiredLocalPriceValueBeforeSnapping(for: point),
              let pricePointsByTerritory = cachedSavePreparation?.pricePointsByTerritory else {
            return nil
        }

        return closestSelectablePricePoint(
            in: pricePointsByTerritory[point.territoryID] ?? [],
            desiredPrice: desiredLocalPrice
        )
    }

    private func recommendedPriceTier(for point: SubscriptionPriceParityPoint) -> String? {
        guard let localValue = autoRecommendedLocalPriceValue(for: point) else { return nil }
        let normalized = normalizedPriceString(localValue)
        return nearestAvailablePriceTier(
            to: normalized,
            availableTiers: regionAvailablePriceTiers(for: point.territoryID)
        ) ?? normalized
    }

    private func regionAvailablePriceTiers(for regionID: String) -> [String] {
        if let liveTiers = availableBasePriceTiersByRegion[regionID], !liveTiers.isEmpty {
            return liveTiers
        }

        let currencyCode = pricePoints.first(where: { $0.territoryID == regionID })?.currencyCode
        return fallbackRegionPriceTiers(for: currencyCode)
    }

    private var selectedOverridePriceValue: Double? {
        guard let overridePriceTier else { return nil }
        return Double(overridePriceTier.replacingOccurrences(of: ",", with: ""))
    }

    private var selectedOverrideComparablePriceValue: Double? {
        guard let overridePrice = selectedOverridePriceValue,
              let territoryID = selectedReferenceTerritoryID,
              let currencyCode = pricePoints.first(where: { $0.territoryID == territoryID })?.currencyCode else {
            return nil
        }

        return comparablePriceValue(
            fromLocalPrice: overridePrice,
            territoryID: territoryID,
            currencyCode: currencyCode
        )
    }

    private func countryIndexMultiplier(for point: SubscriptionPriceParityPoint) -> Double? {
        let normalizedTerritoryID = point.territoryID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        if let customParityMultiplier = customParityMultiplier(for: point.territoryID) {
            return customParityMultiplier
        }

        if bigMacEntries.contains(where: { $0.territoryID == normalizedTerritoryID }),
           let comparableBigMacMultiplier = comparableBigMacMultiplier(for: point) {
            return comparableBigMacMultiplier
        }

        if let fallbackMultiplier = fallbackParityMultiplier(for: normalizedTerritoryID) {
            return fallbackMultiplier
        }

        return 1
    }

    private func comparableBigMacMultiplier(for point: SubscriptionPriceParityPoint) -> Double? {
        guard let referenceComparablePrice = selectedReferenceComparableCountryPrice,
              referenceComparablePrice > 0,
              let pointPrice = Double(point.customerPrice ?? ""),
              let pointComparablePrice = comparablePriceValue(
                fromLocalPrice: pointPrice,
                territoryID: point.territoryID,
                currencyCode: point.currencyCode
              ) else {
            return nil
        }

        return pointComparablePrice / referenceComparablePrice
    }

    private func customParityMultiplier(for territoryID: String) -> Double? {
        let normalized = territoryID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let baseEntry = bigMacBaseEntry else { return nil }
        guard let entry = bigMacEntries.first(where: { $0.territoryID == normalized }) else { return nil }
        return entry.customParityMultiplier(relativeTo: baseEntry)
    }

    private func fallbackParityMultiplier(for territoryID: String) -> Double? {
        let normalizedTerritoryID = territoryID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let targetMultiplier = PPPDataset.multipliers[normalizedTerritoryID],
              let baseTerritoryID = selectedReferenceTerritoryID?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased(),
              let baseMultiplier = PPPDataset.multipliers[baseTerritoryID],
              baseMultiplier > 0 else {
            return nil
        }

        return max(targetMultiplier / baseMultiplier, 0.08)
    }

    private func comparablePriceValue(
        fromLocalPrice localPrice: Double,
        territoryID: String,
        currencyCode: String?
    ) -> Double? {
        let normalizedTerritoryID = territoryID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let exchangeRate = comparableExchangeRate(
            territoryID: normalizedTerritoryID,
            currencyCode: currencyCode,
            entries: bigMacEntries
        ), exchangeRate > 0 else {
            return nil
        }

        return localPrice / exchangeRate
    }

    private func localPriceValue(
        fromComparablePrice comparablePrice: Double,
        territoryID: String,
        currencyCode: String?
    ) -> Double? {
        let normalizedTerritoryID = territoryID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let exchangeRate = comparableExchangeRate(
            territoryID: normalizedTerritoryID,
            currencyCode: currencyCode,
            entries: bigMacEntries
        ), exchangeRate > 0 else {
            return nil
        }

        return comparablePrice * exchangeRate
    }

    private var bigMacBaseEntry: BigMacIndexEntry? {
        guard let referenceTerritoryID = selectedReferenceTerritoryID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() else {
            return bigMacEntries.first
        }

        return bigMacEntries.first(where: { $0.territoryID == referenceTerritoryID }) ?? bigMacEntries.first
    }

    private var selectedReferenceTerritoryID: String? {
        overrideRegionID ?? preferredBasePricePoint(from: pricePoints)?.territoryID
    }

    private var selectedReferenceCountryPrice: Double? {
        guard let regionID = selectedReferenceTerritoryID,
              let regionPrice = pricePoints.first(where: { $0.territoryID == regionID })?.customerPrice else {
            return nil
        }
        return Double(regionPrice)
    }

    private var selectedReferenceComparableCountryPrice: Double? {
        guard let regionID = selectedReferenceTerritoryID,
              let point = pricePoints.first(where: { $0.territoryID == regionID }),
              let regionPrice = Double(point.customerPrice ?? "") else {
            return nil
        }

        return comparablePriceValue(
            fromLocalPrice: regionPrice,
            territoryID: regionID,
            currencyCode: point.currencyCode
        )
    }

    private var selectedReferenceCurrencyCode: String? {
        guard let regionID = selectedReferenceTerritoryID else { return nil }
        return pricePoints.first(where: { $0.territoryID == regionID })?.currencyCode
    }

    @MainActor
    private func savePricesToAppStoreConnect(
        startDate: Date,
        preserveCurrentPrice: Bool,
        progress: @MainActor @Sendable @escaping (SubscriptionPriceSaveProgress) -> Void
    ) async throws {
        if isDemoMode {
            let simulatedTargets = pendingSaveTargets
            let totalCount = max(simulatedTargets.count, 1)

            progress(.init(stage: .preparing, completedCount: totalCount, totalCount: totalCount))

            for completedCount in 1...totalCount {
                try await Task.sleep(nanoseconds: 18_000_000)
                progress(.init(stage: .saving, completedCount: completedCount, totalCount: totalCount))
            }

            saveAlertMessage = "Simulated saving \(totalCount) territory prices in demo mode. No App Store Connect changes were made."
            return
        }

        let targets = pendingSaveTargets
        guard !targets.isEmpty else {
            throw ClientError.invalidResponse(-1, body: "There are no calculated country prices ready to save yet.")
        }

        let result: SubscriptionPriceSaveResult
        switch subscription.kind {
        case .subscription:
            result = try await AppStoreConnectClient.saveSubscriptionPrices(
                subscriptionID: subscription.id,
                targets: targets,
                startDate: startDate,
                preserveCurrentPrice: preserveCurrentPrice,
                issuerID: issuerID,
                keyID: keyID,
                privateKeyData: privateKeyData,
                preparation: cachedSavePreparation,
                progress: progress
            )
        case .inAppPurchase:
            result = try await AppStoreConnectClient.saveInAppPurchasePrices(
                inAppPurchaseID: subscription.id,
                baseTerritoryID: selectedReferenceTerritoryID ?? "USA",
                targets: targets,
                startDate: startDate,
                issuerID: issuerID,
                keyID: keyID,
                privateKeyData: privateKeyData,
                preparation: cachedSavePreparation,
                progress: progress
            )
        }
        await loadPriceParity()
        saveAlertMessage = "Saved \(result.savedCount) territory prices to App Store Connect."
        if result.skippedCount > 0 {
            saveAlertMessage = (saveAlertMessage ?? "") + " Skipped \(result.skippedCount) territories that were already at the selected price."
        }
        if result.unavailableTerritoryCount > 0 {
            saveAlertMessage = (saveAlertMessage ?? "") + " \(result.unavailableTerritoryCount) territories had no valid App Store Connect price point and were skipped."
        }
        if result.existingFuturePriceTerritoryCount > 0 {
            saveAlertMessage = (saveAlertMessage ?? "") + " \(result.existingFuturePriceTerritoryCount) territories already had a future scheduled price and were skipped."
        }
    }

    @MainActor
    private func prepareSaveIfNeeded() async throws {
        guard cachedSavePreparation == nil else { return }
        if isDemoMode {
            let preparation = demoSavePreparation(from: pricePoints)
            savePreparationCompletedCount = comparisonPricePoints.count
            savePreparationTotalCount = comparisonPricePoints.count
            savePreparationProgress = 1
            cachedSavePreparation = preparation
            mergeAvailablePriceTiers(from: preparation.pricePointsByTerritory)
            return
        }

        let territoryIDs = comparisonPricePoints.map(\.territoryID)
        let preparation: SubscriptionPriceSavePreparation
        switch subscription.kind {
        case .subscription:
            preparation = try await AppStoreConnectClient.prepareSubscriptionPriceSave(
                subscriptionID: subscription.id,
                territoryIDs: territoryIDs,
                knownFutureScheduledPriceIDsByTerritory: cachedFutureScheduledPriceIDsByTerritory,
                issuerID: issuerID,
                keyID: keyID,
                privateKeyData: privateKeyData,
                progress: { completedCount, totalCount in
                    savePreparationCompletedCount = completedCount
                    savePreparationTotalCount = totalCount
                    savePreparationProgress = totalCount > 0
                        ? Double(completedCount) / Double(totalCount)
                        : 1
                }
            )
        case .inAppPurchase:
            preparation = try await AppStoreConnectClient.prepareInAppPurchasePriceSave(
                inAppPurchaseID: subscription.id,
                territoryIDs: territoryIDs,
                issuerID: issuerID,
                keyID: keyID,
                privateKeyData: privateKeyData,
                progress: { completedCount, totalCount in
                    savePreparationCompletedCount = completedCount
                    savePreparationTotalCount = totalCount
                    savePreparationProgress = totalCount > 0
                        ? Double(completedCount) / Double(totalCount)
                        : 1
                }
            )
        }
        cachedSavePreparation = preparation
        mergeAvailablePriceTiers(from: preparation.pricePointsByTerritory)
    }

    @MainActor
    private func loadPriceParity() async {
        phase = .loading
        if isDemoMode {
            let demoPoints = demoPriceParityPoints(for: subscription)
            pricePoints = demoPoints
            cachedFutureScheduledPriceIDsByTerritory = [:]
            let basePoint = preferredBasePricePoint(from: demoPoints)
            if overrideRegionID == nil {
                overrideRegionID = basePoint?.territoryID
            }
            if overridePriceTier == nil {
                overridePriceTier = basePoint?.customerPrice
            }
            let preparation = demoSavePreparation(from: demoPoints)
            cachedSavePreparation = preparation
            mergeAvailablePriceTiers(from: preparation.pricePointsByTerritory)
            savePreparationCompletedCount = comparisonPricePoints.count
            savePreparationTotalCount = comparisonPricePoints.count
            savePreparationProgress = 1
            phase = .loaded
            return
        }

        do {
            let parityLoadResult: SubscriptionPriceParityLoadResult
            switch subscription.kind {
            case .subscription:
                parityLoadResult = try await AppStoreConnectClient.fetchSubscriptionPriceParity(
                    subscriptionID: subscription.id,
                    issuerID: issuerID,
                    keyID: keyID,
                    privateKeyData: privateKeyData
                )
            case .inAppPurchase:
                parityLoadResult = try await AppStoreConnectClient.fetchInAppPurchasePriceParity(
                    inAppPurchaseID: subscription.id,
                    issuerID: issuerID,
                    keyID: keyID,
                    privateKeyData: privateKeyData
                )
            }
            pricePoints = parityLoadResult.points
            cachedFutureScheduledPriceIDsByTerritory = parityLoadResult.futureScheduledPriceIDsByTerritory
            let basePoint = preferredBasePricePoint(from: pricePoints)
            if overrideRegionID == nil {
                overrideRegionID = parityLoadResult.baseTerritoryID ?? basePoint?.territoryID
            }
            if overridePriceTier == nil {
                overridePriceTier = basePoint?.customerPrice
            }
            phase = .loaded
            Task {
                await warmSavePreparation()
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    @MainActor
    private func warmSavePreparation(forceRefresh: Bool = false) async {
        guard !isPreparingSavePreparation else { return }
        guard forceRefresh || cachedSavePreparation == nil else { return }

        if forceRefresh {
            cachedSavePreparation = nil
        }

        isPreparingSavePreparation = true
        savePreparationProgress = 0
        savePreparationCompletedCount = 0
        savePreparationTotalCount = comparisonPricePoints.count
        savePreparationErrorMessage = nil

        defer {
            isPreparingSavePreparation = false
        }

        do {
            try await prepareSaveIfNeeded()
            savePreparationProgress = 1
        } catch {
            savePreparationErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadAvailableBasePriceTiersIfNeeded(for regionID: String?) async {
        guard let regionID, !regionID.isEmpty else { return }
        if let preloadedPricePoints = cachedSavePreparation?.pricePointsByTerritory[regionID],
           !preloadedPricePoints.isEmpty {
            availableBasePriceTiersByRegion[regionID] = priceTierStrings(from: preloadedPricePoints)
            return
        }

        guard availableBasePriceTiersByRegion[regionID] == nil,
              !loadingOverridePriceTierRegionIDs.contains(regionID) else { return }

        loadingOverridePriceTierRegionIDs.insert(regionID)
        defer { loadingOverridePriceTierRegionIDs.remove(regionID) }

        do {
            let regionPricePointOptions: [ASCSelectableSubscriptionPricePoint]
            switch subscription.kind {
            case .subscription:
                regionPricePointOptions = try await AppStoreConnectClient.fetchSubscriptionPricePointOptions(
                    subscriptionID: subscription.id,
                    territoryID: regionID,
                    issuerID: issuerID,
                    keyID: keyID,
                    privateKeyData: privateKeyData
                )
            case .inAppPurchase:
                regionPricePointOptions = try await AppStoreConnectClient.fetchInAppPurchasePricePointOptions(
                    inAppPurchaseID: subscription.id,
                    territoryID: regionID,
                    issuerID: issuerID,
                    keyID: keyID,
                    privateKeyData: privateKeyData
                )
            }
            availableBasePriceTiersByRegion[regionID] = priceTierStrings(from: regionPricePointOptions)
        } catch {
            availableBasePriceTiersByRegion[regionID] = nil
        }
    }

    @MainActor
    private func mergeAvailablePriceTiers(
        from pricePointsByTerritory: [String: [ASCSelectableSubscriptionPricePoint]]
    ) {
        for (regionID, pricePoints) in pricePointsByTerritory {
            guard !pricePoints.isEmpty else { continue }
            availableBasePriceTiersByRegion[regionID] = priceTierStrings(from: pricePoints)
        }
    }

    private func priceTierStrings(
        from pricePoints: [ASCSelectableSubscriptionPricePoint]
    ) -> [String] {
        return pricePoints
            .map(\.customerPrice)
            .sorted()
            .reduce(into: [String]()) { result, amount in
                let price = normalizedPriceString(amount)
                if result.last != price {
                    result.append(price)
                }
            }
    }

    private func demoSavePreparation(
        from points: [SubscriptionPriceParityPoint]
    ) -> SubscriptionPriceSavePreparation {
        let grouped = Dictionary(uniqueKeysWithValues: points.map { point in
            let tiers = fallbackRegionPriceTiers(for: point.currencyCode).compactMap { tier -> ASCSelectableSubscriptionPricePoint? in
                guard let value = Double(tier.replacingOccurrences(of: ",", with: "")) else { return nil }
                return ASCSelectableSubscriptionPricePoint(
                    id: "demo.\(point.territoryID).\(tier)",
                    territoryID: point.territoryID,
                    customerPrice: value
                )
            }
            return (point.territoryID, tiers)
        })

        return SubscriptionPriceSavePreparation(
            pricePointsByTerritory: grouped,
            futureScheduledPriceIDsByTerritory: [:]
        )
    }

    @MainActor
    private func loadLiveExchangeRatesIfNeeded(for baseCurrencyCode: String?) async {
        guard let baseCurrencyCode, !baseCurrencyCode.isEmpty else { return }
        guard liveExchangeRatesBaseCurrencyCode != baseCurrencyCode else { return }

        do {
            let rates = try await LiveExchangeRateClient.fetchRates(baseCurrencyCode: baseCurrencyCode)
            liveExchangeRatesBaseCurrencyCode = baseCurrencyCode
            liveExchangeRatesByCurrencyCode = rates
        } catch {
            liveExchangeRatesBaseCurrencyCode = nil
            liveExchangeRatesByCurrencyCode = [:]
        }
    }

}

private enum SubscriptionPriceParityPhase {
    case loading
    case loaded
    case failed(String)
}

private struct OverridePickerSheet: View {
    let pricePoints: [SubscriptionPriceParityPoint]
    let availablePriceTiersByRegion: [String: [String]]
    let loadingRegionIDs: Set<String>
    @Binding var selectedRegionID: String?
    @Binding var selectedPriceTier: String?
    let onRegionSelectionChanged: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var regionSelection: String
    @State private var priceSelection: String

    init(
        pricePoints: [SubscriptionPriceParityPoint],
        availablePriceTiersByRegion: [String: [String]],
        loadingRegionIDs: Set<String>,
        selectedRegionID: Binding<String?>,
        selectedPriceTier: Binding<String?>,
        onRegionSelectionChanged: @escaping (String) -> Void
    ) {
        self.pricePoints = pricePoints
        self.availablePriceTiersByRegion = availablePriceTiersByRegion
        self.loadingRegionIDs = loadingRegionIDs
        self._selectedRegionID = selectedRegionID
        self._selectedPriceTier = selectedPriceTier
        self.onRegionSelectionChanged = onRegionSelectionChanged
        let defaultRegion = selectedRegionID.wrappedValue ?? preferredBasePricePoint(from: pricePoints)?.territoryID ?? ""
        let defaultPrice = selectedPriceTier.wrappedValue ?? pricePoints.first(where: { $0.territoryID == defaultRegion })?.customerPrice ?? "4.99"
        self._regionSelection = State(initialValue: defaultRegion)
        let defaultTiers = OverridePickerSheet.availablePriceTiers(
            for: defaultRegion,
            currencyCode: pricePoints.first(where: { $0.territoryID == defaultRegion })?.currencyCode,
            liveTiers: availablePriceTiersByRegion
        )
        self._priceSelection = State(
            initialValue: Self.nearestPriceTier(to: defaultPrice, availableTiers: defaultTiers) ?? defaultTiers.first ?? defaultPrice
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Country or Region") {
                    Picker("Country or Region", selection: $regionSelection) {
                        ForEach(sortedRegions, id: \.self) { regionID in
                            Text("\(countryFlagString(for: regionID))  \(localizedTerritoryDisplayName(regionID))")
                                .tag(regionID)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Price") {
                    if isLoadingSelectedRegionPriceTiers {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Loading live App Store Connect price tiers for \(localizedTerritoryDisplayName(regionSelection))…")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Picker("Price", selection: $priceSelection) {
                        ForEach(priceTiers, id: \.self) { tier in
                            Text(formattedTierLabel(tier))
                                .tag(tier)
                        }
                    }
                    .pickerStyle(.menu)

                    if selectedCurrencyUsesWholeUnits {
                        Text("Using ASC-style whole-number local presets for \(selectedCurrencyCode ?? "this currency").")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Preview")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("\(localizedTerritoryDisplayName(selectedRegionPoint?.territoryID ?? regionSelection)) • \(formattedPreviewPrice(priceSelection) ?? "—")")
                            .font(.headline)
                    }
                }
            }
            .navigationTitle("Override")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                onRegionSelectionChanged(regionSelection)
                syncPriceSelectionForCurrency()
            }
            .onChange(of: regionSelection) { _, _ in
                onRegionSelectionChanged(regionSelection)
                syncPriceSelectionForCurrency()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        selectedRegionID = regionSelection.isEmpty ? nil : regionSelection
                        selectedPriceTier = priceSelection
                        dismiss()
                    }
                }
            }
        }
    }

    private var sortedRegions: [String] {
        Array(Set(pricePoints.map(\.territoryID))).sorted { lhs, rhs in
            if lhs == "USA" { return true }
            if rhs == "USA" { return false }
            return localizedTerritoryDisplayName(lhs).localizedCaseInsensitiveCompare(localizedTerritoryDisplayName(rhs)) == .orderedAscending
        }
    }

    private var priceTiers: [String] {
        Self.availablePriceTiers(
            for: regionSelection,
            currencyCode: selectedCurrencyCode,
            liveTiers: availablePriceTiersByRegion
        )
    }

    private var isLoadingSelectedRegionPriceTiers: Bool {
        loadingRegionIDs.contains(regionSelection)
    }

    private var selectedRegionPoint: SubscriptionPriceParityPoint? {
        pricePoints.first(where: { $0.territoryID == regionSelection })
    }

    private var selectedCurrencyCode: String? {
        selectedRegionPoint?.currencyCode ?? preferredBasePricePoint(from: pricePoints)?.currencyCode
    }

    private var selectedCurrencyUsesWholeUnits: Bool {
        currencyUsesWholeUnits(selectedCurrencyCode)
    }

    private func formattedTierLabel(_ tier: String) -> String {
        localizedPriceString(price: tier, currencyCode: selectedCurrencyCode) ?? tier
    }

    private func formattedPreviewPrice(_ tier: String) -> String? {
        guard !tier.isEmpty else { return nil }
        return localizedPriceString(price: tier, currencyCode: selectedCurrencyCode)
    }

    private func syncPriceSelectionForCurrency() {
        if !priceTiers.contains(priceSelection) {
            priceSelection = Self.nearestPriceTier(
                to: selectedPriceTier ?? selectedRegionPoint?.customerPrice,
                availableTiers: priceTiers
            ) ?? priceTiers.first ?? selectedRegionPoint?.customerPrice ?? "4.99"
        }
    }

    private static func availablePriceTiers(
        for regionID: String,
        currencyCode: String?,
        liveTiers: [String: [String]]
    ) -> [String] {
        if let liveTiers = liveTiers[regionID], !liveTiers.isEmpty {
            return liveTiers
        }

        return fallbackPriceTiers(for: currencyCode)
    }

    private static func fallbackPriceTiers(for currencyCode: String?) -> [String] {
        if currencyUsesWholeUnits(currencyCode) {
            return ["490", "990", "1990", "2990", "3990", "4990", "5990", "6990", "7990", "8990", "9990", "12990", "14990", "17990", "19990", "24990", "29990", "34990", "39990", "49990", "59990", "69990", "79990", "89990", "99990"]
        }

        return ["0.99", "1.99", "2.99", "3.99", "4.99", "5.99", "6.99", "7.99", "8.99", "9.99", "12.99", "14.99", "17.99", "19.99", "24.99", "29.99", "34.99", "39.99", "44.99", "49.99", "59.99", "69.99", "79.99", "89.99", "99.99"]
    }

    private static func nearestPriceTier(to price: String?, availableTiers: [String]) -> String? {
        guard let price, let amount = Double(price) else { return nil }

        return availableTiers.min(by: { lhs, rhs in
            guard let lhsValue = Double(lhs), let rhsValue = Double(rhs) else { return false }
            return abs(lhsValue - amount) < abs(rhsValue - amount)
        })
    }
}

private struct SubscriptionPriceSaveReviewView: View {
    let subscriptionName: String
    let subscriptionProductID: String
    let appIconURL: URL?
    let basePriceText: String
    let baseSubtitle: String
    let items: [SubscriptionPriceReviewItem]
    let supportsPreserveCurrentPrice: Bool
    let minimumEffectiveDate: Date
    let onPrepare: () async throws -> Void
    let onSave: (Date, Bool, @MainActor @Sendable @escaping (SubscriptionPriceSaveProgress) -> Void) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @State private var effectiveDate: Date
    @State private var preserveCurrentPrice = false
    @State private var isSaving = false
    @State private var progress = SubscriptionPriceSaveProgress(stage: .preparing, completedCount: 0, totalCount: 0)
    @State private var errorMessage: String?

    init(
        subscriptionName: String,
        subscriptionProductID: String,
        appIconURL: URL?,
        basePriceText: String,
        baseSubtitle: String,
        items: [SubscriptionPriceReviewItem],
        supportsPreserveCurrentPrice: Bool,
        minimumEffectiveDate: Date,
        onPrepare: @escaping () async throws -> Void,
        onSave: @escaping (Date, Bool, @MainActor @Sendable @escaping (SubscriptionPriceSaveProgress) -> Void) async throws -> Void
    ) {
        self.subscriptionName = subscriptionName
        self.subscriptionProductID = subscriptionProductID
        self.appIconURL = appIconURL
        self.basePriceText = basePriceText
        self.baseSubtitle = baseSubtitle
        self.items = items
        self.supportsPreserveCurrentPrice = supportsPreserveCurrentPrice
        self.minimumEffectiveDate = minimumEffectiveDate
        self.onPrepare = onPrepare
        self.onSave = onSave
        self._effectiveDate = State(initialValue: minimumEffectiveDate)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                VStack(alignment: .leading, spacing: 14) {
                    Text("Review before saving")
                        .font(.headline)

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Base price")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(basePriceText)
                                .font(.headline)
                            Text(baseSubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Territories")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text("\(items.count)")
                                .font(.title3.weight(.semibold))
                        }
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 16) {
                        DatePicker(
                            "Effective date",
                            selection: $effectiveDate,
                            in: minimumEffectiveDate...,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.compact)

                        if supportsPreserveCurrentPrice {
                            Toggle(isOn: $preserveCurrentPrice) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Preserve current price for existing subscribers")
                                }
                            }
                        }

                        if isSaving {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(progress.stage.title)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(progress.fractionText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                ProgressView(value: progress.fraction)
                                Text(progress.detailText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                )

                VStack(alignment: .leading, spacing: 12) {
                    Text("Price changes")
                        .font(.headline)

                    ForEach(items) { item in
                        HStack(alignment: .center, spacing: 12) {
                            Text(item.flag)
                                .font(.system(size: 24))
                                .frame(width: 32, height: 32)

                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Text(item.territoryName)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text("\(item.currentPriceText) -> \(item.newPriceText)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color.secondary.opacity(0.08))
                        )
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Review Changes")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            try? await onPrepare()
        }
        .task {
            requestReviewIfNeeded()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save") {
                        Task { await saveToASC() }
                    }
                }
            }
        }
        .alert(
            "Couldn’t Save Prices",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                Group {
                    if let appIconURL {
                        AsyncImage(url: appIconURL) { phase in
                            switch phase {
                            case .empty:
                                reviewPlaceholderIcon
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure:
                                reviewPlaceholderIcon
                            @unknown default:
                                reviewPlaceholderIcon
                            }
                        }
                    } else {
                        reviewPlaceholderIcon
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    Text(subscriptionName)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)

                    Text(subscriptionProductID)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.secondary.opacity(0.10))
                        )
                }

                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.secondary.opacity(0.10),
                            Color.secondary.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }

    private var reviewPlaceholderIcon: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.blue.opacity(0.22),
                        Color.cyan.opacity(0.14)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.blue)
            }
    }

    private func requestReviewIfNeeded() {
        guard !ReviewPromptSession.hasRequestedOnSaveView else { return }
        ReviewPromptSession.hasRequestedOnSaveView = true
        requestReview()
    }

    @MainActor
    private func saveToASC() async {
        guard !items.isEmpty else { return }
        isSaving = true
        progress = .init(stage: .preparing, completedCount: 0, totalCount: items.count)
        defer { isSaving = false }

        do {
            try await onSave(effectiveDate, preserveCurrentPrice) { newProgress in
                progress = newProgress
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

@MainActor
private enum ReviewPromptSession {
    static var hasRequestedOnSaveView = false
}

private struct TerritoryPriceAdjustmentSheet: View {
    let regionID: String
    let regionName: String
    let regionFlag: String
    let currentPriceText: String
    let recommendedPriceText: String
    let currencyCode: String?
    let availablePriceTiers: [String]
    @Binding var selectedPriceTier: String?
    let fallbackRecommendedTier: String?
    let isLoadingPriceTiers: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center, spacing: 12) {
                    Text(regionFlag)
                        .font(.system(size: 28))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(regionName)
                            .font(.title3.weight(.semibold))
                        Text(regionID)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Current")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(currentPriceText)
                            .font(.headline)
                    }

                    HStack {
                        Text("Recommended")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(recommendedPriceText)
                            .font(.headline)
                    }

                    HStack {
                        Text("Selected")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(selectedPriceText)
                            .font(.headline.weight(.semibold))
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                )

                VStack(alignment: .leading, spacing: 14) {
                    if isLoadingPriceTiers {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Loading App Store Connect price points…")
                                .foregroundStyle(.secondary)
                        }
                    } else if availablePriceTiers.isEmpty {
                        Text("No App Store Connect price points available for this territory.")
                            .foregroundStyle(.secondary)
                    } else {
                        HStack {
                            Text("Selected price point")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Picker(
                                "Price point",
                                selection: Binding(
                                    get: { resolvedSelectedTier },
                                    set: { newValue in
                                        selectedPriceTier = newValue
                                    }
                                )
                            ) {
                                ForEach(availablePriceTiers, id: \.self) { tier in
                                    Text(formattedTierLabel(tier))
                                        .tag(tier)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                )

                HStack(spacing: 12) {
                    Button("Use Recommended") {
                        selectedPriceTier = fallbackRecommendedTier
                    }
                    .buttonStyle(.bordered)
                    .disabled(fallbackRecommendedTier == nil)

                    Button("Clear Manual Change") {
                        selectedPriceTier = nil
                    }
                    .buttonStyle(.bordered)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("Adjust Price")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var selectedPriceText: String {
        formattedTierLabel(resolvedSelectedTier) 
    }

    private func formattedTierLabel(_ tier: String?) -> String {
        guard let tier else { return "—" }
        return localizedPriceString(price: tier, currencyCode: currencyCode) ?? tier
    }

    private var resolvedSelectedTier: String {
        nearestAvailablePriceTier(
            to: selectedPriceTier ?? fallbackRecommendedTier ?? availablePriceTiers.first,
            availableTiers: availablePriceTiers
        ) ?? availablePriceTiers.first ?? ""
    }
}

private func localizedPriceString(price: String?, currencyCode: String?) -> String? {
    guard let price,
          let amount = Double(price) else { return nil }

    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = currencyCode ?? "USD"
    formatter.maximumFractionDigits = 2
    formatter.minimumFractionDigits = 0
    return formatter.string(from: NSNumber(value: amount))
}

private func currencyUsesWholeUnits(_ currencyCode: String?) -> Bool {
    guard let currencyCode, !currencyCode.isEmpty else { return false }

    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = currencyCode
    return formatter.maximumFractionDigits == 0
}

private func normalizedPriceString(_ amount: Double) -> String {
    if amount.rounded() == amount {
        return String(format: "%.0f", amount)
    }
    return String(format: "%.2f", amount)
}

private func fallbackRegionPriceTiers(for currencyCode: String?) -> [String] {
    if currencyUsesWholeUnits(currencyCode) {
        return ["490", "990", "1990", "2990", "3990", "4990", "5990", "6990", "7990", "8990", "9990", "12990", "14990", "17990", "19990", "24990", "29990", "34990", "39990", "49990", "59990", "69990", "79990", "89990", "99990"]
    }

    return ["0.99", "1.99", "2.99", "3.99", "4.99", "5.99", "6.99", "7.99", "8.99", "9.99", "12.99", "14.99", "17.99", "19.99", "24.99", "29.99", "34.99", "39.99", "44.99", "49.99", "59.99", "69.99", "79.99", "89.99", "99.99"]
}

private func nearestAvailablePriceTier(to price: String?, availableTiers: [String]) -> String? {
    guard let price, let amount = Double(price) else { return nil }

    return availableTiers.min(by: { lhs, rhs in
        guard let lhsValue = Double(lhs), let rhsValue = Double(rhs) else { return false }
        return abs(lhsValue - amount) < abs(rhsValue - amount)
    })
}

private func closestSelectablePricePoint(
    in options: [ASCSelectableSubscriptionPricePoint],
    desiredPrice: Double
) -> ASCSelectableSubscriptionPricePoint? {
    options.min(by: {
        abs($0.customerPrice - desiredPrice) < abs($1.customerPrice - desiredPrice)
    })
}

private enum LiveExchangeRateClient {
    static func fetchRates(baseCurrencyCode: String) async throws -> [String: Double] {
        let normalizedBaseCurrencyCode = baseCurrencyCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        guard let url = URL(string: "https://open.er-api.com/v6/latest/\(normalizedBaseCurrencyCode)") else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let payload = try JSONDecoder().decode(LiveExchangeRateResponse.self, from: data)
        return payload.rates
    }
}

private struct LiveExchangeRateResponse: Decodable {
    let rates: [String: Double]
}

private enum PriceParitySource {
    case bigMac
    case fallback
    case defaulted

    var label: String {
        switch self {
        case .bigMac:
            return "Big Mac"
        case .fallback:
            return "Fallback"
        case .defaulted:
            return "Default"
        }
    }

    var foregroundColor: Color {
        switch self {
        case .bigMac:
            return .orange
        case .fallback:
            return .blue
        case .defaulted:
            return .secondary
        }
    }

    var backgroundColor: Color {
        switch self {
        case .bigMac:
            return Color.orange.opacity(0.14)
        case .fallback:
            return Color.blue.opacity(0.14)
        case .defaulted:
            return Color.secondary.opacity(0.12)
        }
    }
}

private func comparableExchangeRate(territoryID: String, currencyCode: String?, entries: [BigMacIndexEntry]) -> Double? {
    if currencyCode == "USD" {
        return 1
    }

    guard let entry = entries.first(where: { $0.territoryID == territoryID }),
          let localPrice = entry.localPrice,
          let dollarPrice = entry.dollarPrice,
          dollarPrice > 0 else {
        return nil
    }

    return localPrice / dollarPrice
}

func localizedTerritoryDisplayName(_ territoryID: String) -> String {
    let overrides: [String: String] = [
        "USA": "United States",
        "GBR": "United Kingdom",
        "KOR": "South Korea",
        "TWN": "Taiwan",
        "RUS": "Russia",
        "VNM": "Vietnam",
        "IRN": "Iran",
        "SYR": "Syria",
        "COD": "Democratic Republic of the Congo",
        "COG": "Republic of the Congo",
        "CIV": "Ivory Coast"
    ]

    if let override = overrides[territoryID] {
        return override
    }

    return Locale.current.localizedString(forRegionCode: territoryID) ?? territoryID
}

private func countryFlagString(for territoryID: String) -> String {
    let code = territoryID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    let regionCode = countryFlagRegionCode(for: code)
    guard regionCode.count == 2 else { return "" }

    let base: UInt32 = 127397
    return regionCode.unicodeScalars.compactMap { scalar in
        guard let value = UnicodeScalar(base + scalar.value) else { return nil }
        return String(value)
    }.joined()
}

private func countryFlagRegionCode(for territoryID: String) -> String {
    let overrides: [String: String] = [
        "COD": "CD",
        "COG": "CG",
        "CIV": "CI",
        "CUW": "CW",
        "ESH": "EH",
        "FRO": "FO",
        "GIB": "GI",
        "GRL": "GL",
        "HKG": "HK",
        "IMN": "IM",
        "JEY": "JE",
        "LIE": "LI",
        "MAC": "MO",
        "MCO": "MC",
        "PRI": "PR",
        "PSE": "PS",
        "SXM": "SX",
        "TLS": "TL",
        "TWN": "TW",
        "VGB": "VG",
        "VIR": "VI"
    ]

    if let override = overrides[territoryID] {
        return override
    }

    return String(territoryID.prefix(2))
}

private func preferredBasePricePoint(from pricePoints: [SubscriptionPriceParityPoint]) -> SubscriptionPriceParityPoint? {
    pricePoints.first(where: { $0.territoryID == "USA" }) ?? pricePoints.first
}

private func sortedPricePoints(_ pricePoints: [SubscriptionPriceParityPoint]) -> [SubscriptionPriceParityPoint] {
    pricePoints.sorted { comparePricePoints($0, $1) }
}

private func comparePricePoints(_ lhs: SubscriptionPriceParityPoint, _ rhs: SubscriptionPriceParityPoint) -> Bool {
    switch (lhs.territoryID == "USA", rhs.territoryID == "USA") {
    case (true, false):
        return true
    case (false, true):
        return false
    default:
        return lhs.territoryID.localizedCaseInsensitiveCompare(rhs.territoryID) == .orderedAscending
    }
}

private func compareSubscriptionPriceItems(_ lhs: ASCSubscriptionPriceItem, _ rhs: ASCSubscriptionPriceItem) -> Bool {
    switch (lhs.attributes.preserved ?? false, rhs.attributes.preserved ?? false) {
    case (false, true):
        return true
    case (true, false):
        return false
    default:
        break
    }

    let today = Calendar(identifier: .gregorian).startOfDay(for: Date())
    let lhsDate = lhs.attributes.startDate.flatMap(ascDate)
    let rhsDate = rhs.attributes.startDate.flatMap(ascDate)
    let lhsIsActive = lhsDate.map { $0 <= today } ?? true
    let rhsIsActive = rhsDate.map { $0 <= today } ?? true

    switch (lhsIsActive, rhsIsActive) {
    case (true, false):
        return true
    case (false, true):
        return false
    case (true, true):
        return (lhsDate ?? .distantPast) > (rhsDate ?? .distantPast)
    case (false, false):
        return (lhsDate ?? .distantFuture) < (rhsDate ?? .distantFuture)
    }
}

private func compareInAppPurchasePriceItems(_ lhs: ASCInAppPurchasePriceItem, _ rhs: ASCInAppPurchasePriceItem) -> Bool {
    let today = Calendar(identifier: .gregorian).startOfDay(for: Date())
    let lhsStartDate = lhs.attributes.startDate.flatMap(ascDate)
    let rhsStartDate = rhs.attributes.startDate.flatMap(ascDate)
    let lhsEndDate = lhs.attributes.endDate.flatMap(ascDate)
    let rhsEndDate = rhs.attributes.endDate.flatMap(ascDate)
    let lhsIsActive = isActiveInAppPurchasePriceItem(lhs, today: today)
    let rhsIsActive = isActiveInAppPurchasePriceItem(rhs, today: today)

    switch (lhsIsActive, rhsIsActive) {
    case (true, false):
        return true
    case (false, true):
        return false
    default:
        break
    }

    switch (lhs.attributes.manual ?? false, rhs.attributes.manual ?? false) {
    case (true, false):
        return true
    case (false, true):
        return false
    default:
        break
    }

    switch (lhsIsActive, rhsIsActive) {
    case (true, true):
        return (lhsStartDate ?? .distantPast) > (rhsStartDate ?? .distantPast)
    case (false, false):
        let lhsHasEnded = lhsEndDate.map { $0 <= today } ?? false
        let rhsHasEnded = rhsEndDate.map { $0 <= today } ?? false

        switch (lhsHasEnded, rhsHasEnded) {
        case (false, true):
            return true
        case (true, false):
            return false
        default:
            return (lhsStartDate ?? .distantFuture) < (rhsStartDate ?? .distantFuture)
        }
    case (true, false):
        return true
    case (false, true):
        return false
    }
}

private func isActiveInAppPurchasePriceItem(_ item: ASCInAppPurchasePriceItem, today: Date) -> Bool {
    let startDate = item.attributes.startDate.flatMap(ascDate) ?? .distantPast
    let endDate = item.attributes.endDate.flatMap(ascDate)
    return startDate <= today && (endDate == nil || endDate! > today)
}

private func ascDate(_ value: String) -> Date? {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: value)
}

private struct SubscriptionPriceParityPoint: Identifiable, Hashable {
    let id: String
    let territoryID: String
    let currencyCode: String?
    let customerPrice: String?
    let proceeds: String?
    let proceedsYear2: String?
    let startDate: String?
    let isPreserved: Bool
}

fileprivate struct SubscriptionPriceParityLoadResult {
    let points: [SubscriptionPriceParityPoint]
    let futureScheduledPriceIDsByTerritory: [String: String]
    let baseTerritoryID: String?
}

private func demoPriceParityPoints(for subscription: AppMonetizationProduct) -> [SubscriptionPriceParityPoint] {
    let basePrice: String
    switch subscription.id {
    case "demo.priceparity.yearly":
        basePrice = "19.99"
    case "demo.dockui.pro":
        basePrice = "14.99"
    default:
        basePrice = "4.99"
    }

    return demoTerritoryIDs.map { territoryID in
        let currencyCode = demoCurrencyCode(for: territoryID)
        let multiplier = PPPDataset.multipliers[territoryID] ?? 1
        let customerPrice = territoryID == "USA"
            ? basePrice
            : localizedDemoPrice(fromUSD: basePrice, multiplier: multiplier)

        return SubscriptionPriceParityPoint(
            id: "demo.\(subscription.id).\(territoryID)",
            territoryID: territoryID,
            currencyCode: currencyCode,
            customerPrice: customerPrice,
            proceeds: nil,
            proceedsYear2: nil,
            startDate: nil,
            isPreserved: false
        )
    }
}

private func localizedDemoPrice(fromUSD usdPrice: String, multiplier: Double) -> String {
    guard let value = Double(usdPrice), multiplier > 0 else { return usdPrice }
    return normalizedPriceString(max(value * multiplier, 0.99))
}

private let demoTerritoryIDs: [String] = {
    let excluded: Set<String> = [
        "ABW", "AND", "ATG", "BHS", "BMU", "BRB", "BRN", "CPV",
        "CYM", "DMA", "FRO", "FSM", "GRD", "GRL", "KIR", "KNA",
        "MHL", "MDV", "NRU", "PLW", "SMR", "SXM", "TCA", "TUV"
    ]

    return PPPDataset.multipliers.keys
        .filter { !excluded.contains($0) }
        .sorted { lhs, rhs in
            if lhs == "USA" { return true }
            if rhs == "USA" { return false }
            return localizedTerritoryDisplayName(lhs).localizedCaseInsensitiveCompare(localizedTerritoryDisplayName(rhs)) == .orderedAscending
        }
}()

private func demoCurrencyCode(for territoryID: String) -> String {
    if territoryID == "USA" {
        return "USD"
    }

    let regionCode = countryFlagRegionCode(for: territoryID)
    let localeID = Locale.identifier(fromComponents: [
        NSLocale.Key.countryCode.rawValue: regionCode
    ])
    let locale = Locale(identifier: localeID)

    return locale.currency?.identifier ?? "USD"
}

private struct AppSummaryCard: View {
    let app: ASCAppSummary

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Group {
                if let iconURL = app.iconURL {
                    AsyncImage(url: iconURL) { phase in
                        switch phase {
                        case .empty:
                            placeholderIcon
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            placeholderIcon
                        @unknown default:
                            placeholderIcon
                        }
                    }
                } else {
                    placeholderIcon
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 8) {
                Text(app.name)
                    .font(.headline)
                    .lineLimit(2)

                if let bundleID = app.bundleID, !bundleID.isEmpty {
                    Text(bundleID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "arrow.up.right")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.blue)
                .frame(width: 36, height: 36)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private var placeholderIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
            Image(systemName: "app.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

enum AppStoreConnectClient {
    private static let appsURL = URL(string: "https://api.appstoreconnect.apple.com/v1/apps")!
    private static let inAppPurchasesURL = URL(string: "https://api.appstoreconnect.apple.com/v1/inAppPurchases")!
    private static let audience = "appstoreconnect-v1"

    static func fetchAppsBase(issuerID: String, keyID: String, privateKeyData: Data) async throws -> [ASCAppSummary] {
        let records = try await fetchAppRecords(
            issuerID: issuerID,
            keyID: keyID,
            privateKeyData: privateKeyData
        )

        return await withTaskGroup(of: ASCAppSummary.self) { group in
            for record in records {
                group.addTask {
                    let iconURL = try? await fetchAppIconURL(bundleID: record.bundleID)
                    return ASCAppSummary(
                        id: record.id,
                        name: record.name,
                        bundleID: record.bundleID,
                        iconURL: iconURL,
                        subscriptionCount: nil,
                        iapCount: nil
                    )
                }
            }

            var collected: [ASCAppSummary] = []
            for await app in group {
                collected.append(app)
            }

            return collected.sorted {
                switch ($0.iconURL != nil, $1.iconURL != nil) {
                case (true, false):
                    return true
                case (false, true):
                    return false
                default:
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
            }
        }
    }

    static func enrichAppSummary(
        _ app: ASCAppSummary,
        issuerID: String,
        keyID: String,
        privateKeyData: Data
    ) async -> ASCAppSummary {
        let iconURL = try? await fetchAppIconURL(bundleID: app.bundleID)

        return ASCAppSummary(
            id: app.id,
            name: app.name,
            bundleID: app.bundleID,
            iconURL: iconURL ?? app.iconURL,
            subscriptionCount: nil,
            iapCount: nil
        )
    }

    static func fetchApps(
        issuerID: String,
        keyID: String,
        privateKeyData: Data
    ) async throws -> [ASCAppSummary] {
        let baseApps = try await fetchAppsBase(
            issuerID: issuerID,
            keyID: keyID,
            privateKeyData: privateKeyData
        )

        let batchSize = 2
        var collected: [ASCAppSummary] = []

        for batchStart in stride(from: 0, to: baseApps.count, by: batchSize) {
            let batch = Array(baseApps[batchStart..<min(batchStart + batchSize, baseApps.count)])

            let batchResults = await withTaskGroup(of: ASCAppSummary.self) { group in
                for app in batch {
                    group.addTask {
                        await enrichAppSummary(
                            app,
                            issuerID: issuerID,
                            keyID: keyID,
                            privateKeyData: privateKeyData
                        )
                    }
                }

                var results: [ASCAppSummary] = []
                for await summary in group {
                    results.append(summary)
                }

                return results
            }

            collected.append(contentsOf: batchResults)
        }

        return collected.sorted {
            switch ($0.iconURL != nil, $1.iconURL != nil) {
            case (true, false):
                return true
            case (false, true):
                return false
            default:
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    private static func fetchAppRecords(
        issuerID: String,
        keyID: String,
        privateKeyData: Data
    ) async throws -> [ASCAppRecord] {
        var nextURL: URL? = makeAppsListURL()
        var collected: [ASCAppRecord] = []

        while let url = nextURL {
            let token = try makeJWT(issuerID: issuerID, keyID: keyID, privateKeyData: privateKeyData)
            let response: ASCAppsResponse = try await request(url: url, bearerToken: token)
            collected.append(contentsOf: response.data.map {
                ASCAppRecord(
                    id: $0.id,
                    name: $0.attributes.name,
                    bundleID: $0.attributes.bundleID
                )
            })
            nextURL = response.links?.next.flatMap(URL.init(string:))
        }

        return collected
    }

    static func fetchMonetizationCatalog(
        appID: String,
        issuerID: String,
        keyID: String,
        privateKeyData: Data
    ) async throws -> AppMonetizationCatalog {
        async let subscriptions: [AppMonetizationProduct]? = try? await fetchSubscriptions(
            appID: appID,
            issuerID: issuerID,
            keyID: keyID,
            privateKeyData: privateKeyData
        )
        async let inAppPurchases: [AppMonetizationProduct]? = try? await fetchInAppPurchases(
            appID: appID,
            issuerID: issuerID,
            keyID: keyID,
            privateKeyData: privateKeyData
        )

        let resolvedSubscriptions = await subscriptions
        let resolvedInAppPurchases = await inAppPurchases

        if resolvedSubscriptions == nil && resolvedInAppPurchases == nil {
            throw ClientError.invalidResponse(-1, body: "App Store Connect didn’t return monetization data for this app.")
        }

        return AppMonetizationCatalog(
            subscriptions: resolvedSubscriptions ?? [],
            inAppPurchases: resolvedInAppPurchases ?? []
        )
    }

    private static func fetchInAppPurchases(
        appID: String,
        issuerID: String,
        keyID: String,
        privateKeyData: Data
    ) async throws -> [AppMonetizationProduct] {
        let token = try makeJWT(issuerID: issuerID, keyID: keyID, privateKeyData: privateKeyData)
        let response: ASCInAppPurchasesResponse = try await request(
            url: makeAppInAppPurchasesURL(appID: appID),
            bearerToken: token
        )

        let collected: [AppMonetizationProduct] = response.data.compactMap { item in
            guard item.attributes.state != .developerRemovedFromSale else { return nil }
            return AppMonetizationProduct(
                id: item.id,
                referenceName: item.attributes.referenceName ?? item.attributes.name ?? item.attributes.productID ?? item.id,
                productID: item.attributes.productID ?? item.id,
                kind: .inAppPurchase,
                state: item.attributes.state
            )
        }

        return collected.sorted {
            $0.referenceName.localizedCaseInsensitiveCompare($1.referenceName) == .orderedAscending
        }
    }

    private static func fetchSubscriptions(
        appID: String,
        issuerID: String,
        keyID: String,
        privateKeyData: Data
    ) async throws -> [AppMonetizationProduct] {
        let token = try makeJWT(issuerID: issuerID, keyID: keyID, privateKeyData: privateKeyData)
        let response: ASCAppSubscriptionGroupsResponse = try await request(
            url: makeAppSubscriptionGroupsURL(appID: appID),
            bearerToken: token
        )

        let groups = response.included ?? []
        var collected: [AppMonetizationProduct] = []
        for group in groups {
            let groupSubscriptions = try await fetchSubscriptions(
                in: group.id,
                issuerID: issuerID,
                keyID: keyID,
                privateKeyData: privateKeyData
            )
            collected.append(contentsOf: groupSubscriptions)
        }

        return collected.sorted {
            $0.referenceName.localizedCaseInsensitiveCompare($1.referenceName) == .orderedAscending
        }
    }

    private static func fetchSubscriptions(
        in groupID: String,
        issuerID: String,
        keyID: String,
        privateKeyData: Data
    ) async throws -> [AppMonetizationProduct] {
        let token = try makeJWT(issuerID: issuerID, keyID: keyID, privateKeyData: privateKeyData)
        let response: ASCSubscriptionsResponse = try await request(
            url: makeSubscriptionsURL(subscriptionGroupID: groupID),
            bearerToken: token
        )

        return response.data.compactMap { item in
            guard item.attributes.state != .developerRemovedFromSale else { return nil }
            return AppMonetizationProduct(
                id: item.id,
                referenceName: item.attributes.referenceName ?? item.attributes.name ?? item.attributes.productID ?? item.id,
                productID: item.attributes.productID ?? item.id,
                kind: .subscription,
                state: item.attributes.state
            )
        }
    }

    fileprivate static func fetchSubscriptionPriceParity(
        subscriptionID: String,
        issuerID: String,
        keyID: String,
        privateKeyData: Data
    ) async throws -> SubscriptionPriceParityLoadResult {
        let token = try makeJWT(issuerID: issuerID, keyID: keyID, privateKeyData: privateKeyData)
        var territories: [String: String] = [:]
        var pricePoints: [String: ASCSubscriptionPricePointItem] = [:]
        let allPriceResponses = try await fetchAllSubscriptionPriceResponses(
            subscriptionID: subscriptionID,
            bearerToken: token
        )
        let allPrices = allPriceResponses.flatMap(\.data)
        let futureScheduledPriceIDsByTerritory = futureScheduledPriceIDsByTerritory(from: allPrices)

        for response in allPriceResponses {
            for included in response.included ?? [] {
                switch included {
                case .territory(let territory):
                    territories[territory.id] = territory.attributes.currency
                case .pricePoint(let pricePoint):
                    pricePoints[pricePoint.id] = pricePoint
                }
            }
        }

        let points = Dictionary(grouping: allPrices, by: { $0.relationships?.territory?.data?.id ?? "unknown" })
            .values
            .compactMap { items in
                guard let item = items.sorted(by: compareSubscriptionPriceItems).first else { return nil }

                let territoryID = item.relationships?.territory?.data?.id ?? "unknown"
                let pricePointID = item.relationships?.subscriptionPricePoint?.data?.id ?? ""
                let pricePoint = pricePoints[pricePointID]

                return SubscriptionPriceParityPoint(
                    id: item.id,
                    territoryID: territoryID,
                    currencyCode: territories[territoryID],
                    customerPrice: pricePoint?.attributes.customerPrice,
                    proceeds: pricePoint?.attributes.proceeds,
                    proceedsYear2: pricePoint?.attributes.proceedsYear2,
                    startDate: item.attributes.startDate,
                    isPreserved: item.attributes.preserved ?? false
                )
            }
            .sorted { comparePricePoints($0, $1) }

        return SubscriptionPriceParityLoadResult(
            points: points,
            futureScheduledPriceIDsByTerritory: futureScheduledPriceIDsByTerritory,
            baseTerritoryID: nil
        )
    }

    fileprivate static func fetchInAppPurchasePriceParity(
        inAppPurchaseID: String,
        issuerID: String,
        keyID: String,
        privateKeyData: Data
    ) async throws -> SubscriptionPriceParityLoadResult {
        let token = try makeJWT(issuerID: issuerID, keyID: keyID, privateKeyData: privateKeyData)
        let schedule = try await fetchInAppPurchasePriceSchedule(
            inAppPurchaseID: inAppPurchaseID,
            bearerToken: token
        )

        async let automaticPriceResponses = fetchAllInAppPurchasePriceResponses(
            scheduleID: schedule.id,
            kind: .automatic,
            bearerToken: token
        )
        async let manualPriceResponses = fetchAllInAppPurchasePriceResponses(
            scheduleID: schedule.id,
            kind: .manual,
            bearerToken: token
        )

        var territories: [String: String] = [:]
        var pricePoints: [String: ASCInAppPurchasePricePointItem] = [:]
        let automaticResponses = try await automaticPriceResponses
        let manualResponses = try await manualPriceResponses
        let allPriceResponses = automaticResponses + manualResponses
        let allPrices = allPriceResponses.flatMap(\.data)

        for response in allPriceResponses {
            for included in response.included ?? [] {
                switch included {
                case .territory(let territory):
                    territories[territory.id] = territory.attributes.currency
                case .pricePoint(let pricePoint):
                    pricePoints[pricePoint.id] = pricePoint
                }
            }
        }

        let points = Dictionary(grouping: allPrices, by: { $0.relationships?.territory?.data?.id ?? "unknown" })
            .values
            .compactMap { items in
                guard let item = items.sorted(by: compareInAppPurchasePriceItems).first else { return nil }

                let territoryID = item.relationships?.territory?.data?.id ?? "unknown"
                let pricePointID = item.relationships?.inAppPurchasePricePoint?.data?.id ?? ""
                let pricePoint = pricePoints[pricePointID]

                return SubscriptionPriceParityPoint(
                    id: item.id,
                    territoryID: territoryID,
                    currencyCode: territories[territoryID],
                    customerPrice: pricePoint?.attributes.customerPrice,
                    proceeds: pricePoint?.attributes.proceeds,
                    proceedsYear2: nil,
                    startDate: item.attributes.startDate,
                    isPreserved: false
                )
            }
            .sorted { comparePricePoints($0, $1) }

        return SubscriptionPriceParityLoadResult(
            points: points,
            futureScheduledPriceIDsByTerritory: [:],
            baseTerritoryID: schedule.baseTerritoryID
        )
    }

    fileprivate static func saveSubscriptionPrices(
        subscriptionID: String,
        targets: [SubscriptionPriceSaveTarget],
        startDate: Date,
        preserveCurrentPrice: Bool,
        issuerID: String,
        keyID: String,
        privateKeyData: Data,
        preparation: SubscriptionPriceSavePreparation? = nil,
        progress: (@MainActor @Sendable (SubscriptionPriceSaveProgress) -> Void)? = nil
    ) async throws -> SubscriptionPriceSaveResult {
        let token = try makeJWT(issuerID: issuerID, keyID: keyID, privateKeyData: privateKeyData)
        let subscriptionPricesURL = URL(string: "https://api.appstoreconnect.apple.com/v1/subscriptionPrices")!
        let scheduledStartDate = subscriptionPriceStartDateString(from: startDate)

        var savedCount = 0
        var skippedCount = 0
        var unavailableTerritoryIDs: [String] = []
        var existingFuturePriceTerritoryIDs: [String] = []
        var pendingRequests: [PendingSubscriptionPriceRequest] = []
        await MainActor.run {
            progress?(.init(stage: .preparing, completedCount: 0, totalCount: targets.count))
        }

        let resolvedPreparation: SubscriptionPriceSavePreparation
        if let preparation {
            resolvedPreparation = preparation
        } else {
            resolvedPreparation = try await prepareSubscriptionPriceSave(
                subscriptionID: subscriptionID,
                territoryIDs: targets.map(\.territoryID),
                bearerToken: token
            )
        }
        let pricePointsByTerritory = resolvedPreparation.pricePointsByTerritory
        let futureScheduledPriceIDsByTerritory = resolvedPreparation.futureScheduledPriceIDsByTerritory

        for (index, target) in targets.enumerated() {
            let selectedPricePoint: ASCSelectableSubscriptionPricePoint
            if let previewPricePointID = target.subscriptionPricePointID {
                selectedPricePoint = ASCSelectableSubscriptionPricePoint(
                    id: previewPricePointID,
                    territoryID: target.territoryID,
                    customerPrice: target.desiredPrice
                )
            } else {
                do {
                    selectedPricePoint = try await resolveClosestSubscriptionPricePoint(
                        territoryID: target.territoryID,
                        desiredPrice: target.desiredPrice,
                        pricePointsByTerritory: pricePointsByTerritory
                    )
                } catch ClientError.missingPricePoint {
                    unavailableTerritoryIDs.append(target.territoryID)
                    continue
                }
            }

            if let currentPrice = target.currentPrice,
               abs(currentPrice - selectedPricePoint.customerPrice) < 0.005 {
                skippedCount += 1
                continue
            }

            let requestBody = ASCSubscriptionPriceCreateRequest(
                data: .init(
                    attributes: .init(
                        startDate: scheduledStartDate,
                        preserveCurrentPrice: preserveCurrentPrice
                    ),
                    relationships: .init(
                        subscription: .init(data: .init(type: "subscriptions", id: subscriptionID)),
                        territory: .init(data: .init(type: "territories", id: target.territoryID)),
                        subscriptionPricePoint: .init(data: .init(type: "subscriptionPricePoints", id: selectedPricePoint.id))
                    )
                )
            )
            pendingRequests.append(
                PendingSubscriptionPriceRequest(
                    territoryID: target.territoryID,
                    futureScheduledPriceID: futureScheduledPriceIDsByTerritory[target.territoryID],
                    requestBody: requestBody
                )
            )
            await MainActor.run {
                progress?(.init(stage: .preparing, completedCount: index + 1, totalCount: targets.count))
            }
        }

        let totalPendingRequestCount = pendingRequests.count
        await MainActor.run {
            progress?(.init(stage: .saving, completedCount: 0, totalCount: totalPendingRequestCount))
        }
        let batchSize = 3
        let batchCooldownNanoseconds: UInt64 = 750_000_000
        for batchStart in stride(from: 0, to: pendingRequests.count, by: batchSize) {
            let batch = Array(pendingRequests[batchStart..<min(batchStart + batchSize, pendingRequests.count)])

            try await withThrowingTaskGroup(of: SubscriptionPriceSaveAttemptResult.self) { group in
                for pendingRequest in batch {
                    group.addTask {
                        do {
                            _ = try await send(
                                url: subscriptionPricesURL,
                                method: "POST",
                                bearerToken: token,
                                body: pendingRequest.requestBody
                            )
                            return .saved
                        } catch {
                            if isExistingFuturePriceConflict(error),
                               let existingFuturePriceID = pendingRequest.futureScheduledPriceID {
                                try await deleteSubscriptionPrice(
                                    id: existingFuturePriceID,
                                    bearerToken: token
                                )
                                _ = try await send(
                                    url: subscriptionPricesURL,
                                    method: "POST",
                                    bearerToken: token,
                                    body: pendingRequest.requestBody
                                )
                                return .saved
                            }

                            if isExistingFuturePriceConflict(error) {
                                return .existingFuturePrice(territoryID: pendingRequest.territoryID)
                            }
                            throw error
                        }
                    }
                }

                for try await result in group {
                    switch result {
                    case .saved:
                        savedCount += 1
                    case .existingFuturePrice(let territoryID):
                        existingFuturePriceTerritoryIDs.append(territoryID)
                    }

                    let completedCount = savedCount + existingFuturePriceTerritoryIDs.count
                    await MainActor.run {
                        progress?(.init(stage: .saving, completedCount: completedCount, totalCount: totalPendingRequestCount))
                    }
                }
            }

            if batchStart + batchSize < pendingRequests.count {
                try await Task.sleep(nanoseconds: batchCooldownNanoseconds)
            }
        }

        return SubscriptionPriceSaveResult(
            savedCount: savedCount,
            skippedCount: skippedCount,
            unavailableTerritoryIDs: unavailableTerritoryIDs,
            existingFuturePriceTerritoryIDs: existingFuturePriceTerritoryIDs
        )
    }

    fileprivate static func saveInAppPurchasePrices(
        inAppPurchaseID: String,
        baseTerritoryID: String,
        targets: [SubscriptionPriceSaveTarget],
        startDate: Date,
        issuerID: String,
        keyID: String,
        privateKeyData: Data,
        preparation: SubscriptionPriceSavePreparation? = nil,
        progress: (@MainActor @Sendable (SubscriptionPriceSaveProgress) -> Void)? = nil
    ) async throws -> SubscriptionPriceSaveResult {
        let token = try makeJWT(issuerID: issuerID, keyID: keyID, privateKeyData: privateKeyData)
        let scheduledStartDate = subscriptionPriceStartDateString(from: startDate)

        await MainActor.run {
            progress?(.init(stage: .preparing, completedCount: 0, totalCount: targets.count))
        }

        let resolvedPreparation: SubscriptionPriceSavePreparation
        if let preparation {
            resolvedPreparation = preparation
        } else {
            resolvedPreparation = try await prepareInAppPurchasePriceSave(
                inAppPurchaseID: inAppPurchaseID,
                territoryIDs: targets.map(\.territoryID),
                bearerToken: token
            )
        }

        let pricePointsByTerritory = resolvedPreparation.pricePointsByTerritory
        var manualPricesData: [ASCInAppPurchasePriceScheduleCreateRequest.ResourceIdentifier] = []
        var includedPrices: [ASCInAppPurchasePriceScheduleCreateRequest.IncludedPrice] = []
        var skippedCount = 0
        var unavailableTerritoryIDs: [String] = []

        for (index, target) in targets.enumerated() {
            let selectedPricePoint: ASCSelectableSubscriptionPricePoint
            if let previewPricePointID = target.subscriptionPricePointID {
                selectedPricePoint = ASCSelectableSubscriptionPricePoint(
                    id: previewPricePointID,
                    territoryID: target.territoryID,
                    customerPrice: target.desiredPrice
                )
            } else {
                do {
                    selectedPricePoint = try await resolveClosestSubscriptionPricePoint(
                        territoryID: target.territoryID,
                        desiredPrice: target.desiredPrice,
                        pricePointsByTerritory: pricePointsByTerritory
                    )
                } catch ClientError.missingPricePoint {
                    unavailableTerritoryIDs.append(target.territoryID)
                    continue
                }
            }

            let isBaseTerritory = target.territoryID == baseTerritoryID

            if !isBaseTerritory,
               let currentPrice = target.currentPrice,
               abs(currentPrice - selectedPricePoint.customerPrice) < 0.005 {
                skippedCount += 1
                continue
            }

            let localID = "${price-\(target.territoryID.lowercased())}"
            manualPricesData.append(.init(type: "inAppPurchasePrices", id: localID))
            includedPrices.append(
                .init(
                    id: localID,
                    attributes: .init(startDate: scheduledStartDate, endDate: nil),
                    relationships: .init(
                        inAppPurchaseV2: .init(
                            data: .init(type: "inAppPurchases", id: inAppPurchaseID)
                        ),
                        inAppPurchasePricePoint: .init(
                            data: .init(type: "inAppPurchasePricePoints", id: selectedPricePoint.id)
                        )
                    )
                )
            )

            await MainActor.run {
                progress?(.init(stage: .preparing, completedCount: index + 1, totalCount: targets.count))
            }
        }

        guard !includedPrices.isEmpty else {
            return SubscriptionPriceSaveResult(
                savedCount: 0,
                skippedCount: skippedCount,
                unavailableTerritoryIDs: unavailableTerritoryIDs,
                existingFuturePriceTerritoryIDs: []
            )
        }

        let requestBody = ASCInAppPurchasePriceScheduleCreateRequest(
            data: .init(
                relationships: .init(
                    inAppPurchase: .init(data: .init(type: "inAppPurchases", id: inAppPurchaseID)),
                    baseTerritory: .init(data: .init(type: "territories", id: baseTerritoryID)),
                    manualPrices: .init(data: manualPricesData)
                )
            ),
            included: includedPrices
        )

        await MainActor.run {
            progress?(.init(stage: .saving, completedCount: 0, totalCount: 1))
        }

        _ = try await send(
            url: URL(string: "https://api.appstoreconnect.apple.com/v1/inAppPurchasePriceSchedules")!,
            method: "POST",
            bearerToken: token,
            body: requestBody
        )

        await MainActor.run {
            progress?(.init(stage: .saving, completedCount: 1, totalCount: 1))
        }

        return SubscriptionPriceSaveResult(
            savedCount: includedPrices.count,
            skippedCount: skippedCount,
            unavailableTerritoryIDs: unavailableTerritoryIDs,
            existingFuturePriceTerritoryIDs: []
        )
    }

    fileprivate static func prepareSubscriptionPriceSave(
        subscriptionID: String,
        territoryIDs: [String],
        knownFutureScheduledPriceIDsByTerritory: [String: String] = [:],
        issuerID: String,
        keyID: String,
        privateKeyData: Data,
        progress: (@MainActor @Sendable (_ completedCount: Int, _ totalCount: Int) -> Void)? = nil
    ) async throws -> SubscriptionPriceSavePreparation {
        let token = try makeJWT(issuerID: issuerID, keyID: keyID, privateKeyData: privateKeyData)
        return try await prepareSubscriptionPriceSave(
            subscriptionID: subscriptionID,
            territoryIDs: territoryIDs,
            knownFutureScheduledPriceIDsByTerritory: knownFutureScheduledPriceIDsByTerritory,
            bearerToken: token,
            progress: progress
        )
    }

    fileprivate static func prepareInAppPurchasePriceSave(
        inAppPurchaseID: String,
        territoryIDs: [String],
        issuerID: String,
        keyID: String,
        privateKeyData: Data,
        progress: (@MainActor @Sendable (_ completedCount: Int, _ totalCount: Int) -> Void)? = nil
    ) async throws -> SubscriptionPriceSavePreparation {
        let token = try makeJWT(issuerID: issuerID, keyID: keyID, privateKeyData: privateKeyData)
        return try await prepareInAppPurchasePriceSave(
            inAppPurchaseID: inAppPurchaseID,
            territoryIDs: territoryIDs,
            bearerToken: token,
            progress: progress
        )
    }

    nonisolated private static func isExistingFuturePriceConflict(_ error: Error) -> Bool {
        guard case let ClientError.httpStatus(code, body) = error,
              code == 409,
              let body else {
            return false
        }

        return body.localizedCaseInsensitiveContains("You cannot create more than one future prices for territory")
    }

    private static func fetchAllSubscriptionPriceResponses(
        subscriptionID: String,
        bearerToken: String
    ) async throws -> [ASCSubscriptionPricesResponse] {
        var responses: [ASCSubscriptionPricesResponse] = []
        var nextURL: URL? = makeSubscriptionPricesURL(subscriptionID: subscriptionID)

        while let url = nextURL {
            let response: ASCSubscriptionPricesResponse = try await request(
                url: url,
                bearerToken: bearerToken
            )
            responses.append(response)
            nextURL = response.links?.next.flatMap(URL.init(string:))
        }

        return responses
    }

    private static func fetchInAppPurchasePriceSchedule(
        inAppPurchaseID: String,
        bearerToken: String
    ) async throws -> ASCInAppPurchasePriceScheduleSummary {
        let response: ASCInAppPurchasePriceScheduleResponse = try await request(
            url: makeInAppPurchasePriceScheduleURL(inAppPurchaseID: inAppPurchaseID),
            bearerToken: bearerToken
        )

        return ASCInAppPurchasePriceScheduleSummary(
            id: response.data.id,
            baseTerritoryID: response.data.relationships?.baseTerritory?.data?.id
        )
    }

    private static func fetchAllInAppPurchasePriceResponses(
        scheduleID: String,
        kind: ASCInAppPurchasePriceScheduleFetchKind,
        bearerToken: String
    ) async throws -> [ASCInAppPurchasePricesResponse] {
        var responses: [ASCInAppPurchasePricesResponse] = []
        var nextURL: URL? = makeInAppPurchasePricesURL(scheduleID: scheduleID, kind: kind)

        while let url = nextURL {
            let response: ASCInAppPurchasePricesResponse = try await request(
                url: url,
                bearerToken: bearerToken
            )
            responses.append(response)
            nextURL = response.links?.next.flatMap(URL.init(string:))
        }

        return responses
    }

    private static func prepareSubscriptionPriceSave(
        subscriptionID: String,
        territoryIDs: [String],
        knownFutureScheduledPriceIDsByTerritory: [String: String] = [:],
        bearerToken: String,
        progress: (@MainActor @Sendable (_ completedCount: Int, _ totalCount: Int) -> Void)? = nil
    ) async throws -> SubscriptionPriceSavePreparation {
        let uniqueTerritoryIDs = Array(Set(territoryIDs)).sorted()
        let totalTerritoryCount = uniqueTerritoryIDs.count
        var completedTerritoryCount = 0
        let cachedPricePointsByTerritory = loadCachedSubscriptionPricePoints(
            subscriptionID: subscriptionID,
            validFor: 24 * 60 * 60
        ) ?? [:]
        var allPricePoints = cachedPricePointsByTerritory
            .filter { uniqueTerritoryIDs.contains($0.key) }
            .flatMap(\.value)
        let preloadBatchSize = 3
        let territoryIDsNeedingFetch = uniqueTerritoryIDs.filter {
            (cachedPricePointsByTerritory[$0] ?? []).isEmpty
        }

        if totalTerritoryCount > 0 {
            await MainActor.run {
                progress?(0, totalTerritoryCount)
            }
        }

        if !cachedPricePointsByTerritory.isEmpty {
            completedTerritoryCount = uniqueTerritoryIDs.count - territoryIDsNeedingFetch.count
            let completedCount = completedTerritoryCount
            await MainActor.run {
                progress?(completedCount, totalTerritoryCount)
            }
        }

        for batchStart in stride(from: 0, to: territoryIDsNeedingFetch.count, by: preloadBatchSize) {
            let batch = Array(territoryIDsNeedingFetch[batchStart..<min(batchStart + preloadBatchSize, territoryIDsNeedingFetch.count)])

            try await withThrowingTaskGroup(of: [ASCSelectableSubscriptionPricePoint].self) { group in
                for territoryID in batch {
                    group.addTask {
                        try await fetchSubscriptionPricePointOptions(
                            subscriptionID: subscriptionID,
                            territoryID: territoryID,
                            bearerToken: bearerToken
                        )
                    }
                }

                for try await territoryPricePoints in group {
                    allPricePoints.append(contentsOf: territoryPricePoints)
                    completedTerritoryCount += 1
                    let completedCount = completedTerritoryCount
                    await MainActor.run {
                        progress?(completedCount, totalTerritoryCount)
                    }
                }
            }
        }

        storeCachedSubscriptionPricePoints(
            subscriptionID: subscriptionID,
            pricePoints: allPricePoints
        )

        return SubscriptionPriceSavePreparation(
            pricePointsByTerritory: Dictionary(grouping: allPricePoints, by: \.territoryID),
            futureScheduledPriceIDsByTerritory: try await resolvedFutureScheduledPriceIDsByTerritory(
                subscriptionID: subscriptionID,
                knownFutureScheduledPriceIDsByTerritory: knownFutureScheduledPriceIDsByTerritory,
                bearerToken: bearerToken
            )
        )
    }

    private static func prepareInAppPurchasePriceSave(
        inAppPurchaseID: String,
        territoryIDs: [String],
        bearerToken: String,
        progress: (@MainActor @Sendable (_ completedCount: Int, _ totalCount: Int) -> Void)? = nil
    ) async throws -> SubscriptionPriceSavePreparation {
        let uniqueTerritoryIDs = Array(Set(territoryIDs)).sorted()
        let totalTerritoryCount = uniqueTerritoryIDs.count
        var completedTerritoryCount = 0
        let cachedPricePointsByTerritory = loadCachedInAppPurchasePricePoints(
            inAppPurchaseID: inAppPurchaseID,
            validFor: 24 * 60 * 60
        ) ?? [:]
        var allPricePoints = cachedPricePointsByTerritory
            .filter { uniqueTerritoryIDs.contains($0.key) }
            .flatMap(\.value)
        let territoryIDsNeedingFetch = uniqueTerritoryIDs.filter {
            (cachedPricePointsByTerritory[$0] ?? []).isEmpty
        }

        if totalTerritoryCount > 0 {
            await MainActor.run {
                progress?(0, totalTerritoryCount)
            }
        }

        if !cachedPricePointsByTerritory.isEmpty {
            completedTerritoryCount = uniqueTerritoryIDs.count - territoryIDsNeedingFetch.count
            let completedCount = completedTerritoryCount
            await MainActor.run {
                progress?(completedCount, totalTerritoryCount)
            }
        }

        for territoryID in territoryIDsNeedingFetch {
            let territoryPricePoints = try await fetchInAppPurchasePricePointOptions(
                inAppPurchaseID: inAppPurchaseID,
                territoryID: territoryID,
                bearerToken: bearerToken
            )
            allPricePoints.append(contentsOf: territoryPricePoints)
            completedTerritoryCount += 1
            let completedCount = completedTerritoryCount
            await MainActor.run {
                progress?(completedCount, totalTerritoryCount)
            }
        }

        storeCachedInAppPurchasePricePoints(
            inAppPurchaseID: inAppPurchaseID,
            pricePoints: allPricePoints
        )

        return SubscriptionPriceSavePreparation(
            pricePointsByTerritory: Dictionary(grouping: allPricePoints, by: \.territoryID),
            futureScheduledPriceIDsByTerritory: [:]
        )
    }

    private static func futureScheduledSubscriptionPriceIDsByTerritory(
        subscriptionID: String,
        bearerToken: String
    ) async throws -> [String: String] {
        let responses = try await fetchAllSubscriptionPriceResponses(
            subscriptionID: subscriptionID,
            bearerToken: bearerToken
        )
        let allPrices = responses.flatMap(\.data)
        return futureScheduledPriceIDsByTerritory(from: allPrices)
    }

    private static func resolvedFutureScheduledPriceIDsByTerritory(
        subscriptionID: String,
        knownFutureScheduledPriceIDsByTerritory: [String: String],
        bearerToken: String
    ) async throws -> [String: String] {
        if !knownFutureScheduledPriceIDsByTerritory.isEmpty {
            return knownFutureScheduledPriceIDsByTerritory
        }

        return try await futureScheduledSubscriptionPriceIDsByTerritory(
            subscriptionID: subscriptionID,
            bearerToken: bearerToken
        )
    }

    private static func futureScheduledPriceIDsByTerritory(
        from prices: [ASCSubscriptionPriceItem]
    ) -> [String: String] {
        let today = Calendar(identifier: .gregorian).startOfDay(for: Date())

        return Dictionary(grouping: prices, by: { $0.relationships?.territory?.data?.id ?? "unknown" })
            .compactMapValues { items in
                items
                    .filter { item in
                        guard let startDate = item.attributes.startDate.flatMap(ascDate) else { return false }
                        return startDate > today
                    }
                    .sorted { lhs, rhs in
                        let lhsDate = lhs.attributes.startDate.flatMap(ascDate) ?? .distantFuture
                        let rhsDate = rhs.attributes.startDate.flatMap(ascDate) ?? .distantFuture
                        return lhsDate < rhsDate
                    }
                    .first?
                    .id
            }
    }

    private static func deleteSubscriptionPrice(
        id: String,
        bearerToken: String
    ) async throws {
        _ = try await send(
            url: URL(string: "https://api.appstoreconnect.apple.com/v1/subscriptionPrices/\(id)")!,
            method: "DELETE",
            bearerToken: bearerToken,
            body: Optional<Data>.none
        )
    }

    private static func loadCachedSubscriptionPricePoints(
        subscriptionID: String,
        validFor maxAge: TimeInterval
    ) -> [String: [ASCSelectableSubscriptionPricePoint]]? {
        guard let cacheURL = subscriptionPricePointCacheURL(subscriptionID: subscriptionID),
              let data = try? Data(contentsOf: cacheURL),
              let record = try? JSONDecoder.asc.decode(ASCSubscriptionPricePointCacheRecord.self, from: data),
              Date().timeIntervalSince(record.cachedAt) <= maxAge else {
            return nil
        }

        return Dictionary(grouping: record.pricePoints, by: \.territoryID)
    }

    private static func loadCachedInAppPurchasePricePoints(
        inAppPurchaseID: String,
        validFor maxAge: TimeInterval
    ) -> [String: [ASCSelectableSubscriptionPricePoint]]? {
        guard let cacheURL = inAppPurchasePricePointCacheURL(inAppPurchaseID: inAppPurchaseID),
              let data = try? Data(contentsOf: cacheURL),
              let record = try? JSONDecoder.asc.decode(ASCSubscriptionPricePointCacheRecord.self, from: data),
              Date().timeIntervalSince(record.cachedAt) <= maxAge else {
            return nil
        }

        return Dictionary(grouping: record.pricePoints, by: \.territoryID)
    }

    private static func storeCachedSubscriptionPricePoints(
        subscriptionID: String,
        pricePoints: [ASCSelectableSubscriptionPricePoint]
    ) {
        guard let cacheURL = subscriptionPricePointCacheURL(subscriptionID: subscriptionID) else { return }

        let record = ASCSubscriptionPricePointCacheRecord(
            cachedAt: Date(),
            pricePoints: pricePoints
        )

        do {
            let directoryURL = cacheURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(record)
            try data.write(to: cacheURL, options: .atomic)
        } catch {
        }
    }

    private static func storeCachedInAppPurchasePricePoints(
        inAppPurchaseID: String,
        pricePoints: [ASCSelectableSubscriptionPricePoint]
    ) {
        guard let cacheURL = inAppPurchasePricePointCacheURL(inAppPurchaseID: inAppPurchaseID) else { return }

        let record = ASCSubscriptionPricePointCacheRecord(
            cachedAt: Date(),
            pricePoints: pricePoints
        )

        do {
            let directoryURL = cacheURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(record)
            try data.write(to: cacheURL, options: .atomic)
        } catch {
        }
    }

    private static func subscriptionPricePointCacheURL(subscriptionID: String) -> URL? {
        guard let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }

        let cacheDirectory = cachesDirectory
            .appendingPathComponent("PriceParity", isDirectory: true)
            .appendingPathComponent("ASCSubscriptionPricePoints", isDirectory: true)

        return cacheDirectory.appendingPathComponent("\(subscriptionID).json")
    }

    private static func inAppPurchasePricePointCacheURL(inAppPurchaseID: String) -> URL? {
        guard let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }

        let cacheDirectory = cachesDirectory
            .appendingPathComponent("PriceParity", isDirectory: true)
            .appendingPathComponent("ASCInAppPurchasePricePoints", isDirectory: true)

        return cacheDirectory.appendingPathComponent("\(inAppPurchaseID).json")
    }

    static func clearSubscriptionPricePointCache() throws {
        guard let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return
        }

        let subscriptionCacheDirectory = cachesDirectory
            .appendingPathComponent("PriceParity", isDirectory: true)
            .appendingPathComponent("ASCSubscriptionPricePoints", isDirectory: true)

        if FileManager.default.fileExists(atPath: subscriptionCacheDirectory.path) {
            try FileManager.default.removeItem(at: subscriptionCacheDirectory)
        }

        let inAppPurchaseCacheDirectory = cachesDirectory
            .appendingPathComponent("PriceParity", isDirectory: true)
            .appendingPathComponent("ASCInAppPurchasePricePoints", isDirectory: true)

        if FileManager.default.fileExists(atPath: inAppPurchaseCacheDirectory.path) {
            try FileManager.default.removeItem(at: inAppPurchaseCacheDirectory)
        }
    }

    fileprivate static func fetchTerritories(
        issuerID: String,
        keyID: String,
        privateKeyData: Data
    ) async throws -> [ASCTerritoryItem] {
        let token = try makeJWT(issuerID: issuerID, keyID: keyID, privateKeyData: privateKeyData)
        let response: ASCTerritoriesResponse = try await request(
            url: makeTerritoriesURL(),
            bearerToken: token
        )

        return response.data.sorted { lhs, rhs in
            if lhs.id == "USA" { return true }
            if rhs.id == "USA" { return false }
            return localizedTerritoryDisplayName(lhs.id).localizedCaseInsensitiveCompare(localizedTerritoryDisplayName(rhs.id)) == .orderedAscending
        }
    }

    fileprivate static func fetchSubscriptionPricePointOptions(
        subscriptionID: String,
        territoryID: String? = nil,
        issuerID: String,
        keyID: String,
        privateKeyData: Data
    ) async throws -> [ASCSelectableSubscriptionPricePoint] {
        let token = try makeJWT(issuerID: issuerID, keyID: keyID, privateKeyData: privateKeyData)
        return try await fetchSubscriptionPricePointOptions(
            subscriptionID: subscriptionID,
            territoryID: territoryID,
            bearerToken: token
        )
    }

    fileprivate static func fetchInAppPurchasePricePointOptions(
        inAppPurchaseID: String,
        territoryID: String? = nil,
        issuerID: String,
        keyID: String,
        privateKeyData: Data
    ) async throws -> [ASCSelectableSubscriptionPricePoint] {
        let token = try makeJWT(issuerID: issuerID, keyID: keyID, privateKeyData: privateKeyData)
        return try await fetchInAppPurchasePricePointOptions(
            inAppPurchaseID: inAppPurchaseID,
            territoryID: territoryID,
            bearerToken: token
        )
    }

    fileprivate static func fetchEqualizedSubscriptionPricePoints(
        basePricePointID: String,
        issuerID: String,
        keyID: String,
        privateKeyData: Data
    ) async throws -> [ASCSelectableSubscriptionPricePoint] {
        let token = try makeJWT(issuerID: issuerID, keyID: keyID, privateKeyData: privateKeyData)
        return try await fetchEqualizedSubscriptionPricePoints(
            basePricePointID: basePricePointID,
            bearerToken: token
        )
    }

    private static func fetchSubscriptionPricePointOptions(
        subscriptionID: String,
        territoryID: String? = nil,
        bearerToken: String
    ) async throws -> [ASCSelectableSubscriptionPricePoint] {
        var allPoints: [ASCSelectableSubscriptionPricePoint] = []
        var nextURL: URL? = makeSubscriptionPricePointsURL(subscriptionID: subscriptionID, territoryID: territoryID)

        while let url = nextURL {
            let response: ASCSubscriptionPricePointsResponse = try await request(
                url: url,
                bearerToken: bearerToken
            )

            let pagePoints = response.data.compactMap { item -> ASCSelectableSubscriptionPricePoint? in
                let resolvedTerritoryID =
                    item.relationships?.territory?.data?.id ??
                    territoryID ??
                    response.included?.first?.id

                guard let resolvedTerritoryID,
                      let customerPrice = Double(item.attributes.customerPrice ?? "") else {
                    return nil
                }

                return ASCSelectableSubscriptionPricePoint(
                    id: item.id,
                    territoryID: resolvedTerritoryID,
                    customerPrice: customerPrice
                )
            }

            allPoints.append(contentsOf: pagePoints)
            nextURL = response.links?.next.flatMap(URL.init(string:))
        }

        return allPoints
    }

    private static func fetchInAppPurchasePricePointOptions(
        inAppPurchaseID: String,
        territoryID: String? = nil,
        bearerToken: String
    ) async throws -> [ASCSelectableSubscriptionPricePoint] {
        var allPoints: [ASCSelectableSubscriptionPricePoint] = []
        var nextURL: URL? = makeInAppPurchasePricePointsURL(
            inAppPurchaseID: inAppPurchaseID,
            territoryID: territoryID
        )

        while let url = nextURL {
            let response: ASCInAppPurchasePricePointsResponse = try await request(
                url: url,
                bearerToken: bearerToken
            )

            let pagePoints = response.data.compactMap { item -> ASCSelectableSubscriptionPricePoint? in
                let resolvedTerritoryID =
                    item.relationships?.territory?.data?.id ??
                    territoryID ??
                    response.included?.first?.id

                guard let resolvedTerritoryID,
                      let customerPrice = Double(item.attributes.customerPrice ?? "") else {
                    return nil
                }

                return ASCSelectableSubscriptionPricePoint(
                    id: item.id,
                    territoryID: resolvedTerritoryID,
                    customerPrice: customerPrice
                )
            }

            allPoints.append(contentsOf: pagePoints)
            nextURL = response.links?.next.flatMap(URL.init(string:))
        }

        return allPoints
    }

    private static func fetchEqualizedSubscriptionPricePoints(
        basePricePointID: String,
        bearerToken: String
    ) async throws -> [ASCSelectableSubscriptionPricePoint] {
        var allPoints: [ASCSelectableSubscriptionPricePoint] = []
        var nextURL: URL? = makeSubscriptionPricePointEqualizationsURL(basePricePointID: basePricePointID)

        while let url = nextURL {
            let response: ASCSubscriptionPricePointsResponse = try await request(
                url: url,
                bearerToken: bearerToken
            )

            let pagePoints = response.data.compactMap { item -> ASCSelectableSubscriptionPricePoint? in
                guard let territoryID = item.relationships?.territory?.data?.id,
                      let customerPrice = Double(item.attributes.customerPrice ?? "") else {
                    return nil
                }

                return ASCSelectableSubscriptionPricePoint(
                    id: item.id,
                    territoryID: territoryID,
                    customerPrice: customerPrice
                )
            }

            allPoints.append(contentsOf: pagePoints)
            nextURL = response.links?.next.flatMap(URL.init(string:))
        }

        return allPoints
    }

    private static func resolveClosestSubscriptionPricePoint(
        territoryID: String,
        desiredPrice: Double,
        pricePointsByTerritory: [String: [ASCSelectableSubscriptionPricePoint]]
    ) async throws -> ASCSelectableSubscriptionPricePoint {
        let localOptions = pricePointsByTerritory[territoryID] ?? []
        if let closestLocal = closestPricePoint(in: localOptions, desiredPrice: desiredPrice) {
            return closestLocal
        }

        throw ClientError.missingPricePoint(territoryID)
    }

    private static func closestPricePoint(
        in options: [ASCSelectableSubscriptionPricePoint],
        desiredPrice: Double
    ) -> ASCSelectableSubscriptionPricePoint? {
        closestSelectablePricePoint(in: options, desiredPrice: desiredPrice)
    }

    static func minimumSubscriptionPriceStartDate(now: Date = Date()) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        let startOfDay = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: 2, to: startOfDay) ?? startOfDay
    }

    private static func subscriptionPriceStartDateString(from date: Date) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let normalizedDate = calendar.startOfDay(for: date)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: normalizedDate)
    }

    private static func makeAppsListURL() -> URL {
        var components = URLComponents(url: appsURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "limit", value: "50"),
            URLQueryItem(name: "fields[apps]", value: "name,bundleId,sku,primaryLocale")
        ]
        return components.url ?? appsURL
    }

    private static func makeAppInAppPurchasesURL(appID: String) -> URL {
        var components = URLComponents(url: URL(string: "https://api.appstoreconnect.apple.com/v1/apps/\(appID)/inAppPurchasesV2")!, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "fields[inAppPurchases]", value: "name,productId,inAppPurchaseType,state"),
            URLQueryItem(name: "limit", value: "50")
        ]
        return components.url ?? URL(string: "https://api.appstoreconnect.apple.com/v1/apps/\(appID)/inAppPurchasesV2")!
    }

    private static func makeAppSubscriptionGroupsURL(appID: String) -> URL {
        var components = URLComponents(url: URL(string: "https://api.appstoreconnect.apple.com/v1/apps/\(appID)")!, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "include", value: "subscriptionGroups"),
            URLQueryItem(name: "fields[subscriptionGroups]", value: "referenceName")
        ]
        return components.url ?? URL(string: "https://api.appstoreconnect.apple.com/v1/apps/\(appID)")!
    }

    private static func makeSubscriptionsURL(subscriptionGroupID: String) -> URL {
        var components = URLComponents(url: URL(string: "https://api.appstoreconnect.apple.com/v1/subscriptionGroups/\(subscriptionGroupID)/subscriptions")!, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "limit", value: "50"),
            URLQueryItem(name: "fields[subscriptions]", value: "name,productId,state")
        ]
        return components.url ?? URL(string: "https://api.appstoreconnect.apple.com/v1/subscriptionGroups/\(subscriptionGroupID)/subscriptions")!
    }

    private static func makeSubscriptionPricesURL(subscriptionID: String) -> URL {
        var components = URLComponents(url: URL(string: "https://api.appstoreconnect.apple.com/v1/subscriptions/\(subscriptionID)/prices")!, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "fields[subscriptionPrices]", value: "startDate,preserved,planType,territory,subscriptionPricePoint"),
            URLQueryItem(name: "fields[subscriptionPricePoints]", value: "customerPrice,proceeds,proceedsYear2"),
            URLQueryItem(name: "fields[territories]", value: "currency"),
            URLQueryItem(name: "include", value: "territory,subscriptionPricePoint"),
            URLQueryItem(name: "limit", value: "200")
        ]
        return components.url ?? URL(string: "https://api.appstoreconnect.apple.com/v1/subscriptions/\(subscriptionID)/prices")!
    }

    private static func makeInAppPurchasePriceScheduleURL(inAppPurchaseID: String) -> URL {
        var components = URLComponents(url: URL(string: "https://api.appstoreconnect.apple.com/v2/inAppPurchases/\(inAppPurchaseID)/iapPriceSchedule")!, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "fields[inAppPurchasePriceSchedules]", value: "baseTerritory"),
            URLQueryItem(name: "include", value: "baseTerritory"),
            URLQueryItem(name: "fields[territories]", value: "currency")
        ]
        return components.url ?? URL(string: "https://api.appstoreconnect.apple.com/v2/inAppPurchases/\(inAppPurchaseID)/iapPriceSchedule")!
    }

    private static func makeInAppPurchasePricesURL(
        scheduleID: String,
        kind: ASCInAppPurchasePriceScheduleFetchKind
    ) -> URL {
        let pathComponent = kind == .automatic ? "automaticPrices" : "manualPrices"
        var components = URLComponents(url: URL(string: "https://api.appstoreconnect.apple.com/v1/inAppPurchasePriceSchedules/\(scheduleID)/\(pathComponent)")!, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "fields[inAppPurchasePrices]", value: "startDate,endDate,manual,inAppPurchasePricePoint,territory"),
            URLQueryItem(name: "fields[inAppPurchasePricePoints]", value: "customerPrice,proceeds,territory"),
            URLQueryItem(name: "fields[territories]", value: "currency"),
            URLQueryItem(name: "include", value: "inAppPurchasePricePoint,territory"),
            URLQueryItem(name: "limit", value: "200")
        ]
        return components.url ?? URL(string: "https://api.appstoreconnect.apple.com/v1/inAppPurchasePriceSchedules/\(scheduleID)/\(pathComponent)")!
    }

    private static func makeSubscriptionPricePointsURL(subscriptionID: String, territoryID: String? = nil) -> URL {
        var components = URLComponents(url: URL(string: "https://api.appstoreconnect.apple.com/v1/subscriptions/\(subscriptionID)/pricePoints")!, resolvingAgainstBaseURL: false)!
        var queryItems = [
            URLQueryItem(name: "fields[subscriptionPricePoints]", value: "customerPrice,territory"),
            URLQueryItem(name: "fields[territories]", value: "currency"),
            URLQueryItem(name: "include", value: "territory"),
            URLQueryItem(name: "limit", value: "8000")
        ]
        if let territoryID, !territoryID.isEmpty {
            queryItems.append(URLQueryItem(name: "filter[territory]", value: territoryID))
        }
        components.queryItems = queryItems
        return components.url ?? URL(string: "https://api.appstoreconnect.apple.com/v1/subscriptions/\(subscriptionID)/pricePoints")!
    }

    private static func makeInAppPurchasePricePointsURL(inAppPurchaseID: String, territoryID: String? = nil) -> URL {
        var components = URLComponents(url: URL(string: "https://api.appstoreconnect.apple.com/v2/inAppPurchases/\(inAppPurchaseID)/pricePoints")!, resolvingAgainstBaseURL: false)!
        var queryItems = [
            URLQueryItem(name: "fields[inAppPurchasePricePoints]", value: "customerPrice,proceeds,territory"),
            URLQueryItem(name: "fields[territories]", value: "currency"),
            URLQueryItem(name: "include", value: "territory"),
            URLQueryItem(name: "limit", value: "8000")
        ]
        if let territoryID, !territoryID.isEmpty {
            queryItems.append(URLQueryItem(name: "filter[territory]", value: territoryID))
        }
        components.queryItems = queryItems
        return components.url ?? URL(string: "https://api.appstoreconnect.apple.com/v2/inAppPurchases/\(inAppPurchaseID)/pricePoints")!
    }

    private static func makeSubscriptionPricePointEqualizationsURL(basePricePointID: String) -> URL {
        var components = URLComponents(url: URL(string: "https://api.appstoreconnect.apple.com/v1/subscriptionPricePoints/\(basePricePointID)/equalizations")!, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "fields[subscriptionPricePoints]", value: "customerPrice,territory"),
            URLQueryItem(name: "include", value: "territory"),
            URLQueryItem(name: "limit", value: "8000")
        ]
        return components.url ?? URL(string: "https://api.appstoreconnect.apple.com/v1/subscriptionPricePoints/\(basePricePointID)/equalizations")!
    }

    private static func makeTerritoriesURL() -> URL {
        var components = URLComponents(url: URL(string: "https://api.appstoreconnect.apple.com/v1/territories")!, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "fields[territories]", value: "currency"),
            URLQueryItem(name: "limit", value: "200")
        ]
        return components.url ?? URL(string: "https://api.appstoreconnect.apple.com/v1/territories")!
    }

    private static func fetchAppIconURL(bundleID: String?) async throws -> URL? {
        guard let bundleID, !bundleID.isEmpty else { return nil }

        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [
            URLQueryItem(name: "bundleId", value: bundleID)
        ]

        guard let url = components.url else { return nil }

        let response: ITunesLookupResponse = try await request(url: url, bearerToken: "")
        return response.results.first?.artworkURL
    }

    private static func request<Response: Decodable>(url: URL, bearerToken: String) async throws -> Response {
        let data = try await send(url: url, method: "GET", bearerToken: bearerToken, body: Optional<Data>.none)
        do {
            return try JSONDecoder.asc.decode(Response.self, from: data)
        } catch {
            throw ClientError.invalidResponse(200, body: String(data: data, encoding: .utf8))
        }
    }

    private static func send<RequestBody: Encodable>(
        url: URL,
        method: String,
        bearerToken: String,
        body: RequestBody?
    ) async throws -> Data {
        let encodedBody = try body.map { try JSONEncoder().encode($0) }

        let maxAttempts = 6
        var attempt = 0

        while true {
            attempt += 1

            var request = URLRequest(url: url)
            request.httpMethod = method
            request.timeoutInterval = 120
            if !bearerToken.isEmpty {
                request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
            }
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let encodedBody {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = encodedBody
            }

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                _ = try validateHTTPResponse(response, data: data)
                return data
            } catch {
                guard attempt < maxAttempts,
                      isRetryableNetworkError(error) else {
                    throw error
                }

                let delaySeconds = min(pow(2.0, Double(attempt - 1)), 8.0)
                let jitterMultiplier = Double.random(in: 0.85...1.25)
                let delayNanoseconds = UInt64(delaySeconds * jitterMultiplier * 1_000_000_000)
                try await Task.sleep(nanoseconds: delayNanoseconds)
            }
        }
    }

    private static func validateHTTPResponse(_ response: URLResponse, data: Data) throws -> HTTPURLResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse(-1, body: String(data: data, encoding: .utf8))
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ClientError.httpStatus(httpResponse.statusCode, body: String(data: data, encoding: .utf8))
        }

        return httpResponse
    }

    private static func makeJWT(issuerID: String, keyID: String, privateKeyData: Data) throws -> String {
        guard let pem = String(data: privateKeyData, encoding: .utf8) else {
            throw ClientError.invalidPrivateKeyEncoding
        }

        let privateKey: P256.Signing.PrivateKey
        do {
            privateKey = try P256.Signing.PrivateKey(pemRepresentation: pem)
        } catch {
            throw ClientError.invalidPrivateKey(error.localizedDescription)
        }

        let now = Int(Date().timeIntervalSince1970)
        let headerJSON = #"{"alg":"ES256","kid":"\#(keyID)","typ":"JWT"}"#
        let payloadJSON = #"{"iss":"\#(issuerID)","iat":\#(now),"exp":\#(now + 19 * 60),"aud":"appstoreconnect-v1"}"#
        let signingInput = "\(Data(headerJSON.utf8).base64URLString()).\(Data(payloadJSON.utf8).base64URLString())"
        let signature = try privateKey.signature(for: Data(signingInput.utf8))

        return "\(signingInput).\(signature.rawRepresentation.base64URLString())"
    }

    private static func isRateLimitExceeded(_ error: Error) -> Bool {
        guard case let ClientError.httpStatus(code, body) = error,
              code == 429 else {
            return false
        }

        guard let body else { return true }
        return body.localizedCaseInsensitiveContains("RATE_LIMIT_EXCEEDED")
            || body.localizedCaseInsensitiveContains("request rate limit")
    }

    private static func isRetryableNetworkError(_ error: Error) -> Bool {
        if isRateLimitExceeded(error) {
            return true
        }

        if case let ClientError.httpStatus(code, _) = error,
           [500, 502, 503, 504].contains(code) {
            return true
        }

        guard let urlError = error as? URLError else {
            return false
        }

        switch urlError.code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .notConnectedToInternet:
            return true
        default:
            return false
        }
    }
}

private struct ASCAppRecord {
    let id: String
    let name: String
    let bundleID: String?
}

struct ASCSelectableSubscriptionPricePoint: Codable {
    let id: String
    let territoryID: String
    let customerPrice: Double
}

private struct ASCSubscriptionPricePointCacheRecord: Codable {
    let cachedAt: Date
    let pricePoints: [ASCSelectableSubscriptionPricePoint]
}

private struct SubscriptionPriceReviewItem: Identifiable {
    let territoryID: String
    let territoryName: String
    let flag: String
    let currentPriceText: String
    let newPriceText: String
    let source: PriceParitySource

    var id: String { territoryID }
}

private struct ManualOverrideSelection: Identifiable {
    let regionID: String

    var id: String { regionID }
}

private struct SubscriptionPriceSaveProgress {
    let stage: Stage
    let completedCount: Int
    let totalCount: Int

    enum Stage {
        case preparing
        case saving

        var title: String {
            switch self {
            case .preparing:
                return "Preparing price updates"
            case .saving:
                return "Saving to App Store Connect"
            }
        }
    }

    var fraction: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }

    var fractionText: String {
        "\(completedCount)/\(totalCount)"
    }

    var detailText: String {
        switch stage {
        case .preparing:
            return "Matching each country to the closest App Store Connect price point."
        case .saving:
            return "Sending scheduled price changes to App Store Connect."
        }
    }
}

private struct ASCSubscriptionPriceCreateRequest: Encodable, Sendable {
    let data: DataPayload

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(data, forKey: .data)
    }

    private enum CodingKeys: String, CodingKey {
        case data
    }

    struct DataPayload: Encodable, Sendable {
        let type = "subscriptionPrices"
        let attributes: Attributes?
        let relationships: Relationships
    }

    struct Attributes: Encodable, Sendable {
        let startDate: String?
        let preserveCurrentPrice: Bool?

        init(
            startDate: String? = nil,
            preserveCurrentPrice: Bool? = nil
        ) {
            self.startDate = startDate
            self.preserveCurrentPrice = preserveCurrentPrice
        }
    }

    struct Relationships: Encodable, Sendable {
        let subscription: Relationship
        let territory: Relationship?
        let subscriptionPricePoint: Relationship
    }

    struct Relationship: Encodable, Sendable {
        let data: ResourceIdentifier
    }

    struct ResourceIdentifier: Encodable, Sendable {
        let type: String
        let id: String
    }
}

private struct ASCInAppPurchasePriceScheduleCreateRequest: Encodable, Sendable {
    let data: DataPayload
    let included: [IncludedPrice]

    struct DataPayload: Encodable, Sendable {
        let type = "inAppPurchasePriceSchedules"
        let relationships: Relationships
    }

    struct Relationships: Encodable, Sendable {
        let inAppPurchase: ResourceLinkage
        let baseTerritory: ResourceLinkage
        let manualPrices: ResourceCollectionLinkage
    }

    struct ResourceLinkage: Encodable, Sendable {
        let data: ResourceIdentifier
    }

    struct ResourceCollectionLinkage: Encodable, Sendable {
        let data: [ResourceIdentifier]
    }

    struct ResourceIdentifier: Encodable, Sendable {
        let type: String
        let id: String
    }

    struct IncludedPrice: Encodable, Sendable {
        let type = "inAppPurchasePrices"
        let id: String
        let attributes: Attributes
        let relationships: IncludedRelationships
    }

    struct Attributes: Encodable, Sendable {
        let startDate: String?
        let endDate: String?
    }

    struct IncludedRelationships: Encodable, Sendable {
        let inAppPurchaseV2: ResourceLinkage?
        let inAppPurchasePricePoint: ResourceLinkage
    }
}

struct SubscriptionPriceSaveTarget {
    let territoryID: String
    let desiredPrice: Double
    let currentPrice: Double?
    let subscriptionPricePointID: String?
}

private struct SubscriptionPriceSaveResult {
    let savedCount: Int
    let skippedCount: Int
    let unavailableTerritoryIDs: [String]
    let existingFuturePriceTerritoryIDs: [String]

    var unavailableTerritoryCount: Int {
        unavailableTerritoryIDs.count
    }

    var existingFuturePriceTerritoryCount: Int {
        existingFuturePriceTerritoryIDs.count
    }
}

private struct PendingSubscriptionPriceRequest: Sendable {
    let territoryID: String
    let futureScheduledPriceID: String?
    let requestBody: ASCSubscriptionPriceCreateRequest
}

struct SubscriptionPriceSavePreparation {
    let pricePointsByTerritory: [String: [ASCSelectableSubscriptionPricePoint]]
    let futureScheduledPriceIDsByTerritory: [String: String]
}

private enum SubscriptionPriceSaveAttemptResult: Sendable {
    case saved
    case existingFuturePrice(territoryID: String)
}

private struct AppPurchaseCounts {
    let subscriptionCount: Int
    let iapCount: Int
}

private struct ASCAppsResponse: Decodable {
    let data: [ASCAppItem]
    let links: ASCPaginationLinks?
}

private struct ASCAppDetailResponse: Decodable {
    let data: ASCAppItem
    let included: [ASCInAppPurchaseItem]?
}

private struct ASCAppItem: Decodable {
    let id: String
    let attributes: ASCAppAttributes
}

private struct ASCAppAttributes: Decodable {
    let name: String
    let bundleID: String?

    private enum CodingKeys: String, CodingKey {
        case name
        case bundleID = "bundleId"
    }
}

private struct ASCInAppPurchasesResponse: Decodable {
    let data: [ASCInAppPurchaseItem]
    let links: ASCPaginationLinks?
}

private struct ASCAppSubscriptionGroupsResponse: Decodable {
    let data: ASCAppItem
    let included: [ASCSubscriptionGroupItem]?
}

private struct ASCSubscriptionGroupItem: Decodable {
    let id: String
    let attributes: ASCSubscriptionGroupAttributes
}

private struct ASCSubscriptionGroupAttributes: Decodable {
    let referenceName: String?
}

private struct ASCSubscriptionsResponse: Decodable {
    let data: [ASCSubscriptionItem]
    let links: ASCPaginationLinks?
}

private struct ASCSubscriptionPricesResponse: Decodable {
    let data: [ASCSubscriptionPriceItem]
    let included: [ASCSubscriptionPriceIncluded]?
    let links: ASCPaginationLinks?
}

private struct ASCSubscriptionPriceItem: Decodable {
    let id: String
    let attributes: ASCSubscriptionPriceAttributes
    let relationships: ASCSubscriptionPriceRelationships?
}

private struct ASCSubscriptionPriceAttributes: Decodable {
    let startDate: String?
    let preserved: Bool?
    let planType: SubscriptionPlanType?
}

private struct ASCSubscriptionPriceRelationships: Decodable {
    let territory: ASCRelationshipLink?
    let subscriptionPricePoint: ASCRelationshipLink?
}

private enum ASCSubscriptionPriceIncluded: Decodable {
    case territory(ASCTerritoryItem)
    case pricePoint(ASCSubscriptionPricePointItem)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "territories":
            self = .territory(try ASCTerritoryItem(from: decoder))
        case "subscriptionPricePoints":
            self = .pricePoint(try ASCSubscriptionPricePointItem(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unsupported included resource type: \(type)"
            )
        }
    }
}

private struct ASCSubscriptionPricePointItem: Decodable {
    let id: String
    let attributes: ASCSubscriptionPricePointAttributes
    let relationships: ASCSubscriptionPricePointRelationships?
}

private struct ASCSubscriptionPricePointsResponse: Decodable {
    let data: [ASCSubscriptionPricePointItem]
    let included: [ASCTerritoryItem]?
    let links: ASCPaginationLinks?
}

private struct ASCInAppPurchasePriceScheduleResponse: Decodable {
    let data: ASCInAppPurchasePriceScheduleItem
}

private struct ASCInAppPurchasePriceScheduleItem: Decodable {
    let id: String
    let relationships: ASCInAppPurchasePriceScheduleRelationships?
}

private struct ASCInAppPurchasePriceScheduleRelationships: Decodable {
    let baseTerritory: ASCRelationshipLink?
}

private struct ASCInAppPurchasePriceScheduleSummary {
    let id: String
    let baseTerritoryID: String?
}

private enum ASCInAppPurchasePriceScheduleFetchKind {
    case automatic
    case manual
}

private struct ASCInAppPurchasePricesResponse: Decodable {
    let data: [ASCInAppPurchasePriceItem]
    let included: [ASCInAppPurchasePriceIncluded]?
    let links: ASCPaginationLinks?
}

private struct ASCInAppPurchasePriceItem: Decodable {
    let id: String
    let attributes: ASCInAppPurchasePriceAttributes
    let relationships: ASCInAppPurchasePriceRelationships?
}

private struct ASCInAppPurchasePriceAttributes: Decodable {
    let startDate: String?
    let endDate: String?
    let manual: Bool?
}

private struct ASCInAppPurchasePriceRelationships: Decodable {
    let territory: ASCRelationshipLink?
    let inAppPurchasePricePoint: ASCRelationshipLink?
}

private enum ASCInAppPurchasePriceIncluded: Decodable {
    case territory(ASCTerritoryItem)
    case pricePoint(ASCInAppPurchasePricePointItem)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "territories":
            self = .territory(try ASCTerritoryItem(from: decoder))
        case "inAppPurchasePricePoints":
            self = .pricePoint(try ASCInAppPurchasePricePointItem(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unsupported included resource type: \(type)"
            )
        }
    }
}

private struct ASCInAppPurchasePricePointItem: Decodable {
    let id: String
    let attributes: ASCInAppPurchasePricePointAttributes
    let relationships: ASCSubscriptionPricePointRelationships?
}

private struct ASCInAppPurchasePricePointsResponse: Decodable {
    let data: [ASCInAppPurchasePricePointItem]
    let included: [ASCTerritoryItem]?
    let links: ASCPaginationLinks?
}

private struct ASCInAppPurchasePricePointAttributes: Decodable {
    let customerPrice: String?
    let proceeds: String?
}

private struct ASCSubscriptionPricePointAttributes: Decodable {
    let customerPrice: String?
    let proceeds: String?
    let proceedsYear2: String?
}

private struct ASCSubscriptionPricePointRelationships: Decodable {
    let territory: ASCRelationshipLink?
}

fileprivate struct ASCTerritoryItem: Decodable {
    let id: String
    let attributes: ASCTerritoryAttributes
}

private struct ASCTerritoriesResponse: Decodable {
    let data: [ASCTerritoryItem]
    let links: ASCPaginationLinks?
}

private struct ASCTerritoryAttributes: Decodable {
    let currency: String?
}

private enum SubscriptionPlanType: String, Decodable {
    case monthly = "MONTHLY"
    case upfront = "UPFRONT"
}

private struct ASCSubscriptionItem: Decodable {
    let id: String
    let attributes: ASCSubscriptionAttributes
}

private struct ASCSubscriptionAttributes: Decodable {
    let name: String?
    let referenceName: String?
    let productID: String?
    let state: InAppPurchaseState?

    private enum CodingKeys: String, CodingKey {
        case name
        case referenceName
        case productID = "productId"
        case state
    }
}

private struct ASCInAppPurchaseItem: Decodable {
    let id: String
    let attributes: ASCInAppPurchaseAttributes
    let relationships: ASCInAppPurchaseRelationships?
}

private struct ASCInAppPurchaseRelationships: Decodable {
    let subscriptionGroup: ASCRelationshipLink?
}

private struct ASCRelationshipLink: Decodable {
    let data: ASCRelationshipData?
}

private struct ASCRelationshipData: Decodable {
    let id: String
    let type: String
}

private struct ASCInAppPurchaseAttributes: Decodable {
    let name: String?
    let referenceName: String?
    let productID: String?
    let inAppPurchaseType: InAppPurchaseType
    let state: InAppPurchaseState?

    private enum CodingKeys: String, CodingKey {
        case name
        case referenceName
        case productID = "productId"
        case inAppPurchaseType
        case state
    }
}

enum InAppPurchaseState: String, Decodable {
    case approved = "APPROVED"
    case developerRemovedFromSale = "DEVELOPER_REMOVED_FROM_SALE"
    case readyToSubmit = "READY_TO_SUBMIT"
    case waitingForReview = "WAITING_FOR_REVIEW"
    case inReview = "IN_REVIEW"
    case rejected = "REJECTED"
    case missingMetadata = "MISSING_METADATA"
    case developerActionNeeded = "DEVELOPER_ACTION_NEEDED"
    case pendingDeveloperRelease = "PENDING_DEVELOPER_RELEASE"
    case pendingAppleReview = "PENDING_APPLE_REVIEW"
    case pendingContract = "PENDING_CONTRACT"
    case processing = "PROCESSING"
    case waitingForExportCompliance = "WAITING_FOR_EXPORT_COMPLIANCE"
    case deferred = "DEFERRED"
    case unknown
}

private extension InAppPurchaseState {
    var displayName: String {
        switch self {
        case .approved:
            return "Approved"
        case .developerRemovedFromSale:
            return "Removed From Sale"
        case .readyToSubmit:
            return "Ready To Submit"
        case .waitingForReview:
            return "Waiting For Review"
        case .inReview:
            return "In Review"
        case .rejected:
            return "Rejected"
        case .missingMetadata:
            return "Missing Metadata"
        case .developerActionNeeded:
            return "Developer Action Needed"
        case .pendingDeveloperRelease:
            return "Pending Developer Release"
        case .pendingAppleReview:
            return "Pending Apple Review"
        case .pendingContract:
            return "Pending Contract"
        case .processing:
            return "Processing"
        case .waitingForExportCompliance:
            return "Waiting For Export Compliance"
        case .deferred:
            return "Deferred"
        case .unknown:
            return "Unknown"
        }
    }
}

private struct ITunesLookupResponse: Decodable {
    let results: [ITunesLookupResult]
}

private struct ITunesLookupResult: Decodable {
    let artworkURL: URL?

    private enum CodingKeys: String, CodingKey {
        case artworkURL = "artworkUrl100"
    }
}

private enum InAppPurchaseType: String, Decodable {
    case consumable = "CONSUMABLE"
    case nonConsumable = "NON_CONSUMABLE"
    case nonRenewingSubscription = "NON_RENEWING_SUBSCRIPTION"
    case autoRenewableSubscription = "AUTO_RENEWABLE_SUBSCRIPTION"
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = InAppPurchaseType(rawValue: rawValue) ?? .unknown
    }
}

private struct ASCPaginationLinks: Decodable {
    let next: String?
}

private enum ClientError: LocalizedError {
    case invalidPrivateKeyEncoding
    case invalidPrivateKey(String)
    case invalidResponse(Int, body: String?)
    case httpStatus(Int, body: String?)
    case missingPricePoint(String)

    var errorDescription: String? {
        switch self {
        case .invalidPrivateKeyEncoding:
            return "The selected private key file could not be decoded as text."
        case .invalidPrivateKey(let reason):
            return "Price Parity could not load the .p8 key into a signing key: \(reason)"
        case .invalidResponse(let code, let body):
            let bodyText = body.flatMap { $0.isEmpty ? nil : $0 } ?? "No response body."
            return "App Store Connect returned an unreadable response (\(code)). \(bodyText)"
        case .httpStatus(let code, let body):
            let bodyText = body.flatMap { $0.isEmpty ? nil : $0 } ?? "No response body."
            return "App Store Connect returned HTTP \(code). \(bodyText)"
        case .missingPricePoint(let territoryID):
            return "Price Parity couldn’t find a valid App Store Connect price point for \(localizedTerritoryDisplayName(territoryID))."
        }
    }

    private var placeholderIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
            Image(systemName: "app.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

enum PrivateKeyImportError: LocalizedError {
    case invalidContents
    case noFileData
    case pickerFailed(String)
    case unreadableFile(String)

    var errorDescription: String? {
        switch self {
        case .invalidContents:
            "The selected .p8 file does not contain a supported PEM private key. Download the key directly from App Store Connect and try again."
        case .noFileData:
            "The file provider did not return any data for the selected key. Move the .p8 file to On My iPhone and try again."
        case .pickerFailed(let reason):
            "The file picker could not provide the selected key: \(reason)"
        case .unreadableFile(let reason):
            "The selected key could not be read: \(reason)"
        }
    }
}


enum BigMacIndexError: LocalizedError {
    case unreadableCSV
    case emptyDataset

    var errorDescription: String? {
        switch self {
        case .unreadableCSV:
            return "The selected Big Mac file could not be read as UTF-8 CSV."
        case .emptyDataset:
            return "The selected Big Mac CSV did not contain any rows."
        }
    }
}

private extension JSONDecoder {
    static var asc: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        return decoder
    }
}

private extension Data {
    func base64URLString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
