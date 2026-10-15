import SwiftUI

// Port of ui/Screens.kt — every screen, ported 1:1 where SwiftUI has a direct equivalent.
// Cross-promotion row and the AdMob banner (Android-only) are left out for this pass; the
// exit / "privacy settings" rows are iOS-inappropriate and left out too (see the note on
// each below).

// ---------- palette (same as css/style.css) ----------
let BG = Color(red: 0x17 / 255, green: 0x12 / 255, blue: 0x0E / 255)
let BG2 = Color(red: 0x22 / 255, green: 0x1A / 255, blue: 0x14 / 255)
let CARD = Color(red: 0x2B / 255, green: 0x21 / 255, blue: 0x19 / 255)
let LINE = Color(red: 0x3D / 255, green: 0x30 / 255, blue: 0x25 / 255)
let TEXT = Color(red: 0xF3 / 255, green: 0xEA / 255, blue: 0xD8 / 255)
let MUTED = Color(red: 0xB9 / 255, green: 0xA8 / 255, blue: 0x8C / 255)
let GOLD = Color(red: 0xE0 / 255, green: 0xAD / 255, blue: 0x4F / 255)
let GOLD2 = Color(red: 0xF5 / 255, green: 0xCF / 255, blue: 0x7E / 255)
let OK = Color(red: 0x5F / 255, green: 0xB3 / 255, blue: 0x6A / 255)
let BAD = Color(red: 0xD9 / 255, green: 0x58 / 255, blue: 0x4A / 255)
let INK = Color(red: 0x2A / 255, green: 0x1D / 255, blue: 0x0C / 255)

// ---------- shared widgets ----------
struct GoldButton: View {
    let text: String
    var enabled: Bool = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(text).fontWeight(.bold).font(.system(size: 17))
                .foregroundColor(INK.opacity(enabled ? 1 : 0.45))
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(LinearGradient(colors: [GOLD2, GOLD], startPoint: .top, endPoint: .bottom))
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }.disabled(!enabled)
    }
}

struct AltButton: View {
    let text: String
    var enabled: Bool = true
    var ghost: Bool = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(text).fontWeight(ghost ? .medium : .bold).font(.system(size: 17)).multilineTextAlignment(.center)
                .foregroundColor((ghost ? MUTED : TEXT).opacity(enabled ? 1 : 0.45))
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(ghost ? Color.clear : CARD)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(LINE, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }.disabled(!enabled)
    }
}

struct IconBtn: View {
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label).font(.system(size: 20))
                .frame(width: 42, height: 42)
                .background(CARD).overlay(RoundedRectangle(cornerRadius: 12).stroke(LINE, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct MuteButton: View {
    @ObservedObject var c: GameController
    var body: some View { IconBtn(label: c.muted ? "🔇" : "🔊") { c.toggleMute() } }
}

struct Header: View {
    @ObservedObject var c: GameController
    let title: String
    var body: some View {
        HStack {
            IconBtn(label: "🏠") { c.goHome() }
            Text(title).foregroundColor(TEXT).font(.system(size: 19, weight: .bold)).lineLimit(1)
                .frame(maxWidth: .infinity).multilineTextAlignment(.center)
            MuteButton(c: c)
        }.padding(.bottom, 12)
    }
}

struct Chip: View {
    let text: String
    var on: Bool = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(text).font(.system(size: 13, weight: on ? .bold : .regular)).lineLimit(1)
                .foregroundColor(on ? INK : TEXT)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(on ? GOLD : CARD)
                .overlay(Capsule().stroke(on ? GOLD : LINE, lineWidth: 1))
                .clipShape(Capsule())
        }
    }
}

struct Logo: View {
    let size: CGFloat
    var body: some View {
        Canvas { context, sz in
            let rect = CGRect(origin: .zero, size: sz)
            context.fill(Path(ellipseIn: rect), with: .color(CARD))
            context.stroke(Path(ellipseIn: rect.insetBy(dx: sz.width * 0.021, dy: sz.width * 0.021)), with: .color(GOLD), lineWidth: sz.width * 0.042)
            let inset = sz.width * 0.17
            var ctx = context
            ctx.translateBy(x: inset, y: inset * 0.95)
            ctx.drawPiece("N", side: sz.width * 0.66)
        }.frame(width: size, height: size)
    }
}

struct Page<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        ScrollView {
            VStack(spacing: 0) { content }.padding(16)
        }
        .background(LinearGradient(colors: [Color(red: 0x2A / 255, green: 0x20 / 255, blue: 0x18 / 255), BG, BG], startPoint: .top, endPoint: .bottom))
    }
}

// ---------- root ----------
struct RootView: View {
    @ObservedObject var c: GameController

    var body: some View {
        ZStack {
            BG.ignoresSafeArea()
            Group {
                switch c.screen {
                case .splash: SplashScreen(c: c)
                case .lang: LangScreen(c: c)
                case .home: HomeScreen(c: c)
                case .puzzle: PuzzleScreen(c: c)
                case .archive: ArchiveScreen(c: c)
                case .stats: StatsScreen(c: c)
                case .settings: SettingsScreen(c: c)
                case .lessons: LessonsScreen(c: c)
                case .achievements: AchievementsScreen(c: c)
                }
            }
            .frame(maxWidth: c.screen == .puzzle ? .infinity : 560)
            .frame(maxWidth: .infinity, alignment: .top)

            if let moves = c.promotionChoices { PromotionDialog(c: c, moves: moves) }
            if let streak = c.freezeOffer { FreezeDialog(c: c, streak: streak) }
            if let t = c.achToast {
                VStack {
                    Text(t).foregroundColor(INK).fontWeight(.bold).padding(.horizontal, 16).padding(.vertical, 10)
                        .background(GOLD).clipShape(RoundedRectangle(cornerRadius: 14)).padding(12)
                    Spacer()
                }
            }
        }
        .sheet(item: $c.sharePayload) { payload in ShareSheet(payload: payload) }
        .environment(\.layoutDirection, c.lang.rtl ? .rightToLeft : .leftToRight)
    }
}

struct SplashScreen: View {
    @ObservedObject var c: GameController
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Logo(size: 120)
            Text(c.s.appTitle).foregroundColor(TEXT).font(.system(size: 26, weight: .bold)).multilineTextAlignment(.center)
            Text(c.s.subtitle).foregroundColor(MUTED).multilineTextAlignment(.center)
            Spacer().frame(height: 10)
            Text("ARESTI LABS").foregroundColor(GOLD).font(.system(size: 12, weight: .bold)).tracking(4)
            Spacer()
        }
        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(BG)
        .task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            while c.db == nil { try? await Task.sleep(nanoseconds: 100_000_000) }
            try? await Task.sleep(nanoseconds: 400_000_000)
            if c.store.lang != nil && c.consumeChallenge() { return }
            c.go(c.store.lang == nil ? .lang : .home)
        }
    }
}

struct LangScreen: View {
    @ObservedObject var c: GameController
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("🌐 Выберите язык · Choose language").foregroundColor(TEXT).font(.system(size: 20, weight: .bold))
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                ForEach(Lang.allCases, id: \.self) { l in
                    AltButton(text: l.native) { c.setLanguage(l); c.sound.click(); c.go(.home) }
                }
            }
            .padding(24).frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(BG)
    }
}

// ---------- home ----------
struct HomeScreen: View {
    @ObservedObject var c: GameController
    var body: some View {
        guard let db = c.db else { return AnyView(EmptyView()) }
        let s = c.s
        let n = c.today(); let bucket = Daily.bucketOf(n); let rec = Daily.puzzleFor(db, n)
        let done = c.store.days[n].flatMap { $0.status != "progress" ? $0 : nil }
        return AnyView(
            Page {
                HStack {
                    IconBtn(label: "🌐") { c.sound.click(); c.go(.lang) }
                    Spacer()
                    MuteButton(c: c)
                }
                VStack {
                    Logo(size: 64)
                    Text(s.appTitle).foregroundColor(TEXT).font(.system(size: 25, weight: .bold)).multilineTextAlignment(.center).padding(.top, 6)
                    Text(s.subtitle).foregroundColor(MUTED).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity)
                HStack(spacing: 8) {
                    Pill(label: "🔥 \(s.streak):", value: "\(c.store.displayStreak(n))")
                    Pill(label: "♟ \(s.ranks[Ranks.index(c.store.rating)]):", value: "\(Int(c.store.rating))")
                }.padding(.vertical, 14)
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(s.weekday[bucket]).foregroundColor(TEXT).fontWeight(.bold)
                        Spacer()
                        Text("\(s.dailyNo)\(n)").foregroundColor(GOLD2).fontWeight(.bold)
                    }
                    Text("\(s.level[bucket]) · \(rec.mateN > 0 ? s.findMate(rec.mateN) : s.findBest)").foregroundColor(MUTED)
                        .padding(.top, 4).padding(.bottom, 12)
                    HStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 3).fill(i <= bucket ? GOLD : Color(red: 0x4A / 255, green: 0x3A / 255, blue: 0x2B / 255))
                                .frame(height: 6)
                        }
                    }.padding(.bottom, 12)
                    if let done {
                        Text("\(done.status == "solved" ? s.solvedToday : s.failedToday) \(done.grid)")
                            .foregroundColor(done.status == "solved" ? OK : BAD).fontWeight(.bold)
                        Countdown(label: s.nextIn)
                        Spacer().frame(height: 10)
                    }
                    GoldButton(text: done != nil ? s.solution : s.play) { c.startDaily(n) }
                }
                .padding(16)
                .background(LinearGradient(colors: [Color(red: 0x3A / 255, green: 0x2B / 255, blue: 0x1D / 255), Color(red: 0x26 / 255, green: 0x1D / 255, blue: 0x15 / 255)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color(red: 0x5A / 255, green: 0x44 / 255, blue: 0x30 / 255), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 20))

                Spacer().frame(height: 14)
                AltButton(text: "🎯 \(s.training)") { c.startTraining() }
                Spacer().frame(height: 10)
                HStack(spacing: 10) {
                    AltButton(text: "⚡ \(s.rush)") { c.startRush() }
                    AltButton(text: "📚 \(s.lessons)") { c.sound.click(); c.go(.lessons) }
                }
                Spacer().frame(height: 10)
                HStack(spacing: 10) {
                    AltButton(text: "📅 \(s.archive)") { c.sound.click(); c.go(.archive) }
                    AltButton(text: "📊 \(s.stats)") { c.sound.click(); c.go(.stats) }
                }
                Spacer().frame(height: 10)
                HStack(spacing: 10) {
                    AltButton(text: "🏅 \(s.achievements)", ghost: true) { c.sound.click(); c.go(.achievements) }
                    AltButton(text: "⚙️ \(s.settings)", ghost: true) { c.sound.click(); c.go(.settings) }
                }
                Text(s.credit).foregroundColor(Color(red: 0x7D / 255, green: 0x6E / 255, blue: 0x58 / 255)).font(.system(size: 11))
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.top, 12)
            }
        )
    }
}

struct Pill: View {
    let label: String; let value: String
    var body: some View {
        HStack(spacing: 0) {
            Text("\(label) ").foregroundColor(TEXT).font(.system(size: 14))
            Text(value).foregroundColor(GOLD2).font(.system(size: 14, weight: .bold))
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(CARD).overlay(Capsule().stroke(LINE, lineWidth: 1)).clipShape(Capsule())
    }
}

struct Countdown: View {
    let label: String
    @State private var text = ""
    var body: some View {
        HStack(spacing: 0) {
            Text("\(label) ").foregroundColor(MUTED)
            Text(text).foregroundColor(GOLD2).fontWeight(.bold).font(.system(.body, design: .monospaced))
        }
        .padding(.top, 6)
        .task {
            while !Task.isCancelled {
                var cal = Calendar(identifier: .gregorian); cal.timeZone = .current
                let now = Date()
                let next = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!
                let sec = max(0, Int(next.timeIntervalSince(now)))
                text = String(format: "%02d:%02d:%02d", sec / 3600, sec % 3600 / 60, sec % 60)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }
}

// ---------- puzzle ----------
struct PuzzleScreen: View {
    @ObservedObject var c: GameController
    var body: some View {
        GeometryReader { geo in
            Group {
                if geo.size.width > geo.size.height {
                    HStack(spacing: 16) {
                        ChessBoardView(c: c).frame(width: min(geo.size.height - 32, geo.size.width * 0.6))
                        ScrollView {
                            VStack(alignment: .leading) { PuzzleTop(c: c); PuzzleBottom(c: c) }
                        }
                    }.padding(16)
                } else {
                    ScrollView {
                        VStack(alignment: .leading) {
                            PuzzleTop(c: c)
                            Spacer().frame(height: 8)
                            ChessBoardView(c: c)
                            PuzzleBottom(c: c)
                        }.padding(16)
                    }
                }
            }
        }
        .background(BG)
    }
}

private struct PuzzleTop: View {
    @ObservedObject var c: GameController
    var body: some View {
        let s = c.s
        VStack(alignment: .leading, spacing: 8) {
            Header(c: c, title: c.title)
            if c.mode == .train {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(TRAIN_THEMES, id: \.self) { k in
                            Chip(text: themeName(k, c.lang) ?? k, on: k == c.store.theme) { c.setTheme(k) }
                        }
                    }
                }
            }
            if c.mode == .rush {
                HStack {
                    Text(String(format: "⏱ %d:%02d", c.rushSeconds / 60, c.rushSeconds % 60))
                        .foregroundColor(c.rushSeconds <= 15 ? BAD : GOLD2).fontWeight(.bold)
                        .font(.system(.title3, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading)
                    Text("✓ \(c.rushSolved)").foregroundColor(OK).fontWeight(.bold).padding(.trailing, 14)
                    Text(String(repeating: "❌", count: c.rushMistakes) + String(repeating: "▫", count: max(0, Rush.MAX_MISTAKES - c.rushMistakes)))
                }.padding(10).background(CARD).clipShape(RoundedRectangle(cornerRadius: 12))
            }
            if c.mode == .lesson, let i = Lessons.KEYS.firstIndex(of: c.lessonKey) {
                Text(s.lessonTexts[i]).foregroundColor(MUTED).font(.system(size: 14))
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(CARD).clipShape(RoundedRectangle(cornerRadius: 12))
            }
            HStack {
                Circle().fill(c.player == "w" ? Color(red: 0xFB / 255, green: 0xF6 / 255, blue: 0xEA / 255) : Color(red: 0x2B / 255, green: 0x26 / 255, blue: 0x22 / 255))
                    .overlay(Circle().stroke(Color(red: 0x8A / 255, green: 0x7A / 255, blue: 0x62 / 255), lineWidth: 2))
                    .frame(width: 14, height: 14)
                Text(c.player == "w" ? s.youPlayWhite : s.youPlayBlack).foregroundColor(TEXT).fontWeight(.semibold)
                    .padding(.leading, 8).frame(maxWidth: .infinity, alignment: .leading)
                Text(c.goal).foregroundColor(GOLD2).fontWeight(.bold)
            }
        }
    }
}

private struct PuzzleBottom: View {
    @ObservedObject var c: GameController
    var body: some View {
        let s = c.s
        VStack {
            Text(c.msg).frame(maxWidth: .infinity).padding(.vertical, 10).multilineTextAlignment(.center).fontWeight(.semibold)
                .foregroundColor(c.msgKind == .ok ? OK : (c.msgKind == .bad ? BAD : TEXT))
            if let r = c.result {
                ResultCard(c: c, r: r)
            } else if c.mode != .rush {
                AltButton(text: "💡 \(s.hintAd)", enabled: c.hintAvailable) { c.hint() }
            }
        }
    }
}

struct ResultCard: View {
    @ObservedObject var c: GameController
    let r: ResultUi
    var body: some View {
        let s = c.s
        VStack(spacing: 0) {
            if c.mode == .rush {
                Text("⚡ \(s.rushOver)").foregroundColor(TEXT).font(.system(size: 22, weight: .bold))
                Text("\(r.rushScore)").foregroundColor(GOLD2).font(.system(size: 56, weight: .heavy))
                Text(s.rushScore).foregroundColor(MUTED)
                Text(r.rushNewBest ? "🏆 \(s.rushNewBest)" : "\(s.best): \(r.rushBest)").foregroundColor(r.rushNewBest ? OK : TEXT)
                    .fontWeight(.bold).padding(.top, 6)
                Spacer().frame(height: 12)
                GoldButton(text: "⚡ \(s.rushAgain)") { c.rushAgain() }
                Spacer().frame(height: 10)
                AltButton(text: "📤 \(s.share)") { c.shareRush() }
            } else if c.mode == .lesson {
                Text(r.lessonDone ? s.lessonDone : (r.win ? "✅ \(s.solved)" : "❌ \(s.failed)")).foregroundColor(TEXT).font(.system(size: 22, weight: .bold))
                SolutionLine(label: s.solution, line: r.solution)
                Spacer().frame(height: 12)
                GoldButton(text: "\(s.next) →") { c.nextLessonPuzzle() }
            } else if c.mode == .daily {
                Text(r.win ? "🏆 \(s.solved)" : s.failed).foregroundColor(TEXT).font(.system(size: 22, weight: .bold))
                Text(r.grid).font(.system(size: 22)).tracking(3).padding(.vertical, 6)
                if !r.solvedIn.isEmpty { Text(r.solvedIn).foregroundColor(MUTED) }
                SolutionLine(label: s.solution, line: r.solution)
                if r.showStreak {
                    let n = c.today()
                    Text("🔥 \(s.streak): \(c.store.displayStreak(n)) · \(s.best): \(c.store.best)").foregroundColor(TEXT)
                }
                Spacer().frame(height: 12)
                GoldButton(text: "📤 \(s.share)") { c.share() }
                Spacer().frame(height: 10)
                AltButton(text: "🎯 \(s.toTraining)") { c.startTraining() }
            } else {
                Text(r.win ? "✅ \(s.solved)" : "❌ \(s.failed)").foregroundColor(TEXT).font(.system(size: 22, weight: .bold))
                if !r.ratingLine.isEmpty {
                    Text(r.ratingLine).foregroundColor(r.ratingUp ? OK : BAD).font(.system(size: 20, weight: .heavy)).padding(.top, 6)
                }
                if !r.rankUp.isEmpty { Text("🎖 \(r.rankUp)").foregroundColor(GOLD2).font(.system(size: 18, weight: .bold)).padding(.top, 4) }
                Text("\(s.puzzleRating): \(r.puzzleRating)").foregroundColor(MUTED)
                SolutionLine(label: s.solution, line: r.solution)
                Text("\(s.themes): \(r.themes)").foregroundColor(MUTED).font(.system(size: 13)).multilineTextAlignment(.center)
                Spacer().frame(height: 12)
                GoldButton(text: "\(s.next) →") { c.nextTraining() }
                Spacer().frame(height: 10)
                AltButton(text: "⚔️ \(s.share)") { c.share() }
            }
            Spacer().frame(height: 10)
            AltButton(text: "🏠 \(s.home)", ghost: true) { c.goHome() }
        }
        .padding(16).frame(maxWidth: .infinity)
        .background(CARD).overlay(RoundedRectangle(cornerRadius: 18).stroke(LINE, lineWidth: 1)).clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

private struct SolutionLine: View {
    let label: String; let line: String
    var body: some View {
        Text("\(label): \(line)").foregroundColor(GOLD2).font(.system(.body, design: .monospaced))
            .multilineTextAlignment(.center).lineSpacing(6).padding(.vertical, 8)
    }
}

struct PromotionDialog: View {
    @ObservedObject var c: GameController
    let moves: [Move]
    var body: some View {
        let white = c.player == "w"
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea().onTapGesture { c.choosePromotion(nil) }
            VStack(spacing: 12) {
                Text(c.s.promote).foregroundColor(TEXT).fontWeight(.bold)
                HStack(spacing: 8) {
                    ForEach(Array("qrbn"), id: \.self) { q in
                        if let m = moves.first(where: { $0.promo == q }) {
                            Button { c.choosePromotion(m) } label: {
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

// ---------- archive / stats / settings ----------
struct ArchiveScreen: View {
    @ObservedObject var c: GameController
    var body: some View {
        guard c.db != nil else { return AnyView(EmptyView()) }
        let s = c.s; let n = c.today()
        let fmt: DateFormatter = {
            let f = DateFormatter(); f.dateStyle = .medium; f.locale = Locale(identifier: c.lang.rawValue); f.timeZone = TimeZone(identifier: "UTC")
            return f
        }()
        return AnyView(
            Page {
                Header(c: c, title: s.archive)
                if n <= 1 { Text(s.archiveEmpty).foregroundColor(MUTED).multilineTextAlignment(.center).frame(maxWidth: .infinity) }
                ForEach(Array(stride(from: n - 1, through: 1, by: -1)), id: \.self) { d in
                    let b = Daily.bucketOf(d); let r = c.store.days[d]
                    let open = c.store.unlocked.contains(d) || r != nil
                    let date = Date(timeIntervalSince1970: TimeInterval(Daily.civilDaysOf(d)) * 86400)
                    let status: String = {
                        guard let r else { return open ? "" : "🔒" }
                        if r.status == "solved" { return "✅ \(r.grid)" }
                        if r.status == "failed" { return "❌ \(r.grid)" }
                        return "…"
                    }()
                    Button { c.sound.click(); c.openArchiveDay(d) } label: {
                        HStack {
                            Text("\(s.dailyNo)\(d)").foregroundColor(GOLD2).fontWeight(.heavy).frame(minWidth: 48, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(s.weekday[b]), \(fmt.string(from: date))").foregroundColor(TEXT)
                                Text(s.level[b] + (open ? "" : " · \(s.archiveLocked)")).foregroundColor(MUTED).font(.system(size: 13))
                            }.padding(.horizontal, 8).frame(maxWidth: .infinity, alignment: .leading)
                            Text(status).foregroundColor(TEXT)
                        }.padding(12)
                    }
                    .background(CARD).overlay(RoundedRectangle(cornerRadius: 14).stroke(LINE, lineWidth: 1)).clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.bottom, 8)
                }
            }
        )
    }
}

struct StatsScreen: View {
    @ObservedObject var c: GameController
    var body: some View {
        let s = c.s
        let ds = c.store.days.values.filter { $0.status != "progress" }; let won = ds.filter { $0.status == "solved" }.count
        let idx = Ranks.index(c.store.rating)
        let cells: [(String, String)] = [
            (s.played, "\(ds.count)"), (s.winPct, "\(ds.isEmpty ? 0 : 100 * won / ds.count)"),
            (s.streak, "\(c.store.displayStreak(c.today()))"), (s.best, "\(c.store.best)"),
            (s.rating, "\(Int(c.store.rating))"), (s.trainingSolved, "\(c.store.trainSolved)/\(c.store.trainPlayed)"),
            (s.rank, s.ranks[idx]),
            ("→ " + (Ranks.next(c.store.rating) != nil && idx + 1 < s.ranks.count ? s.ranks[idx + 1] : "—"), Ranks.next(c.store.rating).map { String($0) } ?? "👑"),
        ]
        return Page {
            Header(c: c, title: s.stats)
            ForEach(Array(stride(from: 0, to: cells.count, by: 2)), id: \.self) { i in
                HStack(spacing: 10) {
                    ForEach(cells[i..<min(i + 2, cells.count)], id: \.0) { k, v in
                        VStack {
                            Text(v).foregroundColor(GOLD2).font(.system(size: 26, weight: .bold))
                            Text(k).foregroundColor(TEXT).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).padding(14)
                        .background(CARD).overlay(RoundedRectangle(cornerRadius: 14).stroke(LINE, lineWidth: 1)).clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }.padding(.bottom, 10)
            }
            Text(s.calendar).foregroundColor(MUTED).font(.system(size: 13, weight: .medium)).padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            MonthCalendar(c: c)
        }
    }
}

struct SettingsScreen: View {
    @ObservedObject var c: GameController
    @State private var hint = ""
    var body: some View {
        let s = c.s; let stats = c.store.stats()
        return Page {
            Header(c: c, title: s.settings)
            SettingRow(label: s.language) { Seg(text: "🌐 \(c.lang.native)", on: true) { c.sound.click(); c.go(.lang) } }
            SettingRow(label: s.sound) {
                Seg(text: s.on, on: !c.muted) { if c.muted { c.toggleMute() } }
                Seg(text: s.off, on: c.muted) { if !c.muted { c.toggleMute() } }
            }
            Text(s.boardTheme).foregroundColor(MUTED).font(.system(size: 13)).padding(.top, 4).padding(.bottom, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                ForEach(BoardTheme.allCases, id: \.self) { t in
                    let open = t.isUnlocked(stats)
                    VStack {
                        ZStack {
                            Canvas { context, size in
                                let h = size.width / 2
                                for i in 0..<2 { for j in 0..<2 {
                                    context.fill(Path(CGRect(x: CGFloat(i) * h, y: CGFloat(j) * h, width: h, height: h)),
                                                 with: .color((i + j) % 2 == 0 ? Color(rgb: t.light & 0xFFFFFF) : Color(rgb: t.dark & 0xFFFFFF)))
                                } }
                            }
                            if !open { Text("🔒").font(.system(size: 18)) }
                        }
                        .frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(c.boardTheme == t ? GOLD : LINE, lineWidth: c.boardTheme == t ? 3 : 1))
                        Text(s.boardThemes[BoardTheme.allCases.firstIndex(of: t) ?? 0]).foregroundColor(TEXT).font(.system(size: 11)).lineLimit(1).padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity)
                    .onTapGesture {
                        if c.pickBoardTheme(t) { hint = "" }
                        else { hint = t.unlockStreak > 0 ? s.unlockStreak(t.unlockStreak) : s.unlockTrain(t.unlockTrain) }
                    }
                }
            }.padding(.bottom, 6)
            if !hint.isEmpty { Text(hint).foregroundColor(GOLD2).font(.system(size: 13)).padding(.bottom, 8) }
            SettingRow(label: s.notify) {
                Seg(text: s.on, on: c.store.notify) { c.sound.click(); c.setNotify(true) }
                Seg(text: s.off, on: !c.store.notify) { c.sound.click(); c.setNotify(false) }
            }
            Text(s.credit).foregroundColor(Color(red: 0x7D / 255, green: 0x6E / 255, blue: 0x58 / 255)).font(.system(size: 11))
                .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.top, 12)
        }
    }
}

private struct SettingRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        HStack {
            Text(label).foregroundColor(TEXT).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) { content() }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(CARD).overlay(RoundedRectangle(cornerRadius: 14).stroke(LINE, lineWidth: 1)).clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.bottom, 10)
    }
}

private struct Seg: View {
    let text: String; let on: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(text).foregroundColor(on ? INK : TEXT).font(.system(size: 14, weight: on ? .bold : .regular))
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(on ? GOLD : BG2).overlay(RoundedRectangle(cornerRadius: 10).stroke(LINE, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

struct FreezeDialog: View {
    @ObservedObject var c: GameController
    let streak: Int
    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea().onTapGesture { c.declineFreeze() }
            VStack(spacing: 10) {
                Text("❄️").font(.system(size: 44))
                Text(c.s.freezeTitle).foregroundColor(TEXT).font(.system(size: 20, weight: .bold)).multilineTextAlignment(.center)
                Text(c.s.freezeText(streak)).foregroundColor(MUTED).multilineTextAlignment(.center)
                GoldButton(text: c.s.freezeYes) { c.acceptFreeze() }
                AltButton(text: c.s.freezeNo, ghost: true) { c.declineFreeze() }
            }.padding(18).background(CARD).overlay(RoundedRectangle(cornerRadius: 20).stroke(LINE, lineWidth: 1)).clipShape(RoundedRectangle(cornerRadius: 20))
                .padding(24)
        }
    }
}

/// Month calendar on the stats screen: ✓ solved, ✗ failed, ❄️ frozen, today outlined.
struct MonthCalendar: View {
    @ObservedObject var c: GameController
    @State private var y: Int
    @State private var m: Int

    init(c: GameController) {
        self.c = c
        let now = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: Date())
        _y = State(initialValue: now.year ?? 2026)
        _m = State(initialValue: now.month ?? 1)
    }

    var body: some View {
        let today = c.today()
        let cells = MonthGrid.cells(year: y, month: m)
        VStack {
            HStack {
                Text("‹").foregroundColor(GOLD2).font(.system(size: 24)).padding(.horizontal, 12)
                    .onTapGesture { if m == 1 { m = 12; y -= 1 } else { m -= 1 } }
                Text("\(c.s.months[m - 1]) \(String(y))").foregroundColor(TEXT).fontWeight(.bold)
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center)
                Text("›").foregroundColor(GOLD2).font(.system(size: 24)).padding(.horizontal, 12)
                    .onTapGesture { if m == 12 { m = 1; y += 1 } else { m += 1 } }
            }
            HStack { ForEach(c.s.weekShort, id: \.self) { w in Text(w).foregroundColor(MUTED).font(.system(size: 12)).frame(maxWidth: .infinity) } }
                .padding(.top, 8)
            ForEach(Array(stride(from: 0, to: cells.count, by: 7)), id: \.self) { i in
                HStack {
                    ForEach(Array(cells[i..<min(i + 7, cells.count)].enumerated()), id: \.offset) { _, n in
                        ZStack {
                            if let n {
                                let r = c.store.days[n]
                                let (bg, mark): (Color, String) = {
                                    if r?.status == "solved" { return (OK.opacity(0.35), "✓") }
                                    if r?.status == "failed" { return (BAD.opacity(0.3), "✗") }
                                    if c.store.frozenDays.contains(n) { return (Color(red: 0x3F / 255, green: 0xA9 / 255, blue: 0xF5 / 255).opacity(0.33), "❄") }
                                    return (.clear, "")
                                }()
                                RoundedRectangle(cornerRadius: 8).fill(bg)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(n == today ? GOLD : .clear, lineWidth: 2))
                                Text(mark.isEmpty ? "\(MonthGrid.dayOfMonth(n, year: y, month: m))" : mark)
                                    .foregroundColor((n > today || n < 1) ? MUTED.opacity(0.4) : TEXT)
                                    .font(.system(size: 13, weight: mark.isEmpty ? .regular : .bold))
                            }
                        }.frame(maxWidth: .infinity).frame(height: 38).padding(2)
                    }
                }.padding(.top, 4)
            }
        }
        .padding(12).background(CARD).overlay(RoundedRectangle(cornerRadius: 14).stroke(LINE, lineWidth: 1)).clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.top, 6)
    }
}

struct LessonsScreen: View {
    @ObservedObject var c: GameController
    var body: some View {
        let s = c.s
        return Page {
            Header(c: c, title: s.lessons)
            Text(s.lessonsDesc).foregroundColor(MUTED).padding(.bottom, 10).frame(maxWidth: .infinity, alignment: .leading)
            ForEach(Array(Lessons.KEYS.enumerated()), id: \.offset) { i, key in
                let done = c.store.lessonSolved[key]?.count ?? 0
                Button { c.startLesson(key) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(i + 1). \(themeName(key, c.lang) ?? key)").foregroundColor(TEXT).fontWeight(.bold)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(done >= Lessons.PER_LESSON ? "🎓" : "\(done)/\(Lessons.PER_LESSON)").foregroundColor(GOLD2).fontWeight(.bold)
                        }
                        Text(s.lessonTexts[i]).foregroundColor(MUTED).font(.system(size: 13)).lineLimit(2)
                    }.padding(14)
                }
                .background(CARD).overlay(RoundedRectangle(cornerRadius: 14).stroke(LINE, lineWidth: 1)).clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.bottom, 10)
            }
        }
    }
}

struct AchievementsScreen: View {
    @ObservedObject var c: GameController
    var body: some View {
        let s = c.s; let st = c.store.stats()
        return Page {
            Header(c: c, title: s.achievements)
            ForEach(Array(stride(from: 0, to: ACHIEVEMENTS.count, by: 3)), id: \.self) { i in
                HStack(spacing: 10) {
                    let row = Array(ACHIEVEMENTS[i..<min(i + 3, ACHIEVEMENTS.count)])
                    ForEach(row, id: \.id) { a in
                        let got = isEarned(a, st)
                        VStack {
                            Text(got ? a.icon : "🔒").font(.system(size: 28))
                            Text(c.achTitle(a)).foregroundColor(got ? TEXT : MUTED).font(.system(size: 12)).multilineTextAlignment(.center).padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity).padding(10)
                        .background(got ? Color(red: 0x3A / 255, green: 0x2B / 255, blue: 0x1D / 255) : CARD)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(got ? GOLD : LINE, lineWidth: 1)).clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    if row.count < 3 { Spacer() }
                }.padding(.bottom, 10)
            }
        }
    }
}
