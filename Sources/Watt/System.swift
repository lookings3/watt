import AppKit

enum System {
    @discardableResult
    static func run(_ path: String, _ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        do { try p.run() } catch { return (-1, error.localizedDescription) }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    static var lowPowerEnabled: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }

    static let ruleFile = "/etc/sudoers.d/watt-lowpower"

    /// Checks whether the sudo rule allows Low Power Mode changes.
    static var ruleInstalled: Bool {
        run("/usr/bin/sudo", ["-n", "-l", "/usr/bin/pmset", "-a", "lowpowermode", "1"]).status == 0
    }

    static var ruleLine: String? {
        let user = NSUserName()
        guard user.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else { return nil }
        return "\(user) ALL=(root) NOPASSWD: /usr/bin/pmset -a lowpowermode 0, /usr/bin/pmset -a lowpowermode 1"
    }

    enum AdminResult { case done, cancelled, failed(String) }

    /// Runs a command through the macOS administrator prompt. The app never handles the password.
    static func runAsAdmin(_ command: String) -> AdminResult {
        let r = run("/usr/bin/osascript", ["-e", "on run argv",
                                           "-e", "do shell script (item 1 of argv) with administrator privileges",
                                           "-e", "end run", command])
        if r.status == 0 { return .done }
        if r.output.contains("-128") { return .cancelled }
        return .failed(r.output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func installRule() -> AdminResult {
        guard let line = ruleLine else { return .failed(L("이 계정 이름으로는 권한을 설치할 수 없습니다.", "Can't install the permission for this account name.")) }
        return runAsAdmin("""
        T=$(/usr/bin/mktemp) && echo '\(line)' > "$T" && /usr/sbin/visudo -cf "$T" && \
        /usr/bin/install -m 440 -o root -g wheel "$T" \(ruleFile); R=$?; /bin/rm -f "$T"; exit $R
        """)
    }

    static func removeRule() -> AdminResult { runAsAdmin("/bin/rm -f \(ruleFile)") }

    /// Returns nil on success, or a reason to show on failure.
    static func setLowPower(_ on: Bool) -> String? {
        let r = run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "lowpowermode", on ? "1" : "0"])
        if r.status == 0 { return nil }
        if r.output.contains("password") {
            return L("저전력 모드 권한이 없습니다. 스위치를 다시 켜서 권한을 설치하세요.", "Low Power Mode permission is missing. Turn the switch on again to install it.")
        }
        return L("저전력 모드 전환 실패: \(r.output.trimmingCharacters(in: .whitespacesAndNewlines))", "Couldn't change Low Power Mode: \(r.output.trimmingCharacters(in: .whitespacesAndNewlines))")
    }

    static func openBatterySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
