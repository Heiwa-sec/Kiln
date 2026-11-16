import SwiftUI
import KilnCore

struct Wedge: Shape {
    var center: CGPoint
    var inner: Double, outer: Double, start: Double, end: Double   // degrees clockwise from top
    func path(in rect: CGRect) -> Path {
        let c = center
        func pt(_ r: Double, _ deg: Double) -> CGPoint {
            let a = (deg - 90) * .pi / 180
            return CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
        }
        var p = Path()
        p.move(to: pt(inner, start))
        p.addLine(to: pt(outer, start))
        p.addArc(center: c, radius: outer, startAngle: .degrees(start - 90), endAngle: .degrees(end - 90), clockwise: false)
        p.addLine(to: pt(inner, end))
        p.addArc(center: c, radius: inner, startAngle: .degrees(end - 90), endAngle: .degrees(start - 90), clockwise: true)
        p.closeSubpath()
        return p
    }
}

struct WheelView: View {
    @ObservedObject var model: WheelModel
    private let gap = 1.6   // degrees of empty space between wedges

    var body: some View {
        let c = model.center
        return ZStack {
            ring(nodes: model.outer, from: model.geometry.outerFrom, to: model.geometry.outerTo, center: c, isOuter: true)
            ring(nodes: model.inner, from: model.geometry.innerFrom, to: model.geometry.innerTo, center: c, isOuter: false)
            hub.position(c)
        }
    }

    private var hub: some View {
        let g = model.geometry
        return ZStack {
            Circle().fill(Palette.surface).frame(width: g.innerFrom * 2 - 8, height: g.innerFrom * 2 - 8)
            VStack(spacing: 2) {
                Text(model.hoveredNode?.title ?? model.hubTitle).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                Text(model.wheel.title).font(.system(size: 10)).foregroundStyle(Palette.textDim)
            }
            .multilineTextAlignment(.center).foregroundStyle(Palette.text).frame(width: g.innerFrom * 2 - 22)
        }
    }

    @ViewBuilder
    private func ring(nodes: [WheelNode], from: Double, to: Double, center c: CGPoint, isOuter: Bool) -> some View {
        let n = nodes.count
        ForEach(Array(nodes.enumerated()), id: \.element.id) { i, node in
            let hovered = model.zone == (isOuter ? .outer(i) : .inner(i))
            let open = !isOuter && model.activeGroup == i
            let lit = hovered && node.runnable
            let s = WheelGeometry.startAngle(i, of: n) + gap / 2, e = WheelGeometry.startAngle(i, of: n) + WheelGeometry.span(n) - gap / 2
            let w = Wedge(center: c, inner: from, outer: to, start: s, end: n == 1 ? s + 360 - gap : e)
            w.fill(lit ? Palette.accent : (open || hovered ? Palette.ringEdge : Palette.ring))
                .overlay { w.stroke(Palette.ringEdge, lineWidth: 1) }
            label(node, lit: lit).position(labelPoint(c, i, n, (from + to) / 2))
        }
    }

    private func label(_ node: WheelNode, lit: Bool) -> some View {
        VStack(spacing: 2) {
            Image(systemName: node.symbol).font(.system(size: 12))
            Text(node.title).font(.system(size: 11, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(lit ? Palette.onAccent : (node.runnable || !node.children.isEmpty ? Palette.text : Palette.textDim))
        .frame(width: 66)
        .allowsHitTesting(false)
    }

    private func labelPoint(_ c: CGPoint, _ i: Int, _ n: Int, _ r: Double) -> CGPoint {
        let a = (WheelGeometry.midAngle(i, of: n) - 90) * .pi / 180
        return CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
    }
}

extension WheelID {
    var title: String {
        switch self { case .convert: "Convert"; case .tools: "Tools"; case .actions: "Actions" }
    }
}
