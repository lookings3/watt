import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let model = Model()
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private var bag = Set<AnyCancellable>()
    private var appearanceObservation: NSKeyValueObservation?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ note: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.imagePosition = .imageOnly

        popover.behavior = .transient
        popover.delegate = self

        model.$snapshot.combineLatest(model.$lowPower)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.updateIcon() }
            .store(in: &bag)
        appearanceObservation = item.button?.observe(\.effectiveAppearance) { [weak self] _, _ in self?.updateIcon() }
        model.isDemo = CommandLine.arguments.contains("--demo")
        model.start()
        NotificationCenter.default.addObserver(forName: .wattOpenSettings, object: nil, queue: .main) { [weak self] _ in
            self?.openSettings()
        }
        if LaunchAgent.consumeReopenFlag() { openSettings() }
        if CommandLine.arguments.contains("--panel-test") { // For testing: opens the panel briefly, then closes it.
            popover.behavior = .applicationDefined
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.togglePopover() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 18) { self.popover.performClose(nil) }
        }
    }

    private func openSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.title = L("Watt 설정", "Watt Settings")
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func updateIcon() {
        guard let button = item.button else { return }
        let s = model.snapshot
        let dark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        button.image = batteryIcon(percent: s?.percent ?? 0, charging: s?.isCharging ?? false,
                                   plugged: (s?.isExternal ?? false) && !(s?.isCharging ?? false), lowPower: model.lowPower, dark: dark)
        button.setAccessibilityTitle(s.map { L("배터리 \($0.percent)%", "Battery \($0.percent)%") } ?? L("배터리", "Battery"))
    }

    @objc private func togglePopover() {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Builds the panel on open and releases it on close so nothing renders while it's closed.
            popover.contentViewController = NSHostingController(rootView: PanelView(model: model))
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
    func popoverDidShow(_ n: Notification) { model.panelOpened() }
    func popoverDidClose(_ n: Notification) {
        popover.contentViewController = nil
    }
}

/// For testing: prints current values.
func dump() {
    if let s = Battery.read() { print(s) } else { print("battery: nil") }
    print("lowPower(ProcessInfo) =", System.lowPowerEnabled)
    print("preferred =", Locale.preferredLanguages.first ?? "-", "korean =", Language.shared.isKorean)
}

/// For testing: saves the panel and icons as PNG files.
func render(to dir: String) {
    let model = Model()
    model.snapshot = Battery.read()
    model.lowPower = System.lowPowerEnabled
    let now = Date()
    model.history = (0..<600).map { i in
        Sample(date: now.addingTimeInterval(Double(i - 600) * 120), percent: 100 - i / 8,
               watts: -6 - Double(i % 40) / 8, temperature: 28 + Double(i % 90) / 30, charging: false, lowPower: false)
    }
    func write(_ rep: NSBitmapImageRep, _ name: String) {
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir + "/" + name))
    }
    func capture(_ name: String) {
        let host = NSHostingView(rootView: PanelView(model: model).background(Color(white: 0.16)).environment(\.colorScheme, .dark))
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        window.appearance = NSAppearance(named: .darkAqua)
        host.layoutSubtreeIfNeeded()
        print(name, "height", Int(host.frame.height))
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            write(rep, name)
        }
    }
    capture("panel.png")
    do {
        let host = NSHostingView(rootView: SettingsView().background(Color(white: 0.16)).environment(\.colorScheme, .dark))
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            write(rep, "settings.png")
        }
    }
    if var s = model.snapshot {
        func scenario(_ name: String, external: Bool, charging: Bool, watts: Double, load: Double, input: Double?) {
            s.isExternal = external; s.isCharging = charging; s.watts = watts; s.systemLoad = load
            s.inputWatts = input; s.adapterWatts = external ? 65 : nil; s.amps = watts / max(s.volts, 1)
            model.snapshot = s
            capture(name)
        }
        scenario("flow-measuring.png", external: false, charging: false, watts: 0, load: 0, input: nil)
        scenario("flow-battery.png", external: false, charging: false, watts: -7.5, load: 7.5, input: nil)
        scenario("flow-charging.png", external: true, charging: true, watts: 27.3, load: 8.7, input: 36)
        scenario("flow-idle.png", external: true, charging: false, watts: 0, load: 9, input: 9.5)
        scenario("flow-draining.png", external: true, charging: false, watts: -3.8, load: 7.6, input: 3.8)
    }
    let cases: [(String, Int, Bool, Bool, Bool)] = [
        ("icon-72-light.png", 72, false, false, false), ("icon-72-dark.png", 72, false, false, true),
        ("icon-100.png", 100, false, false, true), ("icon-8.png", 8, false, false, true),
        ("icon-low.png", 45, false, true, true), ("icon-charging.png", 72, true, false, true),
        ("icon-low-charging.png", 100, true, true, false), ("icon-plugged.png", 72, false, false, true),
    ]
    let w = 186, h = 84
    for (name, level, charging, low, dark) in cases {
        let image = batteryIcon(percent: level, charging: charging, plugged: name == "icon-plugged.png", lowPower: low, dark: dark)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(white: dark ? 0.15 : 0.92, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: w, height: h).fill()
        // The system tints template images, so tint white here to check them on a dark background.
        let tinted = NSImage(size: image.size, flipped: false) { r in
            image.draw(in: r)
            if image.isTemplate && dark {
                NSColor.white.set()
                r.fill(using: .sourceIn)
            }
            return true
        }
        tinted.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        write(rep, name)
    }
}

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--render-lang"), i + 1 < args.count {
    Language.shared.setting = args[i + 1] == "en" ? .english : .korean
}
if args.contains("--dump") { dump(); exit(0) }
if args.contains("--uninstall-plan") { Uninstaller.targets.forEach { print($0) }; exit(0) }
if args.contains("--print-rule") { print(System.ruleLine ?? "nil"); print("installed:", System.ruleInstalled); exit(0) }
if let i = args.firstIndex(of: "--set-low"), i + 1 < args.count {
    print(System.setLowPower(args[i + 1] == "on") ?? "ok")
    exit(0)
}
if let i = args.firstIndex(of: "--render"), i + 1 < args.count {
    _ = NSApplication.shared
    render(to: args[i + 1])
    exit(0)
}

if let i = args.firstIndex(of: "--set-keep"), i + 1 < args.count {
    LaunchAgent.setKeepAlive(args[i + 1] == "on")
    exit(0)
}
if let i = args.firstIndex(of: "--set-login"), i + 1 < args.count {
    LaunchAgent.setLogin(args[i + 1] == "on")
    exit(0)
}

// Doesn't start a second copy.
if let id = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: id)
    .contains(where: { $0.processIdentifier != getpid() }) {
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
