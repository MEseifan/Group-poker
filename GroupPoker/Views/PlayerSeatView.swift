import SwiftUI
import UniformTypeIdentifiers

struct PlayerSeatView: View {
    let playerIndex: Int
    let rotation: Angle
    @EnvironmentObject var game: GameState
    @State private var pendingBet: Int = 0
    @State private var isDropTargeted: Bool = false
    @State private var showRebuy: Bool = false
    @State private var rebuyAmount: Int = 500

    private var player: Player { game.players[playerIndex] }

    private var isDealer: Bool { game.dealerIndex == playerIndex }
    private var isSmallBlind: Bool { game.smallBlindIndex == playerIndex }
    private var isBigBlind: Bool { game.bigBlindIndex == playerIndex }
    private var isActive: Bool { game.currentActorIndex == playerIndex }

    var body: some View {
        VStack(spacing: 8) {
            if isActive {
                Text("YOUR TURN")
                    .font(.caption.weight(.heavy))
                    .tracking(3)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.yellow))
            }
            headerRow
            chipRow
            dropZone
            actionRow
        }
        .padding(12)
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(player.hasFolded ? Color.black.opacity(0.55) : Color.black.opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: isActive ? 4 : 2)
                )
        )
        .shadow(color: isActive ? Color.yellow.opacity(0.7) : .clear,
                radius: isActive ? 22 : 0)
        .rotationEffect(rotation)
        .opacity(player.hasFolded ? 0.55 : 1)
        .animation(.easeInOut(duration: 0.25), value: isActive)
        .sheet(isPresented: $showRebuy) { rebuySheet }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 8) {
            Text(player.name)
                .font(.headline)
                .lineLimit(1)
            if isDealer { BadgeView(text: "D", color: .yellow) }
            if isSmallBlind { BadgeView(text: "SB", color: .blue) }
            if isBigBlind { BadgeView(text: "BB", color: .orange) }
            Spacer()
            Text("$\(player.stack)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.white)
        }
    }

    // MARK: - Chip row

    private var chipRow: some View {
        HStack(spacing: 6) {
            ForEach(chipStacksForPlayer(), id: \.0.value) { denom, count in
                DraggableChip(
                    denomination: denom,
                    count: count,
                    enabled: player.canAct && count > 0 && pendingBet + denom.value <= player.stack,
                    onTap: { addToBet(denom.value) }
                )
            }
        }
        .frame(height: 78)
    }

    // MARK: - Drop zone / pending bet display

    private var dropZone: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(pendingBet > 0 ? "Your bet" : "Drag chips here")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(pendingBet > 0 ? 0.9 : 0.5))
                Text("$\(pendingBet)")
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(pendingBet > 0 ? .yellow : .white.opacity(0.3))
            }
            Spacer()
            if pendingBet > 0 {
                Button {
                    pendingBet = 0
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isDropTargeted ? Color.yellow.opacity(0.25) : Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            isDropTargeted ? Color.yellow : Color.white.opacity(0.15),
                            style: StrokeStyle(lineWidth: 2, dash: isDropTargeted ? [] : [5, 4])
                        )
                )
        )
        .dropDestination(for: String.self) { items, _ in
            guard player.canAct else { return false }
            var added = false
            for item in items {
                if let value = Int(item) {
                    addToBet(value)
                    added = true
                }
            }
            return added
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
    }

    // MARK: - Action row

    private var actionRow: some View {
        HStack(spacing: 6) {
            Button("Fold") {
                pendingBet = 0
                game.fold(playerIndex: playerIndex)
            }
            .buttonStyle(SeatButtonStyle(tint: .red))
            .disabled(!player.canAct)

            if pendingBet > 0 {
                Button("Commit $\(pendingBet)") {
                    game.commit(playerIndex: playerIndex, amount: pendingBet)
                    pendingBet = 0
                }
                .buttonStyle(SeatButtonStyle(tint: .green))
                .disabled(!player.canAct)
            } else if player.currentBet == game.currentBet {
                Button("Check") {
                    game.check(playerIndex: playerIndex)
                }
                .buttonStyle(SeatButtonStyle(tint: .blue))
                .disabled(!player.canAct)
            } else {
                let toCall = max(game.currentBet - player.currentBet, 0)
                Button("Call $\(toCall)") {
                    game.call(playerIndex: playerIndex)
                }
                .buttonStyle(SeatButtonStyle(tint: .blue))
                .disabled(!player.canAct || toCall == 0)
            }

            Button {
                showRebuy = true
            } label: {
                Image(systemName: "plus.circle")
                    .font(.title3)
            }
            .buttonStyle(SeatButtonStyle(tint: .gray))
        }
    }

    private var rebuySheet: some View {
        NavigationStack {
            Form {
                Section("Rebuy for \(player.name)") {
                    Stepper("$\(rebuyAmount)", value: $rebuyAmount, in: 50...10000, step: 50)
                }
                Button("Add chips") {
                    game.rebuy(playerIndex: playerIndex, amount: rebuyAmount)
                    showRebuy = false
                }
                .buttonStyle(.borderedProminent)
            }
            .navigationTitle("Rebuy")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showRebuy = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Helpers

    private func addToBet(_ amount: Int) {
        guard player.canAct else { return }
        let remaining = player.stack - pendingBet
        pendingBet += min(amount, remaining)
    }

    private func chipStacksForPlayer() -> [(ChipDenomination, Int)] {
        let effectiveStack = max(player.stack - pendingBet, 0)
        let br = breakdown(amount: effectiveStack, denominations: game.denominations)
        return game.denominations
            .sorted(by: { $0.value < $1.value })
            .map { ($0, br[$0] ?? 0) }
    }

    private var borderColor: Color {
        if player.hasFolded { return .clear }
        if isActive { return .yellow }
        if isDealer { return .yellow.opacity(0.7) }
        if isBigBlind { return .orange }
        if isSmallBlind { return .blue }
        return .white.opacity(0.25)
    }
}

// MARK: - Draggable chip

private struct DraggableChip: View {
    let denomination: ChipDenomination
    let count: Int
    let enabled: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            ChipStackGlyph(denomination: denomination, count: count, chipSize: 34)
            Text("x\(count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.8))
        }
        .opacity(count == 0 ? 0.25 : 1)
        .contentShape(Rectangle())
        .onTapGesture { if enabled { onTap() } }
        .draggable(String(denomination.value)) {
            ChipView(denomination: denomination, size: 56)
                .opacity(0.9)
        }
        .allowsHitTesting(enabled)
    }
}

// MARK: - Badges & styles

private struct BadgeView: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.black)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color))
    }
}

private struct SeatButtonStyle: ButtonStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minWidth: 54)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.4 : 0.75))
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
