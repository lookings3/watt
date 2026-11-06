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
    var bucket: TimeInterval { self == .day ? 900 : 7200 } // seconds in each chart point
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

    private struct ChartPoint: Identifiable {
        var id: Date { date }
        let date: Date
        let value: Double
        let segment: Int
    }

    /// Groups records into fixed time buckets. A bucket without records starts a new line segment.
    private func points(from start: Date) -> [ChartPoint] {
        let size = span.bucket
        var buckets: [Int: [Double]] = [:]
        for s in model.history where s.date >= start {
            guard let v = metric.value(s) else { continue }
            buckets[Int(s.date.timeIntervalSince(start) / size), default: []].append(v)
        }
        var result: [ChartPoint] = []
        var segment = 0
        var previous: Int?
        for index in buckets.keys.sorted() {
            let values = buckets[index]!
            // Level keeps existing while the Mac is idle, so only power and temperature break.
            if metric != .percent, let previous, index != previous + 1 { segment += 1 }
            previous = index
            let value = metric == .percent ? values.last! : values.reduce(0, +) / Double(values.count)
            result.append(ChartPoint(date: start.addingTimeInterval((Double(index) + 0.5) * size), value: value, segment: segment))
        }
        return result
    }

    /// Stretches of the selected period without records, shown as shaded areas.
    private func idleRanges(_ data: [ChartPoint], start: Date, end: Date) -> [(from: Date, to: Date)] {
        let half = span.bucket / 2
        var result: [(from: Date, to: Date)] = []
        var edge = start
        for p in data {
            let from = p.date.addingTimeInterval(-half)
            let beforeFirstRecord = edge == start
            if (metric != .percent || beforeFirstRecord), from.timeIntervalSince(edge) >= span.bucket - 1 {
                result.append((edge, from))
            }
            edge = p.date.addingTimeInterval(half)
        }
        if end.timeIntervalSince(edge) >= span.bucket { result.append((edge, end)) }
        return result
    }

    private func yDomain(_ values: [Double]) -> ClosedRange<Double> {
        if metric == .percent { return 0...100 }
        var low = values.min() ?? 0, high = values.max() ?? 1
        if metric == .watts { low = min(low, 0); high = max(high, 0) }
        if metric == .temperature, high - low < 10 {
            let middle = (high + low) / 2
            low = middle - 5; high = middle + 5
        }
        let pad = max((high - low) * 0.1, 0.5)
        return (low - pad)...(high + pad)
    }

    /// Midnights for grid lines, and where to put the labels.
    private func xMarks(start: Date, end: Date) -> (grid: [Date], labels: [Date]) {
        let calendar = Calendar.current
        var grid: [Date] = []
        var labels: [Date] = []
        if span == .day {
            var date = calendar.dateInterval(of: .hour, for: start)!.start
            while date <= end {
                if date >= start, calendar.component(.hour, from: date) % 6 == 0 { grid.append(date) }
                date = date.addingTimeInterval(3600)
            }
            return (grid, grid)
        }
        var day = calendar.startOfDay(for: start)
        while day < end {
            let next = calendar.date(byAdding: .day, value: 1, to: day)!
            if day >= start { grid.append(day) }
            let from = max(day, start), to = min(next, end)
            if to.timeIntervalSince(from) >= 6 * 3600 { labels.append(from.addingTimeInterval(to.timeIntervalSince(from) / 2)) }
            day = next
        }
        return (grid, labels)
    }

    private func xLabel(_ date: Date) -> String {
        let locale = Language.shared.locale
        return span == .day
            ? date.formatted(Date.FormatStyle().hour().locale(locale))
            : date.formatted(Date.FormatStyle().weekday(.abbreviated).locale(locale))
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

            let end = Date()
            let start = end.addingTimeInterval(-span.seconds)
            let data = points(from: start)
            if data.count < 2 {
                Text(L("기록을 모으는 중입니다", "Collecting history", "Verlauf wird gesammelt", "履歴を収集しています")).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 110)
            } else {
                let domain = yDomain(data.map(\.value))
                let base = metric == .watts ? 0 : domain.lowerBound
                let marks = xMarks(start: start, end: end)
                let lonely = Set(Dictionary(grouping: data, by: \.segment).filter { $0.value.count == 1 }.keys)
                Chart {
                    ForEach(idleRanges(data, start: start, end: end), id: \.from) { range in
                        RectangleMark(xStart: .value("시작", range.from), xEnd: .value("끝", range.to))
                            .foregroundStyle(Color.primary.opacity(0.09))
                            .annotation(position: .overlay, alignment: .top, spacing: 4) {
                                if span == .day, range.to.timeIntervalSince(range.from) >= 4 * 3600 {
                                    Text(metric == .percent ? L("기록 없음", "No records", "Keine Daten", "記録なし")
                                                            : L("사용 안 함", "Not in use", "Nicht benutzt", "未使用"))
                                        .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize()
                                }
                            }
                    }
                    if metric == .watts {
                        RuleMark(y: .value("0", 0)).foregroundStyle(Color.primary.opacity(0.35))
                    }
                    ForEach(data) { p in
                        AreaMark(x: .value("시간", p.date), yStart: .value("기준", base), yEnd: .value(metric.rawValue, p.value),
                                 series: .value("구간", p.segment))
                            .foregroundStyle(metric.color.opacity(0.15))
                            .interpolationMethod(metric == .percent ? .monotone : .linear)
                        LineMark(x: .value("시간", p.date), y: .value(metric.rawValue, p.value), series: .value("구간", p.segment))
                            .foregroundStyle(metric.color)
                            .interpolationMethod(metric == .percent ? .monotone : .linear)
                        if lonely.contains(p.segment) {
                            PointMark(x: .value("시간", p.date), y: .value(metric.rawValue, p.value))
                                .symbolSize(10).foregroundStyle(metric.color)
                        }
                    }
                }
                .chartXScale(domain: start...end)
                .chartYScale(domain: domain)
                .chartXAxis {
                    AxisMarks(values: marks.grid) { _ in AxisGridLine() }
                    AxisMarks(values: marks.labels) { value in
                        if let date = value.as(Date.self) {
                            AxisValueLabel(anchor: .top) { Text(xLabel(date)).fixedSize() }
                        }
                    }
                }
                .chartYAxis {
                    if metric == .percent {
                        AxisMarks(values: [0, 50, 100])
                    } else {
                        AxisMarks(values: .automatic(desiredCount: 3))
                    }
                }
                .chartYAxisLabel(metric.unit)
                .font(.caption2)
                .frame(height: 110)
            }
        }
    }
}
