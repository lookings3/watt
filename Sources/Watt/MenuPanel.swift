import AppKit
import SwiftUI

/// A borderless panel that can take keyboard focus for its switches and pickers.
private final class MenuWindow: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Shows the panel like the macOS Wi-Fi and Bluetooth menus: no arrow, aligned to the icon's left edge,
/// with the system menu material. Everything is built on open and released on close.
final class MenuPanelController {
    static let cornerRadius: CGFloat = 18

    var onOpen: () -> Void = {}
    var onClose: () -> Void = {}
    var isShown: Bool { window != nil }
    /// True right after the panel closed, so the icon click that closed it doesn't reopen it.
    var justClosed: Bool { Date().timeIntervalSince(closedAt) < 0.3 }
    private var closedAt = Date.distantPast

    private var window: MenuWindow?
    private var host: NSHostingController<AnyView>?
    private weak var button: NSStatusBarButton?
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var sizeObservation: NSKeyValueObservation?

    func show<Content: View>(_ content: Content, below button: NSStatusBarButton) {
        close()
        self.button = button
        let host = NSHostingController(rootView: AnyView(content))
        host.sizingOptions = [.preferredContentSize]
        let size = host.view.fittingSize
        host.view.frame = NSRect(origin: .zero, size: size)
        host.view.autoresizingMask = [.width, .height]

        let window = MenuWindow(contentRect: NSRect(origin: .zero, size: size),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.contentView = background(for: host.view, size: size)
        window.setFrame(frame(for: size, below: button), display: false)

        self.window = window
        self.host = host
        sizeObservation = host.observe(\.preferredContentSize, options: [.new]) { [weak self] host, _ in
            DispatchQueue.main.async { self?.resize(to: host.preferredContentSize) }
        }
        window.orderFrontRegardless()
        window.makeKey()
        if #unavailable(macOS 27.0) { DispatchQueue.main.async { button.highlight(true) } }
        watchForDismissal()
        onOpen()
    }

    func close() {
        guard let window else { return }
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers = []
        sizeObservation = nil
        window.orderOut(nil)
        self.window = nil
        host = nil
        if #unavailable(macOS 27.0) { button?.highlight(false) }
        closedAt = Date()
        onClose()
    }

    /// The system menu material, which blurs what's behind heavily enough to keep the text readable.
    /// The clear glass of NSGlassEffectView let colorful windows show through too much.
    private func background(for content: NSView, size: CGSize) -> NSView {
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .menu
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = roundedMask(radius: Self.cornerRadius)
        effect.addSubview(content)
        return effect
    }

    private func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    /// Just below the menu bar, with its left edge on the icon's left edge, kept on screen.
    private func frame(for size: CGSize, below button: NSStatusBarButton) -> NSRect {
        guard let buttonWindow = button.window else { return NSRect(origin: .zero, size: size) }
        let anchor = buttonWindow.frame
        let visible = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame ?? anchor
        let x = min(max(anchor.minX, visible.minX + 8), visible.maxX - size.width - 8)
        let top = anchor.minY - 5
        return NSRect(x: x, y: top - size.height, width: size.width, height: size.height)
    }

    /// Keeps the top edge in place when the content changes height.
    private func resize(to size: CGSize) {
        guard let window, size.width > 0, size.height > 0, size != window.frame.size else { return }
        let top = window.frame.maxY
        window.setFrame(NSRect(x: window.frame.minX, y: top - size.height, width: size.width, height: size.height), display: true)
    }

    /// Closes on a click elsewhere, the Escape key, or a Space change, like a menu.
    private func watchForDismissal() {
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] _ in
            // On macOS 27 the menu bar hosts the icon in another process, so clicks on it arrive here too.
            // The system doesn't end the session on a second click, so a click on the icon closes the panel as well.
            if #unavailable(macOS 27.0), let iconFrame = self?.button?.window?.frame, iconFrame.contains(NSEvent.mouseLocation) { return }
            self?.close()
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.keyDown], handler: { [weak self] event in
            guard event.keyCode == 53 else { return event } // Escape
            self?.close()
            return nil
        }) { monitors.append(local) }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.close() })
    }
}

