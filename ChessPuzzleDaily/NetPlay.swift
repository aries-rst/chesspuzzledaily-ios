import Foundation
import UIKit
import MultipeerConnectivity

// iOS equivalent of NetPlay.kt — Bluetooth/Wi-Fi local multiplayer via Apple's
// MultipeerConnectivity framework (the iOS counterpart of Android's Nearby Connections API).
// Hosting needs Premium (GameController.hostNetGame); finding and joining a game is free.
//
// Protocol: the guest picks a host from the list of nearby games. Once connected, the host sends
// `.start` with the opening FEN and its own colour (White first, colours swap on every rematch);
// from then on each side sends the single `.move` it just applied, in UCI form, and the other side
// replays it locally. Both phones apply the same draw rules (stalemate, threefold repetition,
// 50 moves, insufficient material); draw offers and rematches are explicit messages.

/// Shared contract so `ChessBoardView` (BoardView.swift) can render either a puzzle session
/// (`GameController`) or a live nearby game (`NetPlayManager`) without duplicating the Canvas
/// drawing code.
@MainActor
protocol BoardDisplaying: AnyObject {
      var pieces: [BoardPiece] { get }
      var flip: Bool { get }
      var selected: Int { get }
      var targets: Set<Int> { get }
      var lastFrom: Int { get }
      var lastTo: Int { get }
      var hintSq: Int { get }
      var checkSq: Int { get }
      var shake: Int { get }
      var boardTheme: BoardTheme { get }
      func isCaptureTarget(_ sq: Int) -> Bool
      func tapSquare(_ sq: Int)
}

extension GameController: BoardDisplaying {}

private enum NetMsgType: String, Codable { case start, move, resign, drawOffer, drawAccept, drawDecline, rematch }
private struct NetMessage: Codable {
      var type: NetMsgType
      var fen: String = ""
      var uci: String = ""
      var hostColor: String = "w"
}

enum NetConnState { case idle, hosting, browsing, connecting, connected, lost }
enum NetOutcome: Equatable {
      case checkmateWin, checkmateLoss, stalemate, resignedByMe, resignedByOpponent, disconnected
      case drawRepetition, drawFifty, drawInsufficient, drawAgreed
}

private let NET_SERVICE = "cpd-chess"
private let NET_START_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
private let NAME_KEY = "cpd_player_name"

struct NearbyHost: Identifiable, Equatable {
      let peer: MCPeerID
      var id: String { peer.displayName + "#\(peer.hash)" }
      var name: String { peer.displayName }
}

@MainActor
final class NetPlayManager: NSObject, ObservableObject, BoardDisplaying {
      private var myPeerId = MCPeerID(displayName: "Player")
      private var session: MCSession?
      private var advertiser: MCNearbyServiceAdvertiser?
      private var browser: MCNearbyServiceBrowser?
      private let model = BoardModel()
      private var position = Position.fromFen(NET_START_FEN)
      private var keys: [String] = []
      private var connectedPeer: MCPeerID?
      var sound: SoundManager?

      @Published private(set) var state: NetConnState = .idle
      @Published private(set) var peerName = ""
      @Published private(set) var isHost = false
      @Published private(set) var myColor: Character = "w"
      @Published private(set) var started = false
      @Published private(set) var sanList: [String] = []
      @Published private(set) var outcome: NetOutcome? = nil
      @Published private(set) var hosts: [NearbyHost] = []
      @Published private(set) var drawOfferIncoming = false
      @Published private(set) var drawOfferSent = false
      @Published private(set) var drawDeclined = false
      @Published private(set) var rematchIncoming = false
      @Published private(set) var rematchSent = false
      @Published var promotionChoices: [Move]? = nil
      @Published var playerName: String = UserDefaults.standard.string(forKey: NAME_KEY) ?? "" {
                didSet { UserDefaults.standard.set(playerName, forKey: NAME_KEY) }
      }

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

      /// Shown to the other player. iOS 16+ only reports a generic device name, so the player
      /// can type their own (saved between launches).
      private var displayName: String {
                var n = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
                if n.isEmpty { n = UIDevice.current.name }
                // MCPeerID display names must stay within 63 UTF-8 bytes.
                while n.utf8.count > 60 { n.removeLast() }
                return n.isEmpty ? "Player" : n
      }

      private func newSession() -> MCSession {
                session?.delegate = nil
                session?.disconnect()
                myPeerId = MCPeerID(displayName: displayName)
                let s = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .required)
                s.delegate = self
                session = s
                connectedPeer = nil
                return s
      }

      // ---------------- hosting / joining ----------------

      func hostGame() {
                stopRadios()
                resetGame()
                _ = newSession()
                isHost = true
                state = .hosting
                let a = MCNearbyServiceAdvertiser(peer: myPeerId, discoveryInfo: nil, serviceType: NET_SERVICE)
                a.delegate = self
                a.startAdvertisingPeer()
                advertiser = a
      }

      /// Starts looking for hosts nearby; the player then picks one from `hosts`.
      func joinGame() {
                stopRadios()
                resetGame()
                _ = newSession()
                isHost = false
                hosts = []
                state = .browsing
                let b = MCNearbyServiceBrowser(peer: myPeerId, serviceType: NET_SERVICE)
                b.delegate = self
                b.startBrowsingForPeers()
                browser = b
      }

      func connect(to host: NearbyHost) {
                guard state == .browsing, let session, let browser else { return }
                state = .connecting
                peerName = host.name
                browser.invitePeer(host.peer, to: session, withContext: nil, timeout: 20)
      }

      private func stopRadios() {
                advertiser?.stopAdvertisingPeer(); advertiser = nil
                browser?.stopBrowsingForPeers(); browser = nil
      }

      func stop() {
                stopRadios()
                session?.disconnect()
                session?.delegate = nil
                session = nil
                connectedPeer = nil
                hosts = []
                state = .idle; started = false; outcome = nil
      }

      private func resetGame() {
                position = Position.fromFen(NET_START_FEN)
                keys = [ChessRules.key(position)]
                model.load(position); pieces = model.pieces
                flip = myColor == "b"; selected = -1; targets = []
                lastFrom = -1; lastTo = -1; checkSq = -1; sanList = []
                started = false; outcome = nil; promotionChoices = nil
                drawOfferIncoming = false; drawOfferSent = false; drawDeclined = false
                rematchIncoming = false; rematchSent = false
      }

      func resign() {
                guard started, outcome == nil else { return }
                send(NetMessage(type: .resign))
                outcome = .resignedByMe
      }

      // ---------------- draws / rematch ----------------

      func offerDraw() {
                guard started, outcome == nil, !drawOfferSent else { return }
                drawOfferSent = true; drawDeclined = false
                send(NetMessage(type: .drawOffer))
      }

      func answerDraw(_ accept: Bool) {
                guard drawOfferIncoming else { return }
                drawOfferIncoming = false
                send(NetMessage(type: accept ? .drawAccept : .drawDecline))
                if accept && outcome == nil { outcome = .drawAgreed }
      }

      /// Asks for another game. When both sides have asked, the new game starts with colours swapped.
      func requestRematch() {
                guard outcome != nil, state == .connected, !rematchSent else { return }
                rematchSent = true
                send(NetMessage(type: .rematch))
                if rematchIncoming { beginRematch() }
      }

      private func beginRematch() {
                // Only the host decides colours and sends .start, so both phones agree.
                guard isHost else { return }
                let newHostColor: Character = myColor == "w" ? "b" : "w"
                myColor = newHostColor
                resetGame()
                started = true
                send(NetMessage(type: .start, fen: NET_START_FEN, hostColor: String(newHostColor)))
      }

      // ---------------- moves ----------------

      func tapSquare(_ sq: Int) {
                guard started, outcome == nil, promotionChoices == nil, position.turn == myColor else { return }
                let hits = selected >= 0 ? position.legalMoves().filter { $0.from == selected && $0.to == sq } : []
                if !hits.isEmpty {
                              if hits.count > 1 { promotionChoices = hits; return }
                              commitLocal(hits[0])
                              return
                }
                let p = position.board[sq]
                if p != EMPTY, colorOf(p) == myColor {
                              selected = (sq == selected) ? -1 : sq
                              targets = selected >= 0 ? Set(position.legalMoves().filter { $0.from == sq }.map { $0.to }) : []
                } else {
                              selected = -1; targets = []
                }
      }

      func choosePromotion(_ m: Move?) {
                promotionChoices = nil
                if let m { commitLocal(m) } else { selected = -1; targets = [] }
      }

      private func commitLocal(_ m: Move) {
                let mover = position.turn
                var mm = m
                mm.san = position.san(mm)
                position.apply(&mm)
                apply(mm, mover: mover)
                send(NetMessage(type: .move, uci: mm.uci()))
                checkOutcome()
      }

      private func applyRemote(uci: String) {
                guard uci.count >= 4, var m = position.moveFromUci(uci) else { return }
                let mover = position.turn
                m.san = position.san(m)
                position.apply(&m)
                apply(m, mover: mover)
                checkOutcome()
      }

      private func apply(_ m: Move, mover: Character) {
                let promoted: Character? = m.promo.map { mover == "w" ? Character($0.uppercased()) : $0 }
                model.apply(m, promotedTo: promoted)
                pieces = model.pieces
                lastFrom = m.from; lastTo = m.to; selected = -1; targets = []
                sanList.append(m.san)
                keys.append(ChessRules.key(position))
                let check = position.inCheck()
                checkSq = check ? position.kingSq(position.turn) : -1
                if check { sound?.check() } else if m.captured != EMPTY { sound?.capture() } else { sound?.move() }
                // A move cancels any pending draw offer.
                drawOfferIncoming = false; drawOfferSent = false
      }

      private func checkOutcome() {
                guard outcome == nil else { return }
                if position.legalMoves().isEmpty {
                              if position.inCheck() {
                                                outcome = (position.turn == myColor) ? .checkmateLoss : .checkmateWin
                              } else {
                                                outcome = .stalemate
                              }
                } else if ChessRules.insufficientMaterial(position) {
                              outcome = .drawInsufficient
                } else if position.half >= 100 {
                              outcome = .drawFifty
                } else if let k = keys.last, keys.filter({ $0 == k }).count >= 3 {
                              outcome = .drawRepetition
                }
      }

      // ---------------- networking ----------------

      private func send(_ msg: NetMessage) {
                guard let session, !session.connectedPeers.isEmpty, let data = try? JSONEncoder().encode(msg) else { return }
                try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
      }

      private func beginIfHost() {
                guard isHost, state == .connected, !started else { return }
                myColor = "w"; flip = false; started = true
                send(NetMessage(type: .start, fen: NET_START_FEN, hostColor: "w"))
      }

      fileprivate func handle(_ msg: NetMessage) {
                switch msg.type {
                case .start:
                              guard !isHost else { return }
                              myColor = msg.hostColor == "w" ? "b" : "w"
                              resetGame()
                              position = Position.fromFen(msg.fen.isEmpty ? NET_START_FEN : msg.fen)
                              keys = [ChessRules.key(position)]
                              model.load(position); pieces = model.pieces
                              flip = myColor == "b"
                              started = true
                case .move:
                              applyRemote(uci: msg.uci)
                case .resign:
                              if outcome == nil { outcome = .resignedByOpponent }
                case .drawOffer:
                              if outcome == nil { drawOfferIncoming = true }
                case .drawAccept:
                              if drawOfferSent && outcome == nil { outcome = .drawAgreed }
                              drawOfferSent = false
                case .drawDecline:
                              drawOfferSent = false; drawDeclined = true
                case .rematch:
                              rematchIncoming = true
                              if rematchSent { beginRematch() }
                }
      }

      fileprivate func peerChanged(_ peerID: MCPeerID, _ newState: MCSessionState, from s: MCSession) {
                guard s === session else { return }
                switch newState {
                case .connected:
                              guard connectedPeer == nil else { return }
                              connectedPeer = peerID
                              peerName = peerID.displayName
                              state = .connected
                              stopRadios()
                              beginIfHost()
                case .connecting:
                              break
                case .notConnected:
                              guard connectedPeer == nil || connectedPeer == peerID else { return }
                              if started, outcome == nil { outcome = .disconnected }
                              connectedPeer = nil
                              state = .lost
                @unknown default:
                              break
                }
      }

      fileprivate func shouldAccept(_ peerID: MCPeerID) -> MCSession? {
                // One opponent only: refuse further invitations once a game is set up.
                guard state == .hosting, connectedPeer == nil, let session else { return nil }
                peerName = peerID.displayName
                return session
      }

      fileprivate func found(_ peer: MCPeerID) {
                guard state == .browsing else { return }
                if !hosts.contains(where: { $0.peer == peer }) { hosts.append(NearbyHost(peer: peer)) }
      }

      fileprivate func lost(_ peer: MCPeerID) {
                hosts.removeAll { $0.peer == peer }
      }
}

extension NetPlayManager: MCSessionDelegate {
      nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
                Task { @MainActor in self.peerChanged(peerID, state, from: session) }
      }

      nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
                guard let msg = try? JSONDecoder().decode(NetMessage.self, from: data) else { return }
                Task { @MainActor in self.handle(msg) }
      }

      nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
      nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
      nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension NetPlayManager: MCNearbyServiceAdvertiserDelegate {
      nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
                Task { @MainActor in
                                  if let s = self.shouldAccept(peerID) { invitationHandler(true, s) } else { invitationHandler(false, nil) }
                     }
      }
}

extension NetPlayManager: MCNearbyServiceBrowserDelegate {
      nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
                Task { @MainActor in self.found(peerID) }
      }
      nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
                Task { @MainActor in self.lost(peerID) }
      }
}
