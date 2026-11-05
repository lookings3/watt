import AppKit

/// Battery icon in the macOS style, with the level cut out of the battery.
/// A template image normally, with a yellow fill in Low Power Mode.
func batteryIcon(percent: Int, charging: Bool, plugged: Bool = false, lowPower: Bool, dark: Bool) -> NSImage {
    let level = min(max(percent, 0), 100)
    let foreground: NSColor = (lowPower && dark) ? .white : .black
    let image = NSImage(size: NSSize(width: 31, height: 14), flipped: false) { _ in
        guard let context = NSGraphicsContext.current?.cgContext else { return false }
        let body = NSRect(x: 0, y: 0.5, width: 27.5, height: 13)
        let shape = NSBezierPath(roundedRect: body, xRadius: 4, yRadius: 4)

        foreground.withAlphaComponent(0.4).setFill()
        shape.fill()
        NSBezierPath(roundedRect: NSRect(x: 28.5, y: 4.5, width: 1.75, height: 5), xRadius: 0.9, yRadius: 0.9).fill()

        // Clips the fill to the battery shape so the corners match.
        context.saveGState()
        shape.addClip()
        (lowPower ? NSColor.systemYellow : foreground).setFill()
        NSRect(x: body.minX, y: body.minY, width: body.width * CGFloat(level) / 100, height: body.height).fill()
        context.restoreGState()

        let font = NSFont.monospacedDigitSystemFont(ofSize: level == 100 ? 9.5 : 10.5, weight: .bold)
        let text = NSAttributedString(string: "\(level)", attributes: [.font: font, .foregroundColor: NSColor.black])
        let textSize = text.size()
        let symbol = charging ? "bolt.fill" : plugged ? "powerplug.fill" : nil
        let bolt = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }?
            .withSymbolConfiguration(.init(pointSize: charging ? 8.5 : 6.5, weight: .bold))
        let boltWidth = bolt.map { $0.size.width + 0.5 } ?? 0
        let startX = body.midX - (textSize.width + boltWidth) / 2

        // Cuts out the number and symbol so the menu bar shows through.
        context.saveGState()
        context.setBlendMode(.destinationOut)
        text.draw(at: NSPoint(x: startX, y: body.midY - textSize.height / 2))
        if let bolt {
            let rect = NSRect(x: startX + textSize.width + 0.5, y: body.midY - bolt.size.height / 2,
                              width: bolt.size.width, height: bolt.size.height)
            bolt.draw(in: rect, from: .zero, operation: .destinationOut, fraction: 1)
        }
        context.restoreGState()
        return true
    }
    image.isTemplate = !lowPower
    return image
}
