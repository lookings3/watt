import AppKit

/// Battery icon in the macOS style, with the level cut out of the battery.
/// A template image normally. In Low Power Mode the fill is yellow and the level is drawn in black.
func batteryIcon(percent: Int, charging: Bool, plugged: Bool = false, lowPower: Bool, dark: Bool) -> NSImage {
    let level = min(max(percent, 0), 100)
    let foreground: NSColor = (lowPower && dark) ? .white : .black
    let image = NSImage(size: NSSize(width: 25, height: 14), flipped: false) { _ in
        guard let context = NSGraphicsContext.current?.cgContext else { return false }
        // Sized to match the macOS battery icon.
        let body = NSRect(x: 0, y: 1, width: 22, height: 12)
        let shape = NSBezierPath(roundedRect: body, xRadius: 3.5, yRadius: 3.5)

        foreground.withAlphaComponent(0.4).setFill()
        shape.fill()
        NSBezierPath(roundedRect: NSRect(x: 23, y: 4.75, width: 1.5, height: 4.5), xRadius: 0.75, yRadius: 0.75).fill()

        // Clips the fill to the battery shape so the corners match.
        context.saveGState()
        shape.addClip()
        (lowPower ? NSColor(srgbRed: 0.976, green: 0.835, blue: 0.337, alpha: 1) : foreground).setFill()
        NSRect(x: body.minX, y: body.minY, width: body.width * CGFloat(level) / 100, height: body.height).fill()
        context.restoreGState()

        // With a bolt or plug, the number and symbol both shrink so they fit without crowding.
        let hasSymbol = charging || plugged
        let fontSize: CGFloat = level == 100 ? (hasSymbol ? 7 : 8) : (hasSymbol ? 8.5 : 10)
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: lowPower ? .regular : .semibold)
        let text = NSAttributedString(string: "\(level)", attributes: [.font: font, .foregroundColor: NSColor.black])
        let textSize = text.size()
        let symbol = charging ? "bolt.fill" : plugged ? "powerplug.fill" : nil
        let bolt = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }?
            .withSymbolConfiguration(.init(pointSize: charging ? 6 : 5, weight: .bold))
        let boltWidth = bolt.map { $0.size.width + 0.5 } ?? 0
        let startX = body.midX - (textSize.width + boltWidth) / 2

        let textPoint = NSPoint(x: startX, y: body.midY - textSize.height / 2)
        let boltRect = bolt.map { NSRect(x: startX + textSize.width + 0.5, y: body.midY - $0.size.height / 2,
                                         width: $0.size.width, height: $0.size.height) }
        if lowPower {
            // A cut-out would show a light menu bar through the yellow fill, so the number is drawn in black.
            text.draw(at: textPoint)
            if let bolt, let boltRect {
                (bolt.withSymbolConfiguration(.init(paletteColors: [.black])) ?? bolt).draw(in: boltRect)
            }
        } else {
            // Cuts out the number and symbol so the menu bar shows through.
            context.saveGState()
            context.setBlendMode(.destinationOut)
            text.draw(at: textPoint)
            if let bolt, let boltRect { bolt.draw(in: boltRect, from: .zero, operation: .destinationOut, fraction: 1) }
            context.restoreGState()
        }
        return true
    }
    image.isTemplate = !lowPower
    return image
}
