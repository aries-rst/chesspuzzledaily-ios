import SwiftUI

/// Placeholder screen for the initial scaffold — proves the ported chess engine and puzzle
/// core compile and run correctly. Replaced by the real board/screens in a follow-up pass.
struct ContentView: View {
    @State private var selfCheck: String = "Running engine self-check…"

    var body: some View {
        VStack(spacing: 16) {
            Text("♟ Шахматная задача — Ход дня")
                .font(.title2).bold()
            Text("iOS port scaffold")
                .foregroundStyle(.secondary)
            Text(selfCheck)
                .font(.callout)
                .multilineTextAlignment(.center)
                .padding()
        }
        .padding()
        .onAppear { selfCheck = runSelfCheck() }
    }

    /// Exercises the ported engine on a couple of known positions so a build/run instantly
    /// surfaces a translation mistake rather than failing silently deep in a puzzle later.
    private func runSelfCheck() -> String {
        let start = Position.fromFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
        let startMoves = start.legalMoves().count // expected 20

        // Scholar's mate puzzle-style check: back-rank mate in 1 for white.
        // 6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1 → Ra8#
        let mateIn1 = Position.fromFen("6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1")
        var m = mateIn1.moveFromUci("a1a8")!
        let san = mateIn1.san(m)
        mateIn1.apply(&m)
        let isMate = mateIn1.isCheckmate()

        let dailyNumberToday = Daily.numberFor(Calendar0.daysFromCivil(2026, 10, 15))

        return """
        Legal moves from start position: \(startMoves) (expect 20)
        Mate-in-1 SAN: \(san) (expect Ra8#), checkmate: \(isMate)
        Daily puzzle # for 2026-10-15: \(dailyNumberToday)
        """
    }
}

#Preview {
    ContentView()
}
