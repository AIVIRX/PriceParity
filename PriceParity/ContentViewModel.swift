import Combine
import Foundation

@MainActor
final class ContentViewModel: ObservableObject {
    @Published var issuerID = ""
    @Published var keyID = ""
    @Published var privateKeyData: Data?
    @Published var privateKeyFileName: String?
    @Published var importError: String?
    @Published var saveError: String?
    @Published var isReady = false
    @Published var isDemoMode = false
    @Published var appPhase: AppListPhase = .idle
    @Published var apps: [ASCAppSummary] = []
    @Published var bigMacEntries: [BigMacIndexEntry] = []
    @Published var searchText = ""
    @Published var selectedApp: ASCAppSummary?

    private var didRestoreSavedCredentials = false
    private static let appListCacheFileName = "app-list.json"

    var normalizedIssuerID: String {
        issuerID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedKeyID: String {
        Self.normalizedKeyID(from: keyID)
    }

    var isValidIssuerID: Bool {
        UUID(uuidString: normalizedIssuerID) != nil
    }

    var canContinue: Bool {
        isValidIssuerID && !normalizedKeyID.isEmpty && privateKeyData != nil
    }

    var filteredApps: [ASCAppSummary] {
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return apps }

        return apps.filter { app in
            app.name.localizedCaseInsensitiveContains(trimmedQuery) ||
            (app.bundleID?.localizedCaseInsensitiveContains(trimmedQuery) ?? false)
        }
    }

    func signOut() {
        do {
            try KeychainCredentialStore.delete()
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }

        issuerID = ""
        keyID = ""
        privateKeyData = nil
        privateKeyFileName = nil
        importError = nil
        isDemoMode = false
        isReady = false
        appPhase = .idle
        apps = []
        searchText = ""
        selectedApp = nil
        Self.clearCachedApps()
    }

    func importPrivateKey(_ result: Result<[URL], any Error>) {
        var failureMessage: String?

        defer {
            if let failureMessage {
                privateKeyData = nil
                privateKeyFileName = nil
                importError = failureMessage
            }
        }

        let urls: [URL]
        do {
            urls = try result.get()
        } catch {
            failureMessage = PrivateKeyImportError.pickerFailed(error.localizedDescription).errorDescription
            return
        }

        guard let url = urls.first else { return }

        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data: Data
        do {
            data = try Self.readCoordinatedData(from: url)
        } catch {
            failureMessage = PrivateKeyImportError.unreadableFile(error.localizedDescription).errorDescription
            return
        }

        guard Self.containsPEMPrivateKey(data) else {
            failureMessage = PrivateKeyImportError.invalidContents.errorDescription
            return
        }

        privateKeyData = data
        privateKeyFileName = url.lastPathComponent
        importError = nil

        if normalizedKeyID.isEmpty,
           let inferredKeyID = Self.keyID(from: url.deletingPathExtension().lastPathComponent) {
            keyID = inferredKeyID
        }
    }

    func persistCredentialsAndContinue() {
        let stored = StoredASCKeyCredentials(
            issuerID: normalizedIssuerID,
            keyID: normalizedKeyID,
            privateKeyData: privateKeyData ?? Data(),
            privateKeyFileName: privateKeyFileName
        )

        do {
            try KeychainCredentialStore.save(stored)
            saveError = nil
            isReady = true
            appPhase = .loading
            apps = []
            Task { await loadApps() }
        } catch {
            saveError = error.localizedDescription
        }
    }

    func restoreSavedCredentialsIfNeeded() async {
        guard !didRestoreSavedCredentials else { return }
        didRestoreSavedCredentials = true

        do {
            guard let stored = try KeychainCredentialStore.load() else { return }

            issuerID = stored.issuerID
            keyID = stored.keyID
            privateKeyData = stored.privateKeyData
            privateKeyFileName = stored.privateKeyFileName
            importError = nil
            saveError = nil
            isReady = true
            appPhase = .loading
            apps = []
            await loadApps()
        } catch {
            saveError = error.localizedDescription
        }
    }

    func restoreSavedBigMacDatasetIfNeeded() {
        guard bigMacEntries.isEmpty else { return }
        guard let data = BigMacLocalDataset.csv.data(using: .utf8) else { return }
        bigMacEntries = (try? Self.parseBigMacEntries(fromCSV: data)) ?? []
    }

    func enterDemoMode() {
        restoreSavedBigMacDatasetIfNeeded()
        importError = nil
        saveError = nil
        isDemoMode = true
        isReady = true
        selectedApp = nil
        appPhase = .loaded
        apps = DemoModeData.apps
    }

    func exitDemoMode() {
        guard isDemoMode else { return }

        importError = nil
        saveError = nil
        isDemoMode = false
        isReady = false
        appPhase = .idle
        apps = []
        searchText = ""
        selectedApp = nil
    }

    func loadApps() async {
        if isDemoMode {
            apps = DemoModeData.apps
            appPhase = .loaded
            return
        }

        guard let privateKeyData else {
            appPhase = .failed("Missing private key data. Choose your App Store Connect .p8 file again.")
            return
        }

        do {
            let fetchedApps = try await AppStoreConnectClient.fetchApps(
                issuerID: normalizedIssuerID,
                keyID: normalizedKeyID,
                privateKeyData: privateKeyData
            )
            apps = fetchedApps
            appPhase = .loaded
            Self.storeCachedApps(fetchedApps)
        } catch {
            if apps.isEmpty {
                appPhase = .failed(error.localizedDescription)
            }
        }
    }

    private static func loadCachedApps() -> [ASCAppSummary]? {
        guard let cacheURL = appListCacheURL(),
              let data = try? Data(contentsOf: cacheURL) else {
            return nil
        }

        return try? JSONDecoder().decode([ASCAppSummary].self, from: data)
    }

    private static func storeCachedApps(_ apps: [ASCAppSummary]) {
        guard let cacheURL = appListCacheURL() else { return }

        do {
            let directoryURL = cacheURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(apps)
            try data.write(to: cacheURL, options: .atomic)
        } catch {
        }
    }

    private static func clearCachedApps() {
        guard let cacheURL = appListCacheURL(),
              FileManager.default.fileExists(atPath: cacheURL.path) else {
            return
        }

        try? FileManager.default.removeItem(at: cacheURL)
    }

    private static func appListCacheURL() -> URL? {
        guard let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }

        return cachesDirectory
            .appendingPathComponent("PriceParity", isDirectory: true)
            .appendingPathComponent(Self.appListCacheFileName)
    }

    private static func readCoordinatedData(from url: URL) throws -> Data {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var readResult: Result<Data, any Error>?

        coordinator.coordinate(
            readingItemAt: url,
            options: [],
            error: &coordinationError
        ) { coordinatedURL in
            readResult = Result {
                try Data(contentsOf: coordinatedURL)
            }
        }

        if let coordinationError {
            throw coordinationError
        }

        guard let readResult else {
            throw PrivateKeyImportError.noFileData
        }

        return try readResult.get()
    }

    private static func parseBigMacEntries(fromCSV data: Data) throws -> [BigMacIndexEntry] {
        guard let csv = String(data: data, encoding: .utf8) else {
            throw BigMacIndexError.unreadableCSV
        }

        let rows = parseCSVRows(csv)
        guard let headerRow = rows.first, rows.count > 1 else {
            throw BigMacIndexError.emptyDataset
        }

        let headers = headerRow.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        var latestByTerritory: [String: (date: Date?, entry: BigMacIndexEntry)] = [:]

        for row in rows.dropFirst() where row.count == headers.count {
            let fields = Dictionary(uniqueKeysWithValues: zip(headers, row))

            guard let territoryID = Self.bigMacValue(for: fields, keys: ["iso_a3", "isoa3", "country_code"])?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased(),
                  !territoryID.isEmpty else {
                continue
            }

            let entry = BigMacIndexEntry(
                territoryID: territoryID,
                countryName: Self.bigMacValue(for: fields, keys: ["name", "country"]) ?? territoryID,
                currencyCode: Self.bigMacValue(for: fields, keys: ["currency_code", "currency"]),
                dateString: Self.bigMacValue(for: fields, keys: ["date"]),
                localPrice: Self.bigMacDouble(for: fields, keys: ["local_price", "localprice"]),
                dollarPrice: Self.bigMacDouble(for: fields, keys: ["dollar_price", "dollarprice"]),
                usdRawIndex: Self.bigMacDouble(for: fields, keys: ["usd_raw", "usdraw"]),
                adjustedPrice: Self.bigMacDouble(for: fields, keys: ["adj_price", "adjusted_price", "adjprice"]),
                gdpPerCapita: Self.bigMacDouble(for: fields, keys: ["gdp_bigmac", "gdp"])
            )

            let parsedDate = Self.bigMacDate(from: entry.dateString)
            if let existing = latestByTerritory[territoryID] {
                if Self.bigMacDateSortKey(parsedDate) >= Self.bigMacDateSortKey(existing.date) {
                    latestByTerritory[territoryID] = (parsedDate, entry)
                }
            } else {
                latestByTerritory[territoryID] = (parsedDate, entry)
            }
        }

        return latestByTerritory.values
            .map(\.entry)
            .sorted { lhs, rhs in
                if lhs.territoryID == "USA" { return true }
                if rhs.territoryID == "USA" { return false }
                return localizedTerritoryDisplayName(lhs.territoryID).localizedCaseInsensitiveCompare(localizedTerritoryDisplayName(rhs.territoryID)) == .orderedAscending
            }
    }

    private static func parseCSVRows(_ csv: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var isInsideQuotes = false
        var iterator = csv.makeIterator()

        while let character = iterator.next() {
            switch character {
            case "\"":
                if isInsideQuotes {
                    if let next = iterator.next() {
                        if next == "\"" {
                            currentField.append("\"")
                        } else {
                            isInsideQuotes = false
                            switch next {
                            case ",":
                                currentRow.append(currentField)
                                currentField.removeAll(keepingCapacity: true)
                            case "\n":
                                currentRow.append(currentField)
                                rows.append(currentRow)
                                currentRow.removeAll(keepingCapacity: true)
                                currentField.removeAll(keepingCapacity: true)
                            case "\r":
                                currentRow.append(currentField)
                                rows.append(currentRow)
                                currentRow.removeAll(keepingCapacity: true)
                                currentField.removeAll(keepingCapacity: true)
                            default:
                                currentField.append(next)
                            }
                        }
                    } else {
                        isInsideQuotes = false
                    }
                } else {
                    isInsideQuotes = true
                }
            case "," where !isInsideQuotes:
                currentRow.append(currentField)
                currentField.removeAll(keepingCapacity: true)
            case "\n" where !isInsideQuotes:
                currentRow.append(currentField)
                rows.append(currentRow)
                currentRow.removeAll(keepingCapacity: true)
                currentField.removeAll(keepingCapacity: true)
            case "\r" where !isInsideQuotes:
                continue
            default:
                currentField.append(character)
            }
        }

        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            rows.append(currentRow)
        }

        return rows.filter { !$0.isEmpty }
    }

    private static func bigMacValue(for fields: [String: String], keys: [String]) -> String? {
        for key in keys {
            if let value = fields[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func bigMacDouble(for fields: [String: String], keys: [String]) -> Double? {
        guard let value = bigMacValue(for: fields, keys: keys) else { return nil }
        return Double(value.replacingOccurrences(of: ",", with: ""))
    }

    private static func bigMacDate(from value: String?) -> Date? {
        guard let value else { return nil }
        return BigMacLocalDataset.dateFormatter.date(from: value)
    }

    private static func bigMacDateSortKey(_ date: Date?) -> TimeInterval {
        date?.timeIntervalSince1970 ?? .zero
    }

    private static func keyID(from fileName: String) -> String? {
        let prefix = "AuthKey_"
        let trimmedFileName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedFileName.hasPrefix(prefix) else { return nil }

        let value = String(trimmedFileName.dropFirst(prefix.count))
        let normalizedValue = normalizedKeyID(from: value)
        return normalizedValue.isEmpty ? nil : normalizedValue
    }

    private static func normalizedKeyID(from rawValue: String) -> String {
        rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".p8", with: "", options: [.caseInsensitive], range: nil)
    }

    private static func containsPEMPrivateKey(_ data: Data) -> Bool {
        guard !data.isEmpty,
              let contents = String(data: data, encoding: .utf8) else {
            return false
        }

        let supportedMarkers = [
            ("-----BEGIN PRIVATE KEY-----", "-----END PRIVATE KEY-----"),
            ("-----BEGIN EC PRIVATE KEY-----", "-----END EC PRIVATE KEY-----")
        ]

        return supportedMarkers.contains { beginMarker, endMarker in
            contents.contains(beginMarker) && contents.contains(endMarker)
        }
    }
}
