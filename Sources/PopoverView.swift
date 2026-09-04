import SwiftUI
import AppKit
import ImageIO

public struct PopoverView: View {
    @ObservedObject var viewModel: PopoverViewModel
    @ObservedObject var settings = SettingsManager.shared
    @State private var selectedPeriod: TimePeriod = .today
    @State private var showAllProjects = false

    public init(viewModel: PopoverViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                headerView

                if viewModel.usage.isOffline {
                    offlineBanner
                }

                if let advice = viewModel.usage.adviceText, !advice.isEmpty {
                    adviceBanner(text: advice)
                }

                Divider().opacity(0.6)

                usageCard(
                    title: "5 小时会话配额",
                    percent: viewModel.usage.fiveHourPercentInt,
                    countdown: viewModel.usage.fiveHourCountdown,
                    iconName: "clock.arrow.2.circlepath",
                    burnRate: viewModel.usage.fiveHourBurnRate,
                    burnDelta: viewModel.usage.fiveHourBurnDelta,
                    exhaustion: viewModel.usage.fiveHourExhaustion,
                    resetDate: viewModel.usage.fiveHourResetDate,
                    windowLabel: "2小时"
                )

                usageCard(
                    title: "7 天周度配额",
                    percent: viewModel.usage.sevenDayPercentInt,
                    countdown: viewModel.usage.sevenDayCountdown,
                    iconName: "calendar.badge.clock",
                    burnRate: viewModel.usage.sevenDayBurnRate,
                    burnDelta: viewModel.usage.sevenDayBurnDelta,
                    exhaustion: viewModel.usage.sevenDayExhaustion,
                    resetDate: viewModel.usage.sevenDayResetDate,
                    windowLabel: "24小时"
                )

                todayTokensCard

                extraUsageRow

                Divider().opacity(0.6)

                actionButtonsView

                footerView
            }
            .padding(14)
        }
        .frame(width: 340)
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack(spacing: 10) {
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
                    if let tighter = viewModel.usage.tighterWindow {
                        Text("\(tighter.rawValue)更紧")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(tighter == .fiveHour ? Color.orange.opacity(0.15) : Color.red.opacity(0.12))
                            .foregroundColor(tighter == .fiveHour ? Color.orange : Color.red)
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
                    .foregroundColor(.orange)
                    .help(viewModel.usage.errorMessage ?? "离线缓存模式")
            }
        }
    }

    private var offlineBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundColor(.orange)
            Text(viewModel.usage.errorMessage ?? "离线缓存模式")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.10))
        .cornerRadius(6)
    }

    private func adviceBanner(text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 10))
                .foregroundColor(Color(red: 0.85, green: 0.42, blue: 0.26))
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.primary.opacity(0.85))
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(red: 0.85, green: 0.42, blue: 0.26).opacity(0.08))
        .cornerRadius(6)
    }

    private func usageCard(title: String, percent: Int, countdown: String, iconName: String, burnRate: Double?, burnDelta: Double?, exhaustion: Date?, resetDate: Date?, windowLabel: String) -> some View {
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

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 7)
                    Capsule()
                        .fill(LinearGradient(colors: gradientForPercent(percent), startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(7, min(geo.size.width, geo.size.width * CGFloat(percent) / 100.0)), height: 7)
                }
            }
            .frame(height: 7)

            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text(countdown)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
            }

            if let line = burnLine(rate: burnRate, delta: burnDelta, exhaustion: exhaustion, resetDate: resetDate, windowLabel: windowLabel) {
                HStack(spacing: 4) {
                    Image(systemName: line.icon)
                        .font(.system(size: 9))
                        .foregroundColor(line.color)
                    Text(line.text)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(line.color)
                    Spacer()
                }
                .padding(.top, 1)
            }
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 1))
    }

    private struct BurnLine {
        let text: String
        let color: Color
        let icon: String
    }

    private func burnLine(rate: Double?, delta: Double?, exhaustion: Date?, resetDate: Date?, windowLabel: String) -> BurnLine? {
        if let d = delta, d < -0.5 {
            return BurnLine(text: "用量回落 \(String(format: "%.1f%%", d))", color: Color.green, icon: "arrow.down.right")
        }
        guard let r = rate else { return nil }
        if r == 0 {
            return BurnLine(text: "用量平稳 · 重置前够用", color: .secondary, icon: "equal.circle")
        }
        let deltaStr = delta != nil ? String(format: "%+.1f%%", delta!) : String(format: "%.1f%%/h", r)
        let rateStr = String(format: "%.1f%%/h", r)
        let now = Date()
        if let ex = exhaustion, let reset = resetDate {
            if ex < reset {
                let remain = ex.timeIntervalSince(now)
                let hrs = Int(remain / 3600)
                let mins = Int((remain.truncatingRemainder(dividingBy: 3600)) / 60)
                let dur: String
                if hrs > 0 { dur = "\(hrs)小时\(max(0, mins))分后耗尽" }
                else if mins > 0 { dur = "\(mins)分后耗尽" }
                else { dur = "即将耗尽" }
                return BurnLine(text: "过去\(windowLabel) \(deltaStr) · \(rateStr) → \(dur)", color: Color.orange, icon: "flame.fill")
            } else {
                return BurnLine(text: "过去\(windowLabel) \(deltaStr) · \(rateStr) · 重置前够用", color: .secondary, icon: "checkmark.circle")
            }
        }
        return BurnLine(text: "过去\(windowLabel) \(deltaStr) · \(rateStr)", color: .secondary, icon: "chart.line.uptrend.xyaxis")
    }

    private var todayTokensCard: some View {
        let currentStats = viewModel.usage.statsByPeriod[selectedPeriod] ?? viewModel.usage.todayStats

        return VStack(spacing: 7) {
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Color(red: 0.85, green: 0.42, blue: 0.26))
                    Text("Token 消耗")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(TimePeriod.allCases) { period in
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedPeriod = period
                                }
                            }) {
                                Text(period.rawValue)
                                    .font(.system(size: 9.5, weight: selectedPeriod == period ? .semibold : .regular))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(selectedPeriod == period ? Color(red: 0.85, green: 0.42, blue: 0.26).opacity(0.18) : Color.clear)
                                    .foregroundColor(selectedPeriod == period ? Color(red: 0.85, green: 0.42, blue: 0.26) : .secondary)
                                    .cornerRadius(4)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(2)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(5)
                }
                .frame(maxWidth: 168)

                Spacer()

                Text(currentStats.totalFormatted)
                    .font(.system(size: 13, weight: currentStats.totalTokens > 0 ? .bold : .medium, design: .rounded))
                    .foregroundColor(currentStats.totalTokens > 0 ? .primary : .secondary)
            }

            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    metricItem(label: "生成输出", value: currentStats.outputFormatted, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    metricItem(label: "用户输入", value: currentStats.userInputFormatted, alignment: .center)
                        .frame(maxWidth: .infinity, alignment: .center)
                    metricItem(label: "缓存读取", value: currentStats.cacheReadFormatted, alignment: .trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                HStack(spacing: 0) {
                    metricItem(label: "缓存命中", value: "\(currentStats.cacheEfficiencyPercent)%", alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    metricItem(label: "交互轮次", value: "\(currentStats.userPromptsCount)轮", alignment: .center)
                        .frame(maxWidth: .infinity, alignment: .center)
                    metricItem(label: "模型调用", value: "\(currentStats.modelCallsCount)次", alignment: .trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(.top, 2)

            if !currentStats.topProjectsSummary.isEmpty {
                let projects = currentStats.topProjectsSummary
                let visible = showAllProjects ? projects : Array(projects.prefix(3))
                let hasMore = projects.count > 3
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("项目排行")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        if hasMore {
                            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showAllProjects.toggle() } }) {
                                HStack(spacing: 2) {
                                    Text(showAllProjects ? "收起" : "全部 \(projects.count)个")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(Color(red: 0.85, green: 0.42, blue: 0.26))
                                    Image(systemName: showAllProjects ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 7, weight: .semibold))
                                        .foregroundColor(Color(red: 0.85, green: 0.42, blue: 0.26))
                                }
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color(red: 0.85, green: 0.42, blue: 0.26).opacity(0.10))
                                .cornerRadius(4)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        Spacer()
                    }
                    if showAllProjects {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(visible.chunked(into: 2).enumerated()), id: \.offset) { row in
                                HStack(spacing: 4) {
                                    ForEach(row.element, id: \.name) { proj in
                                        projectPill(proj: proj)
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(visible, id: \.name) { proj in
                                    projectPill(proj: proj)
                                }
                            }
                        }
                    }
                }
                .padding(.top, 2)
                .onChange(of: selectedPeriod) { _ in showAllProjects = false }
            }

            if !currentStats.topModelsSummary.isEmpty {
                HStack(spacing: 6) {
                    ForEach(currentStats.topModelsSummary, id: \.name) { model in
                        HStack(spacing: 3) {
                            Text(model.name)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(model.formatted)
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(4)
                    }
                    Spacer()
                }
                .padding(.top, 1)
            }
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 1))
    }

    private func metricItem(label: String, value: String, alignment: HorizontalAlignment = .leading) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
        }
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
            Button(action: { viewModel.refresh() }) {
                Label("刷新", systemImage: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(CompactButtonStyle())
            .disabled(viewModel.isLoading)

            Button(action: {
                NotificationCenter.default.post(name: .closePopover, object: nil)
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
                NotificationCenter.default.post(name: .closePopover, object: nil)
                AppDelegate.openTerminalAndRunClaude()
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
                Toggle("启用额度预警通知", isOn: $settings.enableQuotaNotification)
                Menu("预警阈值") {
                    Stepper("5小时提醒 \(settings.threshold5hWarning)%", value: $settings.threshold5hWarning, in: 10...89)
                    Stepper("5小时紧急 \(settings.threshold5hCritical)%", value: $settings.threshold5hCritical, in: 50...99)
                    Stepper("7天提醒 \(settings.threshold7dWarning)%", value: $settings.threshold7dWarning, in: 10...99)
                }
                Toggle("重置时通知", isOn: $settings.notifyOnReset)
                if NotchIslandController.isSupported {
                    Toggle("在刘海显示配额", isOn: $settings.showNotchIsland)
                }
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
                Button("退出 ClaudeBar") { NSApplication.shared.terminate(nil) }
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
        if percent >= 90 { return Color.red }
        else if percent >= 75 { return Color.orange }
        else { return Color(red: 0.85, green: 0.42, blue: 0.26) }
    }

    private func gradientForPercent(_ percent: Int) -> [Color] {
        if percent >= 90 { return [Color.orange, Color.red] }
        else if percent >= 75 { return [Color.yellow, Color.orange] }
        else { return [Color(red: 0.92, green: 0.58, blue: 0.45), Color(red: 0.85, green: 0.42, blue: 0.26)] }
    }

    private func loadClaudeAppIcon() -> NSImage? { PopoverView.claudeAppIcon }

    private static let claudeAppIcon: NSImage? = {
        var sources: [URL] = []
        if let bundled = Bundle.main.url(forResource: "ClaudeAppIcon", withExtension: "png") {
            sources.append(bundled)
        }
        sources.append(URL(fileURLWithPath: "/Applications/Claude.app/Contents/Resources/ion-dist/images/claude_app_icon.png"))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 128
        ]
        for url in sources {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            else { continue }
            return NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
        }
        return nil
    }()

    private func projectPill(proj: (name: String, formatted: String, percent: Int)) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "folder.fill")
                .font(.system(size: 7))
                .foregroundColor(Color(red: 0.85, green: 0.42, blue: 0.26))
            Text(proj.name)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
            Text(proj.formatted)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundColor(Color(red: 0.85, green: 0.42, blue: 0.26))
            Text("(\(proj.percent)%)")
                .font(.system(size: 8))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(4)
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

struct CompactButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(configuration.isPressed ? Color.primary.opacity(0.12) : Color.primary.opacity(0.06)))
            .foregroundColor(.primary)
    }
}

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

public final class PopoverViewModel: ObservableObject {
    @Published public var usage: FormattedUsage = FormattedUsage()
    @Published public var isLoading: Bool = false
    public init() {}
    public func refresh(force: Bool = false, completion: (() -> Void)? = nil) {
        guard !isLoading || force else { return }
        isLoading = true
        ClaudeUsageService.shared.fetchUsage(force: force) { [weak self] newUsage in
            self?.usage = newUsage
            self?.isLoading = false
            completion?()
        }
    }
}
