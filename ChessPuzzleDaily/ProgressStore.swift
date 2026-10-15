import Foundation

// Port of ProgressStore.kt — persistent player state (UserDefaults-backed; mirrors the
// prototype's localStorage `cpd_state_v1`).

struct DayResult: Codable, Equatable { var status: String; var grid: String; var attempts: Int } // status: progress | solved | failed

/// Supported UI languages. Only Russian and English are translated in this build; the
/// Kotlin original ports 17 languages (see Lang.kt/LangAsia.kt/LangMore.kt) — porting the
/// rest is a mechanical follow-up, not a redesign.
enum Lang: String, CaseIterable {
    case ru, en
    var native: String { self == .ru ? "Русский" : "English" }
    var rtl: Bool { false }
    static func of(_ code: String?) -> Lang? { Lang.allCases.first { $0.rawValue == code } }
}

final class ProgressStore {
    private let d = UserDefaults.standard
    private let p = "cpd_"

    var lang: Lang? { didSet { d.set(lang?.rawValue, forKey: p + "lang") } }
    var streak: Int { didSet { d.set(streak, forKey: p + "streak") } }
    var best: Int { didSet { d.set(best, forKey: p + "best") } }
    var lastSolvedDay: Int { didSet { d.set(lastSolvedDay, forKey: p + "lastSolvedDay") } }
    var rating: Double { didSet { d.set(rating, forKey: p + "rating") } }
    var ratingGames: Int { didSet { d.set(ratingGames, forKey: p + "rgames") } }
    var trainPlayed: Int { didSet { d.set(trainPlayed, forKey: p + "tPlayed") } }
    var trainSolved: Int { didSet { d.set(trainSolved, forKey: p + "tSolved") } }
    var notify: Bool { didSet { d.set(notify, forKey: p + "notify") } }
    var muted: Bool { didSet { d.set(muted, forKey: p + "muted") } }
    var theme: String { didSet { d.set(theme, forKey: p + "theme") } }
    var notifAsked: Bool { didSet { d.set(notifAsked, forKey: p + "notifAsked") } }
    var lastFreezeDay: Int { didSet { d.set(lastFreezeDay, forKey: p + "lastFreezeDay") } }
    var referrerChecked: Bool { didSet { d.set(referrerChecked, forKey: p + "referrerChecked") } }
    var frozenDays: Set<Int> { didSet { d.set(frozenDays.map(String.init), forKey: p + "frozen") } }
    var reviewAsked: Set<Int> { didSet { d.set(reviewAsked.map(String.init), forKey: p + "reviewAsked") } }
    var rushBest: Int { didSet { d.set(rushBest, forKey: p + "rushBest") } }
    var mate3Solved: Bool { didSet { d.set(mate3Solved, forKey: p + "mate3") } }
    var boardTheme: BoardTheme { didSet { d.set(boardTheme.rawValue, forKey: p + "board") } }
    var achSeen: Set<String> { didSet { d.set(Array(achSeen), forKey: p + "achSeen") } }
    var lessonSolved: [String: Set<Int>] {
        didSet { for k in Lessons.KEYS { d.set((lessonSolved[k] ?? []).map(String.init), forKey: p + "lesson_" + k) } }
    }
    var days: [Int: DayResult]
    var unlocked: Set<Int> { didSet { d.set(Array(unlocked), forKey: p + "unlocked") } }
    var seen: [String]

    init() {
        lang = Lang.of(d.string(forKey: p + "lang"))
        streak = d.integer(forKey: p + "streak")
        best = d.integer(forKey: p + "best")
        lastSolvedDay = d.integer(forKey: p + "lastSolvedDay")
        rating = d.object(forKey: p + "rating") != nil ? d.double(forKey: p + "rating") : 1000
        ratingGames = d.integer(forKey: p + "rgames")
        trainPlayed = d.integer(forKey: p + "tPlayed")
        trainSolved = d.integer(forKey: p + "tSolved")
        notify = d.object(forKey: p + "notify") != nil ? d.bool(forKey: p + "notify") : true
        muted = d.bool(forKey: p + "muted")
        theme = d.string(forKey: p + "theme") ?? "all"
        notifAsked = d.bool(forKey: p + "notifAsked")
        lastFreezeDay = d.integer(forKey: p + "lastFreezeDay")
        referrerChecked = d.bool(forKey: p + "referrerChecked")
        frozenDays = Set((d.stringArray(forKey: p + "frozen") ?? []).compactMap { Int($0) })
        reviewAsked = Set((d.stringArray(forKey: p + "reviewAsked") ?? []).compactMap { Int($0) })
        rushBest = d.integer(forKey: p + "rushBest")
        mate3Solved = d.bool(forKey: p + "mate3")
        boardTheme = BoardTheme(rawValue: d.string(forKey: p + "board") ?? "walnut") ?? .walnut
        achSeen = Set(d.stringArray(forKey: p + "achSeen") ?? [])
        var ls: [String: Set<Int>] = [:]
        for k in Lessons.KEYS { ls[k] = Set((d.stringArray(forKey: p + "lesson_" + k) ?? []).compactMap { Int($0) }) }
        lessonSolved = ls
        var dd: [Int: DayResult] = [:]
        if let data = d.data(forKey: p + "days"), let decoded = try? JSONDecoder().decode([String: DayResult].self, from: data) {
            for (k, v) in decoded { if let n = Int(k) { dd[n] = v } }
        }
        days = dd
        unlocked = Set((d.array(forKey: p + "unlocked") as? [Int]) ?? [])
        seen = d.stringArray(forKey: p + "seen") ?? []
    }

    func displayStreak(_ today: Int) -> Int { lastSolvedDay >= today - 1 ? streak : 0 }

    func saveDay(_ n: Int, _ r: DayResult) {
        days[n] = r
        var enc: [String: DayResult] = [:]
        for (k, v) in days { enc[String(k)] = v }
        if let data = try? JSONEncoder().encode(enc) { d.set(data, forKey: p + "days") }
    }

    /// Streak only counts today's puzzle (archive solves never touch it).
    func recordDailyOutcome(_ n: Int, win: Bool) {
        if win { streak = (lastSolvedDay == n - 1) ? streak + 1 : 1; lastSolvedDay = n; best = max(best, streak) }
        else { streak = 0 }
    }

    var dailySolvedCount: Int { days.values.filter { $0.status == "solved" }.count }

    /// Streak freeze accepted: yesterday counts as kept.
    func applyFreeze(_ today: Int) { frozenDays.insert(today - 1); lastSolvedDay = today - 1; lastFreezeDay = today }
    func declineFreeze() { streak = 0 }
    func markReviewAsked(_ m: Int) { reviewAsked.insert(m) }
    func markReferrerChecked() { referrerChecked = true }

    func stats() -> PlayerStats {
        PlayerStats(bestStreak: best, dailySolved: dailySolvedCount, trainSolved: trainSolved, rating: rating,
                    rushBest: rushBest, lessonsDone: lessonSolved.values.filter { $0.count >= Lessons.PER_LESSON }.count,
                    mate3Solved: mate3Solved)
    }
    /// Returns true when `score` is a new record.
    @discardableResult
    func recordRush(_ score: Int) -> Bool { if score <= rushBest { return false }; rushBest = score; return true }
    func markMate3() { if !mate3Solved { mate3Solved = true } }
    func setBoardTheme(_ t: BoardTheme) { boardTheme = t }
    func markAchSeen(_ ids: [String]) { achSeen.formUnion(ids) }
    func solveLesson(_ key: String, _ idx: Int) { lessonSolved[key, default: []].insert(idx) }
    func unlock(_ n: Int) { unlocked.insert(n) }

    func recordTraining(_ id: String, win: Bool, delta: Int) {
        rating = max(400, rating + Double(delta)); ratingGames += 1; trainPlayed += 1; if win { trainSolved += 1 }
        seen.append(id); while seen.count > 3000 { seen.removeFirst() }
        d.set(seen, forKey: p + "seen")
    }

    func setLang(_ l: Lang) { lang = l }
    func setNotify(_ v: Bool) { notify = v }
    func setMuted(_ v: Bool) { muted = v }
    func setTheme(_ v: String) { theme = v }
    func markNotifAsked() { notifAsked = true }
}
