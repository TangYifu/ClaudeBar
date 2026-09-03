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
        var version = 1
        var files: [String: CachedFile] = [:]
    }

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

        var cache = loadCache()
        let discovered = discoverJSONLFiles(modifiedSince: startOfWeek)
        let existingPaths = Set(discovered.map(\.path))
        cache.files = cache.files.filter { existingPaths.contains($0.key) }

        for fileURL in discovered {
            updateCache(for: fileURL, earliestDate: startOfWeek, cache: &cache)
        }
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

    private func discoverJSONLFiles(modifiedSince date: Date) -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: projectsDirectory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var result: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate,
                  modified >= date else { continue }
            result.append(url)
        }
        return result
    }

    private func updateCache(for fileURL: URL, earliestDate: Date, cache: inout ScanCache) {
        let path = fileURL.path
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let fileSize = (attributes[.size] as? NSNumber)?.uint64Value else { return }

        var state = cache.files[path] ?? CachedFile(offset: 0, trailingBytes: Data(), events: [])
        if fileSize < state.offset {
            state = CachedFile(offset: 0, trailingBytes: Data(), events: [])
        }
        state.events.removeAll { $0.timestamp < earliestDate }

        guard fileSize > state.offset,
              let handle = try? FileHandle(forReadingFrom: fileURL) else {
            cache.files[path] = state
            return
        }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: state.offset)
            let appended = try handle.readToEnd() ?? Data()
            var bytes = state.trailingBytes
            bytes.append(appended)
            state.trailingBytes = Data()

            var lineStart = bytes.startIndex
            for index in bytes.indices where bytes[index] == 0x0A {
                if index > lineStart {
                    let line = Data(bytes[lineStart..<index])
                    if let event = parseEvent(line, fileURL: fileURL) {
                        state.events.append(event)
                    }
                }
                lineStart = bytes.index(after: index)
            }
            if lineStart < bytes.endIndex {
                let remainder = Data(bytes[lineStart..<bytes.endIndex])
                if let event = parseEvent(remainder, fileURL: fileURL) {
                    state.events.append(event)
                } else {
                    state.trailingBytes = remainder
                }
            }
            state.offset = fileSize
        } catch {
            return
        }
        cache.files[path] = state
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

    private func loadCache() -> ScanCache {
        guard let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(ScanCache.self, from: data),
              cache.version == 1 else { return ScanCache() }
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
