import SwiftUI
import Charts

enum Metric: String, CaseIterable, Identifiable {
    case percent = "잔량", watts = "전력", temperature = "온도"
    var id: String { rawValue }
    var unit: String { self == .percent ? "%" : self == .watts ? "W" : "°C" }
    var title: String {
        switch self {
        case .percent: return L("잔량", "Level", "Ladestand", "残量")
        case .watts: return L("전력", "Power", "Leistung", "電力")
        case .temperature: return L("온도", "Temp", "Temp.", "温度")
        }
    }
    var color: Color { self == .percent ? .green : self == .watts ? .orange : .red }
    func value(_ s: Sample) -> Double? {
        switch self {
        case .percent: return Double(s.percent)
        case .watts: return s.watts
        case .temperature: return s.temperature
        }
    }
}

enum Span: String, CaseIterable, Identifiable {
    case day = "24시간", week = "7일"
    var id: String { rawValue }
    var title: String { self == .day ? L("24시간", "24h", "24 Std.", "24時間") : L("7일", "7d", "7 Tage", "7日") }
    var seconds: TimeInterval { self == .day ? 86400 : 7 * 86400 }
    var step: Int { self == .day ? 5 : 30 } // minutes between chart samples
}

struct PanelView: View {
    @ObservedObject var model: Model
    @State private var metric = Metric.percent
    @State private var span = Span.day

    /// Level bar color: yellow in Low Power Mode, red at 20% or below, otherwise green.
    private var levelColor: Color {
        if model.lowPower { return .yellow }
        return (model.snapshot?.percent ?? 100) <= 20 ? .red : .green
    }

    private var tempColor: Color {
        guard let t = model.snapshot?.temperature else { return .secondary }
        return t >= 40 ? .red : t >= 35 ? .orange : .teal
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let demo = model.demoLabel {
                Text(demo).font(.caption.weight(.medium)).foregroundStyle(.purple).padding(.bottom, 6)
            }
            header
            lowPowerRow.padding(.top, 10)
            if let message = model.message {
                Text(message).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
            }
            separator
            powerSection
            separator
            stats
            separator
            chart
            separator
            HStack {
                Button(L("충전 한도 설정…", "Charge limit…", "Ladelimit …", "充電上限…")) { System.openBatterySettings() }
                Spacer()
                Button(L("Watt 종료", "Quit Watt", "Watt beenden", "Wattを終了")) { NSApp.terminate(nil) }
                Button { NotificationCenter.default.post(name: .wattOpenSettings, object: nil) } label: {
                    Image(systemName: "gearshape")
                }
                .help(L("설정", "Settings", "Einstellungen", "設定"))
                .padding(.leading, 6)
            }
            .buttonStyle(.plain)
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 310)
        .environment(\.locale, Language.shared.locale)
    }

    private var separator: some View { Divider().padding(.vertical, 9) }

    private var header: some View {
        let shape = RoundedRectangle(cornerRadius: 11)
        return ZStack(alignment: .leading) {
            shape.fill(Color.primary.opacity(0.08))
            GeometryReader { geo in
                shape.fill(levelColor.opacity(0.32))
                    .frame(width: geo.size.width * CGFloat(model.snapshot?.percent ?? 0) / 100)
            }
            HStack(spacing: 5) {
                Text("\(model.snapshot?.percent ?? 0)%")
                    .font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit()
                Spacer()
                Text(headerDetail).font(.system(size: 12)).lineLimit(1).minimumScaleFactor(0.8)
                if let symbol = headerSymbol {
                    Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 42)
    }

    private var headerDetail: String {
        guard let s = model.snapshot else { return L("배터리 정보 없음", "No battery information", "Keine Batterieinformationen", "バッテリー情報がありません") }
        return s.timeText.isEmpty ? s.statusText : s.timeText
    }

    private var headerSymbol: String? {
        guard let s = model.snapshot else { return nil }
        return s.isCharging ? "bolt.fill" : s.isExternal ? "powerplug.fill" : nil
    }

    private var lowPowerRow: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle().fill(model.lowPower ? Color.yellow : Color.primary.opacity(0.12))
                Image(systemName: "leaf.fill").font(.system(size: 11))
                    .foregroundStyle(model.lowPower ? Color.black : Color.primary)
            }
            .frame(width: 26, height: 26)
            Text(L("저전력 모드", "Low Power Mode", "Stromsparmodus", "低電力モード")).font(.system(size: 13))
            Spacer()
            Toggle("", isOn: Binding(get: { model.lowPower }, set: { model.setLowPower($0) }))
                .labelsHidden().toggleStyle(.switch).controlSize(.small).tint(.yellow)
                .disabled(model.switching)
        }
    }

    private func icon(_ name: String, _ color: Color) -> some View {
        Image(systemName: name).font(.system(size: 12)).foregroundStyle(color).frame(width: 18)
    }

    @ViewBuilder private var powerSection: some View {
        if let s = model.snapshot { PowerBandsView(snapshot: s) }
    }

    private var stats: some View {
        VStack(spacing: 5) {
            row("thermometer.medium", tempColor, L("온도", "Temperature", "Temperatur", "温度"), model.snapshot?.temperature.map { String(format: "%.1f °C", $0) })
            row("heart.fill", .pink, L("최대 용량", "Maximum capacity", "Maximale Kapazität", "最大容量"), model.snapshot?.healthPercent.map { String(format: "%.1f%%", $0) })
            row("arrow.triangle.2.circlepath", .blue, L("사이클", "Cycles", "Ladezyklen", "充放電回数"), model.snapshot.map { "\($0.cycleCount) / \($0.designCycles)" })
        }
    }

    private func row(_ symbol: String, _ color: Color, _ title: String, _ value: String?) -> some View {
        HStack {
            icon(symbol, color)
            Text(title).font(.callout).foregroundStyle(.secondary)
            Spacer()
            Text(value ?? "-").font(.callout).monospacedDigit()
        }
    }

    private var points: [(date: Date, value: Double)] {
        let cutoff = Date().addingTimeInterval(-span.seconds)
        let recent = model.history.filter { $0.date >= cutoff }
        var result: [(date: Date, value: Double)] = []
        for (i, s) in recent.enumerated() where i % span.step == 0 || i == recent.count - 1 {
            if let v = metric.value(s) { result.append((s.date, v)) }
        }
        return result
    }

    private func yDomain(_ values: [Double]) -> ClosedRange<Double> {
        if metric == .percent { return 0...100 }
        let low = values.min() ?? 0, high = values.max() ?? 1
        let pad = max((high - low) * 0.15, 0.5)
        return (low - pad)...(high + pad)
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("", selection: $metric) {
                    ForEach(Metric.allCases) { Text($0.title).tag($0) }
                }
                Picker("", selection: $span) {
                    ForEach(Span.allCases) { Text($0.title).tag($0) }
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)

            let data = points
            if data.count < 2 {
                Text(L("기록을 모으는 중입니다", "Collecting history", "Verlauf wird gesammelt", "履歴を収集しています")).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 90)
            } else {
                Chart(data, id: \.date) { p in
                    AreaMark(x: .value("시간", p.date), yStart: .value("기준", yDomain(data.map(\.value)).lowerBound),
                             yEnd: .value(metric.rawValue, p.value))
                        .foregroundStyle(metric.color.opacity(0.15))
                    LineMark(x: .value("시간", p.date), y: .value(metric.rawValue, p.value))
                        .foregroundStyle(metric.color)
                }
                .chartYScale(domain: yDomain(data.map(\.value)))
                .chartYAxisLabel(metric.unit)
                .font(.caption2)
                .frame(height: 90)
            }
        }
    }
}
