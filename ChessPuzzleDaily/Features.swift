import Foundation

// Port of Features.kt — pure logic for growth features (no UIKit/SwiftUI imports).

/// Rating ranks named after the pieces: Pawn → Knight → Bishop → Rook → Queen → King → Grandmaster.
enum Ranks {
    static let THRESHOLDS = [0, 800, 1100, 1400, 1700, 2000, 2300]
    static func index(_ rating: Double) -> Int {
        var idx = 0
        for (i, t) in THRESHOLDS.enumerated() where rating >= Double(t) { idx = i }
        return max(idx, 0)
    }
    /// Rating needed for the next rank, or nil at the top.
    static func next(_ rating: Double) -> Int? {
        let i = index(rating) + 1
        return i < THRESHOLDS.count ? THRESHOLDS[i] : nil
    }
}

/// Everything achievements and unlocks are judged on.
struct PlayerStats {
    let bestStreak: Int
    let dailySolved: Int
    let trainSolved: Int
    let rating: Double
    let rushBest: Int
    let lessonsDone: Int
    let mate3Solved: Bool
}

enum AchKind { case firstDaily, streak, train, rating, rush, lessons, mate3 }
struct Achievement { let id: String; let kind: AchKind; let n: Int; let icon: String }

let ACHIEVEMENTS: [Achievement] = [
    Achievement(id: "first", kind: .firstDaily, n: 1, icon: "♟"),
    Achievement(id: "streak3", kind: .streak, n: 3, icon: "🔥"),
    Achievement(id: "streak7", kind: .streak, n: 7, icon: "🔥"),
    Achievement(id: "streak30", kind: .streak, n: 30, icon: "🔥"),
    Achievement(id: "streak100", kind: .streak, n: 100, icon: "🏆"),
    Achievement(id: "train10", kind: .train, n: 10, icon: "🎯"),
    Achievement(id: "train100", kind: .train, n: 100, icon: "🎯"),
    Achievement(id: "train500", kind: .train, n: 500, icon: "🎯"),
    Achievement(id: "rating1200", kind: .rating, n: 1200, icon: "📈"),
    Achievement(id: "rating1500", kind: .rating, n: 1500, icon: "📈"),
    Achievement(id: "rating1800", kind: .rating, n: 1800, icon: "👑"),
    Achievement(id: "rush10", kind: .rush, n: 10, icon: "⚡"),
    Achievement(id: "rush20", kind: .rush, n: 20, icon: "⚡"),
    Achievement(id: "lessons", kind: .lessons, n: Lessons.KEYS.count, icon: "📚"),
    Achievement(id: "mate3", kind: .mate3, n: 1, icon: "♛"),
]

func isEarned(_ a: Achievement, _ s: PlayerStats) -> Bool {
    switch a.kind {
    case .firstDaily: return s.dailySolved >= a.n
    case .streak: return s.bestStreak >= a.n
    case .train: return s.trainSolved >= a.n
    case .rating: return s.rating >= Double(a.n)
    case .rush: return s.rushBest >= a.n
    case .lessons: return s.lessonsDone >= a.n
    case .mate3: return s.mate3Solved
    }
}

/// Board colour themes; extra themes unlock as rewards (cosmetic only).
enum BoardTheme: String, CaseIterable {
    case walnut, tournament, ocean, marble, amethyst

    var light: UInt32 {
        switch self {
        case .walnut: return 0xFFECD8B0
        case .tournament: return 0xFFEEEED2
        case .ocean: return 0xFFDEE3E6
        case .marble: return 0xFFE8E4DC
        case .amethyst: return 0xFFE9DFF0
        }
    }
    var dark: UInt32 {
        switch self {
        case .walnut: return 0xFFA6774C
        case .tournament: return 0xFF769656
        case .ocean: return 0xFF8CA2AD
        case .marble: return 0xFF9A958C
        case .amethyst: return 0xFF8E6FA8
        }
    }
    var unlockStreak: Int {
        switch self {
        case .tournament: return 3
        case .ocean: return 7
        case .amethyst: return 30
        default: return 0
        }
    }
    var unlockTrain: Int { self == .marble ? 50 : 0 }

    func isUnlocked(_ s: PlayerStats) -> Bool { s.bestStreak >= unlockStreak && s.trainSolved >= unlockTrain }
}

/// Streak freeze: offered when exactly yesterday was missed, at most once per 7 days.
enum Freeze {
    static let COOLDOWN = 7
    static func canOffer(today: Int, lastSolvedDay: Int, streak: Int, lastFreezeDay: Int, todayDone: Bool) -> Bool {
        streak > 0 && !todayDone && lastSolvedDay == today - 2 && (lastFreezeDay == 0 || today - lastFreezeDay >= COOLDOWN)
    }
}

/// 3-minute puzzle rush: difficulty climbs with every solved puzzle, 3 mistakes end the run.
enum Rush {
    static let SECONDS = 180
    static let MAX_MISTAKES = 3
    static func targetRating(_ solved: Int) -> Int { 600 + solved * 70 }
    static func pick(_ db: PuzzleDb, solved: Int, used: Set<String>) -> PuzzleRec {
        let target = targetRating(solved)
        // short puzzles keep the rush fast: at most 2 player moves
        let pool = db.train.filter { !used.contains($0.id) && $0.moves.count <= 4 }
        for w in [50, 100, 200, 400, 4000] {
            let c = pool.filter { abs($0.rating - target) <= w }
            if !c.isEmpty { return c[Int.random(in: 0..<c.count)] }
        }
        return db.train[Int.random(in: 0..<db.train.count)]
    }
}

/// Beginner lessons: one tactic each, 5 easiest puzzles of that theme.
enum Lessons {
    static let KEYS = ["mateIn1", "fork", "pin", "skewer", "discoveredAttack", "backRankMate"]
    static let PER_LESSON = 5
    static func puzzles(_ db: PuzzleDb, _ key: String) -> [PuzzleRec] {
        db.train.filter { Training.matches($0, key) && $0.moves.count <= 4 }
            .sorted { $0.rating < $1.rating }
            .prefix(PER_LESSON).map { $0 }
    }
}

/// "Challenge a friend": the Play link carries the puzzle id through the install referrer / iOS equivalent.
enum Challenge {
    static func link(_ id: String) -> String {
        STORE_URL + "?ct=\(id)"
    }
    static func parse(_ url: URL?) -> String? {
        guard let url, let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        guard let id = comps.queryItems?.first(where: { $0.name == "ct" })?.value else { return nil }
        return id.range(of: "^[A-Za-z0-9]{5}$", options: .regularExpression) != nil ? id : nil
    }
    static func find(_ db: PuzzleDb, _ id: String) -> PuzzleRec? {
        db.daily.flatMap { $0 }.first { $0.id == id } ?? db.train.first { $0.id == id }
    }
}

/// Month calendar: daily-puzzle numbers laid out Monday-first, nil for padding cells.
enum MonthGrid {
    static func cells(year: Int, month: Int) -> [Int?] {
        let first = Calendar0.daysFromCivil(year, month, 1)
        let nextMonth = month == 12 ? Calendar0.daysFromCivil(year + 1, 1, 1) : Calendar0.daysFromCivil(year, month + 1, 1)
        let lead = Calendar0.weekdayMon0(first)
        var out: [Int?] = Array(repeating: nil, count: lead)
        for d in first..<nextMonth { out.append(Daily.numberFor(d)) }
        while out.count % 7 != 0 { out.append(nil) }
        return out
    }
    static func dayOfMonth(_ n: Int, year: Int, month: Int) -> Int {
        Daily.civilDaysOf(n) - Calendar0.daysFromCivil(year, month, 1) + 1
    }
}

/// When to ask for an App Store rating: after the 3rd and the 10th solved daily puzzle, once each.
enum ReviewPrompt {
    static let MILESTONES = [3, 10]
    static func shouldAsk(dailySolved: Int, alreadyAsked: Set<Int>) -> Int? {
        MILESTONES.first { dailySolved >= $0 && !alreadyAsked.contains($0) }
    }
}

/// App Store URL for this app — fill in once the App Store Connect listing exists.
let STORE_URL = "https://apps.apple.com/app/idXXXXXXXXXX"
