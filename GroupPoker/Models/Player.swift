import Foundation

struct Player: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    /// Total chips currently in front of the player (not in the pot).
    var stack: Int
    /// Chips the player has pushed into the current betting round.
    var currentBet: Int = 0
    /// Total chips the player has committed to the pot across all betting rounds this hand.
    var totalCommitted: Int = 0
    var hasFolded: Bool = false
    var isAllIn: Bool = false
    /// True once this player has had at least one voluntary action since the last bet/raise.
    var hasActedThisRound: Bool = false

    init(id: UUID = UUID(), name: String, stack: Int) {
        self.id = id
        self.name = name
        self.stack = stack
    }

    var isInHand: Bool { !hasFolded }
    var canAct: Bool { isInHand && !isAllIn }
}
