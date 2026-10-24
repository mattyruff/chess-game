# Royal Chess

A native SwiftUI and SceneKit chess game for iPhone, iPad, and Mac. Black and white traditional pieces sit on a wooden 3D board, with physically based materials, lighting, shadows, and animated moves and captures. Pieces are generated in code; they are not scanned or photorealistic model assets.

## Open in Xcode

1. On a Mac, install Xcode 16 or newer and clone this repository.
2. Open `RoyalChess.xcodeproj` and select the **RoyalChess** scheme.
3. Choose **My Mac**, an iPhone simulator, or an iPad simulator, then press **Run** (⌘R).

The app supports macOS 13+ and iOS/iPadOS 16+. Local games need no downloaded models, API keys, servers, or paid AI services. Select your Apple development team in the target's **Signing & Capabilities** settings for signed runs. Game Center requires the Apple setup below.

## Play

Start a game against the computer, choose a local two-player game on the same device, or play online through Game Center. Select a piece, then select a highlighted square to move. White moves first. Computer difficulty choices are **Beginner**, **Intermediate**, and **Pro**; these use progressively stronger local search, not a rated or grandmaster engine.

The rules engine handles legal moves, check, checkmate, stalemate, castling, en passant, and promotion. Threefold repetition and the fifty-move rule automatically end the game as draws; basic insufficient-material positions also draw. Local games support undo and board rotation. The move record uses explicit source/destination notation. Computer and local two-player games automatically save after each move and resume on launch, including move history and undo. Online matches can be resumed through Game Center.

## Online play setup

Online games use Apple's Game Center turn-based matchmaking. Players send each completed turn through Game Center and can return to a match later; the connection is not a continuous real-time stream.

1. In your Apple Developer account, register a bundle identifier for the app and enable the **Game Center** capability. Update `PRODUCT_BUNDLE_IDENTIFIER` in the Xcode target to match.
2. Create the app record in **App Store Connect**, using that identifier, and enable Game Center for the app. Configure the Apple-platform app versions as needed.
3. Choose the matching development team in Xcode and let automatic signing create the provisioning profiles. The project includes the Game Center capability and entitlement.
4. Sign into Game Center on two Apple devices or Macs using two different accounts. Run signed builds, find an opponent, complete turns, then close and reopen a match on each side to verify synchronization.

An Apple Developer membership and Apple's app configuration are required for online testing and distribution. Unsigned CI builds check compilation; they cannot verify Game Center authentication or multiplayer behavior. Local play remains available without Game Center authentication.

## Validate

Run the portable rules and AI tests on macOS or Linux with a Swift toolchain:

```sh
swift test
```

Build the app from a Mac terminal:

```sh
xcodebuild -project RoyalChess.xcodeproj -scheme RoyalChess \
  -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project RoyalChess.xcodeproj -scheme RoyalChess \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Signing is disabled only in these verification commands. Use Xcode's normal signing settings for device installation or distribution. The checked-in GitHub Actions workflow runs the tests and both app builds on a macOS runner after the code is pushed to GitHub.

## Can Xcode run in GitHub?

GitHub can store the project, and **GitHub Actions macOS runners can run Xcode builds and tests**. The interactive Xcode editor and iOS Simulator need a Mac; they do not run inside the GitHub website or a standard Linux Codespace. This Linux cloud workspace can edit Swift and test the chess engine, but it cannot compile or visually verify the Apple app.

This is a prototype. The rules and AI have passed Linux tests; the Apple app has not yet been compiled with Xcode, visually inspected, or tested against live Game Center accounts. An App Store release still needs Apple-device validation, an app icon, signing, and store metadata.
