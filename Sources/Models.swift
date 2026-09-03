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
