import AppKit

/// Resolved from this file's own location so the script works from any checkout.
/// It previously carried an absolute path into one developer's home directory,
/// which had already gone stale when the repository moved.
let resourcesDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Resources", isDirectory: true)


// Render Claude Code app icon following macOS squircle design guidelines
func generateAppIcon(outputPath: String) {
    let canvasSize: CGFloat = 1024
    let tileSize: CGFloat = 824
    let origin: CGFloat = (canvasSize - tileSize) / 2.0 // 100
    let cornerRadius: CGFloat = 185.0
    
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvasSize),
        pixelsHigh: Int(canvasSize),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    let cgContext = context.cgContext
    
    // 1. Shadow for macOS Squircle
    cgContext.saveGState()
    let shadowColor = NSColor.black.withAlphaComponent(0.28).cgColor
    cgContext.setShadow(offset: CGSize(width: 0, height: -18), blur: 32, color: shadowColor)
    
    let tileRect = NSRect(x: origin, y: origin, width: tileSize, height: tileSize)
    let tilePath = NSBezierPath(roundedRect: tileRect, xRadius: cornerRadius, yRadius: cornerRadius)
    
    // Fill base
    NSColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1.0).setFill()
    tilePath.fill()
    cgContext.restoreGState()
    
    // 2. Tile Gradient Background (Sleek dark developer terminal surface)
    cgContext.saveGState()
    tilePath.addClip()
    
    let gradient = NSGradient(
        starting: NSColor(red: 0.16, green: 0.15, blue: 0.14, alpha: 1.0), // Deep Charcoal
        ending: NSColor(red: 0.10, green: 0.09, blue: 0.09, alpha: 1.0)
    )!
    gradient.draw(in: tileRect, angle: -90)
    
    // Subtle top inner highlight
    let highlightRect = NSRect(x: origin, y: origin + tileSize - 3, width: tileSize, height: 3)
    NSColor.white.withAlphaComponent(0.12).setFill()
    highlightRect.fill()
    
    // 3. Draw Claude Code Pixel Mascot in Center
    let svgPath = resourcesDirectory.appendingPathComponent("claudecode-color.svg").path
    if let svgContent = try? String(contentsOfFile: svgPath) {
        let modifiedSvg = svgContent
            .replacingOccurrences(of: "width=\"1em\"", with: "width=\"1024\"")
            .replacingOccurrences(of: "height=\"1em\"", with: "height=\"1024\"")
        
        if let svgData = modifiedSvg.data(using: .utf8),
           let svgImage = NSImage(data: svgData) {
            
            let mascotWidth: CGFloat = 520
            let mascotHeight: CGFloat = 520 * (20.0 / 24.0) // aspect ratio of SVG viewBox
            let mascotX = (canvasSize - mascotWidth) / 2.0
            let mascotY = (canvasSize - mascotHeight) / 2.0 - 10
            
            // Soft glow behind mascot
            cgContext.saveGState()
            let glowColor = NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 0.25).cgColor
            cgContext.setShadow(offset: CGSize(width: 0, height: 4), blur: 24, color: glowColor)
            svgImage.draw(in: NSRect(x: mascotX, y: mascotY, width: mascotWidth, height: mascotHeight))
            cgContext.restoreGState()
            
            svgImage.draw(in: NSRect(x: mascotX, y: mascotY, width: mascotWidth, height: mascotHeight))
        }
    }
    
    // 4. Subtle squircle border
    NSColor.white.withAlphaComponent(0.08).setStroke()
    tilePath.lineWidth = 2.0
    tilePath.stroke()
    
    cgContext.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    
    if let pngData = rep.representation(using: .png, properties: [:]) {
        try? pngData.write(to: URL(fileURLWithPath: outputPath))
        print("Generated master 1024x1024 app icon at: \(outputPath)")
    }
}

generateAppIcon(outputPath: resourcesDirectory.appendingPathComponent("ClaudeAppIcon.png").path)
