import Foundation
import SwiftUI

enum BettingRound: Int, CaseIterable, Codable {
    case preflop, flop, turn, river, showdown

    var title: String {
        switch self {
        case .preflop: return "Pre-flop"
        case .flop: return "Flop"
        case .turn: return "Turn"
        case .river: return "River"
        case .showdown: return "Showdown"
        }
    }

    var next: BettingRound? {
        BettingRound(rawValue: rawValue + 1)
    }
}

/// A frozen copy of every `@Published` piece of hand state. Snapshots are taken
/// before each user action so `undo()` can rewind the game.
private struct GameSnapshot {
    let players: [Player]
    let pot: Int
    let round: BettingRound
    let dealerIndex: Int
    let currentBet: Int
    let lastRaiseSize: Int
    let handNumber: Int
    let winnerBanner: String?
}

@MainActor
final class GameState: ObservableObject {
    // MARK: - Configuration
    @Published var players: [Player] = []
    @Published var denominations: [ChipDenomination] = ChipDenomination.standard
    @Published var smallBlind: Int = 5
    @Published var bigBlind: Int = 10
    @Published var isConfigured: Bool = false

    // MARK: - Hand state
    @Published var pot: Int = 0
    @Published var round: BettingRound = .preflop
    @Published var dealerIndex: Int = 0
    @Published var currentBet: Int = 0
    @Published var lastRaiseSize: Int = 0
    @Published var handNumber: Int = 0
    @Published var winnerBanner: String? = nil

    // MARK: - Undo
    @Published private(set) var undoLabels: [String] = []
    private var undoStack: [GameSnapshot] = []
    private let maxUndoDepth = 30

    var canUndo: Bool { !undoStack.isEmpty }
    var nextUndoLabel: String? { undoLabels.last }

    // MARK: - Config mutations

    func addPlayer(name: String, buyIn: Int) {
        players.append(Player(name: name, stack: buyIn))
    }

    func removePlayer(at offsets: IndexSet) {
        players.remove(atOffsets: offsets)
    }

    func startGame() {
        guard players.count >= 2 else { return }
        isConfigured = true
        handNumber = 0
        dealerIndex = 0
        clearUndo()
        beginHand()
    }

    func endGame() {
        isConfigured = false
        pot = 0
        round = .preflop
        winnerBanner = nil
        clearUndo()
    }

    // MARK: - Hand lifecycle

    private func beginHand() {
        handNumber += 1
        pot = 0
        currentBet = 0
        lastRaiseSize = bigBlind
        round = .preflop
        winnerBanner = nil

        for i in players.indices {
            players[i].currentBet = 0
            players[i].totalCommitted = 0
            players[i].hasFolded = players[i].stack <= 0 // broke players sit out
            players[i].isAllIn = false
            players[i].hasActedThisRound = false
        }

        postBlinds()
    }

    private func postBlinds() {
        guard let sb = smallBlindIndex, let bb = bigBlindIndex else { return }
        applyBet(playerIndex: sb, amount: min(smallBlind, players[sb].stack))
        applyBet(playerIndex: bb, amount: min(bigBlind, players[bb].stack))
        currentBet = bigBlind
        lastRaiseSize = bigBlind
        // Blinds are forced — give both blinds the option to check/raise when action returns.
        players[sb].hasActedThisRound = false
        players[bb].hasActedThisRound = false
    }

    /// Next active seat clockwise from `start`. If `inclusive`, `start` itself counts.
    private func nextActiveSeat(from start: Int, inclusive: Bool = false) -> Int? {
        guard !players.isEmpty else { return nil }
        var idx = inclusive ? (start - 1 + players.count) % players.count : start
        for _ in 0..<players.count {
            idx = (idx + 1) % players.count
            if players[idx].isInHand && players[idx].stack > 0 {
                return idx
            }
        }
        return nil
    }

    /// Heads-up: dealer is the small blind. Otherwise SB is the seat after the dealer.
    var smallBlindIndex: Int? {
        let liveCount = players.filter { $0.isInHand && $0.stack > 0 }.count
        if liveCount == 2 {
            return players[dealerIndex].isInHand && players[dealerIndex].stack > 0
                ? dealerIndex
                : nextActiveSeat(from: dealerIndex)
        }
        return nextActiveSeat(from: dealerIndex)
    }

    var bigBlindIndex: Int? {
        guard let sb = smallBlindIndex else { return nil }
        return nextActiveSeat(from: sb)
    }

    var activePlayers: [Player] { players.filter { $0.isInHand } }

    // MARK: - Betting actions (public — each pushes an undo snapshot)

    /// Push `amount` chips from the player's stack into the pot.
    func commit(playerIndex: Int, amount: Int) {
        guard amount > 0, players.indices.contains(playerIndex) else { return }
        let actual = min(amount, players[playerIndex].stack)
        pushUndo("\(players[playerIndex].name) bet $\(actual)")
        applyBet(playerIndex: playerIndex, amount: actual)
        advanceIfRoundComplete()
    }

    /// Player matches the current bet.
    func call(playerIndex: Int) {
        guard players.indices.contains(playerIndex) else { return }
        let need = max(currentBet - players[playerIndex].currentBet, 0)
        if need == 0 {
            check(playerIndex: playerIndex)
            return
        }
        pushUndo("\(players[playerIndex].name) call $\(need)")
        applyBet(playerIndex: playerIndex, amount: need)
        advanceIfRoundComplete()
    }

    /// Player checks (only valid when currentBet is already matched).
    func check(playerIndex: Int) {
        guard players.indices.contains(playerIndex) else { return }
        guard players[playerIndex].currentBet == currentBet else { return }
        pushUndo("\(players[playerIndex].name) check")
        players[playerIndex].hasActedThisRound = true
        advanceIfRoundComplete()
    }

    /// Player folds.
    func fold(playerIndex: Int) {
        guard players.indices.contains(playerIndex) else { return }
        pushUndo("\(players[playerIndex].name) fold")
        players[playerIndex].hasFolded = true
        players[playerIndex].hasActedThisRound = true
        let remaining = players.indices.filter { players[$0].isInHand }
        if remaining.count == 1 {
            // Skip the extra undo snapshot — the fold already covers rollback.
            awardPotInternal(toPlayerIndex: remaining[0])
            return
        }
        advanceIfRoundComplete()
    }

    // MARK: - Internal: mutate without snapshotting

    /// Core bet mutation. Does NOT push an undo snapshot or check round completion.
    @discardableResult
    private func applyBet(playerIndex: Int, amount: Int) -> Int {
        guard amount > 0, players.indices.contains(playerIndex) else { return 0 }
        let actual = min(amount, players[playerIndex].stack)
        guard actual > 0 else { return 0 }
        players[playerIndex].stack -= actual
        players[playerIndex].currentBet += actual
        players[playerIndex].totalCommitted += actual
        pot += actual

        if players[playerIndex].stack == 0 {
            players[playerIndex].isAllIn = true
        }

        let newBet = players[playerIndex].currentBet
        if newBet > currentBet {
            // Raise / bet — re-open action for everyone else.
            lastRaiseSize = newBet - currentBet
            currentBet = newBet
            for i in players.indices where i != playerIndex {
                players[i].hasActedThisRound = false
            }
        }
        players[playerIndex].hasActedThisRound = true
        return actual
    }

    // MARK: - Round inference

    /// A round is complete when every player still in the hand has acted this round
    /// and every non-all-in in-hand player has matched the current bet.
    private func advanceIfRoundComplete() {
        let stillIn = players.indices.filter { players[$0].isInHand }
        guard stillIn.count > 1 else { return }

        for idx in stillIn {
            let p = players[idx]
            if p.isAllIn { continue }
            if !p.hasActedThisRound { return }
            if p.currentBet < currentBet { return }
        }

        advanceRound()
    }

    private func advanceRound() {
        for i in players.indices {
            players[i].currentBet = 0
            players[i].hasActedThisRound = false
        }
        currentBet = 0
        lastRaiseSize = bigBlind
        if let next = round.next { round = next }
    }

    // MARK: - Declaring winner

    func awardPot(toPlayerIndex idx: Int) {
        guard players.indices.contains(idx) else { return }
        pushUndo("award $\(pot) to \(players[idx].name)")
        awardPotInternal(toPlayerIndex: idx)
    }

    private func awardPotInternal(toPlayerIndex idx: Int) {
        let winner = players[idx].name
        players[idx].stack += pot
        let amount = pot
        pot = 0
        winnerBanner = "\(winner) wins $\(amount)"
        advanceDealerAndDealNext()
    }

    func splitPot(amongPlayerIndexes indexes: [Int]) {
        guard !indexes.isEmpty else { return }
        let names = indexes.compactMap { players.indices.contains($0) ? players[$0].name : nil }
        pushUndo("split $\(pot) between \(names.joined(separator: ", "))")
        let share = pot / indexes.count
        var remainder = pot - (share * indexes.count)
        let ordered = indexes.sorted { lhs, rhs in
            let l = (lhs - dealerIndex + players.count) % players.count
            let r = (rhs - dealerIndex + players.count) % players.count
            return l < r
        }
        for i in ordered {
            players[i].stack += share
            if remainder > 0 {
                players[i].stack += 1
                remainder -= 1
            }
        }
        winnerBanner = "Split: \(ordered.map { players[$0].name }.joined(separator: ", ")) win $\(pot)"
        pot = 0
        advanceDealerAndDealNext()
    }

    private func advanceDealerAndDealNext() {
        var next = dealerIndex
        for _ in 0..<players.count {
            next = (next + 1) % players.count
            if players[next].stack > 0 { break }
        }
        dealerIndex = next
    }

    /// Called from the UI once the winner banner has been dismissed.
    func dealNextHand() {
        pushUndo("deal next hand")
        winnerBanner = nil
        beginHand()
    }

    // MARK: - Mid-game mutations

    func adjustBlinds(small: Int, big: Int) {
        smallBlind = max(0, small)
        bigBlind = max(smallBlind, big)
    }

    func rebuy(playerIndex: Int, amount: Int) {
        guard amount > 0, players.indices.contains(playerIndex) else { return }
        pushUndo("rebuy $\(amount) for \(players[playerIndex].name)")
        players[playerIndex].stack += amount
    }

    // MARK: - Undo plumbing

    private func snapshot() -> GameSnapshot {
        GameSnapshot(
            players: players,
            pot: pot,
            round: round,
            dealerIndex: dealerIndex,
            currentBet: currentBet,
            lastRaiseSize: lastRaiseSize,
            handNumber: handNumber,
            winnerBanner: winnerBanner
        )
    }

    private func restore(_ s: GameSnapshot) {
        players = s.players
        pot = s.pot
        round = s.round
        dealerIndex = s.dealerIndex
        currentBet = s.currentBet
        lastRaiseSize = s.lastRaiseSize
        handNumber = s.handNumber
        winnerBanner = s.winnerBanner
    }

    private func pushUndo(_ label: String) {
        undoStack.append(snapshot())
        undoLabels.append(label)
        if undoStack.count > maxUndoDepth {
            undoStack.removeFirst()
            undoLabels.removeFirst()
        }
    }

    private func clearUndo() {
        undoStack.removeAll()
        undoLabels.removeAll()
    }

    /// Rewinds the last public action.
    func undo() {
        guard let last = undoStack.popLast() else { return }
        _ = undoLabels.popLast()
        restore(last)
    }
}
