import AppKit
import IOKit.ps
import Combine

final class Model: ObservableObject {
    @Published var snapshot: BatterySnapshot?
    @Published var lowPower = System.lowPowerEnabled
    @Published var history: [Sample] = []
    @Published var message: String?
    @Published var switching = false
    @Published var demoLabel: String?

    /// Demo mode: cycles through fake states. Saves no history and never changes the real Low Power Mode setting.
    var isDemo = false
    private var demoIndex = 0

    private let store = HistoryStore()
    private var timers: [Timer] = []

    private func startDemo() {
        store.load { [weak self] in self?.history = $0 }
        guard var base = Battery.read() else { return }
        let steps: [(String, Bool, Bool, Bool, Double, Double, Double?)] = [
            (L("배터리 사용", "On battery", "Batteriebetrieb", "バッテリー使用中"), false, false, false, -7.5, 7.5, nil),
            (L("충전 중", "Charging", "Lädt", "充電中"), true, true, false, 27.3, 8.7, 36),
            (L("전원 연결, 충전 안 함", "Plugged in, not charging", "Angeschlossen, lädt nicht", "電源接続、充電停止中"), true, false, false, 0, 9, 9.5),
            (L("충전기 출력 부족", "Charger falls short", "Netzteil reicht nicht aus", "充電器の出力不足"), true, false, false, -3.8, 7.6, 3.8),
            (L("저전력 모드", "Low Power Mode", "Stromsparmodus", "低電力モード"), false, false, true, -4.2, 4.2, nil),
            (L("측정 중", "Measuring", "Wird gemessen", "測定中"), false, false, false, 0, 0, nil),
        ]
        func show() {
            let step = steps[demoIndex % steps.count]
            demoIndex += 1
            base.isExternal = step.1; base.isCharging = step.2
            base.watts = step.4; base.systemLoad = step.5; base.inputWatts = step.6
            base.adapterWatts = step.1 ? 65 : nil
            base.amps = step.4 / max(base.volts, 1)
            base.minutesRemaining = step.1 && !step.2 ? nil : 95
            lowPower = step.3
            snapshot = base
            demoLabel = L("데모 \(demoIndex % steps.count == 0 ? steps.count : demoIndex % steps.count)/\(steps.count): \(step.0)", "Demo \(demoIndex % steps.count == 0 ? steps.count : demoIndex % steps.count)/\(steps.count): \(step.0)", "Demo \(demoIndex % steps.count == 0 ? steps.count : demoIndex % steps.count)/\(steps.count): \(step.0)", "デモ \(demoIndex % steps.count == 0 ? steps.count : demoIndex % steps.count)/\(steps.count): \(step.0)")
        }
        show()
        timers.append(.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in show() })
    }

    func start() {
        if isDemo { startDemo(); return }
        store.load { [weak self] in self?.history = $0 + (self?.history ?? []) }
        refresh()
        record()
        timers.append(.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.refresh() })
        timers.append(.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.record() })

        NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        let source = IOPSNotificationCreateRunLoopSource({ context in
            Unmanaged<Model>.fromOpaque(context!).takeUnretainedValue().refresh()
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
    }

    func refresh() {
        guard !isDemo else { return }
        snapshot = Battery.read()
        lowPower = System.lowPowerEnabled
    }

    private func record() {
        guard let s = snapshot, !s.isMeasuring else { return }
        let sample = Sample(date: Date(), percent: s.percent, watts: s.watts, temperature: s.temperature,
                            charging: s.isCharging, lowPower: lowPower)
        store.append(sample)
        history.append(sample)
        let cutoff = Date().addingTimeInterval(-HistoryStore.keepDays * 86400)
        if let first = history.first, first.date < cutoff { history.removeAll { $0.date < cutoff } }
    }

    func setLowPower(_ on: Bool) {
        if isDemo { lowPower = on; return }
        guard !switching else { return }
        switching = true
        message = nil
        DispatchQueue.global(qos: .userInitiated).async {
            var error: String?
            var proceed = true
            if !System.ruleInstalled {
                proceed = DispatchQueue.main.sync { self.askToInstallRule() }
                if proceed {
                    switch System.installRule() {
                    case .done: break
                    case .cancelled: proceed = false
                    case .failed(let reason):
                        proceed = false
                        error = L("권한 설치 실패: \(reason)", "Couldn't install the permission: \(reason)", "Berechtigung konnte nicht installiert werden: \(reason)", "権限をインストールできませんでした: \(reason)")
                    }
                }
            }
            if proceed { error = System.setLowPower(on) }
            DispatchQueue.main.async {
                self.switching = false
                self.message = error
                self.refresh()
                self.objectWillChange.send() // Returns the switch to the real state after a failure or cancel.
            }
        }
    }

    private func askToInstallRule() -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L("저전력 모드 권한이 필요합니다", "Low Power Mode needs permission", "Stromsparmodus braucht eine Berechtigung", "低電力モードには権限が必要です")
        alert.informativeText = L("macOS는 저전력 모드를 바꿀 때 관리자 권한을 요구합니다. 한 번만 설치하면 저전력 모드 켜기/끄기 두 명령만 비밀번호 없이 실행됩니다. 다음 창에 맥 비밀번호를 입력하세요.", "macOS requires administrator rights to change Low Power Mode. Install this once and only the two Low Power Mode on/off commands will run without a password. Enter your Mac password in the next window.", "macOS verlangt Administratorrechte, um den Stromsparmodus zu ändern. Nach einmaliger Installation laufen nur die beiden Befehle zum Ein- und Ausschalten ohne Passwort. Gib im nächsten Fenster dein Mac-Passwort ein.", "macOSでは低電力モードの変更に管理者権限が必要です。一度インストールすると、低電力モードのオン/オフの2つのコマンドだけがパスワードなしで実行されます。次のウインドウでMacのパスワードを入力してください。")
        alert.addButton(withTitle: L("계속", "Continue", "Fortfahren", "続ける"))
        alert.addButton(withTitle: L("취소", "Cancel", "Abbrechen", "キャンセル"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Reads fresh values when the panel opens.
    func panelOpened() { refresh() }
}
