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
    private let maxSamples = 256
    private let keepDays: TimeInterval = 7 * 24 * 3600
    private let minInterval: TimeInterval = 60

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func record(fiveUtil: Double, sevenUtil: Double, fiveReset: Date?, sevenReset: Date?) {
        lock.lock()
        defer { lock.unlock() }
        var samples = loadLocked()
        let now = Date()
        if let last = samples.last, now.timeIntervalSince(last.date) < minInterval {
            samples[samples.count - 1] = UsageSample(date: now, five: fiveUtil, seven: sevenUtil, fiveReset: fiveReset, sevenReset: sevenReset)
        } else {
            samples.append(UsageSample(date: now, five: fiveUtil, seven: sevenUtil, fiveReset: fiveReset, sevenReset: sevenReset))
        }
        let cutoff = now.addingTimeInterval(-keepDays)
        samples.removeAll { $0.date < cutoff }
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }
        saveLocked(samples)
    }

    public func samples() -> [UsageSample] {
        lock.lock()
        defer { lock.unlock() }
        return loadLocked()
    }

    public struct BurnResult {
        public var rate: Double?
        public var exhaustion: Date?
        public var delta: Double?
    }

    public func fiveHourBurn(currentUtil: Double, currentReset: Date?, now: Date = Date()) -> BurnResult {
        let all = samples()
        return burn(currentUtil: currentUtil, currentReset: currentReset, samples: all, window: 2 * 3600, now: now, keyPath: \.five, resetKeyPath: \.fiveReset)
    }

    public func sevenDayBurn(currentUtil: Double, currentReset: Date?, now: Date = Date()) -> BurnResult {
        let all = samples()
        return burn(currentUtil: currentUtil, currentReset: currentReset, samples: all, window: 24 * 3600, now: now, keyPath: \.seven, resetKeyPath: \.sevenReset)
    }

    private func burn(currentUtil: Double, currentReset: Date?, samples: [UsageSample], window: TimeInterval, now: Date, keyPath: KeyPath<UsageSample, Double>, resetKeyPath: KeyPath<UsageSample, Date?>) -> BurnResult {
        let windowStart = now.addingTimeInterval(-window)
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
        let hoursToExhaust = remain / rate
        let exhaustion = now.addingTimeInterval(hoursToExhaust * 3600)
        return BurnResult(rate: rate, exhaustion: exhaustion, delta: delta)
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
