import Foundation

public struct UsageSample: Codable, Equatable {
    public var date: Date
    public var five: Double
    public var seven: Double
    public var fiveReset: Date?
    public var sevenReset: Date?

    public init(date: Date, five: Double, seven: Double, fiveReset: Date?, sevenReset: Date?) {
        self.date = date
        self.five = five
        self.seven = seven
        self.fiveReset = fiveReset
        self.sevenReset = sevenReset
    }
}

public final class UsageHistoryStore {
    private let fileURL: URL
    private let lock = NSLock()

    /// The longest window any burn calculation asks for is 24 hours, so retaining
    /// more than that plus a margin is dead weight that gets rewritten on every
    /// refresh.
    private let retention: TimeInterval = 26 * 3600
    /// A percent-per-hour rate needs no finer granularity than this. Coarsening the
    /// sampling is what bounds the file at the 1-minute refresh setting, where one
    /// sample per refresh would otherwise mean 1560 of them inside the window.
    private let minInterval: TimeInterval = 300
    /// 26 hours at one sample per 5 minutes, plus margin.
    private let maxSamples = 400

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public struct BurnResult {
        public var rate: Double?
        public var exhaustion: Date?
        public var delta: Double?
    }

    public struct BurnSnapshot {
        public var five: BurnResult
        public var seven: BurnResult
    }

    /// Records the current reading (when online) and derives both burn rates from a
    /// single load. This used to cost four file operations per refresh: the record's
    /// load and save, plus a further load inside each of the two burn calculations.
    public func update(
        fiveUtil: Double,
        sevenUtil: Double,
        fiveReset: Date?,
        sevenReset: Date?,
        record shouldRecord: Bool,
        now: Date = Date()
    ) -> BurnSnapshot {
        lock.lock()
        defer { lock.unlock() }

        var samples = loadLocked()
        if shouldRecord {
            appendLocked(&samples, fiveUtil: fiveUtil, sevenUtil: sevenUtil,
                         fiveReset: fiveReset, sevenReset: sevenReset, now: now)
            saveLocked(samples)
        }

        return BurnSnapshot(
            five: burn(currentUtil: fiveUtil, currentReset: fiveReset, samples: samples,
                       window: 2 * 3600, now: now, keyPath: \.five, resetKeyPath: \.fiveReset),
            seven: burn(currentUtil: sevenUtil, currentReset: sevenReset, samples: samples,
                        window: 24 * 3600, now: now, keyPath: \.seven, resetKeyPath: \.sevenReset)
        )
    }

    public func samples() -> [UsageSample] {
        lock.lock()
        defer { lock.unlock() }
        return loadLocked()
    }

    private func appendLocked(
        _ samples: inout [UsageSample],
        fiveUtil: Double,
        sevenUtil: Double,
        fiveReset: Date?,
        sevenReset: Date?,
        now: Date
    ) {
        if let last = samples.last, now.timeIntervalSince(last.date) < minInterval {
            // Refresh the slot's values but keep its original timestamp. Advancing
            // the timestamp would restart the interval on every refresh, so once the
            // refresh period is shorter than minInterval no second sample would ever
            // be appended and the history would stay one entry long forever.
            samples[samples.count - 1] = UsageSample(date: last.date, five: fiveUtil, seven: sevenUtil,
                                                     fiveReset: fiveReset, sevenReset: sevenReset)
        } else {
            samples.append(UsageSample(date: now, five: fiveUtil, seven: sevenUtil,
                                       fiveReset: fiveReset, sevenReset: sevenReset))
        }
        let cutoff = now.addingTimeInterval(-retention)
        samples.removeAll { $0.date < cutoff }
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }
    }

    private func burn(
        currentUtil: Double,
        currentReset: Date?,
        samples: [UsageSample],
        window: TimeInterval,
        now: Date,
        keyPath: KeyPath<UsageSample, Double>,
        resetKeyPath: KeyPath<UsageSample, Date?>
    ) -> BurnResult {
        let windowStart = now.addingTimeInterval(-window)
        // Only samples from the same quota period may be compared; mixing readings
        // from either side of a reset would report a nonsense rate.
        let filtered = samples.filter { s in
            guard s.date >= windowStart && s.date < now else { return false }
            let r = s[keyPath: resetKeyPath]
            if let a = r, let b = currentReset {
                return abs(a.timeIntervalSince(b)) < 1
            }
            return r == nil && currentReset == nil
        }
        guard let earliest = filtered.first else { return BurnResult(rate: nil, exhaustion: nil, delta: nil) }
        let hours = now.timeIntervalSince(earliest.date) / 3600
        guard hours >= 0.08 else { return BurnResult(rate: nil, exhaustion: nil, delta: nil) }
        let delta = currentUtil - earliest[keyPath: keyPath]
        guard delta > 0.05 else {
            if delta < -0.5 {
                return BurnResult(rate: nil, exhaustion: nil, delta: delta)
            }
            return BurnResult(rate: 0, exhaustion: nil, delta: delta)
        }
        let rate = delta / hours
        let remain = 100 - currentUtil
        if remain <= 0 {
            return BurnResult(rate: rate, exhaustion: now, delta: delta)
        }
        return BurnResult(rate: rate, exhaustion: now.addingTimeInterval(remain / rate * 3600), delta: delta)
    }

    private func loadLocked() -> [UsageSample] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([UsageSample].self, from: data)) ?? []
    }

    private func saveLocked(_ samples: [UsageSample]) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(samples)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("UsageHistoryStore write failed: \(error.localizedDescription)")
        }
    }
}
