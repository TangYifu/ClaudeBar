import Cocoa
import SwiftUI

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var eventMonitor: Any?
    private var refreshTimer: Timer?
    
    private let viewModel = PopoverViewModel()
    private let settings = SettingsManager.shared
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("ClaudeBar background monitoring")
        setupStatusItem()
        setupPopover()
        setupNotifications()
        startTimer()
        
        // Initial fetch
        refreshData()
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        refreshTimer?.invalidate()
    }
    
    // MARK: - Setup UI
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        
        button.image = loadTrayIcon()
        button.imagePosition = .imageLeading
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        
        updateButtonTitle()
    }
    
    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 480)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: PopoverView(viewModel: viewModel))
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSettingsChanged),
            name: .settingsChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleClosePopover),
            name: .closePopover,
            object: nil
        )
    }
    
    @objc private func handleClosePopover() {
        closePopover()
    }
    
    // MARK: - Status Item Interaction
    
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        
        if event.type == .rightMouseUp {
            showContextMenu(sender)
        } else {
            togglePopover(sender)
        }
    }
    
    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            closePopover()
        } else {
            showPopover(sender)
        }
    }
    
    private func showPopover(_ sender: NSStatusBarButton) {
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        viewModel.refresh { [weak self] in
            self?.updateButtonTitle()
        }
        
        // Setup outside click monitor
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }
    
    private func closePopover() {
        popover.performClose(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    
    private func showContextMenu(_ sender: NSStatusBarButton) {
        closePopover()
        
        let menu = NSMenu()
        
        let refreshItem = NSMenuItem(title: "立即刷新", action: #selector(contextRefresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let terminalItem = NSMenuItem(title: "在终端运行 Claude Code", action: #selector(contextOpenTerminal), keyEquivalent: "t")
        terminalItem.target = self
        menu.addItem(terminalItem)
        
        let webItem = NSMenuItem(title: "打开 Claude 网页用量", action: #selector(contextOpenWeb), keyEquivalent: "")
        webItem.target = self
        menu.addItem(webItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "退出 ClaudeBar", action: #selector(contextQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        
        // Clear menu so normal left clicks open popover again
        DispatchQueue.main.async { [weak self] in
            self?.statusItem.menu = nil
        }
    }
    
    // MARK: - Context Menu Actions
    
    @objc private func contextRefresh() {
        refreshData()
    }
    
    @objc private func contextOpenTerminal() {
        AppDelegate.openTerminalAndRunClaude()
    }
    
    public static func openTerminalAndRunClaude() {
        let script = """
        tell application "Terminal"
            reopen
            activate
            do script "export PATH=\\"$HOME/.npm-global/bin:$PATH\\"; claude"
        end tell
        """
        
        if let terminalUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: terminalUrl, configuration: config) { app, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    if #available(macOS 14.0, *) {
                        app?.activate()
                    } else {
                        app?.activate(options: .activateIgnoringOtherApps)
                    }
                    if let appleScript = NSAppleScript(source: script) {
                        var error: NSDictionary?
                        appleScript.executeAndReturnError(&error)
                    }
                }
            }
        } else {
            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
            }
        }
    }
    
    @objc private func contextOpenWeb() {
        if let url = URL(string: "https://claude.ai/settings/usage") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc private func contextQuit() {
        NSApplication.shared.terminate(nil)
    }
    
    // MARK: - Timer & Refresh
    
    private func startTimer() {
        refreshTimer?.invalidate()
        let interval = max(1, settings.refreshInterval) * 60
        refreshTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(interval), repeats: true) { [weak self] _ in
            self?.refreshData()
        }
    }
    
    private func refreshData() {
        viewModel.refresh { [weak self] in
            self?.updateButtonTitle()
        }
    }
    
    @objc private func handleSettingsChanged() {
        startTimer()
        updateButtonTitle()
    }
    
    private func updateButtonTitle() {
        guard let button = statusItem?.button else { return }
        
        if settings.showPercentage {
            let percent = viewModel.usage.fiveHourPercentInt
            button.title = " \(percent)%"
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            
            // Critical warning tooltip
            if percent >= 90 {
                button.toolTip = "Claude Code 额度已用 \(percent)% (临界预警)"
            } else {
                button.toolTip = "Claude Code 额度: \(percent)% | 点击查看详情"
            }
        } else {
            button.title = ""
            button.toolTip = "Claude Code 额度监控 | 点击查看详情"
        }
    }
    
    // MARK: - Icon Loading
    
    private func loadTrayIcon() -> NSImage? {
        let targetSize = NSSize(width: 18, height: 18)
        let icon = NSImage(size: targetSize)
        
        var repsAdded = false
        if let path1x = Bundle.main.path(forResource: "TrayIconTemplate", ofType: "png"),
           let rep1x = NSImageRep(contentsOfFile: path1x) {
            icon.addRepresentation(rep1x)
            repsAdded = true
        }
        
        if let path2x = Bundle.main.path(forResource: "TrayIconTemplate@2x", ofType: "png"),
           let rep2x = NSImageRep(contentsOfFile: path2x) {
            icon.addRepresentation(rep2x)
            repsAdded = true
        }
        
        if repsAdded {
            icon.size = targetSize
            icon.isTemplate = true
            return icon
        }
        
        // Direct file fallback
        let fallbackPath = "/Applications/Claude.app/Contents/Resources/TrayIconTemplate-Dark.png"
        if let img = NSImage(contentsOfFile: fallbackPath) {
            img.size = targetSize
            img.isTemplate = true
            return img
        }
        
        // Programmatic Spark fallback
        let img = NSImage(size: targetSize)
        img.lockFocus()
        let text = NSString(string: "✳")
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .bold),
            .foregroundColor: NSColor.black
        ]
        text.draw(at: NSPoint(x: 2, y: 0), withAttributes: attrs)
        img.unlockFocus()
        img.isTemplate = true
        return img
    }
}
