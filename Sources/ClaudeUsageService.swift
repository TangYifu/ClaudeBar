import Foundation

public final class ClaudeUsageService: @unchecked Sendable {
    public static let shared = ClaudeUsageService()
    
    private let isoFormatterWithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    
    private let isoFormatterStandard: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    
    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
    
    private let monthDayTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()
    
    private let fetchLock = NSLock()
    private var isFetching = false
    private var lastSuccessfulUsage: FormattedUsage?
    private var applicationSupportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ClaudeBar", isDirectory: true)
    }
    private lazy var usageCache = UsageCacheStore(
        fileURL: applicationSupportDirectory.appendingPathComponent("usage-cache-v1.json")
    )
    private lazy var historyStore = UsageHistoryStore(
        fileURL: applicationSupportDirectory.appendingPathComponent("usage-history-v1.json")
    )
    
    private init() {}
    
    // MARK: - Public Fetch
    
    public func fetchUsage(force: Bool = false, completion: @escaping (FormattedUsage) -> Void) {
        fetchLock.lock()
        if isFetching && !force {
            fetchLock.unlock()
            if let cached = lastSuccessfulUsage {
                completion(cached)
            }
            return
        }
        isFetching = true
        fetchLock.unlock()
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let account = self.loadAccountInfo()
            let statsByPeriod = self.computeMultiPeriodTokenStats()
            
            let finish: (FormattedUsage) -> Void = { [weak self] result in
                guard let self = self else { return }
                self.fetchLock.lock()
                self.isFetching = false
                if !result.isOffline {
                    self.lastSuccessfulUsage = result
                }
                self.fetchLock.unlock()
                DispatchQueue.main.async { completion(result) }
            }

            if let cached = self.usageCache.load(),
               let retryDate = cached.retryNotBefore,
               retryDate > Date() {
                let hint = UsageRequestError.http(status: 429, retryNotBefore: retryDate).localizedDescription
                var formatted: FormattedUsage
                if let response = cached.response {
                    formatted = self.formatResponse(response, account: account, isOffline: true)
                    formatted.lastUpdated = cached.savedAt
                } else {
                    formatted = self.fetchFromLocalCache(account: account, errorHint: hint)
                }
                formatted.statsByPeriod = statsByPeriod
                formatted.errorMessage = hint
                finish(formatted)
                return
            }
            
            // 1. Try fetching via API token
            if let token = self.fetchAccessTokenFromKeychain() {
                self.fetchUsageFromAPI(token: token) { result in
                    switch result {
                    case .success(let response):
                        self.usageCache.save(response: response)
                        var formatted = self.formatResponse(response, account: account, isOffline: false)
                        formatted.statsByPeriod = statsByPeriod
                        finish(formatted)
                    case .failure(let error):
                        print("API request failed: \(error.localizedDescription), falling back to local cache")
                        if case UsageRequestError.http(let status, let retryDate) = error,
                           status == 429, let retryDate {
                            self.usageCache.setRetryNotBefore(retryDate)
                        }
                        var formatted = self.fetchBestFallback(account: account, errorHint: error.localizedDescription)
                        formatted.statsByPeriod = statsByPeriod
                        finish(formatted)
                    }
                }
            } else {
                print("Keychain token unavailable, falling back to local cache")
                var formatted = self.fetchBestFallback(account: account, errorHint: "Keychain 凭据未就绪，使用本地缓存")
                formatted.statsByPeriod = statsByPeriod
                finish(formatted)
            }
        }
    }
    
    // MARK: - Keychain Extraction
    
    private func fetchAccessTokenFromKeychain() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let jsonStr = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let jsonData = jsonStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let claudeAi = json["claudeAiOauth"] as? [String: Any],
                  let token = claudeAi["accessToken"] as? String else {
                return nil
            }
            return token
        } catch {
            return nil
        }
    }
    
    // MARK: - API Call
    
    private func fetchUsageFromAPI(token: String, completion: @escaping (Result<UsageResponse, Error>) -> Void) {
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
            completion(.failure(NSError(domain: "ClaudeBar", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("claude-code/0.2.29", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("claude-code-20250219", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 10
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                let retryDate = http.statusCode == 429
                    ? RetryAfterParser.date(from: http.value(forHTTPHeaderField: "Retry-After"))
                        ?? Date().addingTimeInterval(60)
                    : nil
                completion(.failure(UsageRequestError.http(status: http.statusCode, retryNotBefore: retryDate)))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "ClaudeBar", code: -2, userInfo: [NSLocalizedDescriptionKey: "Empty response"])))
                return
            }
            
            do {
                let usage = try JSONDecoder().decode(UsageResponse.self, from: data)
                completion(.success(usage))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    // MARK: - Local Cache Fallback (~/.claude.json)

    private func fetchBestFallback(account: AccountInfo, errorHint: String?) -> FormattedUsage {
        if let cached = usageCache.load(), let response = cached.response {
            var result = formatResponse(response, account: account, isOffline: true)
            result.lastUpdated = cached.savedAt
            result.errorMessage = errorHint
            return result
        }
        return fetchFromLocalCache(account: account, errorHint: errorHint)
    }
    
    private func fetchFromLocalCache(account: AccountInfo, errorHint: String?) -> FormattedUsage {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let claudeJsonUrl = homeDir.appendingPathComponent(".claude.json")
        
        guard let data = try? Data(contentsOf: claudeJsonUrl),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cached = json["cachedUsageUtilization"] as? [String: Any],
              let utilization = cached["utilization"] as? [String: Any] else {
            var failed = FormattedUsage()
            failed.account = account
            failed.isOffline = true
            failed.errorMessage = errorHint ?? "无法读取 Claude Code 用量数据"
            return failed
        }
        
        // Convert utilization dictionary to UsageResponse
        if let utilData = try? JSONSerialization.data(withJSONObject: utilization),
           let response = try? JSONDecoder().decode(UsageResponse.self, from: utilData) {
            var res = formatResponse(response, account: account, isOffline: true)
            res.errorMessage = errorHint
            return res
        }
        
        var fallback = FormattedUsage()
        fallback.account = account
        fallback.isOffline = true
        fallback.errorMessage = errorHint
        return fallback
    }
    
    // MARK: - Multi-Period Token Stats Computation
    
    public func computeMultiPeriodTokenStats() -> [TimePeriod: PeriodTokenStats] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let scanner = TokenStatsScanner(
            projectsDirectory: home.appendingPathComponent(".claude/projects"),
            cacheURL: applicationSupportDirectory.appendingPathComponent("token-stats-cache-v1.json")
        )
        return scanner.compute()
    }

    private func loadAccountInfo() -> AccountInfo {
        var info = AccountInfo()
        
        // 1. Try Keychain for subscriptionType
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let pipe = Pipe()
        process.standardOutput = pipe
        if let _ = try? process.run() {
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let jsonStr = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   let jsonData = jsonStr.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   let claudeAi = json["claudeAiOauth"] as? [String: Any] {
                    info.subscriptionType = (claudeAi["subscriptionType"] as? String) ?? ""
                }
            }
        }
        
        // 2. Read ~/.claude.json for user display name & email
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let claudeJsonUrl = homeDir.appendingPathComponent(".claude.json")
        if let data = try? Data(contentsOf: claudeJsonUrl),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let oauth = json["oauthAccount"] as? [String: Any] {
            info.displayName = (oauth["displayName"] as? String) ?? ""
            info.email = (oauth["emailAddress"] as? String) ?? ""
            info.billingType = (oauth["billingType"] as? String) ?? ""
        }
        
        return info
    }
    
    // MARK: - Response Formatting

    private func formatResponse(_ response: UsageResponse, account: AccountInfo, isOffline: Bool) -> FormattedUsage {
        var item = FormattedUsage()
        item.account = account
        item.isOffline = isOffline
        item.lastUpdated = Date()

        if let five = response.five_hour {
            item.fiveHourUtilization = five.utilization ?? 0
            if let resetsAtStr = five.resets_at, let resetDate = parseDate(resetsAtStr) {
                item.fiveHourResetDate = resetDate
                item.fiveHourCountdown = formatCountdown(resetDate: resetDate, isShort: true)
            } else {
                item.fiveHourCountdown = "无重置时间"
            }
        }
        if let seven = response.seven_day {
            item.sevenDayUtilization = seven.utilization ?? 0
            if let resetsAtStr = seven.resets_at, let resetDate = parseDate(resetsAtStr) {
                item.sevenDayResetDate = resetDate
                item.sevenDayCountdown = formatCountdown(resetDate: resetDate, isShort: false)
            } else {
                item.sevenDayCountdown = "无重置时间"
            }
        }
        if let extra = response.extra_usage {
            item.extraUsageEnabled = extra.is_enabled ?? false
        }
        if let spend = response.spend, let used = spend.used {
            item.extraSpendFormatted = used.formatted
        }

        enrichWithHistory(&item, isOffline: isOffline)
        return item
    }

    private func enrichWithHistory(_ item: inout FormattedUsage, isOffline: Bool) {
        let now = Date()
        // One load and at most one save per refresh; offline readings come from a
        // cache and must not be written back into the series as fresh samples.
        let burn = historyStore.update(
            fiveUtil: item.fiveHourUtilization,
            sevenUtil: item.sevenDayUtilization,
            fiveReset: item.fiveHourResetDate,
            sevenReset: item.sevenDayResetDate,
            record: !isOffline,
            now: now
        )
        item.fiveHourBurnRate = burn.five.rate
        item.fiveHourBurnDelta = burn.five.delta
        item.fiveHourExhaustion = burn.five.exhaustion
        item.sevenDayBurnRate = burn.seven.rate
        item.sevenDayBurnDelta = burn.seven.delta
        item.sevenDayExhaustion = burn.seven.exhaustion

        let fiveRemain = 100 - item.fiveHourUtilization
        let sevenRemain = 100 - item.sevenDayUtilization
        let fiveHoursLeft = item.fiveHourResetDate.map { max(0.1, $0.timeIntervalSince(now) / 3600) } ?? 5
        let sevenHoursLeft = item.sevenDayResetDate.map { max(0.1, $0.timeIntervalSince(now) / 3600) } ?? (7 * 24)
        let fivePressure = fiveRemain / fiveHoursLeft
        let sevenPressure = sevenRemain / sevenHoursLeft
        if fivePressure < sevenPressure {
            item.tighterWindow = .fiveHour
        } else if sevenPressure < fivePressure {
            item.tighterWindow = .sevenDay
        }

        if let ex = item.fiveHourExhaustion, let reset = item.fiveHourResetDate, ex < reset, item.fiveHourUtilization >= 50 {
            item.adviceText = "按此速度将在重置前耗尽，建议切小模型"
        } else if let ex = item.sevenDayExhaustion, let reset = item.sevenDayResetDate, ex < reset, item.sevenDayUtilization >= 50 {
            item.adviceText = "按此速度将在周重置前耗尽，今日尽量用 Sonnet"
        } else if item.tighterWindow == .fiveHour, item.fiveHourUtilization >= 75 {
            item.adviceText = "5小时更紧，暂停大文件上下文"
        } else if item.tighterWindow == .sevenDay, item.sevenDayUtilization >= 65 {
            item.adviceText = "7天更紧，今日尽量用 Sonnet"
        } else if item.tighterWindow != nil {
            item.adviceText = item.tighterWindow == .fiveHour ? "当前 5小时为瓶颈" : "当前 7天为瓶颈"
        }
    }
    
    private func parseDate(_ str: String) -> Date? {
        if let d = isoFormatterWithFractional.date(from: str) {
            return d
        }
        return isoFormatterStandard.date(from: str)
    }
    
    private func formatCountdown(resetDate: Date, isShort: Bool) -> String {
        let diff = resetDate.timeIntervalSince(Date())
        if diff <= 0 {
            return "即将重置"
        }
        
        let hours = Int(diff) / 3600
        let minutes = (Int(diff) % 3600) / 60
        let days = hours / 24
        let remainingHours = hours % 24
        
        let resetTimeStr = isShort ? timeFormatter.string(from: resetDate) : monthDayTimeFormatter.string(from: resetDate)
        
        if days > 0 {
            return "\(days)天\(remainingHours)小时后 (\(resetTimeStr) 重置)"
        } else if hours > 0 {
            return "\(hours)小时\(minutes)分后 (\(resetTimeStr) 重置)"
        } else if minutes > 0 {
            return "\(minutes)分钟后 (\(resetTimeStr) 重置)"
        } else {
            return "< 1分钟后 (\(resetTimeStr) 重置)"
        }
    }
}
