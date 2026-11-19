import AppKit

/// Battery icon in the macOS style, with the level cut out of the battery.
/// A template image normally. In Low Power Mode the fill is yellow and the level is drawn in black.
func batteryIcon(percent: Int, charging: Bool, plugged: Bool = false, lowPower: Bool, dark: Bool) -> NSImage {
    let level = min(max(percent, 0), 100)
    let foreground: NSColor = (lowPower && dark) ? .white : .black
    let image = NSImage(size: NSSize(width: 26, height: 14), flipped: false) { _ in
        guard let context = NSGraphicsContext.current?.cgContext else { return false }
        // Sized to match the macOS battery icon.
        let body = NSRect(x: 0, y: 1, width: 23, height: 12) // 46x24 px, measured from the macOS icon
        let shape = NSBezierPath(roundedRect: body, xRadius: 4.5, yRadius: 4.5)

        foreground.withAlphaComponent(0.4).setFill()
        shape.fill()
        // The tip, measured from the macOS icon: 1pt from the body, 1.5 x 4pt, nearly flat on the left
        // with slightly rounded corners there and rounder corners on the right, a little darker than the track.
        foreground.withAlphaComponent(0.55).setFill()
        let tipRect = NSRect(x: body.maxX + 1, y: body.midY - 2, width: 1.5, height: 4)
        let left: CGFloat = 0.6, right: CGFloat = 0.75
        let tip = NSBezierPath()
        tip.move(to: NSPoint(x: tipRect.minX + left, y: tipRect.minY))
        tip.line(to: NSPoint(x: tipRect.maxX - right, y: tipRect.minY))
        tip.appendArc(withCenter: NSPoint(x: tipRect.maxX - right, y: tipRect.minY + right), radius: right, startAngle: 270, endAngle: 360)
        tip.line(to: NSPoint(x: tipRect.maxX, y: tipRect.maxY - right))
        tip.appendArc(withCenter: NSPoint(x: tipRect.maxX - right, y: tipRect.maxY - right), radius: right, startAngle: 0, endAngle: 90)
        tip.line(to: NSPoint(x: tipRect.minX + left, y: tipRect.maxY))
        tip.appendArc(withCenter: NSPoint(x: tipRect.minX + left, y: tipRect.maxY - left), radius: left, startAngle: 90, endAngle: 180)
        tip.line(to: NSPoint(x: tipRect.minX, y: tipRect.minY + left))
        tip.appendArc(withCenter: NSPoint(x: tipRect.minX + left, y: tipRect.minY + left), radius: left, startAngle: 180, endAngle: 270)
        tip.close()
        tip.fill()

        // Clips the fill to the battery shape so the corners match.
        context.saveGState()
        shape.addClip()
        (lowPower ? NSColor(srgbRed: 0.976, green: 0.835, blue: 0.337, alpha: 1) : foreground).setFill()
        NSRect(x: body.minX, y: body.minY, width: body.width * CGFloat(level) / 100, height: body.height).fill()
        context.restoreGState()

        // 9.75pt medium digits, measured against the macOS battery icon on a real menu bar. The bolt or plug is about as tall as the digits.
        // Layout uses the visible ink, not advance widths or symbol padding, so it fits the way the macOS icon does.
        let symbol = charging ? "bolt.fill" : plugged ? "powerplug.fill" : nil
        func content(_ size: CGFloat) -> (NSAttributedString, NSImage?) {
            let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: lowPower ? .regular : .medium)
            let text = NSAttributedString(string: "\(level)", attributes: [.font: font, .foregroundColor: NSColor.black])
            let mark = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }?
                .withSymbolConfiguration(.init(pointSize: size * (charging ? 0.7 : 0.6), weight: .medium))
            return (text, mark)
        }
        func inkRect(_ text: NSAttributedString) -> NSRect {
            text.boundingRect(with: NSSize(width: 200, height: 50), options: [.usesDeviceMetrics]) // relative to the baseline
        }
        func symbolInk(_ image: NSImage?) -> NSRect {
            guard let image else { return .zero }
            return visibleBounds(of: image)
        }
        let gap: CGFloat = 1
        func width(_ c: (NSAttributedString, NSImage?)) -> CGFloat {
            inkRect(c.0).width + (c.1 == nil ? 0 : gap + symbolInk(c.1).width)
        }
        // Fixed sizes: measuring the symbol's width proved unreliable and kept shrinking the digits on a real menu bar.
        // Only a three-digit number with a symbol needs smaller digits (8.25pt) to fit.
        let fontSize: CGFloat = level >= 100 && symbol != nil ? 8.25 : 9.75
        let parts = content(fontSize)
        let (text, bolt) = parts
        let ink = inkRect(text)
        let boltInk = symbolInk(bolt)
        let font = text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont ?? NSFont.systemFont(ofSize: fontSize)
        // Draws the number and symbol together as one black group, measures what was actually drawn,
        // and centers that horizontally. Vertically, the digits' cap height sits in the middle of the body.
        let pad: CGFloat = 4
        let groupSize = NSSize(width: width(parts) + pad * 2 + 4, height: 14 + pad * 2)
        let baseline = pad + 3
        let group = NSImage(size: groupSize, flipped: false) { _ in
            text.draw(with: NSRect(x: pad - ink.minX, y: baseline, width: 200, height: 50), options: [])
            if let bolt {
                let mark = bolt.withSymbolConfiguration(.init(paletteColors: [.black])) ?? bolt
                mark.draw(in: NSRect(x: pad + ink.width + gap - boltInk.minX, y: baseline + font.capHeight / 2 - boltInk.midY,
                                     width: bolt.size.width, height: bolt.size.height))
            }
            return true
        }
        let drawn = visibleBounds(of: group)
        let groupRect = NSRect(x: body.midX - drawn.midX, y: body.midY - font.capHeight / 2 - baseline,
                               width: groupSize.width, height: groupSize.height)
        if lowPower {
            // A cut-out would show a light menu bar through the yellow fill, so the number is drawn in black.
            group.draw(in: groupRect)
        } else {
            // Cuts out the number and symbol so the menu bar shows through.
            group.draw(in: groupRect, from: .zero, operation: .destinationOut, fraction: 1)
        }
        return true
    }
    image.isTemplate = !lowPower
    return image
}

/// The part of an image that is actually drawn. SF Symbol images carry empty padding,
/// which would otherwise push the number off center and widen the gap before the symbol.
private func visibleBounds(of image: NSImage) -> NSRect {
    let scale: CGFloat = 4
    let w = Int(ceil(image.size.width * scale)), h = Int(ceil(image.size.height * scale))
    guard w > 0, h > 0, let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { return NSRect(origin: .zero, size: image.size) }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
    NSGraphicsContext.restoreGraphicsState()
    var minX = w, maxX = -1, minY = h, maxY = -1
    for y in 0..<h { for x in 0..<w where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.3 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    } }
    guard maxX >= minX else { return NSRect(origin: .zero, size: image.size) }
    // Bitmap rows run top to bottom; image coordinates run bottom to top.
    return NSRect(x: CGFloat(minX) / scale, y: CGFloat(h - 1 - maxY) / scale,
                  width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
}
