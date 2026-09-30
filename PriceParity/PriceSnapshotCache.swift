import CryptoKit
import Foundation

/// Short-lived, account-scoped snapshots of current prices (separate from reusable tiers).
@MainActor
struct PriceSnapshotCache {
    private let directory: URL
    static let shared = PriceSnapshotCache(directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("PriceParity/CurrentPrices", isDirectory: true))

    init(directory: URL) { self.directory = directory }

    private struct Record<Value: Codable>: Codable {
        let savedAt: Date
        let value: Value
    }

    private func fileURL(for key: String) -> URL {
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash + ".json")
    }

    func load<Value: Codable>(_ type: Value.Type, key: String, now: Date = Date()) -> Value? {
        guard let data = try? Data(contentsOf: fileURL(for: key)),
              let record = try? JSONDecoder().decode(Record<Value>.self, from: data),
              now.timeIntervalSince(record.savedAt) >= 0,
              now.timeIntervalSince(record.savedAt) < 5 * 60,
              Calendar.current.isDate(record.savedAt, inSameDayAs: now) else { return nil }
        return record.value
    }

    func store<Value: Codable>(_ value: Value, key: String, now: Date = Date()) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Record(savedAt: now, value: value))
            try data.write(to: fileURL(for: key), options: .atomic)
        } catch { /* Cache failure must not prevent using live prices. */ }
    }

    func remove(key: String) {
        try? FileManager.default.removeItem(at: fileURL(for: key))
    }

    func clear() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }
}
