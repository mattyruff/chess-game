# Prototype validation

Verified in the Linux development workspace with Swift 6.2.3:

- `swift test -c release`: **28 tests passed, 0 failures** (19 rules tests, 5 AI tests, 4 online archive tests).
- Standard perft results: starting position depth 4 = 197,281; Kiwipete depth 3 = 97,862; en-passant endgame depth 3 = 2,812.
- Online archive round trips preserve en passant and threefold repetition; malformed, oversized, unsupported-version, and illegal-move payloads are rejected.
- Swift frontend syntax parsing passed for every app source file. This is not Apple SDK type checking.
- Xcode source references, scheme XML, and entitlement plist passed structural checks.

Not yet verified:

- Xcode compilation/linking for macOS or iOS. The GitHub Actions workflow is included but has not been run.
- Rendering, tap/click input, animation timing, camera framing, and performance on Apple hardware.
- Game Center authentication, automatic matching, remote turns, resignations, and resuming matches between two signed-in accounts.

## First Mac smoke test

1. Open `RoyalChess.xcodeproj` in Xcode 16 or newer, select RoyalChess and My Mac, and run. If signing requires it, select your development team; configure Game Center as described in README.
2. Move e2–e4 against each difficulty. Confirm the computer responds, selection highlights work, and Undo returns to your turn. Start as Black and verify the computer opens as White.
3. Quit and reopen during both a computer game and a local game; verify the board, undo history, and computer turn resume correctly. Automatic save/resume still needs this Apple-runtime check. Choose Two players. Play a short game, rotate the board, and check that move records and turn indicators follow play.
4. Test an iPhone and iPad simulator. Inspect both board edges and the game-options/promotion sheets on the smallest supported display.
5. After configuring Game Center, use two accounts to find a match. White's first move may initiate matchmaking. Send turns both ways, reopen the app, load matches, and confirm the boards agree. Check resignation and failed-network recovery.

The graphics use procedural sculpted pieces with physically based materials. They are a starting point for the requested ultra-realistic look, not a claim of finished photorealism. Pro is the strongest built-in search setting, not a rated professional engine.
