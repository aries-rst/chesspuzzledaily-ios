import Foundation

// Port of Chess.kt (itself a port of js/chess.js, perft-verified).
// Board index 0..63, a8 = 0 ... h1 = 63.

let EMPTY: Character = "."
private let FILES = Array("abcdefgh")

func sqName(_ i: Int) -> String { "\(FILES[i & 7])\(8 - (i >> 3))" }
func sqIndex(_ s: String) -> Int {
    let chars = Array(s)
    let file = FILES.firstIndex(of: chars[0]) ?? 0
    let rank = Int(String(chars[1]))!
    return (8 - rank) * 8 + file
}
func isWhitePiece(_ p: Character) -> Bool { p != EMPTY && p.isUppercase }
func colorOf(_ p: Character) -> Character { p == EMPTY ? " " : (p.isUppercase ? "w" : "b") }

struct Move: Equatable {
    var from: Int
    var to: Int
    var promo: Character? = nil          // lowercase q r b n
    var castle: Character? = nil         // 'K' or 'Q'
    var captured: Character = EMPTY
    var epCapture: Int = -1
    var rookFrom: Int = -1
    var rookTo: Int = -1
    var san: String = ""

    func uci() -> String { sqName(from) + sqName(to) + (promo.map { String($0) } ?? "") }
}

private let KN: [(Int, Int)] = [(-2, -1), (-2, 1), (-1, -2), (-1, 2), (1, -2), (1, 2), (2, -1), (2, 1)]
private let KG: [(Int, Int)] = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]
private let DIAG: [(Int, Int)] = [(-1, -1), (-1, 1), (1, -1), (1, 1)]
private let ORTH: [(Int, Int)] = [(-1, 0), (1, 0), (0, -1), (0, 1)]

final class Position {
    var board: [Character]
    var turn: Character
    var castle: String
    var ep: Int
    var half: Int
    var full: Int

    private init(board: [Character], turn: Character, castle: String, ep: Int, half: Int, full: Int) {
        self.board = board; self.turn = turn; self.castle = castle; self.ep = ep; self.half = half; self.full = full
    }

    static func fromFen(_ fen: String) -> Position {
        let parts = fen.trimmingCharacters(in: .whitespaces).split(separator: " ").map(String.init)
        var b = [Character](repeating: EMPTY, count: 64)
        var i = 0
        for ch in parts[0] {
            if ch == "/" { continue }
            if let d = ch.wholeNumberValue, ch.isNumber { i += d; continue }
            b[i] = ch; i += 1
        }
        let castle = (parts.count > 2 && parts[2] != "-") ? parts[2] : ""
        let ep = (parts.count > 3 && parts[3] != "-") ? sqIndex(parts[3]) : -1
        let turn: Character = (parts.count > 1 ? parts[1].first : nil) ?? "w"
        let half = (parts.count > 4 ? Int(parts[4]) : nil) ?? 0
        let full = (parts.count > 5 ? Int(parts[5]) : nil) ?? 1
        return Position(board: b, turn: turn, castle: castle, ep: ep, half: half, full: full)
    }

    func clone() -> Position { Position(board: board, turn: turn, castle: castle, ep: ep, half: half, full: full) }

    func fen() -> String {
        var rows: [String] = []
        for r in 0..<8 {
            var s = ""; var e = 0
            for f in 0..<8 {
                let p = board[r * 8 + f]
                if p == EMPTY { e += 1 } else { if e > 0 { s += "\(e)"; e = 0 }; s.append(p) }
            }
            if e > 0 { s += "\(e)" }
            rows.append(s)
        }
        let castleStr = castle.isEmpty ? "-" : castle
        let epStr = ep >= 0 ? sqName(ep) : "-"
        return "\(rows.joined(separator: "/")) \(turn) \(castleStr) \(epStr) \(half) \(full)"
    }

    func kingSq(_ color: Character) -> Int { board.firstIndex(of: color == "w" ? "K" : "k") ?? -1 }

    func attacked(_ sq: Int, by: Character) -> Bool {
        let r = sq >> 3, f = sq & 7
        func own(_ p: Character) -> Bool { p != EMPTY && colorOf(p) == by }
        let pr = by == "w" ? r + 1 : r - 1
        let pawn: Character = by == "w" ? "P" : "p"
        for df in [-1, 1] {
            let ff = f + df
            if (0...7).contains(pr) && (0...7).contains(ff) && board[pr * 8 + ff] == pawn { return true }
        }
        for d in KN {
            let rr = r + d.0, ff = f + d.1
            if (0...7).contains(rr) && (0...7).contains(ff) {
                let p = board[rr * 8 + ff]
                if own(p) && p.uppercased() == "N" { return true }
            }
        }
        for d in KG {
            let rr = r + d.0, ff = f + d.1
            if (0...7).contains(rr) && (0...7).contains(ff) {
                let p = board[rr * 8 + ff]
                if own(p) && p.uppercased() == "K" { return true }
            }
        }
        func slide(_ dirs: [(Int, Int)], _ types: String) -> Bool {
            for d in dirs {
                var rr = r + d.0, ff = f + d.1
                while (0...7).contains(rr) && (0...7).contains(ff) {
                    let p = board[rr * 8 + ff]
                    if p != EMPTY {
                        if own(p) && types.contains(Character(p.uppercased())) { return true }
                        break
                    }
                    rr += d.0; ff += d.1
                }
            }
            return false
        }
        return slide(DIAG, "BQ") || slide(ORTH, "RQ")
    }

    func inCheck(_ color: Character? = nil) -> Bool {
        let c = color ?? turn
        return attacked(kingSq(c), by: c == "w" ? "b" : "w")
    }

    func pseudoMoves() -> [Move] {
        var moves: [Move] = []
        moves.reserveCapacity(48)
        let me = turn, opp: Character = me == "w" ? "b" : "w"
        func add(_ from: Int, _ to: Int, _ promo: Bool) {
            if promo { for q in "qrbn" { moves.append(Move(from: from, to: to, promo: q)) } }
            else { moves.append(Move(from: from, to: to)) }
        }
        for sq in 0..<64 {
            let p = board[sq]
            if p == EMPTY || colorOf(p) != me { continue }
            let t = Character(p.uppercased()); let r = sq >> 3, f = sq & 7
            switch t {
            case "P":
                let dir = me == "w" ? -1 : 1
                let start = me == "w" ? 6 : 1
                let last = me == "w" ? 0 : 7
                let r1 = r + dir
                if (0...7).contains(r1) && board[r1 * 8 + f] == EMPTY {
                    add(sq, r1 * 8 + f, r1 == last)
                    let r2 = r + 2 * dir
                    if r == start && board[r2 * 8 + f] == EMPTY { add(sq, r2 * 8 + f, false) }
                }
                for df in [-1, 1] {
                    let ff = f + df
                    if !(0...7).contains(ff) || !(0...7).contains(r1) { continue }
                    let to = r1 * 8 + ff; let q = board[to]
                    if (q != EMPTY && colorOf(q) == opp) || to == ep { add(sq, to, r1 == last) }
                }
            case "N", "K":
                for d in (t == "N" ? KN : KG) {
                    let rr = r + d.0, ff = f + d.1
                    if !(0...7).contains(rr) || !(0...7).contains(ff) { continue }
                    let q = board[rr * 8 + ff]
                    if q == EMPTY || colorOf(q) == opp { add(sq, rr * 8 + ff, false) }
                }
                if t == "K" {
                    let row = me == "w" ? 7 : 0
                    let home = row * 8 + 4
                    let rook: Character = me == "w" ? "R" : "r"
                    if sq == home && !attacked(home, by: opp) {
                        let kc: Character = me == "w" ? "K" : "k"
                        let qc: Character = me == "w" ? "Q" : "q"
                        if castle.contains(kc) && board[home + 1] == EMPTY && board[home + 2] == EMPTY && board[home + 3] == rook &&
                            !attacked(home + 1, by: opp) && !attacked(home + 2, by: opp) {
                            moves.append(Move(from: sq, to: home + 2, castle: "K"))
                        }
                        if castle.contains(qc) && board[home - 1] == EMPTY && board[home - 2] == EMPTY && board[home - 3] == EMPTY &&
                            board[home - 4] == rook && !attacked(home - 1, by: opp) && !attacked(home - 2, by: opp) {
                            moves.append(Move(from: sq, to: home - 2, castle: "Q"))
                        }
                    }
                }
            default:
                let dirs = t == "B" ? DIAG : (t == "R" ? ORTH : DIAG + ORTH)
                for d in dirs {
                    var rr = r + d.0, ff = f + d.1
                    while (0...7).contains(rr) && (0...7).contains(ff) {
                        let q = board[rr * 8 + ff]
                        if q == EMPTY { add(sq, rr * 8 + ff, false) }
                        else { if colorOf(q) == opp { add(sq, rr * 8 + ff, false) }; break }
                        rr += d.0; ff += d.1
                    }
                }
            }
        }
        return moves
    }

    /// Applies the move in place (no legality check) and fills in capture/castle details on the move.
    @discardableResult
    func apply(_ m: inout Move) -> Move {
        let p = board[m.from]; let t = Character(p.uppercased()); let me = turn
        var captured = board[m.to]
        if t == "P" && m.to == ep && captured == EMPTY {
            let capSq = m.to + (me == "w" ? 8 : -8)
            captured = board[capSq]; board[capSq] = EMPTY; m.epCapture = capSq
        }
        if let promo = m.promo {
            board[m.to] = me == "w" ? Character(promo.uppercased()) : promo
        } else {
            board[m.to] = p
        }
        board[m.from] = EMPTY
        if t == "K" && abs(m.to - m.from) == 2 {
            let rFrom = m.to > m.from ? m.from + 3 : m.from - 4
            let rTo = m.to > m.from ? m.from + 1 : m.from - 1
            board[rTo] = board[rFrom]; board[rFrom] = EMPTY
            m.castle = m.to > m.from ? "K" : "Q"; m.rookFrom = rFrom; m.rookTo = rTo
        }
        func strip(_ c: Character) { castle = castle.filter { $0 != c } }
        if t == "K" { if me == "w" { strip("K"); strip("Q") } else { strip("k"); strip("q") } }
        for (sq, c): (Int, Character) in [(63, "K"), (56, "Q"), (7, "k"), (0, "q")] {
            if m.from == sq || m.to == sq { strip(c) }
        }
        ep = (t == "P" && abs(m.to - m.from) == 16) ? (m.from + m.to) / 2 : -1
        half = (t == "P" || captured != EMPTY) ? 0 : half + 1
        if me == "b" { full += 1 }
        turn = me == "w" ? "b" : "w"
        m.captured = captured
        return m
    }

    func legalMoves() -> [Move] {
        pseudoMoves().filter { m in
            let c = clone(); var mm = m; c.apply(&mm); return !c.inCheck(turn)
        }
    }

    func isCheckmate() -> Bool { inCheck() && legalMoves().isEmpty }

    func moveFromUci(_ uci: String) -> Move? {
        let chars = Array(uci)
        let from = sqIndex(String(chars[0...1])); let to = sqIndex(String(chars[2...3]))
        let promo: Character? = chars.count > 4 ? chars[4] : nil
        return legalMoves().first { $0.from == from && $0.to == to && $0.promo == promo }
    }

    /// Standard algebraic notation of a legal move (call before applying it).
    func san(_ m: Move) -> String {
        let p = board[m.from]; let t = Character(p.uppercased())
        let isCastle = t == "K" && abs(m.to - m.from) == 2
        var s: String
        if isCastle {
            s = m.to > m.from ? "O-O" : "O-O-O"
        } else {
            let cap = board[m.to] != EMPTY || (t == "P" && m.to == ep)
            if t == "P" {
                s = (cap ? "\(FILES[m.from & 7])x" : "") + sqName(m.to) + (m.promo.map { "=\($0.uppercased())" } ?? "")
            } else {
                let others = legalMoves().filter { $0.to == m.to && $0.from != m.from && board[$0.from] == p }
                var dis = ""
                if !others.isEmpty {
                    let sameFile = others.contains { ($0.from & 7) == (m.from & 7) }
                    let sameRank = others.contains { ($0.from >> 3) == (m.from >> 3) }
                    if !sameFile { dis = String(FILES[m.from & 7]) }
                    else if !sameRank { dis = "\(8 - (m.from >> 3))" }
                    else { dis = sqName(m.from) }
                }
                s = String(t) + dis + (cap ? "x" : "") + sqName(m.to)
            }
        }
        let c = clone(); var mm = m; c.apply(&mm)
        if c.inCheck() { s += c.legalMoves().isEmpty ? "#" : "+" }
        return s
    }
}
