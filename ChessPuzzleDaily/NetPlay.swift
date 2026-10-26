import Foundation
import UIKit
import MultipeerConnectivity

// iOS equivalent of NetPlay.kt — Bluetooth/Wi-Fi local multiplayer via Apple's
// MultipeerConnectivity framework (the iOS counterpart of Android's Nearby Connections API).
// Gated behind Premium: the UI only reaches here once `PremiumStore.shared.isPremium` is true
// (see NetScreens.swift / GameController.openNetPlay()).
//
// Protocol: the host is always White, the peer who joins is always Black — no in-band
// negotiation needed. Once the MultipeerConnectivity session connects, the host sends a
// `.start` message with the opening FEN; from then on each side sends the single `.move` it
// just applied, in UCI form, and the other side replays that exact move locally.

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

private enum NetMsgType: String, Codable { case start, move, resign }
private struct NetMessage: Codable {
      var type: NetMsgType
      var fen: String = ""
      var uci: String = ""
}

enum NetConnState { case idle, hosting, browsing, connected, lost }
enum NetOutcome: Equatable { case checkmateWin, checkmateLoss, stalemate, resignedByMe, resignedByOpponent, disconnected }

private let NET_SERVICE = "cpd-chess"
private let NET_START_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

@MainActor
final class NetPlayManager: NSObject, ObservableObject, BoardDisplaying {
      private let myPeerId = MCPeerID(displayName: UIDevice.current.name)
      private lazy var session: MCSession = {
                let s = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .required)
                s.delegate = self
                return s
      }()
      private var advertiser: MCNearbyServiceAdvertiser?
      private var browser: MCNearbyServiceBrowser?
      private let model = BoardModel()
      private var position = Position.fromFen(NET_START_FEN)

      @Published private(set) var state: NetConnState = .idle
      @Published private(set) var peerName = ""
      @Published private(set) var isHost = false
      @Published private(set) var myColor: Character = "w"
      @Published private(set) var started = false
      @Published private(set) var sanList: [String] = []
      @Published private(set) var outcome: NetOutcome? = nil
      @Published var promotionChoices: [Move]? = nil

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

      // ---------------- hosting / joining ----------------

      func hostGame() {
                resetGame()
                isHost = true
                state = .hosting
                let a = MCNearbyServiceAdvertiser(peer: myPeerId, discoveryInfo: nil, serviceType: NET_SERVICE)
                a.delegate = self
                a.startAdvertisingPeer()
                advertiser = a
      }

      func joinGame() {
                resetGame()
                isHost = false
                state = .browsing
                let b = MCNearbyServiceBrowser(peer: myPeerId, serviceType: NET_SERVICE)
                b.delegate = self
                b.startBrowsingForPeers()
                browser = b
      }

      func stop() {
                advertiser?.stopAdvertisingPeer(); advertiser = nil
                browser?.stopBrowsingForPeers(); browser = nil
                session.disconnect()
                state = .idle; started = false; outcome = nil
      }

      private func resetGame() {
                position = Position.fromFen(NET_START_FEN)
                model.load(position); pieces = model.pieces
                myColor = "w"; flip = false; selected = -1; targets = []
                lastFrom = -1; lastTo = -1; checkSq = -1; sanList = []
                started = false; outcome = nil; promotionChoices = nil
      }

      func resign() {
                guard started, outcome == nil else { return }
                send(NetMessage(type: .resign))
                outcome = .resignedByMe
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
                guard var m = position.moveFromUci(uci) else { return }
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
                checkSq = position.inCheck() ? position.kingSq(position.turn) : -1
      }

      private func checkOutcome() {
                guard outcome == nil else { return }
                if position.legalMoves().isEmpty {
                              if position.inCheck() {
                                                // The side to move (position.turn) has no legal moves and is in check: that side
                                                // is checkmated, so whoever that side belongs to lost.
                                                outcome = (position.turn == myColor) ? .checkmateLoss : .checkmateWin
                              } else {
                                                outcome = .stalemate
                              }
                }
      }

      // ---------------- networking ----------------

      private func send(_ msg: NetMessage) {
                guard !session.connectedPeers.isEmpty, let data = try? JSONEncoder().encode(msg) else { return }
                try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
      }

      private func beginIfHost() {
                guard isHost, state == .connected, !started else { return }
                myColor = "w"; flip = false; started = true
                send(NetMessage(type: .start, fen: NET_START_FEN))
      }
}

extension NetPlayManager: MCSessionDelegate {
      nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
                Task { @MainActor in
                                  switch state {
                                                case .connected:
                                                    self.peerName = peerID.displayName
                                                    self.state = .connected
                                                    self.advertiser?.stopAdvertisingPeer()
                                                    self.browser?.stopBrowsingForPeers()
                                                    self.beginIfHost()
                                                case .connecting:
                                                    break
                                                case .notConnected:
                                                    if self.started, self.outcome == nil { self.outcome = .disconnected }
                                                    self.state = .lost
                                                @unknown default:
                                                    break
                                  }
                     }
      }

      nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
                guard let msg = try? JSONDecoder().decode(NetMessage.self, from: data) else { return }
                Task { @MainActor in
                                  switch msg.type {
                                                case .start:
                                                    self.myColor = "b"; self.flip = true; self.started = true
                                                    self.position = Position.fromFen(msg.fen.isEmpty ? NET_START_FEN : msg.fen)
                                                    self.model.load(self.position); self.pieces = self.model.pieces
                                                case .move:
                                                    self.applyRemote(uci: msg.uci)
                                                case .resign:
                                                    if self.outcome == nil { self.outcome = .resignedByOpponent }
                                  }
                     }
      }

      nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
      nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
      nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension NetPlayManager: MCNearbyServiceAdvertiserDelegate {
      nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
                Task { @MainActor in invitationHandler(true, self.session) }
      }
}

extension NetPlayManager: MCNearbyServiceBrowserDelegate {
      nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
                Task { @MainActor in
                                  guard self.state == .browsing else { return }
                                  browser.invitePeer(peerID, to: self.session, withContext: nil, timeout: 15)
                     }
      }
      nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}
