// Draws the Sysbar app icon and writes it as a 1024 x 1024 PNG.
// Usage: swift scripts/make-icon.swift <output.png>
// scripts/make-icon.sh turns that PNG into Resources/AppIcon.icns.
import AppKit

let canvas: CGFloat = 1024
/// Apple's macOS icon grid: the rounded body is 824 pt on a 1024 pt canvas.
let body: CGFloat = 824
let cornerRadius: CGFloat = 185

/// The same muted load colours the app uses, lifted slightly for a dark background.
let barColors = [
    NSColor(srgbRed: 0.42, green: 0.67, blue: 0.51, alpha: 1),
    NSColor(srgbRed: 0.83, green: 0.69, blue: 0.38, alpha: 1),
    NSColor(srgbRed: 0.82, green: 0.45, blue: 0.43, alpha: 1),
]
/// How full each bar is, like a live reading in the menu bar.
let barLevels: [CGFloat] = [0.46, 0.78, 0.60]

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output.png>\n".utf8))
    exit(2)
}

let image = NSImage(size: NSSize(width: canvas, height: canvas), flipped: false) { _ in
    let inset = (canvas - body) / 2
    let bodyRect = NSRect(x: inset, y: inset, width: body, height: body)
    let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: cornerRadius, yRadius: cornerRadius)

    // Soft drop shadow under the body, as on other macOS icons.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSColor(srgbRed: 0.13, green: 0.14, blue: 0.16, alpha: 1).setFill()
    bodyPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Graphite body with a gentle top-to-bottom gradient and a hairline highlight.
    NSGradient(
        starting: NSColor(srgbRed: 0.20, green: 0.22, blue: 0.25, alpha: 1),
        ending: NSColor(srgbRed: 0.11, green: 0.12, blue: 0.14, alpha: 1)
    )?.draw(in: bodyPath, angle: -90)
    NSColor.white.withAlphaComponent(0.08).setStroke()
    let highlight = NSBezierPath(roundedRect: bodyRect.insetBy(dx: 2, dy: 2), xRadius: cornerRadius - 2, yRadius: cornerRadius - 2)
    highlight.lineWidth = 4
    highlight.stroke()

    // Three vertical level bars: a faint track and a coloured fill from the bottom.
    let barWidth: CGFloat = 104
    let gap: CGFloat = 76
    let trackHeight: CGFloat = 470
    let totalWidth = barWidth * 3 + gap * 2
    let originX = (canvas - totalWidth) / 2
    let originY = (canvas - trackHeight) / 2
    let radius = barWidth / 2

    for index in 0..<3 {
        let x = originX + CGFloat(index) * (barWidth + gap)
        let track = NSRect(x: x, y: originY, width: barWidth, height: trackHeight)
        NSColor.white.withAlphaComponent(0.10).setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()

        let fill = NSRect(x: x, y: originY, width: barWidth, height: trackHeight * barLevels[index])
        barColors[index].setFill()
        NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius).fill()
    }
    return true
}

guard
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let png = bitmap.representation(using: .png, properties: [:])
else {
    FileHandle.standardError.write(Data("could not encode the icon\n".utf8))
    exit(1)
}
do {
    try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
} catch {
    FileHandle.standardError.write(Data("could not write the icon: \(error.localizedDescription)\n".utf8))
    exit(1)
}
