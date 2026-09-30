import Foundation

private actor Requests {
    var active = 0
    var peak = 0
    var started: [String] = []
    var finished: [String] = []
    var advancedBeforeSlowFinished = false

    func fetch(_ id: String) async throws -> String {
        active += 1
        peak = max(peak, active)
        started.append(id)
        if id == "2" { advancedBeforeSlowFinished = !finished.contains("0") }
        defer { active -= 1 }
        try await Task.sleep(for: .milliseconds(id == "0" ? 200 : 15))
        finished.append(id)
        return id
    }

    func snapshot() -> (Int, Int, [String], Bool) {
        (active, peak, started, advancedBeforeSlowFinished)
    }
}

@main
struct PricePointLoaderTests {
    @MainActor
    static func main() async throws {
        let requests = Requests()
        var results: [String] = []
        try await PricePointLoader.load(
            territoryIDs: (0..<8).map(String.init),
            maxConcurrentRequests: 2,
            fetch: { try await requests.fetch($0) },
            didLoad: { results.append($0) }
        )
        let snapshot = await requests.snapshot()
        precondition(snapshot.0 == 0 && snapshot.1 == 2)
        precondition(snapshot.2.count == 8 && snapshot.3)
        precondition(Set(results).count == 8)

        try await PricePointLoader.load(
            territoryIDs: [],
            fetch: { (_: String) -> String in fatalError("Empty inputs must not fetch") },
            didLoad: { _ in fatalError("Empty inputs must not publish") }
        )

        let cancelledRequests = Requests()
        let task = Task { @MainActor in
            try await PricePointLoader.load(
                territoryIDs: (0..<100).map(String.init),
                maxConcurrentRequests: 2,
                fetch: { try await cancelledRequests.fetch($0) },
                didLoad: { _ in }
            )
        }
        while await cancelledRequests.snapshot().2.count < 2 { await Task.yield() }
        task.cancel()
        do {
            try await task.value
            fatalError("Cancellation must propagate")
        } catch is CancellationError {}
        let cancelled = await cancelledRequests.snapshot()
        precondition(cancelled.0 == 0 && cancelled.2.count == 2)

        enum TestFailure: Error { case expected }
        var completed: [String] = []
        do {
            try await PricePointLoader.load(
                territoryIDs: ["good", "bad", "never"],
                maxConcurrentRequests: 1,
                fetch: { id in
                    if id == "bad" { throw TestFailure.expected }
                    return id
                },
                didLoad: { completed.append($0) }
            )
            fatalError("Errors must propagate")
        } catch TestFailure.expected {}
        precondition(completed == ["good"], "Retain completed results without scheduling after failure")
        try testSnapshots()
        print("PASS: bounded concurrency, rolling scheduling, empty input, cancellation, partial failure, snapshot reuse/expiry/invalidation")
    }

    @MainActor
    static func testSnapshots() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = PriceSnapshotCache(directory: directory)
        defer { try? cache.clear() }
        let now = Calendar.current.startOfDay(for: Date()).addingTimeInterval(12 * 60 * 60)
        let key = "account:key:subscription:123"
        cache.store(["USA": "4.99"], key: key, now: now)
        let reopened = PriceSnapshotCache(directory: directory)
        let reused = reopened.load([String: String].self, key: key, now: now.addingTimeInterval(299))
        precondition(reused == ["USA": "4.99"], "Reuse disk snapshots after recreating the cache")
        precondition(cache.load([String: String].self, key: key, now: now.addingTimeInterval(300)) == nil)
        precondition(cache.load([String: String].self, key: "other:key:subscription:123", now: now) == nil)
        precondition(cache.load([String: String].self, key: "account:key:inAppPurchase:123", now: now) == nil)
        precondition(cache.load([String: String].self, key: key, now: now.addingTimeInterval(-1)) == nil)
        cache.remove(key: key)
        precondition(cache.load([String: String].self, key: key, now: now) == nil)
        cache.store("scheduled", key: key, now: Calendar.current.startOfDay(for: now).addingTimeInterval(-1))
        precondition(cache.load(String.self, key: key, now: Calendar.current.startOfDay(for: now)) == nil)
        cache.store("again", key: key, now: now)
        try cache.clear()
        precondition(cache.load(String.self, key: key, now: now) == nil)
    }

}
