import Foundation

/// Periodically deletes expired items and enforces size limits. 24h-rule always wins:
/// nothing here (or in any AI layer) can extend an item's expiry.
public final class CleanupService: @unchecked Sendable {
    private let repo: ClipboardRepository
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "clippy.cleanup", qos: .utility)
    public var interval: TimeInterval

    public init(repository: ClipboardRepository, interval: TimeInterval = 300) {
        self.repo = repository; self.interval = interval
    }

    public func start() {
        stop()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 2, repeating: interval, leeway: .seconds(10))
        t.setEventHandler { [repo] in _ = try? repo.purgeExpired() }
        t.resume()
        timer = t
    }

    public func stop() { timer?.cancel(); timer = nil }

    /// For wake-from-sleep and on-demand runs.
    public func runNow() { queue.async { [repo] in _ = try? repo.purgeExpired() } }
}
