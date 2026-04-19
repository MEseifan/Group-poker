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
        beginHand()
    }

    func endGame() {
        isConfigured = false
        pot = 0
        round = .preflop
        winnerBanner = nil
    }

    // MARK: - Hand lifecycle

    func beginHand() {
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
        commit(playerIndex: sb, amount: min(smallBlind, players[sb].stack))
        commit(playerIndex: bb, amount: min(bigBlind, players[bb].stack))
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

    // MARK: - Betting actions

    /// Adds `amount` chips from the player's stack into their current bet.
    /// Automatically updates pot, current bet marker, and round progression.
    func commit(playerIndex: Int, amount: Int) {
        guard amount > 0 else { return }
        guard playerIndex >= 0 && playerIndex < players.count else { return }
        let actual = min(amount, players[playerIndex].stack)
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
        advanceIfRoundComplete()
    }

    /// Player calls (matches current bet).
    func call(playerIndex: Int) {
        let need = currentBet - players[playerIndex].currentBet
        commit(playerIndex: playerIndex, amount: max(need, 0))
        players[playerIndex].hasActedThisRound = true
        advanceIfRoundComplete()
    }

    /// Player checks (only valid when currentBet is matched).
    func check(playerIndex: Int) {
        guard players[playerIndex].currentBet == currentBet else { return }
        players[playerIndex].hasActedThisRound = true
        advanceIfRoundComplete()
    }

    /// Player folds.
    func fold(playerIndex: Int) {
        players[playerIndex].hasFolded = true
        players[playerIndex].hasActedThisRound = true
        // If only one player remains, they take the pot immediately.
        let remaining = players.indices.filter { players[$0].isInHand }
        if remaining.count == 1 {
            awardPot(toPlayerIndex: remaining[0])
            return
        }
        advanceIfRoundComplete()
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
        // Sweep current bets into the pot (already done — pot mirrors commits),
        // reset per-round state for the next street.
        for i in players.indices {
            players[i].currentBet = 0
            players[i].hasActedThisRound = false
        }
        currentBet = 0
        lastRaiseSize = bigBlind

        if let next = round.next {
            round = next
        }

        if round == .showdown {
            // Waiting on user to declare winner.
        }
    }

    // MARK: - Declaring winner

    func awardPot(toPlayerIndex idx: Int) {
        let winner = players[idx].name
        players[idx].stack += pot
        let amount = pot
        pot = 0
        winnerBanner = "\(winner) wins $\(amount)"
        advanceDealerAndDealNext()
    }

    /// Splits the pot evenly across the supplied winners (remainder goes to the first player clockwise from the dealer).
    func splitPot(amongPlayerIndexes indexes: [Int]) {
        guard !indexes.isEmpty else { return }
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
        let names = ordered.map { players[$0].name }.joined(separator: ", ")
        winnerBanner = "Split: \(names) win $\(pot)"
        pot = 0
        advanceDealerAndDealNext()
    }

    private func advanceDealerAndDealNext() {
        // Rotate dealer to next player with chips.
        var next = dealerIndex
        for _ in 0..<players.count {
            next = (next + 1) % players.count
            if players[next].stack > 0 { break }
        }
        dealerIndex = next
    }

    /// Called from the UI once the winner banner has been dismissed.
    func dealNextHand() {
        winnerBanner = nil
        beginHand()
    }

    // MARK: - Mid-game mutations

    func adjustBlinds(small: Int, big: Int) {
        smallBlind = max(0, small)
        bigBlind = max(smallBlind, big)
    }

    func rebuy(playerIndex: Int, amount: Int) {
        guard amount > 0 else { return }
        players[playerIndex].stack += amount
    }
}
