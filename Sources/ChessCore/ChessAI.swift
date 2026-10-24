import Foundation

/// The local computer opponent's search strength. No network service is required.
public enum Difficulty: String, CaseIterable, Sendable {
    case beginner
    case intermediate
    case pro
}

public enum ChessAI {
    /// Returns a legal move for the side to move, or nil when the game has ended.
    /// Run this synchronous search off the main actor so animations remain smooth.
    public static func bestMove(in position: Position, difficulty: Difficulty) -> Move? {
        let moves = position.legalMoves()
        guard !moves.isEmpty, position.immediateDrawReason == nil else { return nil }
        if moves.count == 1 { return moves[0] }
        // Always finish an immediate mate, even if a later search would exhaust
        // its budget before visiting that move.
        if let mate = moves.first(where: { move in
            let next = position.applyingUnchecked(move)
            return next.isInCheck(next.sideToMove) && next.legalMoves().isEmpty
        }) { return mate }

        if difficulty == .beginner {
            // A beginner sees immediate material and simple checks, but does not
            // look ahead. Small variation keeps repeat games from feeling scripted.
            return moves.map { ($0, beginnerScore($0, in: position)) }
                .max { $0.1 < $1.1 }?.0
        }

        var search = Search(difficulty: difficulty)
        return search.bestMove(in: position, moves: moves)
    }

    private static func beginnerScore(_ move: Move, in position: Position) -> Int {
        let next = position.applyingUnchecked(move)
        return -Evaluation.score(next) + Int.random(in: -65...65)
    }
}

private struct Search {
    private static let mate = 100_000
    private let maximumDepth: Int
    private let maximumNodes: Int
    private let deadline: Date
    private var nodes = 0

    init(difficulty: Difficulty) {
        maximumDepth = difficulty == .pro ? 5 : 3
        maximumNodes = difficulty == .pro ? 110_000 : 20_000
        deadline = Date().addingTimeInterval(difficulty == .pro ? 1.8 : 0.55)
    }

    mutating func bestMove(in position: Position, moves: [Move]) -> Move {
        var best = ordered(moves, in: position).first!
        // Only commit a fully searched iteration. The previous answer remains
        // valid if a time or node budget interrupts the next, deeper iteration.
        for depth in 1...maximumDepth {
            do {
                var alpha = -Self.mate * 2
                var iterationBest = best
                for move in ordered(moves, in: position, preferred: best) {
                    try checkBudget()
                    let child = position.applyingUnchecked(move)
                    let score = try -negamax(child, depth: depth - 1,
                                             alpha: -Self.mate * 2, beta: -alpha, ply: 1)
                    if score > alpha {
                        alpha = score
                        iterationBest = move
                    }
                }
                best = iterationBest
                if alpha > Self.mate - 100 { break }
            } catch {
                break
            }
        }
        return best
    }

    private mutating func negamax(_ position: Position, depth: Int,
                                 alpha initialAlpha: Int, beta: Int, ply: Int) throws -> Int {
        if depth <= 0 {
            return try quiescence(position, alpha: initialAlpha, beta: beta, ply: ply, remaining: 5)
        }
        try checkBudget()
        let moves = position.legalMoves()
        if moves.isEmpty {
            return position.isInCheck(position.sideToMove) ? -Self.mate + ply : 0
        }
        if position.immediateDrawReason != nil { return 0 }

        var alpha = initialAlpha
        for move in ordered(moves, in: position) {
            let child = position.applyingUnchecked(move)
            let score = try -negamax(child, depth: depth - 1, alpha: -beta, beta: -alpha, ply: ply + 1)
            if score >= beta { return score }
            alpha = max(alpha, score)
        }
        return alpha
    }

    /// Finishes immediate exchanges before evaluating a leaf, so a superficially
    /// free queen that can be recaptured does not look like a winning move.
    private mutating func quiescence(_ position: Position, alpha initialAlpha: Int,
                                    beta: Int, ply: Int, remaining: Int) throws -> Int {
        try checkBudget()
        let moves = position.legalMoves()
        let checked = position.isInCheck(position.sideToMove)
        if moves.isEmpty { return checked ? -Self.mate + ply : 0 }
        if position.immediateDrawReason != nil { return 0 }

        let standing = Evaluation.score(position)
        if remaining <= 0 { return standing }
        var alpha = initialAlpha
        if !checked {
            if standing >= beta { return standing }
            alpha = max(alpha, standing)
        }

        let tactical = checked ? moves : moves.filter { isCapture($0, in: position) || $0.promotion != nil }
        for move in ordered(tactical, in: position) {
            let child = position.applyingUnchecked(move)
            let score = try -quiescence(child, alpha: -beta, beta: -alpha,
                                        ply: ply + 1, remaining: remaining - 1)
            if score >= beta { return score }
            alpha = max(alpha, score)
        }
        return alpha
    }

    private mutating func checkBudget() throws {
        nodes += 1
        if nodes >= maximumNodes || Date() >= deadline || Task<Never, Never>.isCancelled {
            throw BudgetExhausted()
        }
    }

    private struct BudgetExhausted: Error {}
}

private func ordered(_ moves: [Move], in position: Position, preferred: Move? = nil) -> [Move] {
    moves.map { move -> (Move, Int) in
        if move == preferred { return (move, 1_000_000) }
        var score = 0
        if let attacker = position.piece(at: move.from), isCapture(move, in: position) {
            let victim = position.piece(at: move.to)?.kind ?? .pawn
            score += 10_000 + Evaluation.value(victim) * 10 - Evaluation.value(attacker.kind)
        }
        if let promotion = move.promotion { score += 8_000 + Evaluation.value(promotion) }
        // Prefer central development when no tactical ordering applies.
        score += 14 - abs(move.to.file * 2 - 7) - abs(move.to.rank * 2 - 7)
        return (move, score)
    }.sorted { $0.1 > $1.1 }.map(\.0)
}

private func isCapture(_ move: Move, in position: Position) -> Bool {
    if position.piece(at: move.to) != nil { return true }
    // A diagonal pawn move to an empty square is a legal en passant capture.
    return position.piece(at: move.from)?.kind == .pawn && move.from.file != move.to.file
}

private enum Evaluation {
    static func value(_ kind: PieceKind) -> Int {
        switch kind {
        case .pawn: return 100
        case .knight: return 320
        case .bishop: return 335
        case .rook: return 500
        case .queen: return 900
        case .king: return 0
        }
    }

    /// Material, development, pawn structure, and phase-aware king placement.
    /// Positive values always favor the player whose turn it is.
    static func score(_ position: Position) -> Int {
        var entries: [(square: Square, piece: Piece)] = []
        var pawns = [[Int]](repeating: [Int](repeating: 0, count: 8), count: 2)
        var bishopCounts = [0, 0]
        var nonPawnMaterial = 0
        for rank in 0..<8 {
            for file in 0..<8 {
                let square = Square(file: file, rank: rank)
                guard let piece = position.piece(at: square) else { continue }
                entries.append((square, piece))
                let side = piece.side == .white ? 0 : 1
                if piece.kind == .pawn { pawns[side][file] += 1 }
                else { nonPawnMaterial += value(piece.kind) }
                if piece.kind == .bishop { bishopCounts[side] += 1 }
            }
        }

        let endgame = nonPawnMaterial <= 2_600
        var totals = [0, 0]
        for (square, piece) in entries {
            let side = piece.side == .white ? 0 : 1
            let advance = piece.side == .white ? square.rank : 7 - square.rank
            let centrality = 14 - abs(square.file * 2 - 7) - abs(square.rank * 2 - 7)
            var points = value(piece.kind)
            switch piece.kind {
            case .pawn:
                points += advance * 7 + centrality * 2
                if pawns[side][square.file] > 1 { points -= 13 }
                let left = square.file > 0 ? pawns[side][square.file - 1] : 0
                let right = square.file < 7 ? pawns[side][square.file + 1] : 0
                if left + right == 0 { points -= 12 }
                let passed = !entries.contains { other in
                    other.piece.kind == .pawn && other.piece.side != piece.side
                        && abs(other.square.file - square.file) <= 1
                        && (piece.side == .white ? other.square.rank > square.rank : other.square.rank < square.rank)
                }
                if passed { points += advance * advance * (endgame ? 4 : 2) }
            case .knight:
                points += centrality * 5
                if advance == 0 { points -= 12 }
            case .bishop:
                points += centrality * 3
                if advance == 0 { points -= 8 }
            case .rook:
                if pawns[side][square.file] == 0 {
                    points += pawns[1 - side][square.file] == 0 ? 22 : 12
                }
                if advance == 6 { points += 25 }
            case .queen:
                points += centrality
                if !endgame, advance > 3 { points -= 10 }
            case .king:
                if endgame {
                    points += centrality * 5
                } else {
                    points -= centrality * 3
                    if advance <= 1 && (square.file <= 2 || square.file >= 6) { points += 28 }
                    let shieldRank = square.rank + (piece.side == .white ? 1 : -1)
                    if (0..<8).contains(shieldRank) {
                        for file in max(0, square.file - 1)...min(7, square.file + 1) {
                            if let shield = position.piece(at: Square(file: file, rank: shieldRank)),
                               shield.side == piece.side, shield.kind == .pawn { points += 8 }
                        }
                    }
                }
            }
            totals[side] += points
        }
        if bishopCounts[0] >= 2 { totals[0] += 30 }
        if bishopCounts[1] >= 2 { totals[1] += 30 }
        let whiteScore = totals[0] - totals[1]
        return position.sideToMove == .white ? whiteScore : -whiteScore
    }
}
