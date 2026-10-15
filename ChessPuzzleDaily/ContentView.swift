import SwiftUI

/// App root: owns the long-lived store/controller and loads the bundled puzzle database,
/// then hands off to `RootView` (the ported Screens.kt `App(c)` composable).
struct ContentView: View {
    @StateObject private var controller: GameController
    private let store: ProgressStore

    init() {
        let store = ProgressStore()
        self.store = store
        _controller = StateObject(wrappedValue: GameController(store: store, sound: SoundManager(muted: store.muted)))
    }

    var body: some View {
        RootView(c: controller)
            .preferredColorScheme(.dark)
            .task {
                guard controller.db == nil, let url = Bundle.main.url(forResource: "puzzles", withExtension: "json") else { return }
                do {
                    let data = try Data(contentsOf: url)
                    let db = try await Task.detached(priority: .userInitiated) { try PuzzleDb.parse(data) }.value
                    controller.db = db
                } catch {
                    // Falls back to an empty puzzle list; Home/Splash guard against a nil db already.
                    #if DEBUG
                    print("puzzles.json failed to parse: \(error)")
                    #endif
                }
            }
    }
}

#Preview {
    ContentView()
}
