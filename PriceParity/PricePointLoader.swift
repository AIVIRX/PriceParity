import Foundation

/// A rolling request window: a slow territory never holds up the next one.
enum PricePointLoader {
    @MainActor
    static func load<Item: Sendable, Value: Sendable>(
        territoryIDs: [Item],
        maxConcurrentRequests: Int = 6,
        fetch: @escaping @Sendable (Item) async throws -> Value,
        didLoad: @MainActor (Value) -> Void
    ) async throws {
        try Task.checkCancellation()
        var remaining = territoryIDs.makeIterator()
        try await withThrowingTaskGroup(of: Value.self) { group in
            for _ in 0..<min(max(1, maxConcurrentRequests), territoryIDs.count) {
                guard let territoryID = remaining.next() else { break }
                group.addTask { try await fetch(territoryID) }
            }

            while let value = try await group.next() {
                try Task.checkCancellation()
                didLoad(value)
                if let territoryID = remaining.next() {
                    group.addTask { try await fetch(territoryID) }
                }
            }
        }
    }
}
