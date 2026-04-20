import SwiftUI

struct PotView: View {
    @EnvironmentObject var game: GameState
    @State private var showAward: Bool = false
    @State private var showBlindsEditor: Bool = false

    var body: some View {
        VStack(spacing: 12) {
            Text(game.round.title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.12)))

            activeActorBadge

            Text("POT")
                .font(.caption.weight(.bold))
                .tracking(4)
                .foregroundStyle(.white.opacity(0.7))

            Text("$\(game.pot)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.yellow)
                .contentTransition(.numericText())

            HStack(spacing: 10) {
                Button {
                    showBlindsEditor = true
                } label: {
                    Label("SB $\(game.smallBlind) / BB $\(game.bigBlind)",
                          systemImage: "slider.horizontal.3")
                }
                .buttonStyle(PotButtonStyle(tint: .blue))

                Button {
                    showAward = true
                } label: {
                    Label("Declare Winner", systemImage: "crown.fill")
                }
                .buttonStyle(PotButtonStyle(tint: .green))
                .disabled(game.pot == 0)
            }

            undoRow
        }
        .padding(20)
        .background(
            Circle()
                .fill(Color.black.opacity(0.35))
                .overlay(
                    Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 2)
                )
                .padding(-30)
        )
        .sheet(isPresented: $showAward) { awardSheet }
        .sheet(isPresented: $showBlindsEditor) { blindsSheet }
    }

    private var activeActorBadge: some View {
        Group {
            if let idx = game.currentActorIndex, game.players.indices.contains(idx) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.yellow)
                        .frame(width: 8, height: 8)
                    Text("Waiting on \(game.players[idx].name)")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.yellow.opacity(0.18)))
                .overlay(Capsule().strokeBorder(Color.yellow.opacity(0.6), lineWidth: 1))
            } else if game.winnerBanner == nil {
                Text("Hand complete — declare winner")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    // MARK: - Undo

    private var undoRow: some View {
        VStack(spacing: 2) {
            Button {
                game.undo()
            } label: {
                Label(game.canUndo ? "Undo" : "Nothing to undo",
                      systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(PotButtonStyle(tint: .orange))
            .disabled(!game.canUndo)

            if let label = game.nextUndoLabel {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Sheets

    private var awardSheet: some View {
        NavigationStack {
            List {
                Section("Single winner") {
                    ForEach(Array(game.players.enumerated()), id: \.element.id) { idx, player in
                        if player.isInHand {
                            Button {
                                game.awardPot(toPlayerIndex: idx)
                                showAward = false
                            } label: {
                                HStack {
                                    Text(player.name)
                                    Spacer()
                                    Text("$\(player.stack)").foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Section("Split pot") {
                    SplitPotPicker(onSplit: { indexes in
                        game.splitPot(amongPlayerIndexes: indexes)
                        showAward = false
                    })
                }
            }
            .navigationTitle("Who won?")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAward = false }
                }
            }
        }
    }

    private var blindsSheet: some View {
        NavigationStack {
            Form {
                Section("Blinds") {
                    Stepper("Small blind: $\(game.smallBlind)",
                            value: $game.smallBlind, in: 1...1000, step: 1)
                    Stepper("Big blind: $\(game.bigBlind)",
                            value: $game.bigBlind, in: max(game.smallBlind, 1)...2000, step: 1)
                        .onChange(of: game.smallBlind) { _, new in
                            if game.bigBlind < new { game.bigBlind = new }
                        }
                }
                Section("Game") {
                    Button("End game & return to setup", role: .destructive) {
                        game.endGame()
                        showBlindsEditor = false
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showBlindsEditor = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct SplitPotPicker: View {
    @EnvironmentObject var game: GameState
    @State private var selected: Set<UUID> = []
    let onSplit: ([Int]) -> Void

    var body: some View {
        VStack(alignment: .leading) {
            ForEach(Array(game.players.enumerated()), id: \.element.id) { idx, player in
                if player.isInHand {
                    Toggle(isOn: Binding(
                        get: { selected.contains(player.id) },
                        set: { isOn in
                            if isOn { selected.insert(player.id) }
                            else { selected.remove(player.id) }
                        }
                    )) {
                        Text(player.name)
                    }
                }
            }
            Button("Split pot between \(selected.count) players") {
                let indexes = game.players.indices.filter { selected.contains(game.players[$0].id) }
                onSplit(indexes)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selected.count < 2)
        }
    }
}

private struct PotButtonStyle: ButtonStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.5 : 0.85))
            )
    }
}
