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
    
    private init() {
        self.showPercentage = UserDefaults.standard.object(forKey: "showPercentage") as? Bool ?? true
        self.refreshInterval = UserDefaults.standard.object(forKey: "refreshInterval") as? Int ?? 3
        self.enableQuotaNotification = UserDefaults.standard.object(forKey: "enableQuotaNotification") as? Bool ?? true
        
        if #available(macOS 13.0, *) {
            self.launchAtLogin = SMAppService.mainApp.status == .enabled
        } else {
            self.launchAtLogin = false
        }
    }
    
    // MARK: - Quota Threshold Notifications
    
    public func checkAndDeliverQuotaNotification(usage: FormattedUsage) {
        guard enableQuotaNotification else { return }
        
        let fiveHour = Int(round(usage.fiveHourUtilization))
        let sevenDay = Int(round(usage.sevenDayUtilization))
        
        let lastNotified5h = UserDefaults.standard.integer(forKey: "lastNotified5h")
        // Check the highest threshold first. If usage jumps directly above 95%,
        // deliver the urgent warning immediately instead of delaying it until
        // the next refresh after an 80% notification.
        if fiveHour >= 95 && lastNotified5h < 95 {
            sendNotification(
                title: "Claude Code 配额即将耗尽 (5小时)",
                body: "您的 5 小时会话配额已消耗 \(fiveHour)%，请注意用量节奏。"
            )
            UserDefaults.standard.set(95, forKey: "lastNotified5h")
        } else if fiveHour >= 80 && lastNotified5h < 80 {
            sendNotification(
                title: "Claude Code 配额预警 (5小时)",
                body: "您的 5 小时会话配额已消耗 \(fiveHour)%，预计 \(usage.fiveHourCountdown) 重置。"
            )
            UserDefaults.standard.set(80, forKey: "lastNotified5h")
        } else if fiveHour < 70 {
            UserDefaults.standard.set(0, forKey: "lastNotified5h")
        }
        
        let lastNotified7d = UserDefaults.standard.integer(forKey: "lastNotified7d")
        if sevenDay >= 85 && lastNotified7d < 85 {
            sendNotification(
                title: "Claude Code 周度配额预警 (7天)",
                body: "您的 7 天周度配额已消耗 \(sevenDay)%，预计 \(usage.sevenDayCountdown) 重置。"
            )
            UserDefaults.standard.set(85, forKey: "lastNotified7d")
        } else if sevenDay < 75 {
            UserDefaults.standard.set(0, forKey: "lastNotified7d")
        }
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
