import Foundation
import SwiftUI
import ChessCore

enum PlayMode: String, CaseIterable, Identifiable {
    case computer = "Computer"
    case local = "Two players"
    case online = "Online"
    var id: String { rawValue }
}

struct MoveRecord: Identifiable {
    let id = UUID()
    let side: Side
    let text: String
}

@MainActor
final class GameModel: ObservableObject {
    @Published private(set) var position = Position()
    @Published private(set) var selected: Square?
    @Published private(set) var records: [MoveRecord] = []
    @Published private(set) var isThinking = false
    @Published private(set) var isSubmitting = false
    @Published private(set) var mode: PlayMode = .computer
    @Published private(set) var difficulty: Difficulty = .intermediate
    @Published private(set) var humanSide: Side = .white
    @Published private(set) var perspective: Side = .white
    @Published var promotionChoices: [Move] = []
    @Published var showsSetup = false
    @Published var onlineError: String?
    @Published private(set) var storageNotice: String?
    let board = ChessScene()
    let online = OnlineGame()
    private var positions: [Position] = []
    private var moves: [Move] = []
    private var computerTask: Task<Void, Never>?
    private var gameID = UUID()

    init() {
        board.onSquareTapped = { [weak self] square in self?.select(square) }
        online.onUpdate = { [weak self] moves, side in self?.receiveOnline(moves, side: side) }
        restoreLocalGame()
        refreshBoard(animated: false)
        scheduleComputer()
    }

    var isGameOver: Bool { position.outcome != .ongoing || (mode == .online && online.isFinished) }
    var canUndo: Bool { mode != .online && !positions.isEmpty }
    var status: String {
        if mode == .online && online.matchID == nil { return "Find your opponent" }
        if mode == .online && online.isFinished { return online.status }
        if isSubmitting { return "Sending your move…" }
        switch position.outcome {
        case .checkmate(let winner): return "\(winner.title) wins"
        case .stalemate: return "Draw by stalemate"
        case .draw(let reason): return "Draw · \(reason)"
        case .ongoing:
            if isThinking { return "\(position.sideToMove.title) is thinking…" }
            return "\(position.sideToMove.title) to move"
        }
    }
    var detail: String {
        if mode == .online {
            if online.matchID == nil { return "Connect through Game Center to start or resume a match." }
            if isSubmitting { return "Your board updates when Game Center accepts the move." }
            if !online.isLocalTurn && !isGameOver { return "Waiting for your opponent’s next move." }
        }
        if isGameOver { return mode == .online ? "Close this match to find another opponent." : "Start a new game or undo to explore another line." }
        if isThinking { return "\(difficulty.title) computer opponent" }
        if position.isInCheck(position.sideToMove) { return "Check — protect your king." }
        if selected != nil { return "Choose a highlighted square to move." }
        return "Select a piece to see its legal moves."
    }
    var lastMove: Move? { moves.last }

    func start(mode: PlayMode, difficulty: Difficulty, side: Side) {
        invalidateComputer()
        self.mode = mode
        self.difficulty = difficulty
        humanSide = side
        perspective = mode == .computer ? side : .white
        position = Position()
        positions.removeAll()
        moves.removeAll()
        records.removeAll()
        selected = nil
        promotionChoices = []
        onlineError = nil
        showsSetup = false
        refreshBoard(animated: false)
        if mode == .online {
            if online.matchID != nil { online.refresh() }
            else { online.authenticate() }
        } else { saveLocalGame(); scheduleComputer() }
    }

    func select(_ square: Square) {
        guard !isThinking, !isSubmitting, !isGameOver, promotionChoices.isEmpty,
              mode == .local || position.sideToMove == humanSide else { return }
        if mode == .online && (online.matchID == nil || !online.isLocalTurn || online.isBusy) { return }
        if let source = selected {
            let candidates = position.legalMoves().filter { $0.from == source && $0.to == square }
            if candidates.count > 1 {
                promotionChoices = candidates
                return
            }
            if let move = candidates.first { commit(move); return }
        }
        selected = selected == square ? nil : (position.piece(at: square)?.side == position.sideToMove ? square : nil)
        refreshBoard(animated: false)
    }

    func promote(to kind: PieceKind) {
        guard let move = promotionChoices.first(where: { $0.promotion == kind }) else { return }
        promotionChoices = []
        commit(move)
    }

    func cancelPromotion() { promotionChoices = [] }

    func undo() {
        guard canUndo else { return }
        invalidateComputer()
        promotionChoices = []
        repeat {
            guard let previous = positions.popLast() else { break }
            position = previous
            moves.removeLast()
            records.removeLast()
        } while mode == .computer && position.sideToMove != humanSide && !positions.isEmpty
        selected = nil
        refreshBoard(animated: false)
        saveLocalGame()
        scheduleComputer()
    }

    func flipBoard() {
        perspective = perspective.opponent
        refreshBoard(animated: true)
    }

    private func invalidateComputer() {
        gameID = UUID()
        computerTask?.cancel()
        computerTask = nil
        isThinking = false
        isSubmitting = false
    }

    private func commit(_ move: Move) {
        if mode == .online {
            submitOnline(move)
            return
        }
        let before = position
        guard position.play(move) else { return }
        positions.append(before)
        moves.append(move)
        records.append(MoveRecord(side: before.sideToMove, text: notation(move, before: before)))
        selected = nil
        refreshBoard(animated: true)
        saveLocalGame()
        scheduleComputer()
    }

    private struct SavedGame: Codable {
        let version: Int
        let mode: String
        let difficulty: String
        let side: String
        let archive: Data
    }

    private func saveURL() throws -> URL {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("RoyalChess", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("local-game.json")
    }

    private func saveLocalGame() {
        guard mode != .online else { return }
        do {
            let saved = SavedGame(version: 1, mode: mode.rawValue, difficulty: difficulty.rawValue,
                                  side: humanSide.rawValue, archive: try MatchArchive(moves: moves).encoded())
            try JSONEncoder().encode(saved).write(to: saveURL(), options: .atomic)
            storageNotice = nil
        } catch { storageNotice = "Your game could not be saved. Keep the app open to continue playing." }
    }

    private func restoreLocalGame() {
        do {
            let url = try saveURL()
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            let saved = try JSONDecoder().decode(SavedGame.self, from: Data(contentsOf: url))
            guard saved.version == 1, let savedMode = PlayMode(rawValue: saved.mode), savedMode != .online,
                  let level = Difficulty(rawValue: saved.difficulty), let side = Side(rawValue: saved.side) else {
                storageNotice = "This saved game needs a different app version. Start a new game to continue."
                return
            }
            let archive = try MatchArchive(data: saved.archive)
            mode = savedMode
            difficulty = level
            humanSide = side
            perspective = savedMode == .computer ? side : .white
            for move in archive.moves {
                let before = position
                guard position.play(move) else { return } // Already validated by MatchArchive.
                positions.append(before)
                moves.append(move)
                records.append(MoveRecord(side: before.sideToMove, text: notation(move, before: before)))
            }
        } catch { storageNotice = "The saved game could not be restored. Start a new game to continue." }
    }

    private func submitOnline(_ move: Move) {
        guard !isSubmitting, online.isLocalTurn, !online.isBusy else { return }
        var next = position
        guard next.play(move) else { return }
        let submittedMoves = moves + [move]
        let outcome = next.outcome
        let currentGame = gameID
        isSubmitting = true
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.online.submit(moves: submittedMoves, outcome: outcome)
            } catch {
                if self.gameID == currentGame { self.onlineError = error.localizedDescription }
            }
            if self.gameID == currentGame { self.isSubmitting = false }
        }
    }

    private func receiveOnline(_ received: [Move], side: Side) {
        guard mode == .online else { return }
        // Replay the entire log so castling rights, en passant and repetitions survive reconnects.
        var rebuilt = Position()
        var snapshots: [Position] = []
        for move in received {
            snapshots.append(rebuilt)
            guard rebuilt.play(move) else { onlineError = "The online match contains an invalid move."; return }
        }
        let animate = received.count == moves.count + 1 && Array(received.dropLast()) == moves
        positions = snapshots
        moves = received
        records = []
        for (index, move) in received.enumerated() {
            // notation() uses the resulting position for check and mate suffixes.
            position = index + 1 < snapshots.count ? snapshots[index + 1] : rebuilt
            records.append(MoveRecord(side: snapshots[index].sideToMove, text: notation(move, before: snapshots[index])))
        }
        position = rebuilt
        humanSide = side
        perspective = side
        selected = nil
        promotionChoices = []
        refreshBoard(animated: animate)
    }

    private func notation(_ move: Move, before: Position) -> String {
        guard let piece = before.piece(at: move.from) else { return move.from.notation + "–" + move.to.notation }
        var result: String
        if piece.kind == .king && abs(move.to.file - move.from.file) == 2 {
            result = move.to.file > move.from.file ? "O-O" : "O-O-O"
        } else {
            let capture = before.piece(at: move.to) != nil || (piece.kind == .pawn && move.from.file != move.to.file)
            result = piece.kind.letter + move.from.notation + (capture ? "×" : "–") + move.to.notation
            if let promotion = move.promotion { result += "=" + promotion.letter }
        }
        if case .checkmate = position.outcome { result += "#" }
        else if position.isInCheck(position.sideToMove) { result += "+" }
        return result
    }

    private func refreshBoard(animated: Bool) {
        let targets = selected.map { source in position.legalMoves().filter { $0.from == source }.map(\.to) } ?? []
        board.update(position: position, selected: selected, legalTargets: targets,
                     lastMove: moves.last, perspective: perspective, animated: animated)
    }

    private func scheduleComputer() {
        guard mode == .computer, position.sideToMove != humanSide, !isGameOver else { return }
        let snapshot = position
        let level = difficulty
        let currentGame = gameID
        isThinking = true
        computerTask = Task { [weak self] in
            // Keep CPU search off the main actor so SceneKit animation stays responsive.
            let search = Task.detached(priority: .userInitiated) {
                ChessAI.bestMove(in: snapshot, difficulty: level)
            }
            // Search and the minimum response pause overlap. This lets the
            // human's animation finish without adding delay to a longer search.
            let move = await withTaskCancellationHandler(operation: {
                do { try await Task.sleep(nanoseconds: 1_400_000_000) }
                catch { search.cancel(); return nil as Move? }
                return await search.value
            }, onCancel: { search.cancel() })
            guard !Task.isCancelled, let self, self.gameID == currentGame else { return }
            self.isThinking = false
            if let move { self.commit(move) }
        }
    }
}

extension Side {
    var title: String { rawValue.capitalized }
}
extension Difficulty {
    var title: String { rawValue.capitalized }
    var explanation: String {
        switch self {
        case .beginner: return "A relaxed opponent. Learn the board and try new ideas."
        case .intermediate: return "Looks ahead and balances material with piece activity."
        case .pro: return "Our deepest search. A tougher challenge, without hints."
        }
    }
}
extension PieceKind {
    var letter: String {
        switch self {
        case .king: return "K"
        case .queen: return "Q"
        case .rook: return "R"
        case .bishop: return "B"
        case .knight: return "N"
        case .pawn: return ""
        }
    }
    var symbol: String {
        switch self {
        case .king: return "♔"
        case .queen: return "♕"
        case .rook: return "♖"
        case .bishop: return "♗"
        case .knight: return "♘"
        case .pawn: return "♙"
        }
    }
}
