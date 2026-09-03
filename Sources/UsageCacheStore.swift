import Foundation

public struct CachedUsagePayload: Codable {
    public var response: UsageResponse?
    public var savedAt: Date
    public var retryNotBefore: Date?
}

public final class UsageCacheStore {
    private let fileURL: URL
    private let lock = NSLock()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() -> CachedUsagePayload? {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(CachedUsagePayload.self, from: data)
    }

    public func save(response: UsageResponse, retryNotBefore: Date? = nil) {
        write(CachedUsagePayload(response: response, savedAt: Date(), retryNotBefore: retryNotBefore))
    }

    public func setRetryNotBefore(_ date: Date) {
        var payload = load() ?? CachedUsagePayload(response: nil, savedAt: Date(), retryNotBefore: nil)
        payload.retryNotBefore = date
        write(payload)
    }

    private func write(_ payload: CachedUsagePayload) {
        lock.lock()
        defer { lock.unlock() }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(payload)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Usage cache write failed: \(error.localizedDescription)")
        }
    }
}

public enum RetryAfterParser {
    public static func date(from value: String?, now: Date = Date()) -> Date? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if let seconds = TimeInterval(raw), seconds >= 0 {
            return now.addingTimeInterval(seconds)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter.date(from: raw)
    }
}

public enum UsageRequestError: LocalizedError {
    case http(status: Int, retryNotBefore: Date?)

    public var errorDescription: String? {
        switch self {
        case .http(let status, let retryDate):
            if status == 429, let retryDate {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm"
                return "请求受限，将在 \(formatter.string(from: retryDate)) 后重试"
            }
            return "HTTP \(status)"
        }
    }
}
