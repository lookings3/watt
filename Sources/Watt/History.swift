import Foundation

struct Sample: Identifiable {
    var id: Date { date }
    var date: Date
    var percent: Int
    var watts: Double
    var temperature: Double?
    var charging: Bool
    var lowPower: Bool

    var csv: String {
        let t = temperature.map { String(format: "%.1f", $0) } ?? ""
        return "\(Int(date.timeIntervalSince1970)),\(percent),\(String(format: "%.2f", watts)),\(t),\(charging ? 1 : 0),\(lowPower ? 1 : 0)"
    }
    init(date: Date, percent: Int, watts: Double, temperature: Double?, charging: Bool, lowPower: Bool) {
        self.date = date; self.percent = percent; self.watts = watts
        self.temperature = temperature; self.charging = charging; self.lowPower = lowPower
    }
    init?(csv line: Substring) {
        let f = line.split(separator: ",", omittingEmptySubsequences: false)
        guard f.count == 6, let ts = Double(f[0]), let p = Int(f[1]), let w = Double(f[2]) else { return nil }
        self.init(date: Date(timeIntervalSince1970: ts), percent: p, watts: w,
                  temperature: Double(f[3]), charging: f[4] == "1", lowPower: f[5] == "1")
    }
}

enum Storage {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Watt")
    }
    /// History saved next to the app by earlier versions.
    static var legacyHistory: URL {
        Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("data/history.csv")
    }
}

final class HistoryStore {
    static let keepDays = 30.0
    private let file: URL
    /// File work can block on permission prompts, so keep it off the main thread.
    private let queue = DispatchQueue(label: "local.watt.history")

    init() {
        file = Storage.directory.appendingPathComponent("history.csv")
    }

    func load(completion: @escaping ([Sample]) -> Void) {
        queue.async {
            let samples = self.loadNow()
            DispatchQueue.main.async { completion(samples) }
        }
    }

    private func prepare() {
        let manager = FileManager.default
        try? manager.createDirectory(at: Storage.directory, withIntermediateDirectories: true)
        if !manager.fileExists(atPath: file.path), manager.fileExists(atPath: Storage.legacyHistory.path) {
            try? manager.copyItem(at: Storage.legacyHistory, to: file)
        }
    }

    private func loadNow() -> [Sample] {
        prepare()
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        let cutoff = Date().addingTimeInterval(-Self.keepDays * 86400)
        let kept = text.split(separator: "\n").compactMap { Sample(csv: $0) }.filter { $0.date >= cutoff }
        try? kept.map(\.csv).joined(separator: "\n").appending(kept.isEmpty ? "" : "\n")
            .write(to: file, atomically: true, encoding: .utf8)
        return kept
    }

    func append(_ s: Sample) {
        queue.async { self.appendNow(s) }
    }

    private func appendNow(_ s: Sample) {
        let line = Data((s.csv + "\n").utf8)
        if let h = try? FileHandle(forWritingTo: file) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: line)
        } else {
            try? line.write(to: file)
        }
    }
}
