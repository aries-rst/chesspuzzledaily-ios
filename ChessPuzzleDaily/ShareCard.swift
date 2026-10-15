import SwiftUI
import UIKit

// Port of ui/ShareCard.kt — builds a share picture (puzzle position before the player's first
// move, no spoilers, plus headline/goal/result grid) and opens the system share sheet with
// image + text/link.

/// What the share button sends.
struct SharePayload: Identifiable, Equatable {
    let id = UUID()
    let fen: String
    let flip: Bool
    let headline: String
    let goal: String
    let grid: String
    let text: String
}

private let CARD_BG = Color(red: 0x17 / 255, green: 0x12 / 255, blue: 0x0E / 255)
private let CARD_FRAME = Color(red: 0x3B / 255, green: 0x2B / 255, blue: 0x1D / 255)
private let CARD_SQ_L = Color(red: 0xEC / 255, green: 0xD8 / 255, blue: 0xB0 / 255)
private let CARD_SQ_D = Color(red: 0xA6 / 255, green: 0x77 / 255, blue: 0x4C / 255)
private let CARD_TEXT = Color(red: 0xF3 / 255, green: 0xEA / 255, blue: 0xD8 / 255)
private let CARD_GOLD = Color(red: 0xF5 / 255, green: 0xCF / 255, blue: 0x7E / 255)
private let CARD_MUTED = Color(red: 0xB9 / 255, green: 0xA8 / 255, blue: 0x8C / 255)

/// 1080x1350 share image view, rendered off-screen via `ImageRenderer`.
private struct ShareCardView: View {
    let payload: SharePayload
    private let w: CGFloat = 1080, h: CGFloat = 1350

    var body: some View {
        ZStack {
            CARD_BG
            VStack(spacing: 10) {
                Text(payload.headline).font(.system(size: 54, weight: .bold)).foregroundColor(CARD_TEXT)
                Text(payload.goal).font(.system(size: 40, weight: .bold)).foregroundColor(CARD_GOLD)
                Spacer().frame(height: 18)
                boardView.frame(width: w - 120, height: w - 120)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(CARD_FRAME, lineWidth: 12))
                if !payload.grid.isEmpty {
                    Text(payload.grid).font(.system(size: 50)).foregroundColor(CARD_TEXT).padding(.top, 24)
                }
                Spacer()
                Text("♞ ARESTI LABS").font(.system(size: 30)).foregroundColor(CARD_MUTED)
            }
            .padding(.top, 70).padding(.bottom, 50)
        }
        .frame(width: w, height: h)
    }

    private var boardView: some View {
        let pos = Position.fromFen(payload.fen)
        return Canvas { context, size in
            let cell = size.width / 8
            for sq in 0..<64 {
                var r = sq >> 3, f = sq & 7
                if payload.flip { r = 7 - r; f = 7 - f }
                let rect = CGRect(x: CGFloat(f) * cell, y: CGFloat(r) * cell, width: cell, height: cell)
                context.fill(Path(rect), with: .color((r + f) % 2 == 0 ? CARD_SQ_L : CARD_SQ_D))
                let piece = pos.board[sq]
                if piece != EMPTY {
                    var pieceCtx = context
                    pieceCtx.translateBy(x: rect.minX, y: rect.minY)
                    pieceCtx.drawPiece(piece, side: cell)
                }
            }
        }
    }
}

enum ShareCard {
    /// Renders the share image on the main actor (SwiftUI `ImageRenderer` requirement).
    @MainActor
    static func render(_ payload: SharePayload) -> UIImage? {
        let renderer = ImageRenderer(content: ShareCardView(payload: payload))
        renderer.scale = 1
        return renderer.uiImage
    }
}

/// Presents the system share sheet with the rendered image (if any) plus the share text.
struct ShareSheet: UIViewControllerRepresentable {
    let payload: SharePayload

    func makeUIViewController(context: Context) -> UIActivityViewController {
        var items: [Any] = [payload.text]
        if let image = ShareCard.render(payload) { items.insert(image, at: 0) }
        return UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
