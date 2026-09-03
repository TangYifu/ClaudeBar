import Foundation

public final class TokenStatsScanner {
    private struct CachedEvent: Codable {
        let timestamp: Date
        let inputTokens: Int
        let outputTokens: Int
        let cacheCreationTokens: Int
        let cacheReadTokens: Int
        let model: String
        let project: String
        let isUserPrompt: Bool
    }

    private struct CachedFile: Codable {
        var offset: UInt64
        var trailingBytes: Data
        var events: [CachedEvent]
    }

    private struct ScanCache: Codable {
        var version = ScanCache.currentVersion
        // Earliest instant the retained offsets are valid for. Files older than
        // this are fast-forwarded, so a window that reaches further back than
        // the cache was built for has to be rebuilt from scratch.
        var horizon: Date?
        var files: [String: CachedFile] = [:]

        static let currentVersion = 2
    }

    private struct DiscoveredFile {
        let url: URL
        let size: UInt64
        let modified: Date
    }

    /// Appended data is consumed in fixed-size chunks so a multi-megabyte
    /// session log never has to be resident in full.
    private static let chunkSize = 256 * 1024

    private let projectsDirectory: URL
    private let cacheURL: URL
    private let calendar: Calendar
    private let now: () -> Date
    private let isoWithFractional: ISO8601DateFormatter
    private let isoStandard: ISO8601DateFormatter

    public init(
        projectsDirectory: URL,
        cacheURL: URL,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.projectsDirectory = projectsDirectory
        self.cacheURL = cacheURL
        self.calendar = calendar
        self.now = now

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.isoWithFractional = fractional

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        self.isoStandard = standard
    }

    public func compute() -> [TimePeriod: PeriodTokenStats] {
        let currentDate = now()
        let startOfToday = calendar.startOfDay(for: currentDate)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: currentDate)?.start ?? startOfToday
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? currentDate

        var cache = loadCache(horizon: startOfWeek)
        let discovered = discoverJSONLFiles()
        // Only entries whose file is gone from disk are evicted. Offsets for
        // files that fall outside the current window stay valid, so resuming an
        // old session never forces a full re-read of its log.
        let existingPaths = Set(discovered.map(\.url.path))
        cache.files = cache.files.filter { existingPaths.contains($0.key) }

        for file in discovered {
            updateCache(for: file, earliestDate: startOfWeek, cache: &cache)
        }
        cache.horizon = startOfWeek
        saveCache(cache)

        var today = PeriodTokenStats()
        var yesterday = PeriodTokenStats()
        var week = PeriodTokenStats()

        for file in cache.files.values {
            for event in file.events where event.timestamp >= startOfWeek && event.timestamp < endOfToday {
                accumulate(event, into: &week)
                if event.timestamp >= startOfToday {
                    accumulate(event, into: &today)
                } else if event.timestamp >= startOfYesterday {
                    accumulate(event, into: &yesterday)
                }
            }
        }

        return [.today: today, .yesterday: yesterday, .thisWeek: week]
    }

    private func discoverJSONLFiles() -> [DiscoveredFile] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: projectsDirectory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var result: [DiscoveredFile] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate,
                  let size = values.fileSize else { continue }
            result.append(DiscoveredFile(url: url, size: UInt64(size), modified: modified))
        }
        return result
    }

    private func updateCache(for file: DiscoveredFile, earliestDate: Date, cache: inout ScanCache) {
        let path = file.url.path
        var state = cache.files[path] ?? CachedFile(offset: 0, trailingBytes: Data(), events: [])
        if file.size < state.offset {
            state = CachedFile(offset: 0, trailingBytes: Data(), events: [])
        }
        state.events.removeAll { $0.timestamp < earliestDate }

        // Every line in a log last written before the window opened predates the
        // window as well, so none of it can contribute. Skip past those bytes
        // instead of re-reading them the next time the session is resumed.
        if file.modified < earliestDate {
            state.offset = file.size
            state.trailingBytes = Data()
            cache.files[path] = state
            return
        }

        guard file.size > state.offset,
              let handle = try? FileHandle(forReadingFrom: file.url) else {
            cache.files[path] = state
            return
        }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: state.offset)
            var consumed = state.offset
            var pending = [UInt8](state.trailingBytes)
            state.trailingBytes = Data()

            while let chunk = try handle.read(upToCount: Self.chunkSize), !chunk.isEmpty {
                consumed += UInt64(chunk.count)
                pending.append(contentsOf: chunk)
                consumeCompleteLines(from: &pending, fileURL: file.url, into: &state.events)
            }

            // Whatever trails the final newline is either a complete line on a
            // file that does not end in one, or a partial write to resume from.
            if !pending.isEmpty {
                if let event = parseEvent(Data(pending), fileURL: file.url) {
                    state.events.append(event)
                } else {
                    state.trailingBytes = Data(pending)
                }
            }
            state.offset = consumed
        } catch {
            return
        }
        cache.files[path] = state
    }

    private func consumeCompleteLines(from buffer: inout [UInt8], fileURL: URL, into events: inout [CachedEvent]) {
        var lineRanges: [Range<Int>] = []
        var lineStart = 0

        // memchr over a contiguous buffer, rather than subscripting Data once
        // per byte, keeps the line split off the hot path for large logs.
        buffer.withUnsafeBufferPointer { pointer in
            guard let base = pointer.baseAddress else { return }
            let total = pointer.count
            var cursor = 0
            while cursor < total {
                guard let hit = memchr(base + cursor, 0x0A, total - cursor) else { break }
                let newline = UnsafeRawPointer(hit) - UnsafeRawPointer(base)
                if newline > lineStart {
                    lineRanges.append(lineStart..<newline)
                }
                lineStart = newline + 1
                cursor = lineStart
            }
        }

        for range in lineRanges {
            if let event = parseEvent(Data(buffer[range]), fileURL: fileURL) {
                events.append(event)
            }
        }
        if lineStart > 0 {
            buffer.removeFirst(lineStart)
        }
    }

    private func parseEvent(_ data: Data, fileURL: URL) -> CachedEvent? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let timestamp = parseTimestamp(json["timestamp"]) else { return nil }

        let message = json["message"] as? [String: Any]
        let prompt = isActualUserPrompt(json: json, message: message)
        var usage: [String: Any]?
        var model = json["model"] as? String

        if let direct = json["usage"] as? [String: Any] {
            usage = direct
        } else if let nested = message?["usage"] as? [String: Any] {
            usage = nested
            model = model ?? message?["model"] as? String
        } else if let response = json["response"] as? [String: Any],
                  let nested = response["usage"] as? [String: Any] {
            usage = nested
            model = model ?? response["model"] as? String
        }

        guard prompt || usage != nil else { return nil }
        let relative = fileURL.path.replacingOccurrences(of: projectsDirectory.path, with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let fallbackProject = relative.split(separator: "/").first.map(String.init) ?? "default"
        let cwd = json["cwd"] as? String
        let project = cwd.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0).lastPathComponent }
            ?? fallbackProject

        return CachedEvent(
            timestamp: timestamp,
            inputTokens: intValue(usage?["input_tokens"]),
            outputTokens: intValue(usage?["output_tokens"]),
            cacheCreationTokens: intValue(usage?["cache_creation_input_tokens"]),
            cacheReadTokens: intValue(usage?["cache_read_input_tokens"]),
            model: model ?? "unknown",
            project: project,
            isUserPrompt: prompt
        )
    }

    private func parseTimestamp(_ value: Any?) -> Date? {
        if let string = value as? String {
            return isoWithFractional.date(from: string) ?? isoStandard.date(from: string)
        }
        if let number = value as? NSNumber {
            let seconds = number.doubleValue > 1e11 ? number.doubleValue / 1000 : number.doubleValue
            return Date(timeIntervalSince1970: seconds)
        }
        return nil
    }

    private func intValue(_ value: Any?) -> Int {
        if let int = value as? Int { return int }
        return (value as? NSNumber)?.intValue ?? 0
    }

    private func isActualUserPrompt(json: [String: Any], message: [String: Any]?) -> Bool {
        guard json["type"] as? String == "user", message?["role"] as? String == "user",
              json["toolUseResult"] == nil, json["sourceToolAssistantUUID"] == nil,
              let content = message?["content"] else { return false }

        if let text = content as? String { return isUserAuthoredText(text) }
        if let blocks = content as? [[String: Any]] {
            return blocks.contains {
                $0["type"] as? String == "text" && isUserAuthoredText($0["text"] as? String ?? "")
            }
        }
        return false
    }

    private func isUserAuthoredText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let generated = ["<command-message>", "<local-command-stdout>", "<local-command-stderr>",
                         "<system-reminder>", "Base directory for this skill:"]
        return !generated.contains { trimmed.hasPrefix($0) }
    }

    private func accumulate(_ event: CachedEvent, into stats: inout PeriodTokenStats) {
        if event.isUserPrompt { stats.userPromptsCount += 1 }
        let total = event.inputTokens + event.outputTokens + event.cacheCreationTokens + event.cacheReadTokens
        guard total > 0 else { return }
        stats.inputTokens += event.inputTokens
        stats.outputTokens += event.outputTokens
        stats.cacheCreationTokens += event.cacheCreationTokens
        stats.cacheReadTokens += event.cacheReadTokens
        stats.modelCallsCount += 1
        stats.tokensByModel[event.model, default: 0] += total
        stats.tokensByProject[event.project, default: 0] += total
    }

    private func loadCache(horizon: Date) -> ScanCache {
        guard let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(ScanCache.self, from: data),
              cache.version == ScanCache.currentVersion,
              let cachedHorizon = cache.horizon,
              cachedHorizon <= horizon else { return ScanCache() }
        return cache
    }

    private func saveCache(_ cache: ScanCache) {
        do {
            try FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(cache)
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            print("Token stats cache write failed: \(error.localizedDescription)")
        }
    }
}
