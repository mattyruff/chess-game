import Foundation
import SwiftUI
import GameKit
import ChessCore

#if os(macOS)
import AppKit
typealias AuthenticationController = NSViewController
#else
import UIKit
typealias AuthenticationController = UIViewController
#endif

struct AuthenticationPresentation: Identifiable {
    let id = UUID()
    let controller: AuthenticationController
}

#if os(macOS)
struct GameCenterAuthenticationView: NSViewControllerRepresentable {
    let presentation: AuthenticationPresentation
    func makeNSViewController(context: Context) -> NSViewController { presentation.controller }
    func updateNSViewController(_ controller: NSViewController, context: Context) {}
}
#else
struct GameCenterAuthenticationView: UIViewControllerRepresentable {
    let presentation: AuthenticationPresentation
    func makeUIViewController(context: Context) -> UIViewController { presentation.controller }
    func updateUIViewController(_ controller: UIViewController, context: Context) {}
}
#endif

struct OnlineMatchSummary: Identifiable {
    let id: String
    let title: String
    let detail: String
}

/// Game Center stores a complete, versioned move log. Replaying that log preserves
/// castling, en passant and repetition history without trusting a remote position.
@MainActor
final class OnlineGame: NSObject, ObservableObject, GKLocalPlayerListener {
    @Published private(set) var status = "Sign in to Game Center to play online."
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isBusy = false
    @Published private(set) var isWaiting = false
    @Published private(set) var isFinished = false
    @Published private(set) var matchID: String?
    @Published private(set) var opponentName = "Opponent"
    @Published private(set) var localSide: Side = .white
    @Published private(set) var isLocalTurn = false
    @Published private(set) var matches: [OnlineMatchSummary] = []
    @Published var authentication: AuthenticationPresentation?

    var onUpdate: (([Move], Side) -> Void)?

    private var registeredListener = false
    private var needsRefresh = false
    private var activeMatch: GKTurnBasedMatch?
    private var committedMoves: [Move] = []
    private let turnTimeout: TimeInterval = 7 * 24 * 60 * 60

    func authenticate() {
        status = "Connecting to Game Center…"
        GKLocalPlayer.local.authenticateHandler = { [weak self] controller, error in
            Task { @MainActor in
                guard let self else { return }
                if let controller {
                    self.authentication = AuthenticationPresentation(controller: controller)
                    return
                }
                self.authentication = nil
                self.isAuthenticated = GKLocalPlayer.local.isAuthenticated
                if self.isAuthenticated {
                    if !self.registeredListener {
                        GKLocalPlayer.local.register(self)
                        self.registeredListener = true
                    }
                    self.status = "Game Center connected. Find an opponent or resume a match."
                    self.loadMatches()
                } else {
                    self.isLocalTurn = false
                    self.status = error.map { "Game Center: \($0.localizedDescription)" }
                        ?? "Sign in to Game Center in Settings to play online."
                }
            }
        }
    }

    func findMatch() {
        guard requireAuthentication(), !isBusy else { return }
        isBusy = true
        status = "Finding an online opponent…"
        Task {
            defer { finishOperation() }
            do {
                let request = GKMatchRequest()
                request.minPlayers = 2
                request.maxPlayers = 2
                // Keep this rules/protocol version in a separate matchmaking pool.
                request.playerGroup = 1
                let match: GKTurnBasedMatch = try await withCheckedThrowingContinuation { continuation in
                    GKTurnBasedMatch.find(for: request) { match, error in
                        if let error { continuation.resume(throwing: error) }
                        else if let match { continuation.resume(returning: match) }
                        else { continuation.resume(throwing: OnlineError.missingMatch) }
                    }
                }
                let state = try await readState(match)
                try adopt(match, state: state)
            } catch { report(error) }
        }
    }

    func loadMatches() {
        guard requireAuthentication(), !isBusy else { return }
        isBusy = true
        Task {
            defer { finishOperation() }
            do {
                let loaded: [GKTurnBasedMatch] = try await withCheckedThrowingContinuation { continuation in
                    GKTurnBasedMatch.loadMatches { matches, error in
                        if let error { continuation.resume(throwing: error) }
                        else { continuation.resume(returning: matches ?? []) }
                    }
                }
                matches = loaded.sorted { $0.creationDate > $1.creationDate }.map { match in
                    let opponent = match.participants.compactMap(\.player).first { !isLocal($0) }
                    let detail: String
                    if match.status == .ended { detail = "Finished" }
                    else if match.currentParticipant?.player.map(isLocal) == true { detail = "Your turn" }
                    else { detail = "Waiting for opponent" }
                    return OnlineMatchSummary(id: match.matchID, title: opponent?.displayName ?? "Finding opponent", detail: detail)
                }
                if matchID == nil {
                    status = matches.isEmpty ? "Ready to find an online opponent." : "Choose a saved match or find a new opponent."
                }
            } catch { report(error) }
        }
    }

    func selectMatch(_ summary: OnlineMatchSummary) {
        guard requireAuthentication(), !isBusy else { return }
        loadSelected(id: summary.id)
    }

    func refresh() {
        guard isAuthenticated else { return }
        guard let id = matchID else { loadMatches(); return }
        if isBusy { needsRefresh = true; return }
        loadSelected(id: id)
    }

    /// The caller keeps its current board until this operation succeeds. Reloading
    /// before writing rejects stale devices and attempts to replace prior turns.
    func submit(moves: [Move], outcome: GameOutcome) async throws {
        guard requireAuthentication(), !isBusy, let id = matchID else { throw OnlineError.unavailable }
        isBusy = true
        defer { finishOperation() }
        do {
            let match = try await Self.load(id: id)
            let prior = try await readState(match)
            let index = try localParticipantIndex(in: match)
            guard match.status != .ended, !hasDepartedParticipant(match),
                  currentIndex(in: match) == index,
                  prior.position.sideToMove == side(for: index) else { throw OnlineError.notYourTurn }
            guard moves.count == prior.moves.count + 1,
                  moves.dropLast().elementsEqual(prior.moves), let nextMove = moves.last else {
                throw OnlineError.staleTurn
            }
            var next = prior.position
            guard next.play(nextMove), next.outcome == outcome else { throw OnlineError.invalidMoves }
            let payload = try MatchArchive(moves: moves).encoded()
            guard payload.count <= match.matchDataMaximumSize, moves.count <= MatchArchive.maximumMoves else {
                throw OnlineError.tooLarge
            }
            if outcome == .ongoing {
                let opponent = match.participants[1 - index]
                try await perform { completion in
                    match.endTurn(withNextParticipants: [opponent], turnTimeout: turnTimeout,
                                  match: payload, completionHandler: completion)
                }
            } else {
                for (participantIndex, participant) in match.participants.enumerated() {
                    if case .checkmate(let winner) = outcome {
                        participant.matchOutcome = side(for: participantIndex) == winner ? .won : .lost
                    } else { participant.matchOutcome = .tied }
                }
                try await perform { completion in match.endMatchInTurn(withMatch: payload, completionHandler: completion) }
            }
            // endTurn does not promise to mutate currentParticipant on this object.
            // Commit the accepted log, then disable input until the server's next turn.
            try adopt(match, state: ReplayedState(moves: moves, position: next), submitted: true)
        } catch {
            report(error)
            throw error
        }
    }

    /// Resigns the selected online match. Switching play modes should not call this.
    func leave() async throws {
        guard requireAuthentication(), !isBusy, let id = matchID else { throw OnlineError.unavailable }
        isBusy = true
        defer { finishOperation() }
        do {
            let match = try await Self.load(id: id)
            let index = try localParticipantIndex(in: match)
            if match.status != .ended {
                if currentIndex(in: match) == index {
                    let state = try await readState(match)
                    let payload = try MatchArchive(moves: state.moves).encoded()
                    match.participants[index].matchOutcome = .lost
                    match.participants[1 - index].matchOutcome = .won
                    try await perform { completion in match.endMatchInTurn(withMatch: payload, completionHandler: completion) }
                } else {
                    try await perform { completion in
                        match.participantQuitOutOfTurn(with: .quit, withCompletionHandler: completion)
                    }
                }
            }
            activeMatch = nil
            matchID = nil
            committedMoves = []
            isLocalTurn = false
            isWaiting = false
            isFinished = false
            status = "You left the online match."
            matches.removeAll { $0.id == id }
        } catch {
            report(error)
            throw error
        }
    }

    nonisolated func player(_ player: GKPlayer, receivedTurnEventFor match: GKTurnBasedMatch, didBecomeActive: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.matchID == match.matchID { self.refresh() }
            else if self.matchID == nil && didBecomeActive && !self.isBusy { self.loadSelected(id: match.matchID) }
        }
    }

    nonisolated func player(_ player: GKPlayer, matchEnded match: GKTurnBasedMatch) {
        Task { @MainActor [weak self] in
            guard let self, self.matchID == match.matchID else { return }
            self.refresh()
        }
    }

    private func loadSelected(id: String) {
        isBusy = true
        Task {
            defer { finishOperation() }
            do {
                let match = try await Self.load(id: id)
                let state = try await readState(match)
                try adopt(match, state: state)
            } catch { report(error) }
        }
    }

    private func adopt(_ match: GKTurnBasedMatch, state: ReplayedState, submitted: Bool = false) throws {
        let index = try localParticipantIndex(in: match)
        let ownSide = side(for: index)
        let ended = match.status == .ended || state.position.outcome != .ongoing || hasDepartedParticipant(match)
        isFinished = ended
        if !ended, !submitted, let turnIndex = currentIndex(in: match),
           side(for: turnIndex) != state.position.sideToMove { throw OnlineError.invalidTurn }
        activeMatch = match
        matchID = match.matchID
        localSide = ownSide
        committedMoves = state.moves
        opponentName = match.participants[1 - index].player?.displayName ?? "Finding opponent"
        isLocalTurn = !ended && !submitted && currentIndex(in: match) == index && state.position.sideToMove == ownSide
        isWaiting = !ended && !isLocalTurn
        if ended {
            switch state.position.outcome {
            case .checkmate(let winner): status = winner == ownSide ? "Checkmate · you win" : "Checkmate · opponent wins"
            case .stalemate: status = "Draw by stalemate"
            case .draw(let reason): status = "Draw · \(reason)"
            case .ongoing:
                let result = match.participants[index].matchOutcome
                let other = match.participants[1 - index].matchOutcome
                if result == .won || other == .quit || other == .timeExpired { status = "Opponent left · you win" }
                else if result == .lost || result == .quit || result == .timeExpired { status = "Match ended · opponent wins" }
                else if result == .tied { status = "Match ended in a draw" }
                else { status = "Match ended" }
            }
        } else if isLocalTurn {
            status = "Your turn · \(ownSide.rawValue.capitalized)"
            if match.participants[1 - index].player == nil { status += " · move to start matchmaking" }
        } else {
            status = match.participants[1 - index].player == nil ? "Waiting for an opponent to join…" : "Waiting for \(opponentName)…"
        }
        onUpdate?(state.moves, ownSide)
    }

    private func readState(_ match: GKTurnBasedMatch) async throws -> ReplayedState {
        let data: Data? = try await withCheckedThrowingContinuation { continuation in
            match.loadMatchData { data, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: data) }
            }
        }
        let archive = try MatchArchive(data: data)
        return ReplayedState(moves: archive.moves, position: archive.position)
    }

    private static func load(id: String) async throws -> GKTurnBasedMatch {
        try await withCheckedThrowingContinuation { continuation in
            GKTurnBasedMatch.load(withID: id) { match, error in
                if let error { continuation.resume(throwing: error) }
                else if let match { continuation.resume(returning: match) }
                else { continuation.resume(throwing: OnlineError.missingMatch) }
            }
        }
    }

    private func perform(_ operation: (@escaping (Error?) -> Void) -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            operation { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: ()) }
            }
        }
    }

    private func isLocal(_ player: GKPlayer) -> Bool { player.gamePlayerID == GKLocalPlayer.local.gamePlayerID }
    private func side(for participantIndex: Int) -> Side { participantIndex == 0 ? .white : .black }

    private func localParticipantIndex(in match: GKTurnBasedMatch) throws -> Int {
        guard match.participants.count == 2,
              let index = match.participants.firstIndex(where: { $0.player.map(isLocal) == true }) else {
            throw OnlineError.invalidParticipants
        }
        return index
    }

    private func currentIndex(in match: GKTurnBasedMatch) -> Int? {
        guard let current = match.currentParticipant else { return nil }
        return match.participants.firstIndex { participant in
            participant === current || (participant.player != nil && participant.player?.gamePlayerID == current.player?.gamePlayerID)
        }
    }

    private func hasDepartedParticipant(_ match: GKTurnBasedMatch) -> Bool {
        match.participants.contains { $0.matchOutcome == .quit || $0.matchOutcome == .timeExpired }
    }

    private func requireAuthentication() -> Bool {
        guard GKLocalPlayer.local.isAuthenticated else {
            isAuthenticated = false
            isLocalTurn = false
            status = "Sign in to Game Center before starting an online match."
            return false
        }
        return true
    }

    private func finishOperation() {
        isBusy = false
        if needsRefresh {
            needsRefresh = false
            refresh()
        }
    }

    private func report(_ error: Error) {
        status = "Online play: \(error.localizedDescription)"
    }

    private struct ReplayedState {
        let moves: [Move]
        let position: Position
    }

    private enum OnlineError: LocalizedError {
        case missingMatch, unavailable, notYourTurn, staleTurn, invalidMoves
        case invalidParticipants, invalidTurn, tooLarge, unsupportedVersion

        var errorDescription: String? {
            switch self {
            case .missingMatch: return "Game Center did not return a match. Try again."
            case .unavailable: return "Wait for the current request, then select an online match."
            case .notYourTurn: return "It is no longer your turn. Refresh the match."
            case .staleTurn: return "The match changed on another device. Refresh before moving."
            case .invalidMoves: return "This match contains an invalid chess move and cannot be loaded."
            case .invalidParticipants: return "This match is not a two-player match for your account."
            case .invalidTurn: return "The match turn does not match its move history. Refresh to try again."
            case .tooLarge: return "This match exceeds the supported move-history size."
            case .unsupportedVersion: return "This match uses another game version. Update the app to continue."
            }
        }
    }
}
