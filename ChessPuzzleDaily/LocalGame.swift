import Foundation
import SwiftUI

// Full games on one phone: vs. the offline bot (5 levels, Premium) or two players taking turns
// on the same device (free). Draws: stalemate, threefold repetition, 50-move rule, insufficient
// material, agreement. The game in progress is saved and can be continued later.

enum LocalMode: Equatable { case bot(level: Int), twoPlayer }

enum GameEnd: Equatable {
    case checkmate(winner: Character)
    case resigned(loser: Character)
    case stalemate, repetition, fiftyMoves, insufficient, agreement
}

@MainActor
final class LocalGameManager: ObservableObject, BoardDisplaying {
    private let model = BoardModel()
    private(set) var position = Position.fromFen(NET_START_FEN_PUBLIC)
    private var history: [(Position, Move)] = []
    private var keys: [String] = []
    private var gameId = 0
    var sound: SoundManager?

    @Published private(set) var mode: LocalMode = .twoPlayer
    @Published private(set) var humanColor: Character = "w"
    @Published private(set) var sanList: [String] = []
    @Published private(set) var end: GameEnd? = nil
    @Published private(set) var thinking = false
    @Published var promotionChoices: [Move]? = nil
    @Published var rotateBoard = true

    // BoardDisplaying
    @Published private(set) var pieces: [BoardPiece] = []
    @Published private(set) var flip = false
    @Published private(set) var selected = -1
    @Published private(set) var targets: Set<Int> = []
    @Published private(set) var lastFrom = -1
    @Published private(set) var lastTo = -1
    let hintSq = -1
    @Published private(set) var checkSq = -1
    @Published private(set) var shake = 0
    @Published var boardTheme: BoardTheme = .walnut

    func isCaptureTarget(_ sq: Int) -> Bool { position.board[sq] != EMPTY }

    var turn: Character { position.turn }
    var isBotGame: Bool { if case .bot = mode { return true }; return false }
    var botLevel: Int { if case .bot(let l) = mode { return l }; return 0 }
    var canUndo: Bool {
        end == nil && !thinking && !history.isEmpty
    }

    // MARK: start / save / resume

    func start(_ mode: LocalMode, humanColor: Character) {
        self.mode = mode
        self.humanColor = humanColor
        resetBoard()
        save()
        botIfNeeded()
    }

    private func resetBoard() {
        gameId += 1
        position = Position.fromFen(NET_START_FEN_PUBLIC)
        history = []; keys = [ChessRules.key(position)]
        sanList = []; end = nil; thinking = false; promotionChoices = nil
        selected = -1; targets = []; lastFrom = -1; lastTo = -1; checkSq = -1
        model.load(position); pieces = model.pieces
        updateFlip()
    }

    private func updateFlip() {
        switch mode {
        case .bot: flip = humanColor == "b"
        case .twoPlayer: flip = rotateBoard && position.turn == "b"
        }
    }

    func setRotate(_ on: Bool) { rotateBoard = on; updateFlip() }

    private static let saveKey = "cpd_local_game"
    var hasSaved: Bool { UserDefaults.standard.dictionary(forKey: Self.saveKey) != nil }

    private func save() {
        guard end == nil else { UserDefaults.standard.removeObject(forKey: Self.saveKey); return }
        let d: [String: Any] = [
            "mode": isBotGame ? "bot" : "two",
            "level": botLevel,
            "color": String(humanColor),
            "moves": history.map { $0.1.uci() },
        ]
        UserDefaults.standard.set(d, forKey: Self.saveKey)
    }

    /// Restores the saved game (replaying its moves). Returns false if there is none.
    @discardableResult
    func resume() -> Bool {
        guard let d = UserDefaults.standard.dictionary(forKey: Self.saveKey) else { return false }
        let isBot = (d["mode"] as? String) == "bot"
        mode = isBot ? .bot(level: max(1, min(5, d["level"] as? Int ?? 3))) : .twoPlayer
        humanColor = Character((d["color"] as? String) ?? "w")
        resetBoard()
        for uci in (d["moves"] as? [String]) ?? [] {
            guard let m = position.moveFromUci(uci) else { break }
            applyMove(m, silent: true)
        }
        lastFromToFromHistory()
        checkEnd()
        botIfNeeded()
        return true
    }

    private func lastFromToFromHistory() {
        if let last = history.last?.1 { lastFrom = last.from; lastTo = last.to } else { lastFrom = -1; lastTo = -1 }
    }

    func discardSaved() { UserDefaults.standard.removeObject(forKey: Self.saveKey) }

    // MARK: input

    func tapSquare(_ sq: Int) {
        guard end == nil, !thinking, promotionChoices == nil else { return }
        if isBotGame && position.turn != humanColor { return }
        let me = position.turn
        let hits = selected >= 0 ? position.legalMoves().filter { $0.from == selected && $0.to == sq } : []
        if !hits.isEmpty {
            if hits.count > 1 { promotionChoices = hits; return }
            commit(hits[0])
            return
        }
        let p = position.board[sq]
        if p != EMPTY, colorOf(p) == me {
            selected = (sq == selected) ? -1 : sq
            targets = selected >= 0 ? Set(position.legalMoves().filter { $0.from == sq }.map { $0.to }) : []
        } else {
            if selected >= 0 { shake += 1 }
            selected = -1; targets = []
        }
    }

    func choosePromotion(_ m: Move?) {
        promotionChoices = nil
        if let m { commit(m) } else { selected = -1; targets = [] }
    }

    private func commit(_ m: Move) {
        applyMove(m, silent: false)
        checkEnd()
        save()
        botIfNeeded()
    }

    private func applyMove(_ m: Move, silent: Bool) {
        let before = position.clone()
        let mover = position.turn
        var mm = m
        mm.san = position.san(mm)
        position.apply(&mm)
        history.append((before, mm))
        keys.append(ChessRules.key(position))
        let promoted: Character? = mm.promo.map { mover == "w" ? Character($0.uppercased()) : $0 }
        model.apply(mm, promotedTo: promoted)
        pieces = model.pieces
        lastFrom = mm.from; lastTo = mm.to; selected = -1; targets = []
        sanList.append(mm.san)
        let check = position.inCheck()
        checkSq = check ? position.kingSq(position.turn) : -1
        if !silent {
            if check { sound?.check() } else if mm.captured != EMPTY { sound?.capture() } else { sound?.move() }
        }
        updateFlip()
    }

    private func checkEnd() {
        guard end == nil else { return }
        if position.legalMoves().isEmpty {
            end = position.inCheck() ? .checkmate(winner: position.turn == "w" ? "b" : "w") : .stalemate
        } else if ChessRules.insufficientMaterial(position) {
            end = .insufficient
        } else if position.half >= 100 {
            end = .fiftyMoves
        } else if let k = keys.last, keys.filter({ $0 == k }).count >= 3 {
            end = .repetition
        }
        if end != nil { finish() }
    }

    private func finish() {
        thinking = false
        discardSaved()
        if case .checkmate(let w) = end {
            if !isBotGame || w == humanColor { sound?.solved() } else { sound?.failed() }
        }
    }

    // MARK: bot

    private func botIfNeeded() {
        guard case .bot(let level) = mode, end == nil, position.turn != humanColor, !thinking else { return }
        thinking = true
        let snapshot = position.clone()
        let hist = keys
        let id = gameId
        Task.detached(priority: .userInitiated) {
            let started = Date()
            let m = ChessBot.bestMove(snapshot, level: level, history: hist)
            let elapsed = Date().timeIntervalSince(started)
            if elapsed < 0.45 { try? await Task.sleep(nanoseconds: UInt64((0.45 - elapsed) * 1_000_000_000)) }
            await MainActor.run {
                guard self.gameId == id, self.end == nil else { return }
                self.thinking = false
                if let m, let legal = self.position.legalMoves().first(where: { $0.from == m.from && $0.to == m.to && $0.promo == m.promo }) {
                    self.commit(legal)
                }
            }
        }
    }

    // MARK: actions

    func undo() {
        guard end == nil, !thinking, !history.isEmpty else { return }
        // vs. bot: take back the bot's reply and the player's move, so it's the player's turn again.
        var steps = 1
        if isBotGame {
            steps = history.count >= 2 && history.last.map({ colorOf($0.0.board[$0.1.from]) }) != humanColor ? 2 : 1
        }
        let keep = max(0, history.count - steps)
        let moves = history.prefix(keep).map { $0.1.uci() }
        resetBoard()
        for uci in moves { if let m = position.moveFromUci(uci) { applyMove(m, silent: true) } }
        lastFromToFromHistory()
        save()
        botIfNeeded()
    }

    func resign() {
        guard end == nil else { return }
        let loser: Character = isBotGame ? humanColor : position.turn
        gameId += 1
        end = .resigned(loser: loser)
        finish()
    }

    /// vs. bot: the bot accepts when it is not better (from its own point of view). Returns acceptance.
    @discardableResult
    func offerDraw() -> Bool {
        guard end == nil, !thinking else { return false }
        if isBotGame {
            let botPerspective = position.turn == humanColor ? -ChessBot.evaluate(position) : ChessBot.evaluate(position)
            guard history.count >= 20, botPerspective <= 30 else { return false }
        }
        gameId += 1
        end = .agreement
        finish()
        return true
    }

    func rematch() {
        let swapped: Character = humanColor == "w" ? "b" : "w"
        start(mode, humanColor: isBotGame ? swapped : "w")
    }

    func stopThinking() { gameId += 1; thinking = false }
}

let NET_START_FEN_PUBLIC = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

// MARK: - Shared text helpers (RU / EN, other languages fall back to EN)

func playText(_ lang: Lang, _ ru: String, _ en: String) -> String { lang == .ru ? ru : en }

func endText(_ e: GameEnd, lang: Lang, me: Character?) -> (String, Color) {
    let t = { (ru: String, en: String) in playText(lang, ru, en) }
    switch e {
    case .checkmate(let w):
        if let me { return w == me ? (t("🏆 Мат! Вы победили", "🏆 Checkmate! You won"), OK) : (t("❌ Мат. Вы проиграли", "❌ Checkmate. You lost"), BAD) }
        return (w == "w" ? t("🏆 Мат — победили белые", "🏆 Checkmate — White wins") : t("🏆 Мат — победили чёрные", "🏆 Checkmate — Black wins"), OK)
    case .resigned(let l):
        if let me { return l == me ? (t("Вы сдались", "You resigned"), BAD) : (t("🏆 Соперник сдался", "🏆 Opponent resigned"), OK) }
        return (l == "w" ? t("Белые сдались — победа чёрных", "White resigned — Black wins") : t("Чёрные сдались — победа белых", "Black resigned — White wins"), TEXT)
    case .stalemate: return (t("🤝 Ничья — пат", "🤝 Draw — stalemate"), TEXT)
    case .repetition: return (t("🤝 Ничья — троекратное повторение", "🤝 Draw — threefold repetition"), TEXT)
    case .fiftyMoves: return (t("🤝 Ничья — правило 50 ходов", "🤝 Draw — 50-move rule"), TEXT)
    case .insufficient: return (t("🤝 Ничья — недостаточно материала", "🤝 Draw — insufficient material"), TEXT)
    case .agreement: return (t("🤝 Ничья по соглашению", "🤝 Draw by agreement"), TEXT)
    }
}

/// Numbered move list ("1. e4 e5  2. Nf3 …").
struct MoveListView: View {
    let sans: [String]
    var body: some View {
        if !sans.isEmpty {
            let pairs = stride(from: 0, to: sans.count, by: 2).map { i in
                "\(i / 2 + 1). \(sans[i])" + (i + 1 < sans.count ? " \(sans[i + 1])" : "")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                ScrollViewReader { proxy in
                    HStack(spacing: 10) {
                        ForEach(Array(pairs.enumerated()), id: \.offset) { i, s in
                            Text(s).font(.system(size: 13, design: .monospaced)).foregroundColor(MUTED).id(i)
                        }
                    }
                    .padding(.vertical, 8).padding(.horizontal, 10)
                    .onAppear { proxy.scrollTo(pairs.count - 1) }
                    .onChange(of: sans.count) { _ in proxy.scrollTo(pairs.count - 1) }
                }
            }
            .background(CARD).clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Setup screen

struct PlaySetupScreen: View {
    @ObservedObject var c: GameController
    @ObservedObject var game: LocalGameManager
    @State private var vsBot = true
    @State private var level = 3
    @State private var color = "w"

    var body: some View {
        let L = c.lang
        let t = { (ru: String, en: String) in playText(L, ru, en) }
        return Page {
            Header(c: c, title: t("Партия", "Play a Game"))
            VStack(alignment: .leading, spacing: 14) {
                if game.hasSaved {
                    GoldButton(text: t("▶️ Продолжить партию", "▶️ Continue saved game")) { c.continueLocalGame() }
                }
                Text(t("Соперник", "Opponent")).foregroundColor(MUTED).font(.system(size: 13, weight: .semibold))
                HStack(spacing: 8) {
                    Chip(text: t("🤖 Бот", "🤖 Bot") + (c.premium.isPremium ? "" : " 👑"), on: vsBot) { vsBot = true }
                    Chip(text: t("👥 Вдвоём на одном телефоне", "👥 Two players, one phone"), on: !vsBot) { vsBot = false }
                }
                if vsBot {
                    Text(t("Уровень бота", "Bot level")).foregroundColor(MUTED).font(.system(size: 13, weight: .semibold))
                    HStack(spacing: 8) {
                        ForEach(1...5, id: \.self) { l in Chip(text: "\(l)", on: level == l) { level = l } }
                    }
                    Text(levelName(level, L)).foregroundColor(TEXT).font(.system(size: 14))
                    Text(t("Ваш цвет", "Your colour")).foregroundColor(MUTED).font(.system(size: 13, weight: .semibold))
                    HStack(spacing: 8) {
                        Chip(text: t("Белые", "White"), on: color == "w") { color = "w" }
                        Chip(text: t("Чёрные", "Black"), on: color == "b") { color = "b" }
                        Chip(text: t("Случайно", "Random"), on: color == "r") { color = "r" }
                    }
                } else {
                    Text(t("Передавайте телефон друг другу после каждого хода. Доска поворачивается к тому, чей ход (можно отключить во время партии).",
                           "Pass the phone after every move. The board turns to the side to move (can be switched off during the game)."))
                        .foregroundColor(MUTED).font(.system(size: 14))
                }
                GoldButton(text: t("Начать партию", "Start game")) {
                    let col: Character = color == "r" ? (Bool.random() ? "w" : "b") : Character(color)
                    c.startLocalGame(vsBot ? .bot(level: level) : .twoPlayer, humanColor: vsBot ? col : "w")
                }
            }
            .padding(16).frame(maxWidth: .infinity)
            .background(CARD).overlay(RoundedRectangle(cornerRadius: 18).stroke(LINE, lineWidth: 1)).clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }

    private func levelName(_ l: Int, _ lang: Lang) -> String {
        let ru = ["Новичок", "Любитель", "Клубный игрок", "Сильный", "Мастер"]
        let en = ["Beginner", "Casual", "Club player", "Strong", "Master"]
        return lang == .ru ? ru[l - 1] : en[l - 1]
    }
}

// MARK: - Game screen

struct PlayGameScreen: View {
    @ObservedObject var c: GameController
    @ObservedObject var game: LocalGameManager
    @State private var confirmResign = false
    @State private var drawRefused = false

    var body: some View {
        ZStack {
            GeometryReader { geo in
                if geo.size.width > geo.size.height {
                    HStack(spacing: 16) {
                        ChessBoardView(c: game).frame(width: min(geo.size.height - 32, geo.size.width * 0.6))
                        ScrollView { VStack(alignment: .leading) { top; bottom } }
                    }.padding(16)
                } else {
                    ScrollView {
                        VStack(alignment: .leading) {
                            top
                            ChessBoardView(c: game)
                            bottom
                        }.padding(16)
                    }
                }
            }
            .background(BG)

            if let moves = game.promotionChoices { LocalPromotionDialog(game: game, moves: moves, label: c.s.promote) }
            if confirmResign { resignDialog }
        }
    }

    private var t: (String, String) -> String { { ru, en in playText(c.lang, ru, en) } }

    private var top: some View {
        VStack(alignment: .leading, spacing: 6) {
            Header(c: c, title: game.isBotGame ? t("Бот · уровень \(game.botLevel)", "Bot · level \(game.botLevel)") : t("Вдвоём", "Two players"))
            HStack {
                Circle().fill(game.turn == "w" ? Color(red: 0.98, green: 0.96, blue: 0.92) : Color(red: 0.17, green: 0.15, blue: 0.13))
                    .overlay(Circle().stroke(Color(red: 0.54, green: 0.48, blue: 0.38), lineWidth: 2)).frame(width: 14, height: 14)
                Text(statusLine).foregroundColor(TEXT).fontWeight(.semibold)
                Spacer()
                if game.thinking { ProgressView().tint(GOLD) }
            }
            MoveListView(sans: game.sanList)
        }
    }

    private var statusLine: String {
        if game.isBotGame {
            if game.thinking { return t("Бот думает…", "Bot is thinking…") }
            return game.turn == game.humanColor ? t("Ваш ход", "Your move") : t("Ход бота", "Bot's move")
        }
        return game.turn == "w" ? t("Ход белых", "White to move") : t("Ход чёрных", "Black to move")
    }

    @ViewBuilder private var bottom: some View {
        if let e = game.end {
            let r = endText(e, lang: c.lang, me: game.isBotGame ? game.humanColor : nil)
            VStack(spacing: 10) {
                Text(r.0).foregroundColor(r.1).font(.system(size: 20, weight: .bold)).multilineTextAlignment(.center)
                GoldButton(text: t("🔁 Ещё партия", "🔁 Play again")) { c.rematchLocal() }
                AltButton(text: t("Готово", "Done"), ghost: true) { c.goHome() }
            }
            .padding(16).frame(maxWidth: .infinity)
            .background(CARD).overlay(RoundedRectangle(cornerRadius: 18).stroke(LINE, lineWidth: 1)).clipShape(RoundedRectangle(cornerRadius: 18))
            .padding(.top, 10)
        } else {
            VStack(spacing: 10) {
                if drawRefused {
                    Text(t("Бот отклонил ничью", "The bot declined the draw")).foregroundColor(MUTED).font(.system(size: 13))
                }
                HStack(spacing: 10) {
                    AltButton(text: "↩️ " + t("Отменить ход", "Undo"), enabled: game.canUndo) { game.undo() }
                    AltButton(text: "🤝 " + t("Ничья", "Draw"), enabled: !game.thinking) {
                        drawRefused = !game.offerDraw()
                    }
                }
                AltButton(text: "🏳️ " + t("Сдаться", "Resign"), ghost: true) { confirmResign = true }
                if !game.isBotGame {
                    Toggle(isOn: Binding(get: { game.rotateBoard }, set: { game.setRotate($0) })) {
                        Text(t("Поворачивать доску", "Rotate board")).foregroundColor(MUTED)
                    }.tint(GOLD)
                }
            }.padding(.top, 10)
        }
    }

    private var resignDialog: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea().onTapGesture { confirmResign = false }
            VStack(spacing: 10) {
                Text(t("Сдаться?", "Resign?")).foregroundColor(TEXT).font(.system(size: 20, weight: .bold))
                GoldButton(text: t("Да, сдаться", "Yes, resign")) { confirmResign = false; game.resign() }
                AltButton(text: t("Нет", "No"), ghost: true) { confirmResign = false }
            }
            .padding(18).background(CARD).overlay(RoundedRectangle(cornerRadius: 20).stroke(LINE, lineWidth: 1)).clipShape(RoundedRectangle(cornerRadius: 20))
            .padding(24)
        }
    }
}

private struct LocalPromotionDialog: View {
    @ObservedObject var game: LocalGameManager
    let moves: [Move]
    let label: String
    var body: some View {
        let white = game.turn == "w"
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea().onTapGesture { game.choosePromotion(nil) }
            VStack(spacing: 12) {
                Text(label).foregroundColor(TEXT).fontWeight(.bold)
                HStack(spacing: 8) {
                    ForEach(Array("qrbn"), id: \.self) { q in
                        if let m = moves.first(where: { $0.promo == q }) {
                            Button { game.choosePromotion(m) } label: {
                                Canvas { context, size in context.drawPiece(white ? Character(q.uppercased()) : q, side: size.width) }
                                    .frame(width: 56, height: 56).padding(4)
                                    .background(Color(red: 0xEC / 255, green: 0xD8 / 255, blue: 0xB0 / 255))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                }
            }.padding(18).background(CARD).clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }
}
