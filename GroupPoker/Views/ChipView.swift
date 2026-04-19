import SwiftUI

/// Draws a single poker chip. Size is the diameter in points.
struct ChipView: View {
    let denomination: ChipDenomination
    var size: CGFloat = 60

    var body: some View {
        ZStack {
            Circle()
                .fill(denomination.color.primary)
                .overlay(
                    Circle()
                        .strokeBorder(denomination.color.accent, lineWidth: size * 0.06)
                )
                .overlay(edgeDashes)
            Circle()
                .stroke(denomination.color.accent.opacity(0.6), lineWidth: size * 0.02)
                .padding(size * 0.18)
            Text("$\(denomination.value)")
                .font(.system(size: size * 0.28, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(denomination.color.textColor)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.35), radius: size * 0.04, y: size * 0.03)
    }

    private var edgeDashes: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                Rectangle()
                    .fill(denomination.color.accent)
                    .frame(width: size * 0.08, height: size * 0.18)
                    .offset(y: -size / 2 + size * 0.09)
                    .rotationEffect(.degrees(Double(i) * 45))
            }
        }
    }
}

/// Draws a vertical stack of chips (visually stacked, regardless of real count).
struct ChipStackGlyph: View {
    let denomination: ChipDenomination
    let count: Int
    var chipSize: CGFloat = 48

    var visibleCount: Int {
        // Cap how many we draw — stacks of 40 chips don't need 40 layers.
        min(max(count, 0), 8)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ForEach(0..<visibleCount, id: \.self) { i in
                Circle()
                    .fill(denomination.color.primary)
                    .overlay(
                        Circle()
                            .strokeBorder(denomination.color.accent, lineWidth: chipSize * 0.05)
                    )
                    .frame(width: chipSize, height: chipSize * 0.22)
                    .offset(y: -CGFloat(i) * chipSize * 0.18)
            }
            if count > 0 {
                ChipView(denomination: denomination, size: chipSize)
                    .offset(y: -CGFloat(visibleCount) * chipSize * 0.18)
            }
        }
        .frame(width: chipSize, height: chipSize + CGFloat(visibleCount) * chipSize * 0.18 + 8)
    }
}

#Preview {
    HStack(spacing: 20) {
        ForEach(ChipDenomination.standard) { d in
            ChipStackGlyph(denomination: d, count: 5)
        }
    }
    .padding()
    .background(Color(red: 0.05, green: 0.3, blue: 0.15))
}
