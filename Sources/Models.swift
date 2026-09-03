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

// MARK: - Today Token Stats

public struct TodayTokenStats {
    public var totalTokens: Int = 0
    public var inputTokens: Int = 0
    public var outputTokens: Int = 0
    public var cacheCreationTokens: Int = 0
    public var cacheReadTokens: Int = 0
    public var messageCount: Int = 0
    public var tokensByModel: [String: Int] = [:]
    
    public var totalFormatted: String {
        formatTokenNumber(totalTokens)
    }
    
    public var outputFormatted: String {
        formatTokenNumber(outputTokens)
    }
    
    public var cacheCreationFormatted: String {
        formatTokenNumber(cacheCreationTokens)
    }
    
    public var cacheReadFormatted: String {
        formatTokenNumber(cacheReadTokens)
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

// MARK: - Formatted Usage View Model

public struct FormattedUsage {
    public var fiveHourUtilization: Double = 0
    public var fiveHourResetDate: Date?
    public var fiveHourCountdown: String = "--"
    
    public var sevenDayUtilization: Double = 0
    public var sevenDayResetDate: Date?
    public var sevenDayCountdown: String = "--"
    
    public var extraUsageEnabled: Bool = false
    public var extraSpendFormatted: String = "$0.00"
    
    public var todayStats: TodayTokenStats = TodayTokenStats()
    
    public var account: AccountInfo = AccountInfo()
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
