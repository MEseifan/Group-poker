# Group Poker

A SwiftUI iPad app for tracking chips during live poker games. No cards, no
dealer — just a shared chip tracker for 2–6 players sitting around a single
iPad.

## Features

- **Setup screen** — add up to 6 players, each with a configurable buy-in.
- **Rotated per-seat UI** — every player's chip tray, bet controls, and stack
  total face their seat. Six seats auto-distribute around the felt.
- **Draggable chips** — each player's stack is shown as real poker-chip
  denominations ($1, $5, $25, $100, $500). Drag a chip onto your personal bet
  pad (or tap to stack it) and hit **Commit** to push those chips into the pot.
- **Auto-blind posting** — small/big blind badges track the dealer, and the
  blinds are deducted automatically at the start of every hand.
- **Round inference** — the engine watches the betting pattern and advances
  pre-flop → flop → turn → river → showdown automatically as soon as all
  in-hand players have acted and matched the current bet.
- **Declare winner / split pot** — the pot dialog lets you pick one winner or
  split across several. Dealer button rotates, the next hand is dealt
  automatically.
- **Mid-game blinds & rebuys** — change the blinds or rebuy chips for any
  player at any time from the center pot menu or the seat's "+".

## Getting started

Open `GroupPoker.xcodeproj` in Xcode 15+ and run on an iPad (simulator or
device). The target is iOS 17+ and iPad-only, landscape.

## Architecture

- `Models/` — `Player`, `ChipDenomination`, `BettingRound`, and `GameState`
  (the single `@MainActor ObservableObject` that owns the hand). Round
  transitions live in `GameState.advanceIfRoundComplete()`.
- `Views/`:
  - `SetupView` — list-style player/blind configuration.
  - `TableView` — ellipse-based seat layout and felt background.
  - `PlayerSeatView` — per-seat rotated panel with draggable chip stacks,
    pending bet drop zone, and action buttons (Fold/Check/Call/Commit).
  - `PotView` — center pot, round banner, blinds editor, winner picker.
  - `ChipView` — chip glyph + `ChipStackGlyph` for visual stacks.

The single source of truth is `GameState`; every view reads from it via
`@EnvironmentObject`.
