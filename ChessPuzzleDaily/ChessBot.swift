import Foundation

// Offline chess bot (5 levels) + draw rules shared by the local game and nearby play.
// Search: iterative-deepening negamax with alpha-beta, MVV-LVA move ordering and a capture-only
// quiescence search; evaluation = material + piece-square tables. Weaker levels search less and
// sometimes pick a random reasonable move instead of the best one, so level 1 is beatable by a
// beginner and level 5 plays solid club-level tactics.

// MARK: - Draw rules

enum ChessRules {
    /// Key used for threefold repetition: piece placement, side to move, castling rights, en passant.
    static func key(_ p: Position) -> String {
        String(p.board) + "|" + String(p.turn) + "|" + p.castle + "|" + String(p.ep)
    }

    /// Neither side can possibly mate: K v K, K+minor v K, K+B v K+B with same-coloured bishops.
    static func insufficientMaterial(_ p: Position) -> Bool {
        var minors: [(Character, Int)] = []
        for sq in 0..<64 {
            let c = p.board[sq]
            switch c {
            case EMPTY, "K", "k": continue
            case "B", "b", "N", "n": minors.append((c, sq))
            default: return false
            }
        }
        if minors.count <= 1 { return true }
        if minors.count == 2 {
            let a = minors[0], b = minors[1]
            let bishops = (a.0 == "B" || a.0 == "b") && (b.0 == "B" || b.0 == "b")
            let opposite = isWhitePiece(a.0) != isWhitePiece(b.0)
            if bishops && opposite {
                let colA = ((a.1 >> 3) + (a.1 & 7)) % 2, colB = ((b.1 >> 3) + (b.1 & 7)) % 2
                return colA == colB
            }
        }
        return false
    }
}

// MARK: - Bot

enum ChessBot {
    struct Level {
        let maxDepth: Int
        let seconds: Double
        let blunder: Double   // chance to play a random non-losing move instead of the best one
    }

    static let levels: [Level] = [
        Level(maxDepth: 1, seconds: 0.25, blunder: 0.35),
        Level(maxDepth: 2, seconds: 0.5, blunder: 0.18),
        Level(maxDepth: 3, seconds: 0.9, blunder: 0.07),
        Level(maxDepth: 4, seconds: 1.6, blunder: 0.02),
        Level(maxDepth: 6, seconds: 2.6, blunder: 0.0),
    ]

    private static let MATE = 100_000

    private static func value(_ c: Character) -> Int {
        switch c {
        case "P", "p": return 100
        case "N", "n": return 320
        case "B", "b": return 330
        case "R", "r": return 500
        case "Q", "q": return 900
        case "K", "k": return 20_000
        default: return 0
        }
    }

    // Piece-square tables from White's point of view, index 0 = a8 ... 63 = h1 (same as Position).
    private static let PST_P: [Int] = [
        0, 0, 0, 0, 0, 0, 0, 0,
        50, 50, 50, 50, 50, 50, 50, 50,
        10, 10, 20, 30, 30, 20, 10, 10,
        5, 5, 10, 25, 25, 10, 5, 5,
        0, 0, 0, 20, 20, 0, 0, 0,
        5, -5, -10, 0, 0, -10, -5, 5,
        5, 10, 10, -20, -20, 10, 10, 5,
        0, 0, 0, 0, 0, 0, 0, 0,
    ]
    private static let PST_N: [Int] = [
        -50, -40, -30, -30, -30, -30, -40, -50,
        -40, -20, 0, 0, 0, 0, -20, -40,
        -30, 0, 10, 15, 15, 10, 0, -30,
        -30, 5, 15, 20, 20, 15, 5, -30,
        -30, 0, 15, 20, 20, 15, 0, -30,
        -30, 5, 10, 15, 15, 10, 5, -30,
        -40, -20, 0, 5, 5, 0, -20, -40,
        -50, -40, -30, -30, -30, -30, -40, -50,
    ]
    private static let PST_B: [Int] = [
        -20, -10, -10, -10, -10, -10, -10, -20,
        -10, 0, 0, 0, 0, 0, 0, -10,
        -10, 0, 5, 10, 10, 5, 0, -10,
        -10, 5, 5, 10, 10, 5, 5, -10,
        -10, 0, 10, 10, 10, 10, 0, -10,
        -10, 10, 10, 10, 10, 10, 10, -10,
        -10, 5, 0, 0, 0, 0, 5, -10,
        -20, -10, -10, -10, -10, -10, -10, -20,
    ]
    private static let PST_R: [Int] = [
        0, 0, 0, 0, 0, 0, 0, 0,
        5, 10, 10, 10, 10, 10, 10, 5,
        -5, 0, 0, 0, 0, 0, 0, -5,
        -5, 0, 0, 0, 0, 0, 0, -5,
        -5, 0, 0, 0, 0, 0, 0, -5,
        -5, 0, 0, 0, 0, 0, 0, -5,
        -5, 0, 0, 0, 0, 0, 0, -5,
        0, 0, 0, 5, 5, 0, 0, 0,
    ]
    private static let PST_Q: [Int] = [
        -20, -10, -10, -5, -5, -10, -10, -20,
        -10, 0, 0, 0, 0, 0, 0, -10,
        -10, 0, 5, 5, 5, 5, 0, -10,
        -5, 0, 5, 5, 5, 5, 0, -5,
        0, 0, 5, 5, 5, 5, 0, -5,
        -10, 5, 5, 5, 5, 5, 0, -10,
        -10, 0, 5, 0, 0, 0, 0, -10,
        -20, -10, -10, -5, -5, -10, -10, -20,
    ]
    private static let PST_K_MID: [Int] = [
        -30, -40, -40, -50, -50, -40, -40, -30,
        -30, -40, -40, -50, -50, -40, -40, -30,
        -30, -40, -40, -50, -50, -40, -40, -30,
        -30, -40, -40, -50, -50, -40, -40, -30,
        -20, -30, -30, -40, -40, -30, -30, -20,
        -10, -20, -20, -20, -20, -20, -20, -10,
        20, 20, 0, 0, 0, 0, 20, 20,
        20, 30, 10, 0, 0, 10, 30, 20,
    ]
    private static let PST_K_END: [Int] = [
        -50, -40, -30, -20, -20, -30, -40, -50,
        -30, -20, -10, 0, 0, -10, -20, -30,
        -30, -10, 20, 30, 30, 20, -10, -30,
        -30, -10, 30, 40, 40, 30, -10, -30,
        -30, -10, 30, 40, 40, 30, -10, -30,
        -30, -10, 20, 30, 30, 20, -10, -30,
        -30, -30, 0, 0, 0, 0, -30, -30,
        -50, -30, -30, -30, -30, -30, -30, -50,
    ]

    /// Static evaluation from the side-to-move's point of view.
    static func evaluate(_ p: Position) -> Int {
        var score = 0
        var nonPawn = 0
        for sq in 0..<64 {
            let c = p.board[sq]
            switch c {
            case "Q", "q": nonPawn += 900
            case "R", "r": nonPawn += 500
            case "B", "b", "N", "n": nonPawn += 320
            default: break
            }
        }
        let endgame = nonPawn <= 1_800
        for sq in 0..<64 {
            let c = p.board[sq]
            if c == EMPTY { continue }
            let white = isWhitePiece(c)
            let i = white ? sq : (sq ^ 56)
            var v = value(c)
            switch c {
            case "P", "p": v += PST_P[i]
            case "N", "n": v += PST_N[i]
            case "B", "b": v += PST_B[i]
            case "R", "r": v += PST_R[i]
            case "Q", "q": v += PST_Q[i]
            case "K", "k": v += endgame ? PST_K_END[i] : PST_K_MID[i]
            default: break
            }
            score += white ? v : -v
        }
        return p.turn == "w" ? score : -score
    }

    /// Legal moves for the side to move, generated with one clone per pseudo move.
    private static func legal(_ p: Position) -> [Move] {
        let me = p.turn
        var out: [Move] = []
        for m in p.pseudoMoves() {
            let c = p.clone(); var mm = m; c.apply(&mm)
            if !c.inCheck(me) { out.append(mm) }
        }
        return out
    }

    private static func order(_ moves: [Move], _ p: Position) -> [Move] {
        moves.sorted { a, b in score(a, p) > score(b, p) }
    }

    private static func score(_ m: Move, _ p: Position) -> Int {
        var s = 0
        let victim = p.board[m.to]
        if victim != EMPTY { s += 10 * value(victim) - value(p.board[m.from]) / 10 + 10_000 }
        if m.epCapture >= 0 { s += 10_000 }
        if m.promo != nil { s += 9_000 }
        return s
    }

    private final class Search {
        let deadline: Date
        var nodes = 0
        var stopped = false
        init(deadline: Date) { self.deadline = deadline }

        func timeUp() -> Bool {
            nodes += 1
            if nodes & 1023 == 0 && Date() >= deadline { stopped = true }
            return stopped
        }

        func quiesce(_ p: Position, _ alphaIn: Int, _ beta: Int, _ qDepth: Int) -> Int {
            if timeUp() { return 0 }
            var alpha = alphaIn
            let stand = ChessBot.evaluate(p)
            if stand >= beta { return beta }
            if stand > alpha { alpha = stand }
            if qDepth <= 0 { return alpha }
            let me = p.turn
            let captures = p.pseudoMoves().filter { p.board[$0.to] != EMPTY || $0.promo != nil }
            for m in ChessBot.order(captures, p) {
                let c = p.clone(); var mm = m; c.apply(&mm)
                if c.inCheck(me) { continue }
                let v = -quiesce(c, -beta, -alpha, qDepth - 1)
                if stopped { return 0 }
                if v >= beta { return beta }
                if v > alpha { alpha = v }
            }
            return alpha
        }

        func negamax(_ p: Position, _ depth: Int, _ alphaIn: Int, _ beta: Int, _ ply: Int) -> Int {
            if timeUp() { return 0 }
            if depth <= 0 { return quiesce(p, alphaIn, beta, 4) }
            if p.half >= 100 || ChessRules.insufficientMaterial(p) { return 0 }
            var alpha = alphaIn
            let me = p.turn
            var any = false
            for m in ChessBot.order(p.pseudoMoves(), p) {
                let c = p.clone(); var mm = m; c.apply(&mm)
                if c.inCheck(me) { continue }
                any = true
                let v = -negamax(c, depth - 1, -beta, -alpha, ply + 1)
                if stopped { return 0 }
                if v >= beta { return beta }
                if v > alpha { alpha = v }
            }
            if !any { return p.inCheck(me) ? -(ChessBot.MATE - ply) : 0 }
            return alpha
        }
    }

    /// Best move for the side to move at `level` (1...5). Runs synchronously — call off the main thread.
    static func bestMove(_ pos: Position, level: Int, history: [String] = []) -> Move? {
        let lv = levels[max(0, min(levels.count - 1, level - 1))]
        let root = pos.clone()
        var moves = order(legal(root), root)
        if moves.isEmpty { return nil }
        if moves.count == 1 { return moves[0] }

        let search = Search(deadline: Date().addingTimeInterval(lv.seconds))
        var scored: [(Move, Int)] = moves.map { ($0, 0) }
        var best = moves[0]
        var depth = 1
        var completedDepth = 0
        while depth <= lv.maxDepth {
            var results: [(Move, Int)] = []
            var alpha = -ChessBot.MATE - 1
            for m in moves {
                let c = root.clone(); var mm = m; c.apply(&mm)
                var v = -search.negamax(c, depth - 1, -ChessBot.MATE - 1, -alpha, 1)
                if search.stopped { break }
                // Avoid walking into a threefold repetition when not losing.
                if history.filter({ $0 == ChessRules.key(c) }).count >= 2 { v = min(v, 0) }
                results.append((m, v))
                if v > alpha { alpha = v }
            }
            if search.stopped {
                // Out of time mid-iteration: keep the last fully searched depth; only if not even
                // depth 1 finished, fall back to the best of the partial results.
                if completedDepth == 0, !results.isEmpty {
                    results.sort { $0.1 > $1.1 }
                    scored = results
                    best = results[0].0
                }
                break
            }
            results.sort { $0.1 > $1.1 }
            scored = results
            best = results[0].0
            moves = results.map { $0.0 }
            completedDepth = depth
            if abs(results[0].1) >= ChessBot.MATE - 100 { break }
            depth += 1
        }

        if lv.blunder > 0, Double.random(in: 0..<1) < lv.blunder, scored.count > 1 {
            // A "human" slip: any move that doesn't hang mate and isn't far worse than the best.
            let bestScore = scored[0].1
            let ok = scored.filter { $0.1 > -ChessBot.MATE + 100 && $0.1 >= bestScore - 250 }
            if let pick = ok.randomElement() { return pick.0 }
        }
        return best
    }
}
