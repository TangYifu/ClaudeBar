import Foundation
import ServiceManagement
import UserNotifications

public final class SettingsManager: ObservableObject {
    public static let shared = SettingsManager()
    
    @Published public var showPercentage: Bool {
        didSet {
            UserDefaults.standard.set(showPercentage, forKey: "showPercentage")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }
    
    @Published public var refreshInterval: Int { // in minutes
        didSet {
            UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }
    
    @Published public var launchAtLogin: Bool {
        didSet {
            if #available(macOS 13.0, *) {
                do {
                    if launchAtLogin {
                        if SMAppService.mainApp.status != .enabled {
                            try SMAppService.mainApp.register()
                        }
                    } else {
                        if SMAppService.mainApp.status == .enabled {
                            try SMAppService.mainApp.unregister()
                        }
                    }
                } catch {
                    print("Failed to toggle launch at login: \(error)")
                }
            }
        }
    }
    
    @Published public var enableQuotaNotification: Bool {
        didSet {
            UserDefaults.standard.set(enableQuotaNotification, forKey: "enableQuotaNotification")
        }
    }

    @Published public var threshold5hWarning: Int {
        didSet { UserDefaults.standard.set(threshold5hWarning, forKey: "threshold5hWarning") }
    }
    @Published public var threshold5hCritical: Int {
        didSet { UserDefaults.standard.set(threshold5hCritical, forKey: "threshold5hCritical") }
    }
    @Published public var threshold7dWarning: Int {
        didSet { UserDefaults.standard.set(threshold7dWarning, forKey: "threshold7dWarning") }
    }
    @Published public var notifyOnReset: Bool {
        didSet { UserDefaults.standard.set(notifyOnReset, forKey: "notifyOnReset") }
    }

    /// On by default where the hardware has a notch. Switching it off tears the
    /// window down again, which matters because that window lives for the whole
    /// session and costs roughly as much memory as the rest of the app.
    @Published public var showNotchIsland: Bool {
        didSet {
            UserDefaults.standard.set(showNotchIsland, forKey: "showNotchIsland")
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
    }

    private init() {
        self.showPercentage = UserDefaults.standard.object(forKey: "showPercentage") as? Bool ?? true
        self.refreshInterval = UserDefaults.standard.object(forKey: "refreshInterval") as? Int ?? 3
        self.enableQuotaNotification = UserDefaults.standard.object(forKey: "enableQuotaNotification") as? Bool ?? true
        self.threshold5hWarning = UserDefaults.standard.object(forKey: "threshold5hWarning") as? Int ?? 80
        self.threshold5hCritical = UserDefaults.standard.object(forKey: "threshold5hCritical") as? Int ?? 95
        self.threshold7dWarning = UserDefaults.standard.object(forKey: "threshold7dWarning") as? Int ?? 85
        self.notifyOnReset = UserDefaults.standard.object(forKey: "notifyOnReset") as? Bool ?? true
        self.showNotchIsland = UserDefaults.standard.object(forKey: "showNotchIsland") as? Bool ?? true
        
        if #available(macOS 13.0, *) {
            self.launchAtLogin = SMAppService.mainApp.status == .enabled
        } else {
            self.launchAtLogin = false
        }
    }
    
    // MARK: - Quota Threshold Notifications

    public func checkAndDeliverQuotaNotification(usage: FormattedUsage) {
        if notifyOnReset { checkResetNotification(usage: usage) }
        guard enableQuotaNotification else { return }

        let fiveHour = Int(round(usage.fiveHourUtilization))
        let sevenDay = Int(round(usage.sevenDayUtilization))
        let crit = max(1, min(100, threshold5hCritical))
        let warn = max(1, min(crit - 1, threshold5hWarning))
        let sevenWarn = max(1, min(100, threshold7dWarning))

        let lastNotified5h = UserDefaults.standard.integer(forKey: "lastNotified5h")
        if fiveHour >= crit && lastNotified5h < crit {
            sendNotification(title: "Claude Code 配额即将耗尽 (5小时)", body: "您的 5 小时会话配额已消耗 \(fiveHour)%，请注意用量节奏。")
            UserDefaults.standard.set(crit, forKey: "lastNotified5h")
        } else if fiveHour >= warn && lastNotified5h < warn {
            sendNotification(title: "Claude Code 配额预警 (5小时)", body: "您的 5 小时会话配额已消耗 \(fiveHour)%，预计 \(usage.fiveHourCountdown) 重置。")
            UserDefaults.standard.set(warn, forKey: "lastNotified5h")
        } else if fiveHour < warn - 10 {
            UserDefaults.standard.set(0, forKey: "lastNotified5h")
        }

        let lastNotified7d = UserDefaults.standard.integer(forKey: "lastNotified7d")
        if sevenDay >= sevenWarn && lastNotified7d < sevenWarn {
            sendNotification(title: "Claude Code 周度配额预警 (7天)", body: "您的 7 天周度配额已消耗 \(sevenDay)%，预计 \(usage.sevenDayCountdown) 重置。")
            UserDefaults.standard.set(sevenWarn, forKey: "lastNotified7d")
        } else if sevenDay < sevenWarn - 10 {
            UserDefaults.standard.set(0, forKey: "lastNotified7d")
        }
    }

    private func checkResetNotification(usage: FormattedUsage) {
        let prevFive = UserDefaults.standard.object(forKey: "prevFiveReset") as? Date
        let prevSeven = UserDefaults.standard.object(forKey: "prevSevenReset") as? Date
        if let cur = usage.fiveHourResetDate, let prev = prevFive, cur > prev {
            sendNotification(title: "Claude Code 5小时配额已重置", body: "新的 5 小时会话已开始。")
        }
        if let cur = usage.sevenDayResetDate, let prev = prevSeven, cur > prev {
            sendNotification(title: "Claude Code 7天配额已重置", body: "新的 7 天周期已开始。")
        }
        if let cur = usage.fiveHourResetDate { UserDefaults.standard.set(cur, forKey: "prevFiveReset") }
        if let cur = usage.sevenDayResetDate { UserDefaults.standard.set(cur, forKey: "prevSevenReset") }
    }
    
    private func sendNotification(title: String, body: String) {
        if #available(macOS 10.14, *) {
            let center = UNUserNotificationCenter.current()
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                guard granted else { return }
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default
                let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                center.add(request, withCompletionHandler: nil)
            }
        }
    }
}

extension Notification.Name {
    public static let settingsChanged = Notification.Name("ClaudeBarSettingsChanged")
    public static let closePopover = Notification.Name("ClaudeBarClosePopover")
}
