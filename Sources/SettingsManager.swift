import Foundation
import ServiceManagement

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
    
    private init() {
        self.showPercentage = UserDefaults.standard.object(forKey: "showPercentage") as? Bool ?? true
        self.refreshInterval = UserDefaults.standard.object(forKey: "refreshInterval") as? Int ?? 3
        
        if #available(macOS 13.0, *) {
            self.launchAtLogin = SMAppService.mainApp.status == .enabled
        } else {
            self.launchAtLogin = false
        }
    }
}

extension Notification.Name {
    public static let settingsChanged = Notification.Name("ClaudeBarSettingsChanged")
}
