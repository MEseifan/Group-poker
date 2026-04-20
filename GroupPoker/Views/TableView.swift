import SwiftUI

struct TableView: View {
    @EnvironmentObject var game: GameState

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Felt background
                feltBackground

                // Center pot
                PotView()
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)

                // Seats arranged around the table
                ForEach(Array(game.players.enumerated()), id: \.element.id) { idx, _ in
                    let layout = seatLayout(index: idx,
                                            of: game.players.count,
                                            in: geo.size)
                    PlayerSeatView(playerIndex: idx, rotation: layout.rotation)
                        .position(layout.position)
                }

                // Winner banner — dimmed overlay so it never collides with seats
                if let banner = game.winnerBanner {
                    winnerOverlay(banner: banner)
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: game.winnerBanner)
        }
        .ignoresSafeArea()
    }

    private func winnerOverlay(banner: String) -> some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { /* swallow taps so nothing behind fires */ }

            VStack(spacing: 18) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.yellow)

                Text(banner)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    game.dealNextHand()
                } label: {
                    Label("Deal next hand", systemImage: "arrow.forward.circle.fill")
                        .font(.title3.weight(.semibold))
                        .frame(minWidth: 220)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.black)

                Button("Undo") {
                    game.undo()
                }
                .buttonStyle(.bordered)
                .tint(.black)
            }
            .padding(32)
            .frame(maxWidth: 480)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.yellow)
                    .shadow(color: .black.opacity(0.4), radius: 24, y: 8)
            )
        }
    }

    private var feltBackground: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.02, green: 0.18, blue: 0.08),
                         Color(red: 0.05, green: 0.3, blue: 0.15)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Felt oval outline
            GeometryReader { geo in
                Ellipse()
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 3)
                    .padding(.horizontal, geo.size.width * 0.1)
                    .padding(.vertical, geo.size.height * 0.12)
            }
        }
    }

    /// Computes position + rotation so every seat faces inward toward the center.
    private func seatLayout(index: Int, of count: Int, in size: CGSize)
        -> (position: CGPoint, rotation: Angle)
    {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        // Place player 0 at the bottom of the screen, then distribute clockwise.
        // Angle 90° (pointing down from center) for bottom.
        let startDegrees: Double = 90
        let step = 360.0 / Double(max(count, 1))
        let angleDeg = startDegrees + step * Double(index)
        let angleRad = angleDeg * .pi / 180

        // Ellipse radius — keep seats inside screen bounds with padding for the card size.
        let rx = size.width / 2 - 190
        let ry = size.height / 2 - 150
        let x = center.x + cos(angleRad) * rx
        let y = center.y + sin(angleRad) * ry

        // Rotation: each seat rotates so "up" (toward the player) faces outward from the center.
        // The chip row/drop zone reads correctly when the seat's top edge points away from center.
        // Default text orientation faces the player at the bottom (angle 90°).
        let rotation = Angle.degrees(angleDeg - 90)

        return (CGPoint(x: x, y: y), rotation)
    }
}

#Preview {
    let gs = GameState()
    gs.addPlayer(name: "Alice", buyIn: 500)
    gs.addPlayer(name: "Bob", buyIn: 500)
    gs.addPlayer(name: "Carol", buyIn: 500)
    gs.addPlayer(name: "Dan", buyIn: 500)
    gs.startGame()
    return TableView().environmentObject(gs)
}
