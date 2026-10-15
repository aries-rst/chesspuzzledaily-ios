import Foundation
import SwiftUI

// Port of GameController.kt — drives one screen at a time; logic ported 1:1 from the
// Kotlin/Compose original. Coroutines + delay() become Swift structured concurrency
// (Task + Task.sleep); mutableStateOf becomes @Published.

enum Screen { case splash, lang, home, puzzle, archive, stats, settings, lessons, achievements }
enum Mode { case daily, train, challenge, rush, lesson }
enum MsgKind { case neutral, ok, bad }

struct ResultUi: Equatable {
    var win: Bool
    var solution: String
    var grid: String = ""
    var solvedIn: String = ""
    var ratingLine: String = ""
    var ratingUp: Bool = true
    var puzzleRating: Int = 0
    var themes: String = ""
    var showStreak: Bool = false
    var rankUp: String = ""
    var rushScore: Int = -1
    var rushBest: Int = 0
    var rushNewBest: Bool = false
    var lessonDone: Bool = false
}

@MainActor
final class GameController: ObservableObject {
    let store: ProgressStore
    let sound: SoundManager

    @Published var screen: Screen = .splash
    @Published private(set) var lang: Lang
    var s: Strings { stringsFor(lang) }
    @Published var db: PuzzleDb?
    @Published private(set) var muted: Bool
    @Published var privacyRequired = false
    @Published var tick = 0

    // ----- board state -----
    private let model = BoardModel()
    @Published private(set) var pieces: [BoardPiece] = []
    @Published private(set) var flip = false
    @Published private(set) var selected = -1
    @Published private(set) var targets: Set<Int> = []
    @Published private(set) var lastFrom = -1
    @Published private(set) var lastTo = -1
    @Published private(set) var hintSq = -1
    @Published private(set) var checkSq = -1
    @Published private(set) var shake = 0
    @Published private(set) var promotionChoices: [Move]? = nil

    // ----- puzzle state -----
    @Published private(set) var mode: Mode = .daily
    @Published private(set) var title = ""
    @Published private(set) var goal = ""
    @Published private(set) var player: Character = "w"
    @Published private(set) var msg = ""
    @Published private(set) var msgKind: MsgKind = .neutral
    @Published private(set) var attempts = Daily.ATTEMPTS
    @Published private(set) var hintAvailable = false
    @Published private(set) var result: ResultUi? = nil
    private var session: PuzzleSession?
    private var dailyN = 0
    private var archive = false
    private var grid = ""
    private var hintUsed = false
    private var inputOn = false
    private var trainCount = 0
    private var puzzleTask: Task<Void, Never>?

    init(store: ProgressStore, sound: SoundManager) {
        self.store = store; self.sound = sound
        self.lang = store.lang ?? .ru
        self.muted = store.muted
        self.boardTheme = store.boardTheme
    }

    func today() -> Int {
        let cal = Calendar(identifier: .gregorian)
        let c = cal.dateComponents([.year, .month, .day], from: Date())
        return Daily.numberFor(Calendar0.daysFromCivil(c.year ?? 2026, c.month ?? 1, c.day ?? 1))
    }

    // ---------------- navigation ----------------
    func go(_ target: Screen) {
        stopPuzzle(); stopRush(); screen = target; tick += 1
        if target == .home { checkFreeze() }
    }

    // ---------------- streak freeze ----------------
    @Published private(set) var freezeOffer: Int? = nil
    private var freezeAskedToday = -1
    private func checkFreeze() {
        let t = today()
        if freezeAskedToday == t { return }
        let done = store.days[t].map { $0.status != "progress" } ?? false
        if Freeze.canOffer(today: t, lastSolvedDay: store.lastSolvedDay, streak: store.streak, lastFreezeDay: store.lastFreezeDay, todayDone: done) {
            freezeOffer = store.streak; freezeAskedToday = t
        }
    }
    func acceptFreeze() {
        freezeOffer = nil
        RewardedAdManager.show { [weak self] in
            guard let self else { return }
            self.store.applyFreeze(self.today()); self.sound.solved(); self.tick += 1
        }
    }
    func declineFreeze() { freezeOffer = nil; store.declineFreeze(); tick += 1 }

    // ---------------- hooks for app-level features ----------------
    var onReviewMilestone: () -> Void = {}
    @Published var sharePayload: SharePayload? = nil
    @Published var pendingChallenge: String? = nil
    @discardableResult
    func consumeChallenge() -> Bool {
        guard let id = pendingChallenge else { return false }
        pendingChallenge = nil; startChallenge(id); return session != nil
    }
    func goHome() { sound.click(); go(.home) }
    func setLanguage(_ l: Lang) { store.setLang(l); lang = l; tick += 1; onLanguageChanged(l) }
    func toggleMute() { muted.toggle(); store.setMuted(muted); sound.muted = muted; if !muted { sound.click() } }
    var onNotifyChanged: (Bool) -> Void = { _ in }
    var onLanguageChanged: (Lang) -> Void = { _ in }
    func setNotify(_ v: Bool) { store.setNotify(v); onNotifyChanged(v); tick += 1 }

    private func stopPuzzle() { puzzleTask?.cancel(); puzzleTask = nil; inputOn = false; promotionChoices = nil }
    private func launchP(_ block: @escaping () async -> Void) {
        puzzleTask?.cancel()
        puzzleTask = Task { await block() }
    }
    private func sleep(_ ms: Int) async { try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000) }
    private func say(_ text: String, _ kind: MsgKind = .neutral) { msg = text; msgKind = kind }

    // ---------------- board helpers ----------------
    private func syncMarks() {
        guard let ses = session else { return }
        checkSq = ses.pos.inCheck() ? ses.pos.kingSq(ses.pos.turn) : -1
    }
    private func animate(_ m: Move, _ promoted: Character?) {
        model.apply(m, promotedTo: promoted)
        withAnimation(.easeOut(duration: 0.22)) { pieces = model.pieces }
        lastFrom = m.from; lastTo = m.to; selected = -1; targets = []; hintSq = -1
        syncMarks()
        if let ses = session, ses.pos.inCheck() { sound.check() }
        else if m.captured != EMPTY { sound.capture() }
        else { sound.move() }
    }
    private func promotedPiece(_ m: Move, _ mover: Character) -> Character? {
        guard let promo = m.promo else { return nil }
        return mover == "w" ? Character(promo.uppercased()) : promo
    }
    private func loadBoard(_ pos: Position) { model.load(pos); pieces = model.pieces; syncMarks() }

    // ---------------- puzzle lifecycle ----------------
    private func setup(_ rec: PuzzleRec, _ m: Mode) {
        stopPuzzle()
        let ses = PuzzleSession(rec); session = ses
        mode = m; player = ses.player; flip = ses.player == "b"
        lastFrom = -1; lastTo = -1; selected = -1; targets = []; hintSq = -1; result = nil
        hintAvailable = m != .rush; hintUsed = false
        goal = rec.mateN > 0 ? s.findMate(rec.mateN) : s.findBest
        loadBoard(ses.pos)
        say(s.opponentMoves)
        screen = .puzzle
        launchP { [weak self] in
            guard let self else { return }
            await self.sleep(m == .rush ? 300 : 650)
            if Task.isCancelled { return }
            let mover = ses.pos.turn
            let mv = ses.playSetup(); self.animate(mv, self.promotedPiece(mv, mover))
            self.awaitPlayer()
        }
    }

    private func awaitPlayer() {
        say(mode == .daily ? "\(s.attemptsLeft): \(String(repeating: "❤️", count: max(0, attempts)))\(String(repeating: "🤍", count: max(0, Daily.ATTEMPTS - attempts)))" : s.findBest)
        inputOn = true
    }

    func tapSquare(_ sq: Int) {
        guard let ses = session else { return }
        if !inputOn || promotionChoices != nil { return }
        let hits = selected >= 0 ? ses.legalFrom(selected).filter { $0.to == sq } : []
        if !hits.isEmpty {
            if hits.count > 1 { promotionChoices = hits; return }
            submit(hits[0]); return
        }
        let p = ses.pos.board[sq]
        if p != EMPTY && colorOf(p) == ses.pos.turn {
            selected = sq == selected ? -1 : sq
            targets = selected >= 0 ? Set(ses.legalFrom(sq).map { $0.to }) : []
            sound.click()
        } else { selected = -1; targets = [] }
    }

    func choosePromotion(_ m: Move?) {
        promotionChoices = nil
        if let m { submit(m) } else { selected = -1; targets = [] }
    }

    /// Squares in `targets` that hold an enemy piece (drawn as rings instead of dots).
    func isCaptureTarget(_ sq: Int) -> Bool { (session?.pos.board[sq]).map { $0 != EMPTY } ?? false }

    private func submit(_ m: Move) {
        guard let ses = session else { return }
        inputOn = false
        let mover = ses.pos.turn
        let verdict = ses.play(m)
        animate(m, promotedPiece(m, mover))
        switch verdict {
        case .solved:
            if mode == .rush { rushSolvedOne() }
            else { launchP { [weak self] in await self?.sleep(450); self?.finish(true) } }
        case .cont:
            say(s.correct, .ok); sound.correct()
            launchP { [weak self] in
                guard let self else { return }
                await self.sleep(self.mode == .rush ? 300 : 600)
                if Task.isCancelled { return }
                let rm = ses.pos.turn
                let r = ses.playReply(); self.animate(r, self.promotedPiece(r, rm))
                self.awaitPlayer()
            }
        case .wrong:
            sound.wrong(); say(s.wrong, .bad); shake += 1
            if mode == .rush { rushMistake(); return }
            if mode == .daily {
                attempts -= 1; grid += "🟥"; persistDaily("progress")
                launchP { [weak self] in
                    guard let self else { return }
                    await self.sleep(900)
                    if Task.isCancelled { return }
                    if self.attempts <= 0 { self.finish(false) }
                    else {
                        ses.restart(); self.loadBoard(ses.pos)
                        if let sm = ses.setupMove { self.lastFrom = sm.from; self.lastTo = sm.to }
                        self.awaitPlayer()
                    }
                }
            } else {
                launchP { [weak self] in await self?.sleep(900); self?.finish(false) }
            }
        }
    }

    func hint() {
        guard let ses = session else { return }
        if !inputOn || !hintAvailable { return }
        RewardedAdManager.show { [weak self] in
            guard let self else { return }
            self.hintSq = sqIndex(String(ses.expectedUci().prefix(2))); self.hintUsed = true; self.hintAvailable = false; self.sound.click()
        }
    }

    /// After a failure: replay the full solution from the start position, then show the result.
    private func playSolution() async -> [String] {
        guard let ses = session else { return [] }
        let sol = ses.solutionMoves()
        ses.resetForPlayback(); loadBoard(ses.pos)
        if let sm = ses.setupMove { lastFrom = sm.from; lastTo = sm.to }
        await sleep(500)
        for m in sol {
            if Task.isCancelled { break }
            let mover = ses.pos.turn
            ses.applyPlayback(m)
            animate(m, promotedPiece(m, mover))
            await sleep(750)
        }
        return sol.map { $0.san }
    }

    private func finish(_ win: Bool) {
        guard let ses = session else { return }
        inputOn = false; hintAvailable = false
        if win && ses.rec.mateN >= 3 { store.markMate3() }
        if mode == .lesson { finishLesson(win); return }
        if win { say(s.solved, .ok); sound.solved() } else { say(s.failed, .bad); sound.failed() }
        if mode == .daily {
            if win { grid += hintUsed ? "💡" : "🟩" }
            persistDaily(win ? "solved" : "failed")
            if !archive && dailyN == today() { store.recordDailyOutcome(dailyN, win: win) }
            if win && !archive, let mst = ReviewPrompt.shouldAsk(dailySolved: store.dailySolvedCount, alreadyAsked: store.reviewAsked) {
                store.markReviewAsked(mst)
                launchP { [weak self] in await self?.sleep(2500); self?.onReviewMilestone() }
            }
            tick += 1; checkAchievements()
            launchP { [weak self] in
                guard let self else { return }
                let sans: [String]
                if win { sans = ses.sanList } else { await self.sleep(400); sans = await self.playSolution() }
                self.result = ResultUi(win: win, solution: sanLine(sans, player: ses.player), grid: self.grid,
                                        solvedIn: win ? self.s.solvedIn(Daily.ATTEMPTS - self.attempts + 1, Daily.ATTEMPTS) : "",
                                        showStreak: !self.archive)
            }
        } else {
            let rankBefore = Ranks.index(store.rating)
            let delta = mode == .challenge ? 0 : Elo.delta(player: store.rating, puzzle: ses.rec.rating, games: store.ratingGames, win: win)
            if mode == .train { store.recordTraining(ses.rec.id, win: win, delta: delta) }
            tick += 1; checkAchievements()
            let rankAfter = Ranks.index(store.rating)
            if mode == .train { title = "\(s.training) · \(Int(store.rating))" }
            launchP { [weak self] in
                guard let self else { return }
                let sans: [String]
                if win { sans = ses.sanList } else { await self.sleep(400); sans = await self.playSolution() }
                let themesLine = ses.rec.themeList.compactMap { themeName($0, self.lang) }.joined(separator: ", ")
                self.result = ResultUi(win: win, solution: sanLine(sans, player: ses.player),
                                        ratingLine: self.mode == .challenge ? "" : "\(self.s.rating): \(Int(self.store.rating)) (\(delta >= 0 ? "+" : "")\(delta))",
                                        ratingUp: delta >= 0, puzzleRating: ses.rec.rating,
                                        themes: themesLine.isEmpty ? "—" : themesLine,
                                        rankUp: rankAfter > rankBefore ? "\(self.s.rankUp) \(self.s.ranks[rankAfter])" : "")
            }
        }
    }

    // ---------------- daily ----------------
    private func persistDaily(_ status: String) { store.saveDay(dailyN, DayResult(status: status, grid: grid, attempts: attempts)) }

    func startDaily(_ n: Int, fromArchive: Bool = false) {
        guard let d = db else { return }
        sound.click()
        dailyN = n; archive = fromArchive
        let prev = store.days[n]
        let rec = Daily.puzzleFor(d, n)
        title = "\(s.daily) \(s.dailyNo)\(n)"
        if let prev, prev.status != "progress" {
            // already finished: replay the solution and show the stored result
            grid = prev.grid; attempts = prev.attempts
            setup(rec, .daily)
            stopPuzzle()
            let ses = session!
            launchP { [weak self] in
                guard let self else { return }
                await self.sleep(650)
                if Task.isCancelled { return }
                let mover = ses.pos.turn
                let mv = ses.playSetup(); self.animate(mv, self.promotedPiece(mv, mover)); self.hintAvailable = false
                let win = prev.status == "solved"
                if win { self.say(self.s.solved, .ok) } else { self.say(self.s.failed, .bad) }
                let sans = await self.playSolution()
                self.result = ResultUi(win: win, solution: sanLine(sans, player: ses.player), grid: self.grid, showStreak: !fromArchive)
            }
            return
        }
        grid = prev?.grid ?? ""; attempts = prev?.attempts ?? Daily.ATTEMPTS
        setup(rec, .daily)
    }

    func openArchiveDay(_ n: Int) {
        if store.unlocked.contains(n) || store.days[n] != nil { startDaily(n, fromArchive: true); return }
        RewardedAdManager.show { [weak self] in self?.store.unlock(n); self?.startDaily(n, fromArchive: true) }
    }

    func share() {
        guard let ses = session else { return }
        let link = Challenge.link(ses.rec.id)
        sound.click()
        if mode == .daily {
            sharePayload = SharePayload(fen: ses.startFen, flip: ses.player == "b", headline: "\(s.daily) \(s.dailyNo)\(dailyN)",
                                         goal: goal, grid: grid, text: s.shareText(dailyN, grid, store.displayStreak(today()), link))
        } else {
            sharePayload = SharePayload(fen: ses.startFen, flip: ses.player == "b", headline: s.challengeText(goal),
                                         goal: goal, grid: "", text: s.challengeText(goal) + "\n" + link)
        }
    }

    /// Opened from a friend's challenge link: unrated, then normal training.
    func startChallenge(_ id: String) {
        guard let d = db, let rec = Challenge.find(d, id) else { return }
        title = s.challengeTitle
        setup(rec, .challenge)
    }

    // ---------------- training ----------------
    func startTraining() {
        guard let d = db else { return }
        sound.click()
        let rec = Training.pick(d, rating: store.rating, theme: store.theme, seen: Set(store.seen))
        title = "\(s.training) · \(Int(store.rating))"
        setup(rec, .train)
    }
    func setTheme(_ key: String) { store.setTheme(key); startTraining() }
    func nextTraining() {
        sound.click(); trainCount += 1
        if trainCount % Training.AD_EVERY == 0 { InterstitialAdManager.show { [weak self] in self?.startTraining() } }
        else { startTraining() }
    }

    // ---------------- achievements ----------------
    @Published private(set) var achToast: String? = nil
    /// Checks for newly earned achievements and shows a short banner.
    private func checkAchievements() {
        let st = store.stats()
        let fresh = ACHIEVEMENTS.filter { isEarned($0, st) && !store.achSeen.contains($0.id) }
        if fresh.isEmpty { return }
        store.markAchSeen(fresh.map { $0.id })
        let a = fresh.last!
        achToast = "\(a.icon) \(s.achNew) \(achTitle(a))"
        Task { [weak self] in try? await Task.sleep(nanoseconds: 3_500_000_000); self?.achToast = nil }
    }
    func achTitle(_ a: Achievement) -> String {
        switch a.kind {
        case .firstDaily: return s.achFirst
        case .streak: return s.achStreak(a.n)
        case .train: return s.achTrain(a.n)
        case .rating: return s.achRating(a.n)
        case .rush: return s.achRush(a.n)
        case .lessons: return s.achLessons
        case .mate3: return s.achMate3
        }
    }

    // ---------------- board themes ----------------
    @Published private(set) var boardTheme: BoardTheme
    @discardableResult
    func pickBoardTheme(_ t: BoardTheme) -> Bool {
        if !t.isUnlocked(store.stats()) { return false }
        store.setBoardTheme(t); boardTheme = t; sound.click(); return true
    }

    // ---------------- puzzle rush ----------------
    @Published private(set) var rushSeconds = Rush.SECONDS
    @Published private(set) var rushSolved = 0
    @Published private(set) var rushMistakes = 0
    private var rushTask: Task<Void, Never>?
    private var rushUsed: Set<String> = []
    private var rushRuns = 0

    func startRush() {
        guard let d = db else { return }
        sound.click(); stopRush()
        rushSolved = 0; rushMistakes = 0; rushSeconds = Rush.SECONDS; rushUsed.removeAll()
        title = s.rush
        nextRush(d)
        rushTask = Task { [weak self] in
            while let self, self.rushSeconds > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                self.rushSeconds -= 1
            }
            self?.endRush()
        }
    }
    private func stopRush() { rushTask?.cancel(); rushTask = nil }
    private func nextRush(_ d: PuzzleDb) {
        let rec = Rush.pick(d, solved: rushSolved, used: rushUsed); rushUsed.insert(rec.id)
        setup(rec, .rush)
    }
    private func rushSolvedOne() {
        rushSolved += 1; sound.correct(); say(s.correct, .ok)
        launchP { [weak self] in await self?.sleep(250); if let d = self?.db { self?.nextRush(d) } }
    }
    private func rushMistake() {
        rushMistakes += 1
        if rushMistakes >= Rush.MAX_MISTAKES {
            launchP { [weak self] in await self?.sleep(500); self?.endRush() }
            return
        }
        launchP { [weak self] in await self?.sleep(500); if let d = self?.db { self?.nextRush(d) } }
    }
    private func endRush() {
        if mode != .rush || result != nil { return }
        stopRush(); puzzleTask?.cancel(); inputOn = false
        let newBest = store.recordRush(rushSolved)
        say(s.rushOver, .ok); sound.solved()
        result = ResultUi(win: true, solution: "", rushScore: rushSolved, rushBest: store.rushBest, rushNewBest: newBest)
        tick += 1; checkAchievements()
    }
    func rushAgain() {
        rushRuns += 1
        if rushRuns % 2 == 0 { InterstitialAdManager.show { [weak self] in self?.startRush() } } else { startRush() }
    }
    func shareRush() {
        guard let ses = session else { return }
        sound.click()
        sharePayload = SharePayload(fen: ses.startFen, flip: ses.player == "b", headline: "⚡ \(s.rush): \(rushSolved)",
                                     goal: s.rushDesc, grid: "", text: s.shareRush(rushSolved) + "\n" + STORE_URL)
    }

    // ---------------- lessons ----------------
    @Published private(set) var lessonKey = ""
    @Published private(set) var lessonIdx = 0
    func lessonPuzzles(_ key: String) -> [PuzzleRec] { db.map { Lessons.puzzles($0, key) } ?? [] }
    func startLesson(_ key: String, _ idx: Int = -1) {
        let list = lessonPuzzles(key); if list.isEmpty { return }
        sound.click()
        let solved = store.lessonSolved[key] ?? []
        let i = idx >= 0 ? idx : ((0..<list.count).first { !solved.contains($0) } ?? 0)
        lessonKey = key; lessonIdx = i
        title = "\(themeName(key, lang) ?? key) · \(s.lessonOf(i + 1, list.count))"
        setup(list[i], .lesson)
    }
    private func finishLesson(_ win: Bool) {
        guard let ses = session else { return }
        if win { store.solveLesson(lessonKey, lessonIdx) }
        let done = (store.lessonSolved[lessonKey]?.count ?? 0) >= Lessons.PER_LESSON
        tick += 1; checkAchievements()
        launchP { [weak self] in
            guard let self else { return }
            let sans: [String]
            if win { sans = ses.sanList } else { await self.sleep(400); sans = await self.playSolution() }
            self.result = ResultUi(win: win, solution: sanLine(sans, player: ses.player), lessonDone: done)
        }
    }
    func nextLessonPuzzle() {
        let list = lessonPuzzles(lessonKey)
        if lessonIdx + 1 < list.count { startLesson(lessonKey, lessonIdx + 1) } else { go(.lessons) }
    }

    func dispose() { puzzleTask?.cancel(); rushTask?.cancel() }
}
