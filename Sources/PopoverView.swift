import SwiftUI
import AppKit

public struct PopoverView: View {
    @ObservedObject var viewModel: PopoverViewModel
    @ObservedObject var settings = SettingsManager.shared
    
    public init(viewModel: PopoverViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(spacing: 14) {
            // MARK: - Header
            headerView
            
            Divider().opacity(0.6)
            
            // MARK: - 5-Hour Session Limit Card
            usageCard(
                title: "5 小时会话配额",
                percent: viewModel.usage.fiveHourPercentInt,
                countdown: viewModel.usage.fiveHourCountdown,
                iconName: "clock.arrow.2.circlepath",
                badgeText: "Session"
            )
            
            // MARK: - 7-Day Weekly Limit Card
            usageCard(
                title: "7 天周度配额",
                percent: viewModel.usage.sevenDayPercentInt,
                countdown: viewModel.usage.sevenDayCountdown,
                iconName: "calendar.badge.clock",
                badgeText: "Weekly"
            )
            
            // MARK: - Extra Usage Card (if applicable)
            extraUsageRow
            
            Divider().opacity(0.6)
            
            // MARK: - Quick Actions
            actionButtonsView
            
            // MARK: - Footer (Status & Settings)
            footerView
        }
        .padding(14)
        .frame(width: 320)
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        HStack(spacing: 10) {
            // App Icon
            if let image = loadClaudeAppIcon() {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .shadow(color: Color.black.opacity(0.15), radius: 2, x: 0, y: 1)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(red: 0.85, green: 0.42, blue: 0.26))
                        .frame(width: 32, height: 32)
                    Text("✳")
                        .foregroundColor(.white)
                        .font(.system(size: 18, weight: .bold))
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Claude Code")
                        .font(.system(size: 14, weight: .semibold))
                    
                    if !viewModel.usage.account.planSummary.isEmpty {
                        Text(viewModel.usage.account.planSummary)
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color(red: 0.85, green: 0.42, blue: 0.26).opacity(0.15))
                            .foregroundColor(Color(red: 0.85, green: 0.42, blue: 0.26))
                            .cornerRadius(4)
                    }
                }
                
                Text(viewModel.usage.account.email.isEmpty ? "本地用户" : viewModel.usage.account.email)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer()
            
            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 16, height: 16)
            } else if viewModel.usage.isOffline {
                Image(systemName: "wifi.slash")
                    .foregroundColor(.secondary)
                    .help(viewModel.usage.errorMessage ?? "离线缓存模式")
            }
        }
    }
    
    private func usageCard(title: String, percent: Int, countdown: String, iconName: String, badgeText: String) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(percent)%")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(colorForPercent(percent))
            }
            
            // Sleek Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 7)
                    
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: gradientForPercent(percent),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(7, min(geo.size.width, geo.size.width * CGFloat(percent) / 100.0)), height: 7)
                }
            }
            .frame(height: 7)
            
            // Countdown Row
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text(countdown)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
    
    private var extraUsageRow: some View {
        HStack {
            Image(systemName: "creditcard")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text("额外用量 (Extra Usage)")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            Spacer()
            
            if viewModel.usage.extraUsageEnabled {
                Text(viewModel.usage.extraSpendFormatted)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
            } else {
                Text("未开启")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(3)
            }
        }
        .padding(.horizontal, 4)
    }
    
    private var actionButtonsView: some View {
        HStack(spacing: 8) {
            Button(action: {
                viewModel.refresh()
            }) {
                Label("刷新", systemImage: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(CompactButtonStyle())
            .disabled(viewModel.isLoading)
            
            Button(action: {
                if let url = URL(string: "https://claude.ai/settings/usage") {
                    NSWorkspace.shared.open(url)
                }
            }) {
                Label("网页用量", systemImage: "globe")
                    .font(.system(size: 11, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(CompactButtonStyle())
            
            Button(action: {
                openClaudeInTerminal()
            }) {
                Label("终端启动", systemImage: "terminal")
                    .font(.system(size: 11, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(CompactButtonStyle())
        }
    }
    
    private var footerView: some View {
        HStack {
            Menu {
                Toggle("菜单栏显示百分比", isOn: $settings.showPercentage)
                
                if #available(macOS 13.0, *) {
                    Toggle("开机自动启动", isOn: $settings.launchAtLogin)
                }
                
                Picker("刷新频率", selection: $settings.refreshInterval) {
                    Text("每 1 分钟").tag(1)
                    Text("每 3 分钟").tag(3)
                    Text("每 5 分钟").tag(5)
                    Text("每 10 分钟").tag(10)
                }
                
                Divider()
                
                Button("退出 ClaudeBar") {
                    NSApplication.shared.terminate(nil)
                }
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            
            Spacer()
            
            Text(footerTimestampText)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.top, -4)
    }
    
    // MARK: - Helpers
    
    private var footerTimestampText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timeStr = formatter.string(from: viewModel.usage.lastUpdated)
        if viewModel.usage.isOffline {
            return "缓存数据 (更新于 \(timeStr))"
        }
        return "刚刚更新: \(timeStr)"
    }
    
    private func colorForPercent(_ percent: Int) -> Color {
        if percent >= 90 {
            return Color.red
        } else if percent >= 75 {
            return Color.orange
        } else {
            return Color(red: 0.85, green: 0.42, blue: 0.26) // Claude terracotta
        }
    }
    
    private func gradientForPercent(_ percent: Int) -> [Color] {
        if percent >= 90 {
            return [Color.orange, Color.red]
        } else if percent >= 75 {
            return [Color.yellow, Color.orange]
        } else {
            return [Color(red: 0.92, green: 0.58, blue: 0.45), Color(red: 0.85, green: 0.42, blue: 0.26)]
        }
    }
    
    private func loadClaudeAppIcon() -> NSImage? {
        if let bundleImage = NSImage(named: "ClaudeAppIcon") {
            return bundleImage
        }
        if let resourcePath = Bundle.main.path(forResource: "ClaudeAppIcon", ofType: "png"),
           let img = NSImage(contentsOfFile: resourcePath) {
            return img
        }
        let fallbackPath = "/Applications/Claude.app/Contents/Resources/ion-dist/images/claude_app_icon.png"
        return NSImage(contentsOfFile: fallbackPath)
    }
    
    private func openClaudeInTerminal() {
        let script = "tell application \"Terminal\" to do script \"claude\" activate"
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }
}

// MARK: - Compact Button Style

struct CompactButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(configuration.isPressed ? Color.primary.opacity(0.12) : Color.primary.opacity(0.06))
            )
            .foregroundColor(.primary)
    }
}

// MARK: - Visual Effect View (Frosted Glass)

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - ViewModel

public final class PopoverViewModel: ObservableObject {
    @Published public var usage: FormattedUsage = FormattedUsage()
    @Published public var isLoading: Bool = false
    
    public init() {}
    
    public func refresh(completion: (() -> Void)? = nil) {
        isLoading = true
        ClaudeUsageService.shared.fetchUsage { [weak self] newUsage in
            self?.usage = newUsage
            self?.isLoading = false
            completion?()
        }
    }
}
