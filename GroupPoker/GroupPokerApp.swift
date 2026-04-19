import SwiftUI

@main
struct GroupPokerApp: App {
    @StateObject private var game = GameState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(game)
                .preferredColorScheme(.dark)
                .statusBarHidden()
        }
    }
}

struct RootView: View {
    @EnvironmentObject var game: GameState

    var body: some View {
        if game.isConfigured {
            TableView()
        } else {
            SetupView()
        }
    }
}
