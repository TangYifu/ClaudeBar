import AppKit
import SwiftUI

// MARK: - Notch Geometry

/// Position and size of the built-in display's notch.
///
/// macOS exposes no API for placing content *in* the notch; it only reports the
/// two usable strips beside it. The gap between them is the notch itself, which
/// is what this derives so a window can be pinned around it.
struct NotchGeometry {
    let screen: NSScreen
    /// The notch cutout, in global screen coordinates.
    let notch: CGRect

    static let expandedSize = CGSize(width: 320, height: 128)
    /// How far the collapsed island hangs below the cutout. The cutout itself
    /// can never show anything, so this strip carries the whole collapsed state.
    static let collapsedOverhang: CGFloat = 6

    static func detect() -> NotchGeometry? {
        for screen in NSScreen.screens {
            guard let left = screen.auxiliaryTopLeftArea,
                  let right = screen.auxiliaryTopRightArea,
                  right.minX > left.maxX else { continue }

            let width = right.minX - left.maxX
            let height = left.height
            // The cutout is centred on the display, so x is derived from the
            // screen frame rather than from the auxiliary rects — that keeps it
            // correct whichever coordinate space those rects are reported in.
            let notch = CGRect(x: screen.frame.midX - width / 2,
                               y: screen.frame.maxY - height,
                               width: width,
                               height: height)
            return NotchGeometry(screen: screen, notch: notch)
        }
        return nil
    }

    var collapsedSize: CGSize {
        CGSize(width: notch.width, height: notch.height + Self.collapsedOverhang)
    }

    /// The window is always this size. Expanding and collapsing move only the
    /// content inside it — resizing the window itself makes the animation stutter,
    /// because every frame costs a synchronous window-server resize plus a full
    /// SwiftUI relayout at the intermediate size.
    var windowFrame: CGRect {
        CGRect(x: screen.frame.midX - Self.expandedSize.width / 2,
               y: screen.frame.maxY - Self.expandedSize.height,
               width: Self.expandedSize.width,
               height: Self.expandedSize.height)
    }

    /// Pointer region that opens the island while it is collapsed.
    var hotZone: CGRect {
        CGRect(x: notch.minX,
               y: notch.minY - Self.collapsedOverhang,
               width: notch.width,
               height: notch.height + Self.collapsedOverhang)
    }
}

// MARK: - Shape

/// Rounded along the bottom only. The island's top edge sits flush against the
/// physical top of the display, so rounding it would carve a visible notch of
/// desktop out of each top corner.
struct BottomRoundedRectangle: Shape {
    var radius: CGFloat

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = max(0, min(radius, min(rect.width, rect.height) / 2))
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
                    radius: r,
                    startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
                    radius: r,
                    startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.closeSubpath()
        return path
    }
}

// MARK: - View State

final class NotchState: ObservableObject {
    @Published var expanded = false
}

// MARK: - Island Content

struct NotchIslandView: View {
    @ObservedObject var viewModel: PopoverViewModel
    @ObservedObject var state: NotchState
    let collapsedSize: CGSize

    private var usage: FormattedUsage { viewModel.usage }

    private var severityColor: Color {
        switch usage.severity {
        case .critical: return Color(red: 0.91, green: 0.30, blue: 0.24)
        case .warning: return Color(red: 0.95, green: 0.61, blue: 0.07)
        case .normal: return Color(red: 0.85, green: 0.47, blue: 0.34)
        }
    }

    private var size: CGSize { state.expanded ? NotchGeometry.expandedSize : collapsedSize }

    var body: some View {
        VStack(spacing: 0) {
            // The black rect alone decides the size. Both contents ride as
            // overlays, which do not feed back into that size — as ZStack children
            // the fixed-size detail would stretch the container to 320x128 and push
            // the collapsed hairline outside the visible strip.
            Color.black
                .frame(width: size.width, height: size.height)
                .overlay(detail.opacity(state.expanded ? 1 : 0), alignment: .top)
                .overlay(hairline.opacity(state.expanded ? 0 : 1), alignment: .bottom)
                // One shape that grows, rather than two views swapping places: Core
                // Animation interpolates it on the GPU without any relayout, and the
                // clip turns the growth into a reveal.
                .clipShape(BottomRoundedRectangle(radius: state.expanded ? 18 : 8))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Without this SwiftUI insets the content to dodge the notch, pushing the
        // island down and leaving a strip of desktop above it.
        .ignoresSafeArea()
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: state.expanded)
    }

    /// Collapsed: a single hairline just below the cutout, filled to the 5-hour window.
    private var hairline: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14))
                Capsule()
                    .fill(severityColor)
                    .frame(width: max(3, geo.size.width * CGFloat(usage.fiveHourUtilization) / 100))
            }
        }
        .frame(height: 3)
        .padding(.horizontal, 12)
        .padding(.bottom, 2)
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 9) {
            Spacer(minLength: 30)   // clear the physical cutout
            row("5 小时", percent: usage.fiveHourPercentInt, countdown: usage.fiveHourCountdown)
            row("7 天", percent: usage.sevenDayPercentInt, countdown: usage.sevenDayCountdown)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 13)
        // Pinned to the expanded size and clipped by the parent, so the text
        // never reflows while the container grows.
        .frame(width: NotchGeometry.expandedSize.width,
               height: NotchGeometry.expandedSize.height,
               alignment: .top)
    }

    private func row(_ title: String, percent: Int, countdown: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.65))
                Spacer()
                Text("\(percent)%")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                Text(countdown)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.45))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.14))
                    Capsule()
                        .fill(severityColor)
                        .frame(width: max(2, geo.size.width * CGFloat(percent) / 100))
                }
            }
            .frame(height: 3)
        }
    }
}

// MARK: - Window Controller

/// Owns the floating window pinned around the notch. Created only while the
/// feature is switched on, so a user who leaves it off pays nothing for it.
final class NotchIslandController {
    private var panel: NSPanel?
    private var monitors: [Any] = []
    private let viewModel: PopoverViewModel
    private let state = NotchState()

    /// Whether this Mac has a notch at all — external displays and pre-2021
    /// machines do not, and the setting is meaningless there.
    static var isSupported: Bool { NotchGeometry.detect() != nil }

    init(viewModel: PopoverViewModel) {
        self.viewModel = viewModel
    }

    var isVisible: Bool { panel != nil }

    func show() {
        guard panel == nil, let geometry = NotchGeometry.detect() else { return }

        let panel = NSPanel(
            contentRect: geometry.windowFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        // Above .mainMenu so the island is not clipped by the menu bar it sits in.
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // Collapsed, the window is mostly empty space sitting over the menu bar,
        // so it must not swallow clicks meant for what is underneath.
        panel.ignoresMouseEvents = true

        let hosting = NSHostingView(rootView: NotchIslandView(
            viewModel: viewModel,
            state: state,
            collapsedSize: geometry.collapsedSize
        ))
        hosting.frame = CGRect(origin: .zero, size: geometry.windowFrame.size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        panel.orderFrontRegardless()
        self.panel = panel

        installMonitors(geometry: geometry)
    }

    func hide() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        panel?.orderOut(nil)
        panel = nil
        state.expanded = false
    }

    /// Proximity is read from the pointer's screen position rather than from a
    /// tracking area, because the window ignores mouse events while collapsed and
    /// would therefore never receive enter/exit of its own.
    private func installMonitors(geometry: NotchGeometry) {
        let handler: (NSEvent?) -> Void = { [weak self] _ in
            self?.updateExpansion(geometry: geometry)
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { handler($0) }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { event in
            handler(event)
            return event
        }) {
            monitors.append(local)
        }
    }

    private func updateExpansion(geometry: NotchGeometry) {
        let point = NSEvent.mouseLocation
        // Collapsing uses the whole window so the pointer can travel down into
        // the opened panel without it snapping shut on the way.
        let shouldExpand = state.expanded
            ? geometry.windowFrame.insetBy(dx: -4, dy: -4).contains(point)
            : geometry.hotZone.contains(point)

        guard shouldExpand != state.expanded else { return }
        state.expanded = shouldExpand
        panel?.ignoresMouseEvents = !shouldExpand
    }
}
