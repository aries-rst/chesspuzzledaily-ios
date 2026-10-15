import SwiftUI

// Port of ui/Pieces.kt — original geometric piece set (same shapes as js/pieces.js),
// drawn on a 100x100 grid from hand-written SVG path data.

/// Minimal SVG path-data parser — just enough for the piece shapes below
/// (M/L/H/V/C/A/Z, absolute and relative, implicit command repeats). Produces a SwiftUI `Path`.
enum SVGPath {
    static func parse(_ d: String) -> Path {
        var path = Path()
        var current = CGPoint.zero
        var start = CGPoint.zero
        var lastCommand: Character = " "
        let tokens = tokenize(d)
        var i = 0
        func num() -> CGFloat { defer { i += 1 }; return i < tokens.count ? CGFloat(Double(tokens[i]) ?? 0) : 0 }

        while i < tokens.count {
            var cmd: Character
            if let f = tokens[i].first, tokens[i].count == 1, "MmLlHhVvCcSsQqTtAaZz".contains(f) {
                cmd = f; i += 1
            } else {
                // implicit repeat of the previous command (a bare M/m repeat is an L/l)
                cmd = lastCommand == "M" ? "L" : (lastCommand == "m" ? "l" : lastCommand)
            }
            switch cmd {
            case "M":
                current = CGPoint(x: num(), y: num()); start = current; path.move(to: current)
            case "m":
                current = CGPoint(x: current.x + num(), y: current.y + num()); start = current; path.move(to: current)
            case "L":
                current = CGPoint(x: num(), y: num()); path.addLine(to: current)
            case "l":
                current = CGPoint(x: current.x + num(), y: current.y + num()); path.addLine(to: current)
            case "H":
                current = CGPoint(x: num(), y: current.y); path.addLine(to: current)
            case "h":
                current = CGPoint(x: current.x + num(), y: current.y); path.addLine(to: current)
            case "V":
                current = CGPoint(x: current.x, y: num()); path.addLine(to: current)
            case "v":
                current = CGPoint(x: current.x, y: current.y + num()); path.addLine(to: current)
            case "C":
                let c1 = CGPoint(x: num(), y: num()); let c2 = CGPoint(x: num(), y: num()); let end = CGPoint(x: num(), y: num())
                path.addCurve(to: end, control1: c1, control2: c2); current = end
            case "c":
                let c1 = CGPoint(x: current.x + num(), y: current.y + num())
                let c2 = CGPoint(x: current.x + num(), y: current.y + num())
                let end = CGPoint(x: current.x + num(), y: current.y + num())
                path.addCurve(to: end, control1: c1, control2: c2); current = end
            case "A", "a":
                let rx = num(), ry = num(), rot = num()
                let laf = num() != 0, sf = num() != 0
                let end = cmd == "A" ? CGPoint(x: num(), y: num()) : CGPoint(x: current.x + num(), y: current.y + num())
                arcTo(&path, from: current, to: end, rx: rx, ry: ry, rotationDeg: rot, largeArc: laf, sweep: sf)
                current = end
            case "Z", "z":
                path.closeSubpath(); current = start
            default:
                i += 1
            }
            lastCommand = cmd
        }
        return path
    }

    private static func tokenize(_ d: String) -> [String] {
        var tokens: [String] = []; var num = ""
        func flush() { if !num.isEmpty { tokens.append(num); num = "" } }
        for ch in d {
            if "MmLlHhVvCcSsQqTtAaZz".contains(ch) { flush(); tokens.append(String(ch)) }
            else if ch == "," || ch == " " || ch == "\n" || ch == "\t" { flush() }
            else if ch == "-" { flush(); num.append(ch) }
            else { num.append(ch) }
        }
        flush()
        return tokens
    }

    /// Endpoint-to-center arc converted to cubic Bézier segments (W3C SVG implementation notes).
    private static func arcTo(_ path: inout Path, from p0: CGPoint, to p1: CGPoint, rx rxIn: CGFloat, ry ryIn: CGFloat,
                               rotationDeg: CGFloat, largeArc: Bool, sweep: Bool) {
        if p0 == p1 { return }
        var rx = abs(rxIn), ry = abs(ryIn)
        if rx == 0 || ry == 0 { path.addLine(to: p1); return }
        let phi = rotationDeg * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx2 = (p0.x - p1.x) / 2, dy2 = (p0.y - p1.y) / 2
        let x1p = cosPhi * dx2 + sinPhi * dy2
        let y1p = -sinPhi * dx2 + cosPhi * dy2
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 { let s = lambda.squareRoot(); rx *= s; ry *= s }
        let sign: CGFloat = (largeArc != sweep) ? 1 : -1
        let num = max(0, rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p)
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        let co = den == 0 ? 0 : sign * (num / den).squareRoot()
        let cxp = co * (rx * y1p) / ry
        let cyp = co * -(ry * x1p) / rx
        let cx = cosPhi * cxp - sinPhi * cyp + (p0.x + p1.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p0.y + p1.y) / 2

        func angleBetween(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let len = (ux * ux + uy * uy).squareRoot() * (vx * vx + vy * vy).squareRoot()
            var a = acos(max(-1, min(1, len == 0 ? 1 : dot / len)))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }
        let theta1 = angleBetween(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var dtheta = angleBetween((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && dtheta > 0 { dtheta -= 2 * .pi }
        if sweep && dtheta < 0 { dtheta += 2 * .pi }

        let segments = max(1, Int(ceil(abs(dtheta) / (.pi / 2))))
        let delta = dtheta / CGFloat(segments)
        let t = 4.0 / 3.0 * tan(delta / 4)
        func ellipsePoint(_ a: CGFloat) -> CGPoint {
            let ex = rx * cos(a), ey = ry * sin(a)
            return CGPoint(x: cosPhi * ex - sinPhi * ey + cx, y: sinPhi * ex + cosPhi * ey + cy)
        }
        func ellipseDeriv(_ a: CGFloat) -> CGPoint {
            let ex = -rx * sin(a), ey = ry * cos(a)
            return CGPoint(x: cosPhi * ex - sinPhi * ey, y: sinPhi * ex + cosPhi * ey)
        }
        var angle1 = theta1
        for _ in 0..<segments {
            let angle2 = angle1 + delta
            let s = ellipsePoint(angle1), e = ellipsePoint(angle2)
            let d1 = ellipseDeriv(angle1), d2 = ellipseDeriv(angle2)
            let c1 = CGPoint(x: s.x + t * d1.x, y: s.y + t * d1.y)
            let c2 = CGPoint(x: e.x - t * d2.x, y: e.y - t * d2.y)
            path.addCurve(to: e, control1: c1, control2: c2)
            angle1 = angle2
        }
    }
}

private struct PieceShape {
    let paths: [String]
    var circles: [(CGFloat, CGFloat, CGFloat)] = []
    var eye: (CGFloat, CGFloat, CGFloat)? = nil
    var cut: String? = nil
}

private let BASE = "M22 86h56a4 4 0 0 1 4 4v2H18v-2a4 4 0 0 1 4-4z"

private let SHAPES: [Character: PieceShape] = [
    "P": PieceShape(paths: [BASE, "M34 84c2-12 7-20 10-24h12c3 4 8 12 10 24z", "M38 60h24a3 3 0 0 0 0-6H38a3 3 0 0 0 0 6z"],
                     circles: [(50, 40, 13)]),
    "R": PieceShape(paths: [BASE, "M30 84l3-34h34l3 34z", "M28 50h44v-6H28z", "M28 44V22h9v8h8v-8h10v8h8v-8h9v22z"]),
    "N": PieceShape(paths: [BASE, "M30 84c0-14 6-22 14-30-8 2-14 4-18 0-4-5 0-10 6-16 6-7 10-14 12-20 2 4 3 6 2 9 10 0 20 6 25 18 5 13 2 28 0 39z"],
                     eye: (44, 32, 3)),
    "B": PieceShape(paths: [BASE, "M33 84c2-9 6-14 9-17h16c3 3 7 8 9 17z", "M36 67h28a3 3 0 0 0 0-6H36a3 3 0 0 0 0 6z",
                             "M50 14c11 9 17 19 17 28 0 9-7 16-17 17-10-1-17-8-17-17 0-9 6-19 17-28z"],
                     circles: [(50, 11, 4)], cut: "M55 28l-9 12"),
    "Q": PieceShape(paths: [BASE, "M30 84l4-16h32l4 16z", "M32 68h36l6-40-13 18-11-24-11 24-13-18z"],
                     circles: [(26, 26, 5), (38, 18, 5), (50, 14, 5), (62, 18, 5), (74, 26, 5)]),
    "K": PieceShape(paths: [BASE, "M30 84l4-16h32l4 16z",
                             "M32 68h36c4-10 8-18 8-24 0-8-8-12-16-8-4 2-7 6-10 10-3-4-6-8-10-10-8-4-16 0-16 8 0 6 4 14 8 24z",
                             "M47 8h6v7h7v6h-7v12h-6V21h-7v-6h7z"]),
]

private let PARSED: [Character: (paths: [Path], cut: Path?)] = SHAPES.mapValues { s in
    (s.paths.map { SVGPath.parse($0) }, s.cut.map { SVGPath.parse($0) })
}

private let WHITE_FILL = Color(red: 0xFB / 255.0, green: 0xF6 / 255.0, blue: 0xEA / 255.0)
private let WHITE_LINE = Color(red: 0x3A / 255.0, green: 0x31 / 255.0, blue: 0x28 / 255.0)
private let BLACK_FILL = Color(red: 0x2B / 255.0, green: 0x26 / 255.0, blue: 0x22 / 255.0)
private let BLACK_LINE = Color(red: 0x0E / 255.0, green: 0x0C / 255.0, blue: 0x0A / 255.0)
private let BLACK_DETAIL = Color(red: 0xE9 / 255.0, green: 0xDC / 255.0, blue: 0xC0 / 255.0)

extension GraphicsContext {
    /// Draws `piece` (e.g. "N" white knight, "q" black queen) to fill a `side`x`side` box
    /// anchored at this context's current origin.
    func drawPiece(_ piece: Character, side: CGFloat) {
        let t = Character(piece.uppercased())
        guard let shape = SHAPES[t], let parsed = PARSED[t] else { return }
        let white = piece.isUppercase
        let fill = white ? WHITE_FILL : BLACK_FILL
        let line = white ? WHITE_LINE : BLACK_LINE
        let detail = white ? WHITE_LINE : BLACK_DETAIL
        let k = side / 100
        let stroke = StrokeStyle(lineWidth: 3, lineJoin: .round)

        var ctx = self
        ctx.scaleBy(x: k, y: k)

        var shadowCtx = ctx
        shadowCtx.translateBy(x: 0, y: 2)
        for p in parsed.paths { shadowCtx.fill(p, with: .color(.black.opacity(0.2))) }

        for p in parsed.paths {
            ctx.fill(p, with: .color(fill))
            ctx.stroke(p, with: .color(line), style: stroke)
        }
        for (x, y, r) in shape.circles {
            let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(fill))
            ctx.stroke(Path(ellipseIn: rect), with: .color(line), style: stroke)
        }
        if let (ex, ey, er) = shape.eye {
            let rect = CGRect(x: ex - er, y: ey - er, width: er * 2, height: er * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(detail))
        }
        if let cutPath = parsed.cut {
            ctx.stroke(cutPath, with: .color(detail), style: StrokeStyle(lineWidth: 3))
        }
    }
}
