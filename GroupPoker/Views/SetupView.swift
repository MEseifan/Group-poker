import SwiftUI

struct SetupView: View {
    @EnvironmentObject var game: GameState
    @State private var newName: String = ""
    @State private var newBuyIn: Int = 500
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Players (\(game.players.count)/6)") {
                    ForEach(game.players) { player in
                        HStack {
                            Text(player.name)
                                .font(.title3.weight(.medium))
                            Spacer()
                            Text("$\(player.stack)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete(perform: game.removePlayer)

                    if game.players.count < 6 {
                        HStack {
                            TextField("Player name", text: $newName)
                                .focused($nameFocused)
                                .onSubmit(addPlayer)
                            Stepper("$\(newBuyIn)", value: $newBuyIn, in: 50...10000, step: 50)
                                .fixedSize()
                            Button("Add", action: addPlayer)
                                .buttonStyle(.borderedProminent)
                                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }

                Section("Blinds") {
                    Stepper("Small blind: $\(game.smallBlind)",
                            value: $game.smallBlind, in: 1...1000, step: 1)
                    Stepper("Big blind: $\(game.bigBlind)",
                            value: $game.bigBlind, in: max(game.smallBlind, 1)...2000, step: 1)
                        .onChange(of: game.smallBlind) { _, new in
                            if game.bigBlind < new { game.bigBlind = new }
                        }
                }

                Section("Chip denominations") {
                    ForEach(game.denominations) { denom in
                        HStack {
                            ChipView(denomination: denom, size: 36)
                            Text("$\(denom.value)")
                                .monospacedDigit()
                        }
                    }
                }

                Section {
                    Button {
                        game.startGame()
                    } label: {
                        Text("Start game")
                            .frame(maxWidth: .infinity)
                            .font(.title3.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(game.players.count < 2)
                }
            }
            .navigationTitle("Group Poker")
        }
    }

    private func addPlayer() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, game.players.count < 6 else { return }
        game.addPlayer(name: trimmed, buyIn: newBuyIn)
        newName = ""
        nameFocused = true
    }
}

#Preview {
    SetupView().environmentObject(GameState())
}
