import AppKit
import SwiftUI
import Combine

// A separate preview app for checking the icon and panel with made-up values.
// It shows its own menu bar icon for side-by-side comparison, saves no history,
// never changes Low Power Mode, and doesn't save the language choice.

enum PreviewState: String, CaseIterable, Identifiable {
    case battery = "배터리 사용"
    case charging = "충전 중"
    case plugged = "연결만, 충전 안 함"
    case short = "충전기 출력 부족"
    case measuring = "측정 중"
    var id: String { rawValue }
}

final class PreviewSettings: ObservableObject {
    @Published var level = 85.0
    @Published var state = PreviewState.battery
    @Published var lowPower = false
    @Published var load = 6.0
    @Published var chargeWatts = 25.0
    @Published var adapter = 65
    @Published var temperature = 27.0
    @Published var health = 100.0
    @Published var cycles = 22.0
    @Published var minutes = 300.0
    @Published var language = AppLanguage.system
    @Published var darkPanel = true
}

final class PreviewController: NSObject, NSApplicationDelegate {
    let settings = PreviewSettings()
    let model = Model()
    private var item: NSStatusItem!
    private var window: NSWindow!
    private var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ note: Notification) {
        Language.persists = false
        model.isDemo = true
        model.history = sampleHistory()

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.imagePosition = .imageOnly

        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.apply() } }
            .store(in: &bag)
        apply()

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 820),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Watt Preview"
        window.contentView = NSHostingView(rootView: PreviewView(settings: settings, model: model))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Builds a snapshot from the controls and updates the panel and the menu bar icon.
    private func apply() {
        let s = settings
        Language.shared.setting = s.language
        let volts = 12.6
        var snap = BatterySnapshot(percent: Int(s.level), isCharging: false, isExternal: false, fullyCharged: s.level >= 100,
                                   minutesRemaining: Int(s.minutes), watts: -s.load, temperature: s.temperature,
                                   cycleCount: Int(s.cycles), designCycles: 1000, healthPercent: s.health,
                                   volts: volts, amps: 0, systemLoad: s.load, inputWatts: nil, adapterWatts: nil)
        switch s.state {
        case .battery:
            break
        case .charging:
            snap.isExternal = true; snap.isCharging = true
            snap.watts = s.chargeWatts; snap.inputWatts = s.load + s.chargeWatts; snap.adapterWatts = s.adapter
        case .plugged:
            snap.isExternal = true
            snap.watts = 0; snap.inputWatts = s.load; snap.adapterWatts = s.adapter; snap.minutesRemaining = nil
        case .short:
            snap.isExternal = true
            let shortfall = s.load / 2
            snap.watts = -shortfall; snap.inputWatts = s.load - shortfall; snap.adapterWatts = s.adapter; snap.minutesRemaining = nil
        case .measuring:
            snap.watts = 0; snap.systemLoad = 0
        }
        snap.amps = snap.watts / volts
        model.snapshot = snap
        model.lowPower = s.lowPower

        if let button = item.button {
            let dark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            button.image = batteryIcon(percent: snap.percent, charging: snap.isCharging,
                                       plugged: snap.isExternal && !snap.isCharging, lowPower: s.lowPower, dark: dark)
        }
    }

    /// 24 hours and a week of made-up history with charging stretches and lid-closed gaps.
    private func sampleHistory() -> [Sample] {
        let now = Date(), calendar = Calendar.current
        var level = 80.0, result: [Sample] = []
        for m in stride(from: 7 * 1440, to: 0, by: -1) {
            let date = now.addingTimeInterval(-Double(m) * 60)
            let hour = calendar.component(.hour, from: date)
            if hour >= 1 && hour < 8 { continue }
            let plugged = hour >= 19 && hour < 21
            let charging = plugged && level < 95
            let watts = charging ? 25.0 : plugged ? 0 : -(5 + Double(m % 7))
            level = min(100, max(10, level + watts / 60 * 1.4))
            result.append(Sample(date: date, percent: Int(level), watts: watts, temperature: 26 + abs(watts) * 0.4,
                                 charging: charging, lowPower: false))
        }
        return result
    }
}

struct PreviewView: View {
    @ObservedObject var settings: PreviewSettings
    @ObservedObject var model: Model

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            controls.frame(width: 300)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    iconPreviews
                    PanelView(model: model)
                        .id("\(settings.language.rawValue)-\(settings.darkPanel)")
                        .background(Color(nsColor: .windowBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
                        .environment(\.colorScheme, settings.darkPanel ? .dark : .light)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(20)
        .frame(minWidth: 940, minHeight: 760)
    }

    private var controls: some View {
        Form {
            Section("배터리") {
                slider("잔량", $settings.level, 0...100, "%.0f%%")
                Picker("상태", selection: $settings.state) {
                    ForEach(PreviewState.allCases) { Text($0.rawValue).tag($0) }
                }
                Toggle("저전력 모드", isOn: $settings.lowPower)
                slider("남은 시간", $settings.minutes, 0...1200, "%.0f분")
            }
            Section("전력") {
                slider("맥 소비", $settings.load, 0...60, "%.1f W")
                slider("충전 전력", $settings.chargeWatts, 0...90, "%.1f W")
                Picker("충전기", selection: $settings.adapter) {
                    ForEach([30, 65, 96, 140], id: \.self) { Text("\($0) W").tag($0) }
                }
            }
            Section("상태 정보") {
                slider("온도", $settings.temperature, 15...50, "%.1f °C")
                slider("최대 용량", $settings.health, 60...105, "%.1f%%")
                slider("사이클", $settings.cycles, 0...1500, "%.0f")
            }
            Section("보기") {
                Picker("언어", selection: $settings.language) {
                    Text("시스템").tag(AppLanguage.system)
                    Text("한국어").tag(AppLanguage.korean)
                    Text("English").tag(AppLanguage.english)
                    Text("Deutsch").tag(AppLanguage.german)
                    Text("日本語").tag(AppLanguage.japanese)
                }
                Toggle("패널 다크 모드", isOn: $settings.darkPanel)
            }
        }
        .formStyle(.grouped)
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, _ format: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value.wrappedValue)).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    private var iconPreviews: some View {
        let charging = model.snapshot?.isCharging ?? false
        let plugged = (model.snapshot?.isExternal ?? false) && !charging
        return VStack(alignment: .leading, spacing: 8) {
            Text("메뉴바 아이콘 (실제 크기, 3배, 6배)").font(.headline)
            ForEach([false, true], id: \.self) { dark in
                HStack(spacing: 24) {
                    ForEach([1.0, 3.0, 6.0], id: \.self) { scale in
                        let icon = batteryIcon(percent: Int(settings.level), charging: charging, plugged: plugged,
                                               lowPower: settings.lowPower, dark: dark)
                        Image(nsImage: icon)
                            .renderingMode(icon.isTemplate ? .template : .original)
                            .interpolation(scale > 1 ? .none : .high)
                            .resizable()
                            .frame(width: icon.size.width * scale, height: icon.size.height * scale)
                            .foregroundStyle(dark ? Color.white : Color.black)
                    }
                    Spacer()
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10)
                    .fill(dark ? Color(white: 0.15) : Color(red: 0.78, green: 0.85, blue: 0.9)))
            }
            Text("메뉴바에도 이 앱의 아이콘이 하나 더 떠 있어요. 기본 배터리 아이콘 옆에서 비교해 보세요.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

func runPreview() -> Never {
    let app = NSApplication.shared
    let controller = PreviewController()
    app.delegate = controller
    app.setActivationPolicy(.regular)
    app.run()
    exit(0)
}
