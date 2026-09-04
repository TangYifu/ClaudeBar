import Foundation

// MARK: - API Response Models

public struct WindowInfo: Codable {
    public let utilization: Double?
    public let resets_at: String?
    public let limit_dollars: Double?
    public let used_dollars: Double?
    public let remaining_dollars: Double?
}

public struct ExtraUsage: Codable {
    public let is_enabled: Bool?
    public let monthly_limit: Double?
    public let used_credits: Double?
    public let utilization: Double?
}

public struct SpendAmount: Codable {
    public let amount_minor: Int?
    public let currency: String?
    public let exponent: Int?
    
    public var formatted: String {
        guard let amount = amount_minor, let exp = exponent else { return "$0.00" }
        let val = Double(amount) / pow(10.0, Double(exp))
        return String(format: "$%.2f", val)
    }
}

public struct SpendInfo: Codable {
    public let used: SpendAmount?
    public let percent: Double?
    public let enabled: Bool?
}

public struct UsageResponse: Codable {
    public let five_hour: WindowInfo?
    public let seven_day: WindowInfo?
    public let extra_usage: ExtraUsage?
    public let spend: SpendInfo?
}

// MARK: - Account Info

public struct AccountInfo {
    public var displayName: String = ""
    public var email: String = ""
    public var billingType: String = ""
    public var subscriptionType: String = ""
    
    public var planSummary: String {
        if !subscriptionType.isEmpty {
            return subscriptionType.capitalized
        }
        if billingType.contains("subscription") {
            return "Pro / Subscription"
        }
        return "Claude Account"
    }
}

// MARK: - Time Period

public enum TimePeriod: String, CaseIterable, Identifiable, Codable {
    case today = "今天"
    case yesterday = "昨天"
    case thisWeek = "本周"
    case thisMonth = "本月"
    case last30Days = "近30天"

    public var id: String { rawValue }
}

// MARK: - Period Token Stats

public struct PeriodTokenStats: Codable {
    public var inputTokens: Int = 0
    public var outputTokens: Int = 0
    public var cacheCreationTokens: Int = 0
    public var cacheReadTokens: Int = 0
    public var modelCallsCount: Int = 0
    public var userPromptsCount: Int = 0
    public var tokensByModel: [String: Int] = [:]
    public var tokensByProject: [String: Int] = [:]
    
    public init() {}
    
    public var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }
    
    public var totalFormatted: String {
        guard totalTokens > 0 else { return "暂无" }
        return formatTokenNumber(totalTokens)
    }
    
    public var outputFormatted: String {
        guard outputTokens > 0 else { return totalTokens == 0 ? "暂无" : "0" }
        return formatTokenNumber(outputTokens)
    }
    
    public var userInputTokens: Int {
        inputTokens + cacheCreationTokens
    }
    
    public var userInputFormatted: String {
        guard userInputTokens > 0 else { return totalTokens == 0 ? "暂无" : "0" }
        return formatTokenNumber(userInputTokens)
    }
    
    public var cacheCreationFormatted: String {
        guard cacheCreationTokens > 0 else { return totalTokens == 0 ? "暂无" : "0" }
        return formatTokenNumber(cacheCreationTokens)
    }
    
    public var cacheReadFormatted: String {
        guard cacheReadTokens > 0 else { return totalTokens == 0 ? "暂无" : "0" }
        return formatTokenNumber(cacheReadTokens)
    }
    
    public var cacheEfficiencyPercent: Int {
        let totalInput = inputTokens + cacheCreationTokens + cacheReadTokens
        guard totalInput > 0 else { return 0 }
        return Int(round(Double(cacheReadTokens) / Double(totalInput) * 100.0))
    }
    
    public var topModelsSummary: [(name: String, formatted: String)] {
        tokensByModel.sorted { $0.value > $1.value }.prefix(2).map { (key, val) in
            let cleanName = key
                .replacingOccurrences(of: "claude-", with: "")
                .replacingOccurrences(of: "-20251001", with: "")
                .capitalized
            return (cleanName, formatTokenNumber(val))
        }
    }
    
    public var topProjectsSummary: [(name: String, formatted: String, percent: Int)] {
        let sorted = tokensByProject.sorted { $0.value > $1.value }.prefix(8)
        let total = totalTokens > 0 ? totalTokens : 1
        return sorted.map { (proj, count) in
            let pct = Int(round(Double(count) / Double(total) * 100.0))
            return (proj, formatTokenNumber(count), pct)
        }
    }
    
    private func formatTokenNumber(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000.0)
        } else {
            return "\(count)"
        }
    }
}

public typealias TodayTokenStats = PeriodTokenStats

// MARK: - Formatted Usage View Model

public struct FormattedUsage {
    public var fiveHourUtilization: Double = 0
    public var fiveHourResetDate: Date?
    public var fiveHourCountdown: String = "--"
    public var fiveHourBurnRate: Double? = nil
    public var fiveHourBurnDelta: Double? = nil
    public var fiveHourExhaustion: Date? = nil

    public var sevenDayUtilization: Double = 0
    public var sevenDayResetDate: Date?
    public var sevenDayCountdown: String = "--"
    public var sevenDayBurnRate: Double? = nil
    public var sevenDayBurnDelta: Double? = nil
    public var sevenDayExhaustion: Date? = nil

    public enum TighterWindow: String { case fiveHour = "5小时"; case sevenDay = "7天" }
    public var tighterWindow: TighterWindow? = nil
    public var adviceText: String? = nil

    public var extraUsageEnabled: Bool = false
    public var extraSpendFormatted: String = "--"

    public var account: AccountInfo = AccountInfo()
    public var statsByPeriod: [TimePeriod: PeriodTokenStats] = [:]
    
    public var todayStats: PeriodTokenStats {
        get { statsByPeriod[.today] ?? PeriodTokenStats() }
        set { statsByPeriod[.today] = newValue }
    }
    
    public var lastUpdated: Date = Date()
    public var isOffline: Bool = false
    public var errorMessage: String? = nil
    
    public var fiveHourPercentInt: Int {
        return Int(round(fiveHourUtilization))
    }
    
    public var sevenDayPercentInt: Int {
        return Int(round(sevenDayUtilization))
    }
    
    public enum Severity {
        case normal, warning, critical
    }
    
    public var severity: Severity {
        let maxPercent = max(fiveHourPercentInt, sevenDayPercentInt)
        if maxPercent >= 90 { return .critical }
        if maxPercent >= 75 { return .warning }
        return .normal
    }
}
