import SwiftUI

// New screens for the premium-gated nearby multiplayer feature: the StoreKit paywall, the
// Multipeer host/join lobby, and the live board. Kept in their own file with a tiny RU/EN
// string table (NetStr below) so the existing 17-language Strings.swift — where every string
// is a required field across 17 struct literals — doesn't need touching for this pilot feature.
// Full localization of these few strings can follow if the other 4 games get ported too.

private struct NetStr {
      let payTitle: String
      let payBody: String
      let payBullet1: String
      let payBullet2: String
      let buy: String
      let restore: String
      let back: String

      let lobbyTitle: String
      let host: String
      let join: String
      let hosting: String
      let searching: String
      let connectedTo: (String) -> String
      let cancel: String

      let youWhite: String
      let youBlack: String
      let resign: String
      let resignConfirmTitle: String
      let resignConfirmYes: String
      let resignConfirmNo: String

      let youWon: String
      let youLost: String
      let draw: String
      let opponentLeft: String
      let opponentResigned: String
      let youResigned: String
      let done: String
      let promote: String
}

private let NET_RU = NetStr(
      payTitle: "Премиум",
      payBody: "Разовая покупка — навсегда.",
      payBullet1: "🚫 Без рекламы",
      payBullet2: "📡 Игра рядом по Bluetooth / Wi-Fi",
      buy: "Купить",
      restore: "Восстановить покупки",
      back: "Назад",
      lobbyTitle: "Играть рядом",
      host: "📶 Создать игру",
      join: "🔎 Найти игру",
      hosting: "Ждём соперника рядом…",
      searching: "Ищем игру рядом…",
      connectedTo: { "Соперник: \($0)" },
      cancel: "Отмена",
      youWhite: "Вы играете белыми",
      youBlack: "Вы играете чёрными",
      resign: "Сдаться",
      resignConfirmTitle: "Сдаться?",
      resignConfirmYes: "Да, сдаться",
      resignConfirmNo: "Нет",
      youWon: "🏆 Вы победили — мат!",
      youLost: "❌ Вы проиграли — мат",
      draw: "🤝 Ничья — пат",
      opponentLeft: "Соперник отключился",
      opponentResigned: "🏆 Соперник сдался",
      youResigned: "Вы сдались",
      done: "Готово",
      promote: "Выберите фигуру"
)

private let NET_EN = NetStr(
      payTitle: "Premium",
      payBody: "One-time purchase — yours forever.",
      payBullet1: "🚫 No ads",
      payBullet2: "📡 Nearby play over Bluetooth / Wi-Fi",
      buy: "Buy",
      restore: "Restore Purchases",
      back: "Back",
      lobbyTitle: "Play Nearby",
      host: "📶 Host a Game",
      join: "🔎 Find a Game",
      hosting: "Waiting for an opponent nearby…",
      searching: "Looking for a game nearby…",
      connectedTo: { "Opponent: \($0)" },
      cancel: "Cancel",
      youWhite: "You're playing White",
      youBlack: "You're playing Black",
      resign: "Resign",
      resignConfirmTitle: "Resign?",
      resignConfirmYes: "Yes, resign",
      resignConfirmNo: "No",
      youWon: "🏆 You won — checkmate!",
      youLost: "❌ You lost — checkmate",
      draw: "🤝 Draw — stalemate",
      opponentLeft: "Opponent disconnected",
      opponentResigned: "🏆 Opponent resigned",
      youResigned: "You resigned",
      done: "Done",
      promote: "Choose a piece"
)

private func netStr(_ lang: Lang) -> NetStr { lang == .ru ? NET_RU : NET_EN }

// ---------- paywall ----------
struct PremiumScreen: View {
      @ObservedObject var c: GameController
      @ObservedObject var premium: PremiumStore
      var body: some View {
                let t = netStr(c.lang)
                return Page {
                              Header(c: c, title: t.payTitle)
                              VStack(spacing: 14) {
                                                Text("👑").font(.system(size: 52))
                                                Text(t.payTitle).foregroundColor(TEXT).font(.system(size: 22, weight: .bold))
                                                Text(t.payBody).foregroundColor(MUTED).multilineTextAlignment(.center)
                                                VStack(alignment: .leading, spacing: 8) {
                                                                      Text(t.payBullet1).foregroundColor(TEXT)
                                                                      Text(t.payBullet2).foregroundColor(TEXT)
                                                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                                                GoldButton(text: "\(t.buy) · \(premium.priceText)", enabled: !premium.isLoading) {
                                                                      Task { await premium.purchase() }
                                                }
                                                AltButton(text: t.restore, ghost: true) {
                                                                      Task { await premium.restore() }
                                                }
                                                if let err = premium.lastError {
                                                                      Text(err).foregroundColor(BAD).font(.system(size: 13)).multilineTextAlignment(.center)
                                                }
                              }
                              .padding(16).frame(maxWidth: .infinity)
                              .background(CARD).overlay(RoundedRectangle(cornerRadius: 18).stroke(LINE, lineWidth: 1)).clipShape(RoundedRectangle(cornerRadius: 18))
                }
                .onChange(of: premium.isPremium) { owned in if owned { c.go(.netLobby) } }
      }
}

// ---------- lobby ----------
struct NetLobbyScreen: View {
      @ObservedObject var c: GameController
      @ObservedObject var net: NetPlayManager
      var body: some View {
                let t = netStr(c.lang)
                return Page {
                              Header(c: c, title: t.lobbyTitle)
                              VStack(spacing: 14) {
                                                switch net.state {
                                                                  case .idle:
                                                                      GoldButton(text: t.host) { net.hostGame() }
                                                                      AltButton(text: t.join) { net.joinGame() }
                                                                  case .hosting:
                                                                      ProgressView().tint(GOLD)
                                                                      Text(t.hosting).foregroundColor(MUTED).multilineTextAlignment(.center)
                                                                      AltButton(text: t.cancel, ghost: true) { net.stop() }
                                                                  case .browsing:
                                                                      ProgressView().tint(GOLD)
                                                                      Text(t.searching).foregroundColor(MUTED).multilineTextAlignment(.center)
                                                                      AltButton(text: t.cancel, ghost: true) { net.stop() }
                                                                  case .connected, .lost:
                                                                      ProgressView().tint(GOLD)
                                                                      Text(t.connectedTo(net.peerName)).foregroundColor(TEXT)
                                                                      AltButton(text: t.cancel, ghost: true) { net.stop() }
                                                }
                              }
                              .padding(16).frame(maxWidth: .infinity)
                              .background(CARD).overlay(RoundedRectangle(cornerRadius: 18).stroke(LINE, lineWidth: 1)).clipShape(RoundedRectangle(cornerRadius: 18))
                }
                .onChange(of: net.started) { started in if started { c.go(.netGame) } }
      }
}

// ---------- live game ----------
struct NetGameScreen: View {
      @ObservedObject var c: GameController
      @ObservedObject var net: NetPlayManager
      @State private var confirmResign = false
      var body: some View {
                let t = netStr(c.lang)
                return ZStack {
                              GeometryReader { geo in
                                                              Group {
                                                                                    if geo.size.width > geo.size.height {
                                                                                                              HStack(spacing: 16) {
                                                                                                                                            ChessBoardView(c: net).frame(width: min(geo.size.height - 32, geo.size.width * 0.6))
                                                                                                                                            ScrollView {
                                                                                                                                                                              VStack(alignment: .leading) {
                                                                                                                                                                                                                    NetTop(c: c, net: net, t: t)
                                                                                                                                                                                                                    NetBottom(c: c, net: net, t: t, confirmResign: $confirmResign)
                                                                                                                                                                                                                }
                                                                                                                                            }
                                                                                                              }.padding(16)
                                                                                    } else {
                                                                                                              ScrollView {
                                                                                                                                            VStack(alignment: .leading) {
                                                                                                                                                                              NetTop(c: c, net: net, t: t)
                                                                                                                                                                              Spacer().frame(height: 8)
                                                                                                                                                                              ChessBoardView(c: net)
                                                                                                                                                                              NetBottom(c: c, net: net, t: t, confirmResign: $confirmResign)
                                                                                                                                            }.padding(16)
                                                                                                              }
                                                                                    }
                                                              }
                                             }
                              .background(BG)

                              if let moves = net.promotionChoices { NetPromotionDialog(net: net, moves: moves, promoteLabel: t.promote) }
                              if confirmResign { NetResignDialog(net: net, t: t, show: $confirmResign) }
                }
      }
}

private struct NetTop: View {
      @ObservedObject var c: GameController
      @ObservedObject var net: NetPlayManager
      let t: NetStr
      var body: some View {
                VStack(alignment: .leading, spacing: 8) {
                              Header(c: c, title: t.lobbyTitle)
                              HStack {
                                                Circle().fill(net.myColor == "w" ? Color(red: 0xFB / 255, green: 0xF6 / 255, blue: 0xEA / 255) : Color(red: 0x2B / 255, green: 0x26 / 255, blue: 0x22 / 255))
                                                    .overlay(Circle().stroke(Color(red: 0x8A / 255, green: 0x7A / 255, blue: 0x62 / 255), lineWidth: 2))
                                                    .frame(width: 14, height: 14)
                                                Text(net.myColor == "w" ? t.youWhite : t.youBlack).foregroundColor(TEXT).fontWeight(.semibold)
                                                    .padding(.leading, 8).frame(maxWidth: .infinity, alignment: .leading)
                                                Text(t.connectedTo(net.peerName)).foregroundColor(MUTED).font(.system(size: 13))
                              }
                }
      }
}

private struct NetBottom: View {
      @ObservedObject var c: GameController
      @ObservedObject var net: NetPlayManager
      let t: NetStr
      @Binding var confirmResign: Bool
      var body: some View {
                VStack {
                              if let o = net.outcome {
                                                NetResultCard(c: c, t: t, outcome: o)
                              } else {
                                                AltButton(text: "🏳️ \(t.resign)") { confirmResign = true }
                              }
                }
      }
}

private struct NetResultCard: View {
      @ObservedObject var c: GameController
      let t: NetStr
      let outcome: NetOutcome
      var body: some View {
                let pair: (String, Color) = {
                              switch outcome {
                                            case .checkmateWin: return (t.youWon, OK)
                                            case .checkmateLoss: return (t.youLost, BAD)
                                            case .stalemate: return (t.draw, TEXT)
                                            case .resignedByOpponent: return (t.opponentResigned, OK)
                                            case .resignedByMe: return (t.youResigned, BAD)
                                            case .disconnected: return (t.opponentLeft, BAD)
                              }
                }()
                VStack(spacing: 10) {
                              Text(pair.0).foregroundColor(pair.1).font(.system(size: 20, weight: .bold)).multilineTextAlignment(.center)
                              GoldButton(text: t.done) { c.goHome() }
                }
                .padding(16).frame(maxWidth: .infinity)
                .background(CARD).overlay(RoundedRectangle(cornerRadius: 18).stroke(LINE, lineWidth: 1)).clipShape(RoundedRectangle(cornerRadius: 18))
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

private struct NetResignDialog: View {
      @ObservedObject var net: NetPlayManager
      let t: NetStr
      @Binding var show: Bool
      var body: some View {
                ZStack {
                              Color.black.opacity(0.5).ignoresSafeArea().onTapGesture { show = false }
                              VStack(spacing: 10) {
                                                Text(t.resignConfirmTitle).foregroundColor(TEXT).font(.system(size: 20, weight: .bold))
                                                GoldButton(text: t.resignConfirmYes) { show = false; net.resign() }
                                                AltButton(text: t.resignConfirmNo, ghost: true) { show = false }
                              }.padding(18).background(CARD).overlay(RoundedRectangle(cornerRadius: 20).stroke(LINE, lineWidth: 1)).clipShape(RoundedRectangle(cornerRadius: 20))
                                  .padding(24)
                }
      }
}
