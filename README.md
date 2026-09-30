# Price Parity

Price Parity is a native iOS app that helps App Store developers set country-level prices for subscriptions and in-app purchases. It combines App Store Connect pricing data with purchasing-power-parity signals to generate practical, territory-specific recommendations.

[Download Price Parity on the App Store](https://apps.apple.com/us/app/price-parity-ppp-pricing-tool/id6783185631)

## What it does

- Connects directly to App Store Connect with an API key.
- Lists an account’s apps, subscriptions, and in-app purchases.
- Calculates recommended local prices from purchasing-power data and exchange rates.
- Lets developers review, adjust, and schedule price changes by territory.
- Caches price-tier and current-price data locally to keep repeat workflows fast.
- Includes a demo mode that works without App Store Connect credentials.

## Privacy and security

The app keeps App Store Connect credentials in the device Keychain. It fetches pricing data from App Store Connect, app-icon metadata from Apple’s iTunes lookup service, and exchange rates from ExchangeRate-API. The app does not include analytics, accounts, subscriptions, or a paywall. API private-key files (`.p8`) are excluded from source control.

## Requirements

- Xcode 16 or later
- iOS 18 or later
- An App Store Connect API key with access to the apps you want to manage

## Run locally

1. Open `PriceParity.xcodeproj` in Xcode.
2. Choose the **PriceParity** scheme and an iOS simulator or device.
3. Build and run.
4. Enter an Issuer ID, Key ID, and `.p8` private key, or select **Try Demo Mode**.

## Validation

Build the app from Xcode, or run:

```sh
xcodebuild -project PriceParity.xcodeproj -scheme PriceParity \
  -sdk iphonesimulator -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build
```

The repository also includes focused tests for the rolling request scheduler and local price snapshot cache:

```sh
swiftc -parse-as-library PriceParity/PricePointLoader.swift \
  PriceParity/PriceSnapshotCache.swift Tests/PricePointLoaderTests.swift \
  -o /tmp/PricePointLoaderTests
/tmp/PricePointLoaderTests
```

## Project structure

- `PriceParity/ContentView.swift` — primary SwiftUI screens and App Store Connect client.
- `PriceParity/ContentViewModel.swift` — credential, app-list, and demo-mode state.
- `PriceParity/PricePointLoader.swift` — bounded-concurrency request scheduler.
- `PriceParity/PriceSnapshotCache.swift` — account-scoped local price cache.
- `PriceParity/KeychainCredentialStore.swift` — secure credential persistence.
- `Tests/` — isolated regression checks that do not call App Store Connect.
