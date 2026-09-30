import RevenueCatUI
import StoreKit
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var revenueCat: RevenueCatManager
    @Environment(\.requestReview) private var requestReview
    @Binding var appearanceSelection: AppAppearance
    let onDeleteData: () -> Void
    @State private var isShowingDeleteCacheConfirmation = false
    @State private var cacheAlertMessage: String?

    var body: some View {
        NavigationStack {
            VStack {
                Form {
                    Section("Premium") {
                        HStack {
                            Label("Status", systemImage: revenueCat.isPremium ? "checkmark.seal.fill" : "lock.fill")
                                .foregroundStyle(revenueCat.isPremium ? .green : .primary)
                            Spacer()
                            Text(revenueCat.isPremium ? "Unlocked" : "Free")
                                .foregroundStyle(revenueCat.isPremium ? .green : .secondary)
                        }

                        Button {
                            Task {
                                await revenueCat.restorePurchases()
                            }
                        } label: {
                            Label("Restore Purchases", systemImage: "arrow.clockwise")
                        }
                        .foregroundStyle(.primary)

                        if !revenueCat.isPremium {
                            Button {
                                revenueCat.presentPaywall()
                            } label: {
                                Label("Unlock Premium", systemImage: "crown.fill")
                            }
                            .foregroundStyle(.primary)
                        }
                    }

                    Section("Appearance") {
                        Picker("Theme", selection: $appearanceSelection) {
                            ForEach(AppAppearance.allCases) { appearance in
                                Text(appearance.title)
                                    .tag(appearance)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Section("Support") {
                    Button {
                        requestReview()
                    } label: {
                        Label("Give Us a Review", systemImage: "star.bubble")
                    }
                    .foregroundStyle(.primary)

                        SupportAppRow(
                            iconName: "stringcat",
                            title: "String Catalog - Translate",
                            destination: URL(string: "https://apps.apple.com/us/app/string-catalog-translate/id6761640833?mt=12")!
                        )
                        SupportAppRow(
                            iconName: "dockui",
                            title: "DockUI - Design For SwiftUI",
                            destination: URL(string: "https://apps.apple.com/us/app/dockui-design-for-swiftui/id6496860953")!
                        )
                    }

                    Section("Legal") {
                        Link(destination: URL(string: "https://aivirx.com/contact")!) {
                            Label("Contact Us", systemImage: "envelope")
                        }
                        .foregroundStyle(.primary)
                        Link(destination: URL(string: "https://aivirx.com/price-parity/privacy-policy")!) {
                            Label("Privacy Policy", systemImage: "hand.raised")
                        }
                        .foregroundStyle(.primary)
                        
                        Link(destination: URL(string: "https://www.apple.com/legal/macapps/stdeula/")!) {
                            Label("Terms of Service", systemImage: "doc.text")
                        }
                        .foregroundStyle(.primary)
                    }

                    Section {
                        Button(role: .destructive) {
                            isShowingDeleteCacheConfirmation = true
                        } label: {
                            Label("Delete Data", systemImage: "trash")
                        }
                    } header: {
                        Text("Data")
                    } footer: {
                        Text("Removes saved App Store Connect credentials and locally cached pricing data from this device.")
                    }
                    .alert(
                        "Delete App Data?",
                        isPresented: $isShowingDeleteCacheConfirmation
                    ) {
                        Button("Delete Data", role: .destructive) {
                            deletePricePointCache()
                        }

                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This deletes your saved App Store Connect credentials and clears the local cached pricing data on this device.")
                    }

                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .alert(
                "App Data",
                isPresented: Binding(
                    get: { cacheAlertMessage != nil },
                    set: { if !$0 { cacheAlertMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    cacheAlertMessage = nil
                }
            } message: {
                Text(cacheAlertMessage ?? "")
            }
            .sheet(isPresented: $revenueCat.isShowingPaywall, onDismiss: {
                Task {
                    await revenueCat.refreshCustomerInfo()
                }
            }) {
                PaywallView()
            }
            .task {
                await revenueCat.refreshCustomerInfoIfNeeded()
            }
        }
    }

    private func deletePricePointCache() {
        do {
            try AppStoreConnectClient.clearSubscriptionPricePointCache()
            onDeleteData()
            cacheAlertMessage = "Deleted saved credentials and local cached data."
        } catch {
            cacheAlertMessage = error.localizedDescription
        }
    }
}

private struct SupportAppRow: View {
    let iconName: String
    let title: String
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: 12) {
                Image(iconName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text(title)
                    .foregroundStyle(.primary)
            }
        }
    }
}
