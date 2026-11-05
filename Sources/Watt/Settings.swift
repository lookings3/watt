import SwiftUI

extension Notification.Name {
    static let wattOpenSettings = Notification.Name("wattOpenSettings")
}

/// Handles open at login and automatic restart with a single user LaunchAgent.
enum LaunchAgent {
    static let label = "local.watt.menubar"
    static var plist: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }
    static var domain: String { "gui/\(getuid())" }
    static var reopenFlag: URL {
        // Uses the temp folder so a Desktop permission prompt can't block it.
        FileManager.default.temporaryDirectory.appendingPathComponent("local.watt.open-settings")
    }

    static var state: (login: Bool, keep: Bool) {
        guard let dict = NSDictionary(contentsOf: plist) else { return (false, false) }
        return (dict["RunAtLoad"] as? Bool ?? false, dict["KeepAlive"] != nil)
    }

    private static func write(login: Bool, keep: Bool) {
        guard login || keep else { try? FileManager.default.removeItem(at: plist); return }
        var dict: [String: Any] = [
            "Label": label,
            "ProgramArguments": [Bundle.main.executablePath ?? ""],
            "RunAtLoad": login,
            "ProcessType": "Interactive",
            "AbandonProcessGroup": true,
            "ThrottleInterval": 5,
        ]
        if keep { dict["KeepAlive"] = ["SuccessfulExit": false] }
        try? FileManager.default.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
        (dict as NSDictionary).write(to: plist, atomically: true)
    }

    /// Takes effect at the next login, so the app doesn't need a restart.
    static func setLogin(_ on: Bool) { write(login: on, keep: state.keep) }

    /// Restarts the app because launchd has to own it for relaunching to work.
    static func setKeepAlive(_ on: Bool) {
        write(login: state.login, keep: on)
        FileManager.default.createFile(atPath: reopenFlag.path, contents: nil)
        let start = on
            ? "launchctl bootstrap \(domain) '\(plist.path)'; launchctl kickstart \(domain)/\(label)"
            : "open '\(Bundle.main.bundleURL.path)'"
        let script = "sleep 0.4; launchctl bootout \(domain)/\(label) 2>/dev/null; pkill -x Watt; sleep 0.6; \(start)"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script]
        try? p.run()
    }

    static func consumeReopenFlag() -> Bool {
        guard FileManager.default.fileExists(atPath: reopenFlag.path) else { return false }
        try? FileManager.default.removeItem(at: reopenFlag)
        return true
    }
}

/// Removes everything the app left on the system.
enum Uninstaller {
    static var targets: [String] {
        [L("저전력 모드 권한 (\(System.ruleFile))", "Low Power Mode permission (\(System.ruleFile))"), L("자동 실행 설정 (\(LaunchAgent.plist.path))", "Launch settings (\(LaunchAgent.plist.path))"),
         L("기록 (\(Storage.directory.path))", "History (\(Storage.directory.path))"), L("앱 (\(Bundle.main.bundleURL.path) → 휴지통)", "App (\(Bundle.main.bundleURL.path) → Trash)")]
    }

    private static var hasRule: Bool {
        FileManager.default.fileExists(atPath: System.ruleFile) || System.ruleInstalled
    }

    /// Quits the app on success. Returns nil if cancelled, or the reason on failure.
    static func run() -> String? {
        if hasRule {
            switch System.removeRule() {
            case .done: break
            case .cancelled: return nil
            case .failed(let reason): return "권한 삭제 실패: \(reason)"
            }
        }
        let manager = FileManager.default
        try? manager.removeItem(at: LaunchAgent.plist)
        try? manager.removeItem(at: LaunchAgent.reopenFlag)
        try? manager.removeItem(at: Storage.directory)
        var trashError: String?
        do {
            try manager.trashItem(at: Bundle.main.bundleURL, resultingItemURL: nil)
        } catch {
            trashError = L("앱을 휴지통으로 옮기지 못했습니다. 직접 휴지통에 넣어 주세요.", "Couldn't move the app to the Trash. Move it there yourself.")
        }
        if let trashError { return trashError }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 0.3; launchctl bootout \(LaunchAgent.domain)/\(LaunchAgent.label) 2>/dev/null"]
        try? p.run()
        exit(0)
    }
}

struct SettingsView: View {
    @State private var login = LaunchAgent.state.login
    @State private var keep = LaunchAgent.state.keep
    @State private var uninstallError: String?
    @ObservedObject private var language = Language.shared

    private func confirmUninstall() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = L("Watt를 완전히 삭제할까요?", "Completely remove Watt?")
        alert.informativeText = L("다음 항목을 지웁니다.\n\n", "This removes:\n\n") + Uninstaller.targets.map { "• \($0)" }.joined(separator: "\n")
        alert.addButton(withTitle: L("삭제", "Remove"))
        alert.addButton(withTitle: L("취소", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let error = Uninstaller.run()
            DispatchQueue.main.async { uninstallError = error }
        }
    }

    var body: some View {
        Form {
            Picker(L("언어", "Language"), selection: $language.setting) {
                Text(L("시스템", "System")).tag(AppLanguage.system)
                Text("한국어").tag(AppLanguage.korean)
                Text("English").tag(AppLanguage.english)
            }
            Toggle(L("로그인 시 열기", "Open at login"), isOn: Binding(get: { login }, set: { login = $0; LaunchAgent.setLogin($0) }))
            VStack(alignment: .leading, spacing: 3) {
                Toggle(L("자동으로 다시 실행", "Restart automatically"), isOn: Binding(get: { keep }, set: { keep = $0; LaunchAgent.setKeepAlive($0) }))
                Text(L("앱이 비정상 종료되면 다시 켭니다. 바꾸면 앱이 잠깐 다시 시작됩니다.", "Reopens Watt if it crashes. Changing this restarts the app briefly."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button(L("Watt 완전 삭제…", "Completely remove Watt…"), role: .destructive) { confirmUninstall() }
                Text(L("휴지통에 버리면 권한과 기록이 남아요.",
                       "Trashing the app leaves its permission and history behind."))
                    .font(.caption).foregroundStyle(.secondary)
                if let uninstallError {
                    Text(uninstallError).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
    }
}
