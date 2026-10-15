import Foundation

// Port of Core.kt — pure game logic (no UIKit/SwiftUI imports).

struct PuzzleRec: Equatable {
    let id: String
    let fen: String
    let moves: [String]
    let rating: Int
    let themes: String

    var themeList: [String] { themes.split(separator: " ").map(String.init).filter { !$0.isEmpty } }
    /// N for "mateInN" puzzles, 0 otherwise.
    var mateN: Int {
        guard let r = try? NSRegularExpression(pattern: "mateIn(\\d)"),
              let m = r.firstMatch(in: themes, range: NSRange(themes.startIndex..., in: themes)),
              let range = Range(m.range(at: 1), in: themes) else { return 0 }
        return Int(themes[range]) ?? 0
    }
}

final class PuzzleDb {
    let daily: [[PuzzleRec]]
    let train: [PuzzleRec]

    init(daily: [[PuzzleRec]], train: [PuzzleRec]) {
        self.daily = daily; self.train = train
    }

    /// Parses the bundled puzzles.json: {"daily":[[rec...] x7],"train":[rec...]}, rec = [id,fen,moves,rating,themes].
    static func parse(_ data: Data) throws -> PuzzleDb {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dailyRaw = root["daily"] as? [[Any]], let trainRaw = root["train"] as? [Any] else {
            throw NSError(domain: "PuzzleDb", code: 1)
        }
        func rec(_ a: Any) -> PuzzleRec {
            let l = a as! [Any]
            return PuzzleRec(id: l[0] as! String, fen: l[1] as! String,
                              moves: (l[2] as! String).split(separator: " ").map(String.init),
                              rating: (l[3] as! NSNumber).intValue, themes: l[4] as! String)
        }
        let daily = dailyRaw.map { day in day.map(rec) }
        let train = trainRaw.map(rec)
        return PuzzleDb(daily: daily, train: train)
    }
}

enum Calendar0 {
    /// Days since 1970-01-01 for a civil date (proleptic Gregorian). month 1..12.
    static func daysFromCivil(_ y0: Int, _ m: Int, _ d: Int) -> Int {
        let y = m <= 2 ? y0 - 1 : y0
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }
    /// 0 = Monday ... 6 = Sunday.
    static func weekdayMon0(_ days: Int) -> Int { (((days + 3) % 7) + 7) % 7 }
}

enum Daily {
    // Puzzle #1 = 1 Oct 2026 (same as the Android/HTML prototype's EPOCH).
    static let EPOCH_DAYS: Int = Calendar0.daysFromCivil(2026, 10, 1)
    static let ATTEMPTS = 3

    static func numberFor(_ civilDays: Int) -> Int { civilDays - EPOCH_DAYS + 1 }
    static func civilDaysOf(_ n: Int) -> Int { EPOCH_DAYS + n - 1 }
    static func bucketOf(_ n: Int) -> Int { Calendar0.weekdayMon0(civilDaysOf(n)) }
    static func puzzleFor(_ db: PuzzleDb, _ n: Int) -> PuzzleRec {
        let pool = db.daily[bucketOf(n)]
        let idx = ((n - 1) / 7) % pool.count
        return pool[idx >= 0 ? idx : idx + pool.count]
    }
}

enum Elo {
    /// Returns the rating change for the player (rounded, like the prototype).
    static func delta(player: Double, puzzle: Int, games: Int, win: Bool) -> Int {
        let e = 1.0 / (1.0 + pow(10.0, (Double(puzzle) - player) / 400.0))
        let k: Double = games < 30 ? 40 : 20
        return Int((k * ((win ? 1.0 : 0.0) - e)).rounded())
    }
}

enum Training {
    static let AD_EVERY = 5
    static func matches(_ rec: PuzzleRec, _ key: String) -> Bool {
        switch key {
        case "all": return true
        case "mateIn3":
            return (try? NSRegularExpression(pattern: "mateIn[3-9]"))
                .map { $0.firstMatch(in: rec.themes, range: NSRange(rec.themes.startIndex..., in: rec.themes)) != nil } ?? false
        default: return rec.themeList.contains(key)
        }
    }
    static func pick(_ db: PuzzleDb, rating: Double, theme: String, seen: Set<String>) -> PuzzleRec {
        let themed = db.train.filter { matches($0, theme) }
        let fresh = themed.filter { !seen.contains($0.id) }
        let src = !fresh.isEmpty ? fresh : (!themed.isEmpty ? themed : db.train)
        for w in [100, 200, 400, 4000] {
            let c = src.filter { abs($0.rating - Int(rating)) <= w }
            if !c.isEmpty { return c[Int.random(in: 0..<c.count)] }
        }
        return src[0]
    }
}

/// Formats the solution, numbering moves from the player's side: "1. Qf8#" or "1… Rb4 Qe2 2… Rxa4".
func sanLine(_ sans: [String], player: Character) -> String {
    var out: [String] = []; var n = 1
    for (k, s) in sans.enumerated() {
        if k % 2 == 0 { out.append(player == "w" ? "\(n). \(s)" : "\(n)… \(s)") }
        else { out.append(s); n += 1 }
    }
    return out.joined(separator: " ")
}

/// One puzzle attempt: position bookkeeping and move judging (timing/animation is the UI's job).
final class PuzzleSession {
    let rec: PuzzleRec
    private(set) var pos: Position
    let player: Character
    private(set) var idx = 0
    private(set) var startFen: String = ""
    private(set) var setupMove: Move? = nil
    var sanList: [String] = []

    enum Verdict { case cont, solved, wrong }

    init(_ rec: PuzzleRec) {
        self.rec = rec
        self.pos = Position.fromFen(rec.fen)
        self.player = pos.turn == "w" ? "b" : "w"
    }

    /// Opponent's first move (part of the puzzle definition).
    @discardableResult
    func playSetup() -> Move {
        var m = pos.moveFromUci(rec.moves[0])!
        m.san = pos.san(m); pos.apply(&m)
        idx = 1; startFen = pos.fen(); setupMove = m
        return m
    }

    func expectedUci() -> String { rec.moves[idx] }
    func legalFrom(_ sq: Int) -> [Move] { pos.legalMoves().filter { $0.from == sq } }

    /// Judges and applies the player's move. Any checkmating move wins (Lichess rule for mates).
    func play(_ m: Move) -> Verdict {
        let test = pos.clone(); var testMove = m; test.apply(&testMove)
        let mate = test.isCheckmate()
        let ok = m.uci() == rec.moves[idx] || mate
        var mm = m
        mm.san = pos.san(mm); pos.apply(&mm)
        if !ok { return .wrong }
        sanList.append(mm.san); idx += 1
        return (idx >= rec.moves.count || mate) ? .solved : .cont
    }

    @discardableResult
    func playReply() -> Move {
        var m = pos.moveFromUci(rec.moves[idx])!
        m.san = pos.san(m); pos.apply(&m)
        sanList.append(m.san); idx += 1
        return m
    }

    /// After a wrong daily attempt: back to the position after the opponent's setup move.
    func restart() { pos = Position.fromFen(startFen); idx = 1; sanList.removeAll() }

    /// Full solution from the start position (moves 1..end), each with SAN.
    func solutionMoves() -> [Move] {
        let p = Position.fromFen(startFen); var out: [Move] = []
        for k in 1..<rec.moves.count {
            var m = p.moveFromUci(rec.moves[k])!
            m.san = p.san(m); p.apply(&m); out.append(m)
        }
        return out
    }
    func resetForPlayback() { pos = Position.fromFen(startFen); idx = 1 }
    func applyPlayback(_ m: Move) { var mm = m; pos.apply(&mm); idx += 1 }
}

/// Visual board model with stable piece ids so the UI can animate pieces between squares.
struct BoardPiece: Identifiable, Equatable {
    let id: Int
    var piece: Character
    var sq: Int
}

final class BoardModel {
    private(set) var pieces: [BoardPiece] = []
    private var nextId = 0

    func load(_ pos: Position) {
        pieces = pos.board.enumerated().filter { $0.element != EMPTY }.map { idx, p in
            defer { nextId += 1 }
            return BoardPiece(id: nextId, piece: p, sq: idx)
        }
    }

    /// Mirrors an applied move (m must already carry capture/castle details from Position.apply).
    func apply(_ m: Move, promotedTo: Character?) {
        let capSq = m.epCapture >= 0 ? m.epCapture : (m.captured != EMPTY ? m.to : -1)
        pieces = pieces.filter { $0.sq != capSq || $0.sq == m.from }.map { piece in
            var p = piece
            if p.sq == m.from { p.sq = m.to; p.piece = promotedTo ?? p.piece }
            else if m.rookFrom >= 0 && p.sq == m.rookFrom { p.sq = m.rookTo }
            return p
        }
    }
}
