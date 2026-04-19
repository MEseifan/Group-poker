import SwiftUI

struct ChipDenomination: Identifiable, Hashable, Codable {
    let value: Int
    var color: ChipColor

    var id: Int { value }

    static let standard: [ChipDenomination] = [
        .init(value: 1, color: .white),
        .init(value: 5, color: .red),
        .init(value: 25, color: .green),
        .init(value: 100, color: .black),
        .init(value: 500, color: .purple)
    ]
}

enum ChipColor: String, Codable, CaseIterable {
    case white, red, green, black, purple, blue

    var primary: Color {
        switch self {
        case .white: return Color(red: 0.95, green: 0.95, blue: 0.92)
        case .red: return Color(red: 0.82, green: 0.17, blue: 0.19)
        case .green: return Color(red: 0.12, green: 0.55, blue: 0.25)
        case .black: return Color(red: 0.12, green: 0.12, blue: 0.12)
        case .purple: return Color(red: 0.45, green: 0.22, blue: 0.62)
        case .blue: return Color(red: 0.18, green: 0.42, blue: 0.78)
        }
    }

    var accent: Color {
        switch self {
        case .white: return Color(red: 0.75, green: 0.18, blue: 0.18)
        case .red: return .white
        case .green: return .white
        case .black: return .white
        case .purple: return .white
        case .blue: return .white
        }
    }

    var textColor: Color {
        self == .white ? .black : .white
    }
}

/// Breaks an amount into a multiset of denominations using the largest-first greedy
/// approach. Always returns chips that sum exactly to `amount`.
func breakdown(amount: Int, denominations: [ChipDenomination]) -> [ChipDenomination: Int] {
    var remaining = amount
    var result: [ChipDenomination: Int] = [:]
    for denom in denominations.sorted(by: { $0.value > $1.value }) {
        guard denom.value > 0 else { continue }
        let count = remaining / denom.value
        if count > 0 {
            result[denom] = count
            remaining -= count * denom.value
        }
    }
    // Anything left over falls into the smallest denom as singletons.
    if remaining > 0, let smallest = denominations.min(by: { $0.value < $1.value }) {
        result[smallest, default: 0] += remaining
    }
    return result
}
