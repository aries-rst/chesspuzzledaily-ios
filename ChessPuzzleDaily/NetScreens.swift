import SwiftUI

// Paywall, nearby-play lobby and the live nearby board. Strings are RU/EN (other languages fall
// back to English) via `playText`, like the local game screens in LocalGame.swift.

// ---------- paywall ----------
struct PremiumScreen: View {
    @ObservedObject var c: GameController
    @ObservedObject var premium: PremiumStore
    var body: some View {
        let t = { (ru: String, en: String) in playText(c.lang, ru, en) }
        return Page {
            Header(c: c, title: t("Премиум", "Premium"))
            VStack(spacing: 14) {
                Text("👑").font(.system(size: 52))
                Text(t("Премиум", "Premium")).foregroundColor(TEXT).font(.system(size: 22, weight: .bold))
                Text(t("Разовая покупка — навсегда.", "One-time purchase — yours forever.")).foregroundColor(MUTED).multilineTextAlignment(.center)
                VStack(alignment: .leading, spacing: 8) {
                    Text(t("🚫 Без рекламы", "🚫 No ads")).foregroundColor(TEXT)
                    Text(t("💡 Подсказки, архив и заморозка серии без видео", "💡 Hints, archive and streak freeze without videos")).foregroundColor(TEXT)
                    Text(t("🤖 Игра с ботом — 5 уровней", "🤖 Play the bot — 5 levels")).foregroundColor(TEXT)
                    Text(t("📡 Создание игры рядом по Bluetooth / Wi-Fi (присоединиться можно бесплатно)",
                           "📡 Host nearby games over Bluetooth / Wi-Fi (joining is free)")).foregroundColor(TEXT)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                GoldButton(text: "\(t("Купить", "Buy")) · \(premium.priceText)", enabled: !premium.isLoading && !premium.isPremium) {
                    Task { await premium.purchase() }
                }
                AltButton(text: t("Восстановить покупки", "Restore Purchases"), ghost: true) {
                    Task { await premium.restore() }
                }
                if let err = premium.lastError {
                    Text(err).foregroundColor(BAD).font(.system(size: 13)).multilineTextAlignment(.center)
                }
            }
            .padding(16).frame(maxWidth: .infinity)
            .background(CARD).overlay(RoundedRectangle(cornerRadius: 18).stroke(LINE, lineWidth: 1)).clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .onChange(of: premium.isPremium) { owned in if owned { c.go(c.afterPremium) } }
    }
}

// ---------- lobby ----------
struct NetLobbyScreen: View {
    @ObservedObject var c: GameController
    @ObservedObject var net: NetPlayManager
    var body: some View {
        let t = { (ru: String, en: String) in playText(c.lang, ru, en) }
        return Page {
            Header(c: c, title: t("Играть рядом", "Play Nearby"))
            VStack(alignment: .leading, spacing: 14) {
                switch net.state {
                case .idle:
                    Text(t("Ваше имя для соперника", "Your name for the opponent")).foregroundColor(MUTED).font(.system(size: 13, weight: .semibold))
                    TextField(t("Например, Рустам", "e.g. Alex"), text: $net.playerName)
                        .textInputAutocapitalization(.words).autocorrectionDisabled()
                        .padding(12).background(BG2).foregroundColor(TEXT)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    GoldButton(text: "📶 " + t("Создать игру", "Host a Game") + (c.premium.isPremium ? "" : " 👑")) { c.hostNetGame() }
                    AltButton(text: "🔎 " + t("Найти игру (бесплатно)", "Find a Game (free)")) { net.joinGame() }
                    Text(t("Оба телефона должны быть рядом, с включёнными Bluetooth и Wi-Fi. Игра между iPhone и Android невозможна.",
                           "Both phones must be near each other with Bluetooth and Wi-Fi on. iPhone and Android can't play each other."))
                        .foregroundColor(MUTED).font(.system(size: 12))
                case .hosting:
                    HStack { Spacer(); ProgressView().tint(GOLD); Spacer() }
                    Text(t("Ждём соперника рядом… Имя игры: ", "Waiting for an opponent nearby… Game name: ") + net.playerNameOrDevice)
                        .foregroundColor(MUTED).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                    AltButton(text: t("Отмена", "Cancel"), ghost: true) { net.stop() }
                case .browsing:
                    Text(t("Найденные игры", "Games nearby")).foregroundColor(MUTED).font(.system(size: 13, weight: .semibold))
                    if net.hosts.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView().tint(GOLD)
                            Text(t("Ищем игры рядом…", "Looking for games nearby…")).foregroundColor(MUTED)
                        }
                    } else {
                        ForEach(net.hosts) { h in
                            AltButton(text: "♟️ " + h.name) { net.connect(to: h) }
                        }
                    }
                    AltButton(text: t("Отмена", "Cancel"), ghost: true) { net.stop() }
                case .connecting, .connected:
                    HStack { Spacer(); ProgressView().tint(GOLD); Spacer() }
                    Text(t("Подключаемся к: ", "Connecting to: ") + net.peerName).foregroundColor(TEXT).frame(maxWidth: .infinity)
                    AltButton(text: t("Отмена", "Cancel"), ghost: true) { net.stop() }
                case .lost:
                    Text(t("Не удалось подключиться. Проверьте, что телефоны рядом и Bluetooth / Wi-Fi включены.",
                           "Couldn't connect. Make sure the phones are close and Bluetooth / Wi-Fi are on."))
                        .foregroundColor(BAD).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                    GoldButton(text: t("Попробовать снова", "Try again")) { net.stop() }
                }
            }
            .padding(16).frame(maxWidth: .infinity)
            .background(CARD).overlay(RoundedRectangle(cornerRadius: 18).stroke(LINE, lineWidth: 1)).clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .onChange(of: net.started) { started in if started { c.go(.netGame) } }
    }
}

extension NetPlayManager {
    var playerNameOrDevice: String {
        let n = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? UIDevice.current.name : n
    }
}

// ---------- live game ----------
struct NetGameScreen: View {
    @ObservedObject var c: GameController
    @ObservedObject var net: NetPlayManager
    @State private var confirmResign = false

    private var t: (String, String) -> String { { ru, en in playText(c.lang, ru, en) } }

    var body: some View {
        ZStack {
            GeometryReader { geo in
                if geo.size.width > geo.size.height {
                    HStack(spacing: 16) {
                        ChessBoardView(c: net).frame(width: min(geo.size.height - 32, geo.size.width * 0.6))
                        ScrollView { VStack(alignment: .leading) { top; bottom } }
                    }.padding(16)
                } else {
                    ScrollView {
                        VStack(alignment: .leading) {
                            top
                            ChessBoardView(c: net)
                            bottom
                        }.padding(16)
                    }
                }
            }
            .background(BG)

            if let moves = net.promotionChoices { NetPromotionDialog(net: net, moves: moves, promoteLabel: c.s.promote) }
            if confirmResign { resignDialog }
            if net.drawOfferIncoming && net.outcome == nil { drawOfferDialog }
        }
    }

    private var top: some View {
        VStack(alignment: .leading, spacing: 6) {
            Header(c: c, title: t("Играть рядом", "Play Nearby"))
            HStack {
                Circle().fill(net.myColor == "w" ? Color(red: 0.98, green: 0.96, blue: 0.92) : Color(red: 0.17, green: 0.15, blue: 0.13))
                    .overlay(Circle().stroke(Color(red: 0.54, green: 0.48, blue: 0.38), lineWidth: 2)).frame(width: 14, height: 14)
                Text(net.outcome != nil ? (net.myColor == "w" ? t("Вы играли белыми", "You played White") : t("Вы играли чёрными", "You played Black"))
                     : (net.turn == net.myColor ? t("Ваш ход", "Your move") : t("Ход соперника", "Opponent's move")))
                    .foregroundColor(TEXT).fontWeight(.semibold)
                Spacer()
                Text(t("Соперник: ", "Opponent: ") + net.peerName).foregroundColor(MUTED).font(.system(size: 13)).lineLimit(1)
            }
            MoveListView(sans: net.sanList)
        }
    }

    private func outcomeText(_ o: NetOutcome) -> (String, Color) {
        switch o {
        case .checkmateWin: return (t("🏆 Мат! Вы победили", "🏆 Checkmate! You won"), OK)
        case .checkmateLoss: return (t("❌ Мат. Вы проиграли", "❌ Checkmate. You lost"), BAD)
        case .stalemate: return (t("🤝 Ничья — пат", "🤝 Draw — stalemate"), TEXT)
        case .resignedByOpponent: return (t("🏆 Соперник сдался", "🏆 Opponent resigned"), OK)
        case .resignedByMe: return (t("Вы сдались", "You resigned"), BAD)
        case .disconnected: return (t("Соперник отключился", "Opponent disconnected"), BAD)
        case .drawRepetition: return (t("🤝 Ничья — троекратное повторение", "🤝 Draw — threefold repetition"), TEXT)
        case .drawFifty: return (t("🤝 Ничья — правило 50 ходов", "🤝 Draw — 50-move rule"), TEXT)
        case .drawInsufficient: return (t("🤝 Ничья — недостаточно материала", "🤝 Draw — insufficient material"), TEXT)
        case .drawAgreed: return (t("🤝 Ничья по соглашению", "🤝 Draw by agreement"), TEXT)
        }
    }

    @ViewBuilder private var bottom: some View {
        if let o = net.outcome {
            let r = outcomeText(o)
            VStack(spacing: 10) {
                Text(r.0).foregroundColor(r.1).font(.system(size: 20, weight: .bold)).multilineTextAlignment(.center)
                if net.state == .connected {
                    if net.rematchIncoming && !net.rematchSent {
                        Text(t("Соперник предлагает реванш", "Your opponent wants a rematch")).foregroundColor(GOLD)
                    }
                    GoldButton(text: net.rematchSent ? t("Ждём соперника…", "Waiting for opponent…") : t("🔁 Реванш (цвета меняются)", "🔁 Rematch (colours swap)"),
                               enabled: !net.rematchSent) { net.requestRematch() }
                }
                AltButton(text: t("Готово", "Done"), ghost: true) { c.goHome() }
            }
            .padding(16).frame(maxWidth: .infinity)
            .background(CARD).overlay(RoundedRectangle(cornerRadius: 18).stroke(LINE, lineWidth: 1)).clipShape(RoundedRectangle(cornerRadius: 18))
            .padding(.top, 10)
        } else {
            VStack(spacing: 10) {
                if net.drawDeclined { Text(t("Соперник отклонил ничью", "Draw offer declined")).foregroundColor(MUTED).font(.system(size: 13)) }
                HStack(spacing: 10) {
                    AltButton(text: net.drawOfferSent ? t("Ничья предложена…", "Draw offered…") : "🤝 " + t("Предложить ничью", "Offer draw"),
                              enabled: !net.drawOfferSent) { net.offerDraw() }
                    AltButton(text: "🏳️ " + t("Сдаться", "Resign")) { confirmResign = true }
                }
            }.padding(.top, 10)
        }
    }

    private var resignDialog: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea().onTapGesture { confirmResign = false }
            VStack(spacing: 10) {
                Text(t("Сдаться?", "Resign?")).foregroundColor(TEXT).font(.system(size: 20, weight: .bold))
                GoldButton(text: t("Да, сдаться", "Yes, resign")) { confirmResign = false; net.resign() }
                AltButton(text: t("Нет", "No"), ghost: true) { confirmResign = false }
            }
            .padding(18).background(CARD).overlay(RoundedRectangle(cornerRadius: 20).stroke(LINE, lineWidth: 1)).clipShape(RoundedRectangle(cornerRadius: 20))
            .padding(24)
        }
    }

    private var drawOfferDialog: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(spacing: 10) {
                Text(t("Соперник предлагает ничью", "Your opponent offers a draw")).foregroundColor(TEXT).font(.system(size: 19, weight: .bold)).multilineTextAlignment(.center)
                GoldButton(text: t("Принять ничью", "Accept draw")) { net.answerDraw(true) }
                AltButton(text: t("Отклонить", "Decline"), ghost: true) { net.answerDraw(false) }
            }
            .padding(18).background(CARD).overlay(RoundedRectangle(cornerRadius: 20).stroke(LINE, lineWidth: 1)).clipShape(RoundedRectangle(cornerRadius: 20))
            .padding(24)
        }
    }
}

private struct NetPromotionDialog: View {
    @ObservedObject var net: NetPlayManager
    let moves: [Move]
    let promoteLabel: String
    var body: some View {
        let white = net.myColor == "w"
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea().onTapGesture { net.choosePromotion(nil) }
            VStack(spacing: 12) {
                Text(promoteLabel).foregroundColor(TEXT).fontWeight(.bold)
                HStack(spacing: 8) {
                    ForEach(Array("qrbn"), id: \.self) { q in
                        if let m = moves.first(where: { $0.promo == q }) {
                            Button { net.choosePromotion(m) } label: {
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
