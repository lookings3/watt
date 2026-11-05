import SwiftUI

/// Power view that shows the flow with thick bands.
struct PowerBandsView: View {
    let snapshot: BatterySnapshot

    private struct Tile: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let color: Color
    }
    private struct Band: Identifiable {
        let id = UUID()
        let watts: Double
        let color: Color
    }

    private var charger: Tile { Tile(id: "charger", symbol: "powerplug.fill", title: snapshot.adapterWatts.map { "\($0) W" } ?? L("충전기", "Charger", "Netzteil", "充電器"), color: .primary) }
    private var mac: Tile { Tile(id: "mac", symbol: "laptopcomputer", title: L("맥", "Mac", "Mac", "Mac"), color: .primary) }
    private var battery: Tile {
        Tile(id: "battery", symbol: snapshot.isCharging ? "battery.100percent.bolt" : "battery.75percent",
             title: "\(snapshot.percent)%", color: snapshot.isCharging ? .green : .primary)
    }

    private var routes: (left: [Tile], bands: [Band], right: [Tile]) {
        let f = snapshot.flow
        if !snapshot.isExternal {
            return ([battery], [Band(watts: f.toMacFromBattery, color: .gray)], [mac])
        }
        if f.toMacFromBattery > 0 {
            return ([charger, battery],
                    [Band(watts: f.toMacFromAdapter, color: .gray), Band(watts: f.toMacFromBattery, color: .gray)], [mac])
        }
        if f.toBatteryFromAdapter > 0 {
            return ([charger], [Band(watts: f.toMacFromAdapter, color: .gray), Band(watts: f.toBatteryFromAdapter, color: .green)], [mac, battery])
        }
        return ([charger], [Band(watts: f.toMacFromAdapter, color: .gray)], [mac])
    }

    private var statusLabel: (text: String, color: Color) {
        let f = snapshot.flow
        if snapshot.isMeasuring { return (L("측정 중", "Measuring", "Wird gemessen", "測定中"), .secondary) }
        if !snapshot.isExternal { return (L("방전 중", "Discharging", "Entlädt", "放電中"), .secondary) }
        if f.toMacFromBattery > 0 { return (L("충전 중 소모", "Draining while plugged in", "Entlädt trotz Netzteil", "接続中も消費"), .orange) }
        if snapshot.isCharging { return (L("충전 중", "Charging", "Lädt", "充電中"), .green) }
        return (L("전원 사용", "On power adapter", "Netzbetrieb", "電源使用中"), .secondary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            flow
            Text(snapshot.flowText).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let rated = snapshot.adapterWatts {
                HStack {
                    Label(L("충전기", "Charger", "Netzteil", "充電器"), systemImage: "powerplug.fill").foregroundStyle(.secondary)
                    Spacer()
                    Text(snapshot.inputWatts.map { String(format: "%.1f / %d W", $0, rated) } ?? "\(rated) W")
                        .monospacedDigit()
                }
                .font(.callout)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                number(L("전력 사용량", "Power usage", "Stromverbrauch", "消費電力"), snapshot.isMeasuring ? L("측정 중", "Measuring", "Wird gemessen", "測定中") : String(format: "%.1f W", snapshot.flow.macWatts))
                number(L("전류", "Current", "Stromstärke", "電流"), snapshot.isMeasuring ? L("측정 중", "Measuring", "Wird gemessen", "測定中") : String(format: "%.0f mA", abs(snapshot.amps) * 1000))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                number(L("전압", "Voltage", "Spannung", "電圧"), String(format: "%.2f V", snapshot.volts), trailing: true)
                Text(statusLabel.text).font(.callout.weight(.semibold)).foregroundStyle(statusLabel.color)
            }
        }
    }

    private func number(_ title: String, _ value: String, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 0) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 19, weight: .bold, design: .monospaced))
        }
    }

    private var flow: some View {
        let r = routes
        return GeometryReader { geo in
            let gap: CGFloat = 6
            let side: CGFloat = 60
            let total = geo.size.height
            let usable = total - gap
            let watts = r.bands.map(\.watts)
            let thick = proportional(watts, usable: usable)
            let even = [usable / 2, usable / 2]
            // The side with one tile splits by power share. The other side lines up with its tiles.
            let leftEnds = r.bands.count == 1 ? [total] : (r.left.count == 1 ? thick : even)
            let rightEnds = r.bands.count == 1 ? [total] : (r.right.count == 1 ? thick : even)
            let leftSlots = slots(leftEnds, gap: gap)
            let rightSlots = slots(rightEnds, gap: gap)
            let width = geo.size.width - 2 * (side + gap)

            HStack(spacing: gap) {
                column(r.left, heights: r.left.count == 1 ? [total] : even, width: side, gap: gap)
                ZStack(alignment: .topLeading) {
                    ForEach(Array(r.bands.enumerated()), id: \.offset) { i, band in
                        let shape = FlowBandShape(leftTop: leftSlots[i].top, leftBottom: leftSlots[i].bottom,
                                                  rightTop: rightSlots[i].top, rightBottom: rightSlots[i].bottom)
                        shape.fill(band.color.opacity(0.16))
                        shape.stroke(Color.primary.opacity(0.14), lineWidth: 0.5)
                        Text(snapshot.isMeasuring ? L("측정 중", "Measuring", "Wird gemessen", "測定中") : String(format: "%.1f W", band.watts))
                            .font(.system(size: 15, weight: .bold)).monospacedDigit()
                            .foregroundStyle(snapshot.isMeasuring ? Color.secondary : Color.primary)
                            .position(x: width / 2,
                                      y: (leftSlots[i].top + leftSlots[i].bottom + rightSlots[i].top + rightSlots[i].bottom) / 4)
                    }
                }
                .frame(width: width, height: total)
                .animation(.easeInOut(duration: 0.5), value: watts)
                column(r.right, heights: r.right.count == 1 ? [total] : even, width: side, gap: gap)
            }
        }
        .frame(height: 132)
    }

    /// Splits by power share, keeping a minimum thickness so the number fits.
    private func proportional(_ watts: [Double], usable: CGFloat) -> [CGFloat] {
        guard watts.count == 2 else { return [usable] }
        let minimum: CGFloat = 32
        let share = CGFloat(watts[0] / max(watts[0] + watts[1], 0.1))
        let first = min(max(usable * share, minimum), usable - minimum)
        return [first, usable - first]
    }

    private func slots(_ heights: [CGFloat], gap: CGFloat) -> [(top: CGFloat, bottom: CGFloat)] {
        var y: CGFloat = 0
        return heights.map { h in
            defer { y += h + gap }
            return (y, y + h)
        }
    }

    private func column(_ tiles: [Tile], heights: [CGFloat], width: CGFloat, gap: CGFloat) -> some View {
        VStack(spacing: gap) {
            ForEach(Array(tiles.enumerated()), id: \.element.id) { i, tile in
                VStack(spacing: 3) {
                    Image(systemName: tile.symbol).font(.system(size: 17))
                    Text(tile.title).font(.system(size: 11, weight: .semibold)).monospacedDigit().lineLimit(1)
                }
                .foregroundStyle(tile.color)
                .frame(width: width, height: heights[min(i, heights.count - 1)])
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
            }
        }
    }
}

/// A power band that curves when its left and right ends differ. The shape changes only when values change.
private struct FlowBandShape: Shape {
    var leftTop: CGFloat
    var leftBottom: CGFloat
    var rightTop: CGFloat
    var rightBottom: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(.init(leftTop, leftBottom), .init(rightTop, rightBottom)) }
        set {
            leftTop = newValue.first.first; leftBottom = newValue.first.second
            rightTop = newValue.second.first; rightBottom = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width, mid = w / 2
        let c: CGFloat = 12
        var p = Path()
        p.move(to: CGPoint(x: c, y: leftTop))
        p.addCurve(to: CGPoint(x: w - c, y: rightTop), control1: CGPoint(x: mid, y: leftTop), control2: CGPoint(x: mid, y: rightTop))
        p.addQuadCurve(to: CGPoint(x: w, y: rightTop + c), control: CGPoint(x: w, y: rightTop))
        p.addLine(to: CGPoint(x: w, y: rightBottom - c))
        p.addQuadCurve(to: CGPoint(x: w - c, y: rightBottom), control: CGPoint(x: w, y: rightBottom))
        p.addCurve(to: CGPoint(x: c, y: leftBottom), control1: CGPoint(x: mid, y: rightBottom), control2: CGPoint(x: mid, y: leftBottom))
        p.addQuadCurve(to: CGPoint(x: 0, y: leftBottom - c), control: CGPoint(x: 0, y: leftBottom))
        p.addLine(to: CGPoint(x: 0, y: leftTop + c))
        p.addQuadCurve(to: CGPoint(x: c, y: leftTop), control: CGPoint(x: 0, y: leftTop))
        p.closeSubpath()
        return p
    }
}
