import SwiftUI

// Port of ui/Board.kt — the interactive chess board.

private let LAST = Color(red: 0xE0 / 255, green: 0xAD / 255, blue: 0x4F / 255).opacity(0.42)
private let SEL = Color(red: 0xF5 / 255, green: 0xCF / 255, blue: 0x7E / 255).opacity(0.55)
private let HINT = Color(red: 0x5F / 255, green: 0xB3 / 255, blue: 0x6A / 255).opacity(0.6)
private let CHECK = Color(red: 0xD9 / 255, green: 0x58 / 255, blue: 0x4A / 255).opacity(0.8)
private let MARK = Color(red: 0x28 / 255, green: 0x1E / 255, blue: 0x14 / 255).opacity(0.32)
private let FRAME = Color(red: 0x3B / 255, green: 0x2B / 255, blue: 0x1D / 255)

extension Color {
    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
    }
}

private func screenXY(_ sq: Int, _ flip: Bool) -> (x: Int, y: Int) {
    var r = sq >> 3, f = sq & 7
    if flip { r = 7 - r; f = 7 - f }
    return (f, r)
}

struct ChessBoardView<C: ObservableObject & BoardDisplaying>: View {
    @ObservedObject var c: C
    @State private var shakeX: CGFloat = 0
    @State private var lastShake = 0

    var body: some View {
        GeometryReader { geo in
                        let side = min(geo.size.width, geo.size.height)
                        let cell = side / 8

                        ZStack {
                            Canvas { context, _ in
                                    let light = Color(rgb: c.boardTheme.light & 0xFFFFFF)
                                    let dark = Color(rgb: c.boardTheme.dark & 0xFFFFFF)
                                    for sq in 0..<64 {
                                        let (x, y) = screenXY(sq, c.flip)
                                        let rect = CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell)
                                        context.fill(Path(rect), with: .color((x + y) % 2 == 0 ? light : dark))
                                        if sq == c.lastFrom || sq == c.lastTo { context.fill(Path(rect), with: .color(LAST)) }
                                        if sq == c.selected { context.fill(Path(rect), with: .color(SEL)) }
                                        if sq == c.hintSq { context.fill(Path(rect), with: .color(HINT)) }
                                        if sq == c.checkSq {
                                            let r = cell * 0.48
                                            context.fill(Path(ellipseIn: CGRect(x: rect.midX - r, y: rect.midY - r, width: r * 2, height: r * 2)), with: .color(CHECK))
                                        }
                                        if c.targets.contains(sq) {
                                            let center = CGPoint(x: rect.midX, y: rect.midY)
                                            if c.isCaptureTarget(sq) {
                                                let r = cell * 0.44
                                                context.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)), with: .color(MARK), lineWidth: cell * 0.08)
                                            } else {
                                                let r = cell * 0.13
                                                context.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)), with: .color(MARK))
                                            }
                                        }
                                        if x == 0 {
                                            let label = "\(8 - (sq >> 3))"
                                            context.draw(Text(label).font(.system(size: cell * 0.16, weight: .bold)).foregroundColor((x + y) % 2 == 0 ? dark : light), at: CGPoint(x: rect.minX + cell * 0.1, y: rect.minY + cell * 0.12), anchor: .topLeading)
                                        }
                                        if y == 7 {
                                            let label = String(Array("abcdefgh")[sq & 7])
                                            context.draw(Text(label).font(.system(size: cell * 0.16, weight: .bold)).foregroundColor((x + y) % 2 == 0 ? dark : light), at: CGPoint(x: rect.maxX - cell * 0.12, y: rect.maxY - cell * 0.14), anchor: .bottomTrailing)
                                        }
                                    }
                                   }
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(FRAME, lineWidth: 4))

                            ForEach(c.pieces) { p in
                                               let (x, y) = screenXY(p.sq, c.flip)
                                               Canvas { context, _ in context.drawPiece(p.piece, side: cell) }
                                               .frame(width: cell, height: cell)
                                               .position(x: CGFloat(x) * cell + cell / 2, y: CGFloat(y) * cell + cell / 2)
                                               .animation(.easeOut(duration: 0.22), value: p.sq)
                                              }
                        }
                        .frame(width: side, height: side)
                        .offset(x: shakeX)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0).onEnded { value in
                                                                     let fx = min(7, max(0, Int(value.location.x / cell)))
                                                                     let fy = min(7, max(0, Int(value.location.y / cell)))
                                                                     let sq = c.flip ? (7 - fy) * 8 + (7 - fx) : fy * 8 + fx
                                                                     c.tapSquare(sq)
                                                                    }
                        )
                        .onChange(of: c.shake) { newValue in
                                                guard newValue != lastShake else { return }
                                                lastShake = newValue
                                                let seq: [CGFloat] = [-14, 14, -10, 10, 0]
                                                for (i, v) in seq.enumerated() {
                                                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.05) {
                                                        withAnimation(.easeInOut(duration: 0.05)) { shakeX = v }
                                                    }
                                                }
                                               }
                       }
        .aspectRatio(1, contentMode: .fit)
        .environment(\.layoutDirection, .leftToRight)
    }
}
