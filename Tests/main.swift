import Foundation

private var failures = 0

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        failures += 1
        fputs("FAIL: \(message)\n", stderr)
    }
}

private func jsonLine(_ object: [String: Any]) -> Data {
    var data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    data.append(0x0A)
    return data
}

private func user(_ timestamp: String, text: String) -> [String: Any] {
    ["type": "user", "timestamp": timestamp, "message": ["role": "user", "content": text]]
}

private func usage(_ timestamp: String, output: Int, cwd: String = "/tmp/TestProject") -> [String: Any] {
    [
        "type": "assistant",
        "timestamp": timestamp,
        "cwd": cwd,
        "message": [
            "role": "assistant",
            "model": "claude-test-model",
            "usage": [
                "input_tokens": 10,
                "output_tokens": output,
                "cache_creation_input_tokens": 20,
                "cache_read_input_tokens": 30
            ]
        ]
    ]
}

private func runTokenScannerTests() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeBarTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let projects = root.appendingPathComponent("projects/demo")
    try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
    let log = projects.appendingPathComponent("session.jsonl")
    let cache = root.appendingPathComponent("cache/token.json")

    var initial = Data()
    initial.append(jsonLine(user("2026-09-03T01:00:00.000Z", text: "真实提问")))
    initial.append(jsonLine([
        "type": "user",
        "timestamp": "2026-09-03T01:01:00.000Z",
        "sourceToolAssistantUUID": "tool-id",
        "message": ["role": "user", "content": [["type": "tool_result", "content": "done"]]]
    ]))
    initial.append(jsonLine(usage("2026-09-03T01:02:00.000Z", output: 40)))
    initial.append(jsonLine(usage("2026-09-02T01:02:00.000Z", output: 50)))
    initial.append(jsonLine(usage("2026-08-30T01:02:00.000Z", output: 999)))
    try initial.write(to: log)

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 2
    let fixedNow = ISO8601DateFormatter().date(from: "2026-09-03T12:00:00Z")!
    let scanner = TokenStatsScanner(projectsDirectory: root.appendingPathComponent("projects"), cacheURL: cache, calendar: calendar) {
        fixedNow
    }

    let first = scanner.compute()
    expect(first[.today]?.userPromptsCount == 1, "tool results must not count as user prompts")
    expect(first[.today]?.modelCallsCount == 1, "today should contain one model call")
    expect(first[.yesterday]?.modelCallsCount == 1, "yesterday should contain one model call")
    expect(first[.thisWeek]?.modelCallsCount == 2, "natural week must exclude the previous Sunday")
    expect(first[.today]?.tokensByProject["TestProject"] == 100, "project totals should be aggregated")
    expect(FileManager.default.fileExists(atPath: cache.path), "scanner cache should be persisted")

    let handle = try FileHandle(forWritingTo: log)
    try handle.seekToEnd()
    try handle.write(contentsOf: jsonLine(usage("2026-09-03T02:00:00.000Z", output: 140)))
    try handle.close()

    let second = scanner.compute()
    expect(second[.today]?.modelCallsCount == 2, "appended JSONL data should be scanned incrementally")
    expect(second[.today]?.totalTokens == 300, "incremental totals should include old and new events once")

    let unchanged = scanner.compute()
    expect(unchanged[.today]?.modelCallsCount == 2, "unchanged files must not be counted twice")
    expect(unchanged[.today]?.totalTokens == 300, "cached totals must remain stable")
}

private func runStaleFileFastForwardTests() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeBarStale-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let projects = root.appendingPathComponent("projects/demo")
    try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
    let log = projects.appendingPathComponent("session.jsonl")
    let cache = root.appendingPathComponent("cache/token.json")

    // The line carries an in-window timestamp even though the file itself was
    // last written before the window opened. Skipping it is the whole point:
    // it is what stops a resumed old session from forcing a full re-read.
    try jsonLine(usage("2026-09-03T01:00:00.000Z", output: 40)).write(to: log)
    let stale = ISO8601DateFormatter().date(from: "2026-08-20T00:00:00Z")!
    try FileManager.default.setAttributes([.modificationDate: stale], ofItemAtPath: log.path)

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 2
    let fixedNow = ISO8601DateFormatter().date(from: "2026-09-03T12:00:00Z")!
    let scanner = TokenStatsScanner(projectsDirectory: root.appendingPathComponent("projects"), cacheURL: cache, calendar: calendar) {
        fixedNow
    }

    let first = scanner.compute()
    expect(first[.today]?.modelCallsCount == 0, "logs untouched since before the window must be skipped entirely")

    let handle = try FileHandle(forWritingTo: log)
    try handle.seekToEnd()
    try handle.write(contentsOf: jsonLine(usage("2026-09-03T02:00:00.000Z", output: 140)))
    try handle.close()

    let second = scanner.compute()
    expect(second[.today]?.modelCallsCount == 1, "only bytes appended after the fast-forward should be scanned")
    expect(second[.today]?.totalTokens == 200, "fast-forwarded bytes must not be re-parsed")
}

private func runCacheHorizonTests() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeBarHorizon-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let projects = root.appendingPathComponent("projects/demo")
    try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
    let log = projects.appendingPathComponent("session.jsonl")
    let cache = root.appendingPathComponent("cache/token.json")

    var initial = Data()
    initial.append(jsonLine(usage("2026-08-26T01:00:00.000Z", output: 40)))
    initial.append(jsonLine(usage("2026-09-03T01:00:00.000Z", output: 60)))
    try initial.write(to: log)

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 2
    let projectsRoot = root.appendingPathComponent("projects")

    let current = TokenStatsScanner(projectsDirectory: projectsRoot, cacheURL: cache, calendar: calendar) {
        ISO8601DateFormatter().date(from: "2026-09-03T12:00:00Z")!
    }
    let thisWeek = current.compute()
    expect(thisWeek[.thisWeek]?.modelCallsCount == 1, "only the current natural week should be counted")

    // A second pass is what actually evicts the earlier week's events from the
    // cache, so the rebuild below has something real to recover.
    _ = current.compute()

    // Reaching further back than the cache was built for has to discard the
    // fast-forwarded offsets, otherwise the earlier week would read as empty.
    let earlier = TokenStatsScanner(projectsDirectory: projectsRoot, cacheURL: cache, calendar: calendar) {
        ISO8601DateFormatter().date(from: "2026-08-27T12:00:00Z")!
    }
    let previousWeek = earlier.compute()
    expect(previousWeek[.thisWeek]?.modelCallsCount == 1, "a window reaching before the cache horizon must rebuild")
}

private func runMondayWeekTests() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeBarMonday-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let projects = root.appendingPathComponent("projects/demo")
    try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
    let log = projects.appendingPathComponent("session.jsonl")
    let cache = root.appendingPathComponent("cache/token.json")

    // 每条事件的 output 取 2 的幂，使任何子集的合计唯一，从而能区分出
    // 究竟哪几条被算了进去——只比对条数会被「起点早一天、终点早两天」
    // 这类互相抵消的错误蒙混过去。usage() 的固定开销是 60，故合计 = 60 + output。
    var initial = Data()
    initial.append(jsonLine(usage("2026-08-30T12:00:00.000Z", output: 1)))    // 上周日，应排除 -> 61
    initial.append(jsonLine(usage("2026-08-31T00:00:00.000Z", output: 2)))    // 周一零点，应包含 -> 62
    initial.append(jsonLine(usage("2026-09-01T12:00:00.000Z", output: 4)))    // 周二，应包含 -> 64
    initial.append(jsonLine(usage("2026-09-06T23:59:59.000Z", output: 8)))    // 本周日最后一秒，应包含 -> 68
    initial.append(jsonLine(usage("2026-09-07T00:00:00.000Z", output: 16)))   // 下周一零点，应排除 -> 76
    try initial.write(to: log)

    // firstWeekday = 1 是 zh-Hans_TW 等区域的系统默认（周日起算）。扫描器必须
    // 自己钉死周一，而不是听这个日历的。
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 1
    let scanner = TokenStatsScanner(projectsDirectory: root.appendingPathComponent("projects"), cacheURL: cache, calendar: calendar) {
        ISO8601DateFormatter().date(from: "2026-09-03T12:00:00Z")!
    }

    let stats = scanner.compute()
    expect(stats[.thisWeek]?.modelCallsCount == 3,
           "week must hold exactly the Monday, Tuesday and Sunday events")
    expect(stats[.thisWeek]?.totalTokens == 62 + 64 + 68,
           "week must run Monday 00:00 through Sunday 23:59:59 regardless of the region's first weekday")
    expect(stats[.today]?.modelCallsCount == 0,
           "an event later in the week must not leak into today")
}

private func runQuotaWindowTests() {
    let base = ISO8601DateFormatter().date(from: "2026-09-04T05:59:59Z")!

    // 实测到的真实噪声：同一响应内 5 小时与 7 天窗口的微秒数相差数十微秒，
    // 换一个响应两者又一起变化——亚秒部分是服务端生成响应的时刻，与窗口无关。
    expect(!isNewQuotaWindow(previous: base.addingTimeInterval(0.721907),
                             current: base.addingTimeInterval(0.960867)),
           "sub-second jitter on the same window must not read as a reset")
    expect(!isNewQuotaWindow(previous: base.addingTimeInterval(0.960867),
                             current: base.addingTimeInterval(0.721907)),
           "jitter in the other direction must not read as a reset either")

    expect(!isNewQuotaWindow(previous: base, current: base.addingTimeInterval(59)),
           "a move inside the tolerance is still the same window")
    expect(isNewQuotaWindow(previous: base, current: base.addingTimeInterval(5 * 3600)),
           "the next five-hour window must be reported")
    expect(!isNewQuotaWindow(previous: nil, current: base),
           "with no baseline there is nothing to compare and nothing to report")
    expect(!isNewQuotaWindow(previous: base, current: nil),
           "a missing reset date must not report a reset")
}

private func runRetryAfterTests() {
    let now = Date(timeIntervalSince1970: 1_000)
    expect(RetryAfterParser.date(from: "120", now: now) == Date(timeIntervalSince1970: 1_120),
           "numeric Retry-After should be interpreted as seconds")

    let parsed = RetryAfterParser.date(from: "Wed, 21 Oct 2015 07:28:00 GMT", now: now)
    expect(parsed != nil, "HTTP-date Retry-After should parse")
    expect(Int(parsed?.timeIntervalSince1970 ?? 0) == 1_445_412_480,
           "HTTP-date Retry-After should produce the expected instant")

    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeBarUsageCache-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = UsageCacheStore(fileURL: root.appendingPathComponent("usage.json"))
    let retryDate = now.addingTimeInterval(90)
    store.setRetryNotBefore(retryDate)
    expect(store.load()?.retryNotBefore == retryDate,
           "rate-limit state should persist even before the first successful response")
}

do {
    try runTokenScannerTests()
    try runStaleFileFastForwardTests()
    try runCacheHorizonTests()
    try runMondayWeekTests()
    runQuotaWindowTests()
    runRetryAfterTests()
} catch {
    failures += 1
    fputs("FAIL: unexpected error: \(error)\n", stderr)
}

if failures > 0 {
    fputs("\(failures) test(s) failed\n", stderr)
    exit(1)
}
print("All ClaudeBar tests passed")
