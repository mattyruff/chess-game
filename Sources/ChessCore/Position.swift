import Foundation

/// A value-type chess position. Every public move is checked against the legal move list.
public struct Position: Sendable {
    private var board: [Piece?]
    public private(set) var sideToMove: Side
    private var castlingRights: UInt8
    public private(set) var enPassantTarget: Square?
    public private(set) var halfmoveClock: Int
    public private(set) var fullmoveNumber: Int
    private var repetitions: [String: Int]

    public init() {
        // This constant is also a useful, reproducible interchange format for the initial state.
        self = try! Position(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
    }

    public init(fen: String) throws {
        let fields = fen.split(whereSeparator: { $0.isWhitespace })
        guard (4...6).contains(fields.count) else { throw FENError.invalid("expected 4–6 fields") }
        let rows = fields[0].split(separator: "/", omittingEmptySubsequences: false)
        guard rows.count == 8 else { throw FENError.invalid("expected eight ranks") }
        board = Array(repeating: nil, count: 64)
        sideToMove = .white
        castlingRights = 0
        enPassantTarget = nil
        halfmoveClock = 0
        fullmoveNumber = 1
        repetitions = [:]

        for (row, contents) in rows.enumerated() {
            var file = 0
            for character in contents {
                if let empty = character.wholeNumberValue, (1...8).contains(empty) {
                    file += empty
                } else {
                    guard file < 8, let kind = PieceKind(fenCharacter: character) else {
                        throw FENError.invalid("unknown piece or overfull rank")
                    }
                    let side: Side = character.isUppercase ? .white : .black
                    board[(7 - row) * 8 + file] = Piece(side: side, kind: kind)
                    file += 1
                }
                guard file <= 8 else { throw FENError.invalid("overfull rank") }
            }
            guard file == 8 else { throw FENError.invalid("each rank must contain eight squares") }
        }
        for side in Side.allCases {
            guard board.compactMap({ $0 }).filter({ $0.side == side && $0.kind == .king }).count == 1 else {
                throw FENError.invalid("each side must have exactly one king")
            }
        }
        switch fields[1] {
        case "w": sideToMove = .white
        case "b": sideToMove = .black
        default: throw FENError.invalid("invalid active color")
        }
        if fields[2] != "-" {
            var seen = Set<Character>()
            for character in fields[2] {
                guard seen.insert(character).inserted else { throw FENError.invalid("duplicate castling right") }
                switch character {
                case "K": castlingRights |= 1
                case "Q": castlingRights |= 2
                case "k": castlingRights |= 4
                case "q": castlingRights |= 8
                default: throw FENError.invalid("invalid castling rights")
                }
            }
        }
        if fields[3] != "-" {
            guard let target = Square(notation: String(fields[3])),
                  target.rank == (sideToMove == .white ? 5 : 2), piece(at: target) == nil else {
                throw FENError.invalid("invalid en passant target")
            }
            enPassantTarget = target
        }
        if fields.count >= 5 {
            guard let value = Int(fields[4]), value >= 0 else { throw FENError.invalid("invalid halfmove clock") }
            halfmoveClock = value
        }
        if fields.count == 6 {
            guard let value = Int(fields[5]), value >= 1 else { throw FENError.invalid("invalid fullmove number") }
            fullmoveNumber = value
        }
        repetitions[repetitionKey] = 1
    }

    public func piece(at square: Square) -> Piece? {
        guard square.isValid else { return nil }
        return board[square.index]
    }

    public var fen: String {
        "\(boardFEN) \(sideToMove == .white ? "w" : "b") \(castlingFEN) \(enPassantTarget?.notation ?? "-") \(halfmoveClock) \(fullmoveNumber)"
    }

    public func legalMoves() -> [Move] {
        pseudoLegalMoves().filter { move in
            var next = self
            next.apply(move, recordHistory: false)
            return !next.isInCheck(sideToMove)
        }
    }

    public func isInCheck(_ side: Side) -> Bool {
        guard let index = board.firstIndex(of: Piece(side: side, kind: .king)) else { return true }
        return isAttacked(Square(file: index % 8, rank: index / 8), by: side.opponent)
    }

    /// Illegal moves, including promotions without a selected piece, leave the position unchanged.
    @discardableResult
    public mutating func play(_ move: Move) -> Bool {
        guard immediateDrawReason == nil, legalMoves().contains(move) else { return false }
        apply(move, recordHistory: true)
        return true
    }

    public var outcome: GameOutcome {
        let moves = legalMoves()
        if moves.isEmpty {
            return isInCheck(sideToMove) ? .checkmate(winner: sideToMove.opponent) : .stalemate
        }
        if let reason = immediateDrawReason { return .draw(reason: reason) }
        return .ongoing
    }

    /// Draw claims are automatically accepted in this local game.
    var immediateDrawReason: String? {
        if halfmoveClock >= 100 { return "Fifty-move rule" }
        if repetitions[repetitionKey, default: 0] >= 3 { return "Threefold repetition" }
        if hasInsufficientMaterial { return "Insufficient material" }
        return nil
    }

    func applyingUnchecked(_ move: Move) -> Position {
        var next = self
        next.apply(move, recordHistory: true)
        return next
    }

    private mutating func apply(_ move: Move, recordHistory: Bool) {
        guard let movingPiece = piece(at: move.from) else { return }
        var captured = piece(at: move.to)
        if movingPiece.kind == .pawn, move.from.file != move.to.file, captured == nil,
           move.to == enPassantTarget {
            let capturedSquare = Square(file: move.to.file, rank: move.from.rank)
            captured = piece(at: capturedSquare)
            board[capturedSquare.index] = nil
        }
        board[move.from.index] = nil
        board[move.to.index] = Piece(side: movingPiece.side, kind: move.promotion ?? movingPiece.kind)
        if movingPiece.kind == .king {
            castlingRights &= movingPiece.side == .white ? 12 : 3
            if abs(move.to.file - move.from.file) == 2 {
                let rookFrom = Square(file: move.to.file == 6 ? 7 : 0, rank: move.from.rank)
                let rookTo = Square(file: move.to.file == 6 ? 5 : 3, rank: move.from.rank)
                board[rookTo.index] = board[rookFrom.index]
                board[rookFrom.index] = nil
            }
        }
        // Moving a rook from its home square or capturing it there permanently removes that right.
        for square in [move.from, move.to] {
            switch square.index {
            case 0: castlingRights &= ~UInt8(2)
            case 7: castlingRights &= ~UInt8(1)
            case 56: castlingRights &= ~UInt8(8)
            case 63: castlingRights &= ~UInt8(4)
            default: break
            }
        }
        enPassantTarget = movingPiece.kind == .pawn && abs(move.to.rank - move.from.rank) == 2
            ? Square(file: move.from.file, rank: (move.from.rank + move.to.rank) / 2) : nil
        halfmoveClock = movingPiece.kind == .pawn || captured != nil ? 0 : halfmoveClock + 1
        if sideToMove == .black { fullmoveNumber += 1 }
        sideToMove = sideToMove.opponent
        if recordHistory {
            // Positions before an irreversible move can never recur.
            if halfmoveClock == 0 { repetitions.removeAll(keepingCapacity: true) }
            repetitions[repetitionKey, default: 0] += 1
        }
    }

    private func pseudoLegalMoves() -> [Move] {
        var moves: [Move] = []
        moves.reserveCapacity(48)
        for index in 0..<64 {
            guard let piece = board[index], piece.side == sideToMove else { continue }
            let from = Square(file: index % 8, rank: index / 8)
            switch piece.kind {
            case .pawn: appendPawnMoves(from: from, side: piece.side, to: &moves)
            case .knight:
                appendJumpMoves(from: from, side: piece.side, offsets: Self.knightOffsets, to: &moves)
            case .king:
                appendJumpMoves(from: from, side: piece.side, offsets: Self.kingOffsets, to: &moves)
                appendCastles(from: from, side: piece.side, to: &moves)
            case .bishop:
                appendSlidingMoves(from: from, side: piece.side, directions: Self.diagonals, to: &moves)
            case .rook:
                appendSlidingMoves(from: from, side: piece.side, directions: Self.orthogonals, to: &moves)
            case .queen:
                appendSlidingMoves(from: from, side: piece.side, directions: Self.kingOffsets, to: &moves)
            }
        }
        return moves
    }

    private func appendPawnMoves(from: Square, side: Side, to moves: inout [Move]) {
        let direction = side == .white ? 1 : -1
        let forward = Square(file: from.file, rank: from.rank + direction)
        if forward.isValid, piece(at: forward) == nil {
            appendPawnMove(from: from, to: forward, into: &moves)
            let double = Square(file: from.file, rank: from.rank + direction * 2)
            if from.rank == (side == .white ? 1 : 6), piece(at: double) == nil {
                moves.append(Move(from: from, to: double))
            }
        }
        for offset in [-1, 1] {
            let target = Square(file: from.file + offset, rank: from.rank + direction)
            guard target.isValid else { continue }
            if let captured = piece(at: target), captured.side != side, captured.kind != .king {
                appendPawnMove(from: from, to: target, into: &moves)
            } else if target == enPassantTarget, piece(at: target) == nil,
                      piece(at: Square(file: target.file, rank: from.rank)) == Piece(side: side.opponent, kind: .pawn) {
                moves.append(Move(from: from, to: target))
            }
        }
    }

    private func appendPawnMove(from: Square, to: Square, into moves: inout [Move]) {
        if to.rank == 0 || to.rank == 7 {
            for kind in [PieceKind.queen, .rook, .bishop, .knight] {
                moves.append(Move(from: from, to: to, promotion: kind))
            }
        } else {
            moves.append(Move(from: from, to: to))
        }
    }

    private func appendJumpMoves(from: Square, side: Side, offsets: [(Int, Int)], to moves: inout [Move]) {
        for (file, rank) in offsets {
            let target = Square(file: from.file + file, rank: from.rank + rank)
            guard target.isValid else { continue }
            if let occupant = piece(at: target), occupant.side == side || occupant.kind == .king { continue }
            moves.append(Move(from: from, to: target))
        }
    }

    private func appendSlidingMoves(from: Square, side: Side, directions: [(Int, Int)], to moves: inout [Move]) {
        for (file, rank) in directions {
            var target = Square(file: from.file + file, rank: from.rank + rank)
            while target.isValid {
                if let occupant = piece(at: target) {
                    if occupant.side != side, occupant.kind != .king { moves.append(Move(from: from, to: target)) }
                    break
                }
                moves.append(Move(from: from, to: target))
                target = Square(file: target.file + file, rank: target.rank + rank)
            }
        }
    }

    private func appendCastles(from: Square, side: Side, to moves: inout [Move]) {
        let rank = side == .white ? 0 : 7
        guard from == Square(file: 4, rank: rank), !isInCheck(side) else { return }
        let shift: UInt8 = side == .white ? 0 : 2
        if castlingRights & (1 << shift) != 0,
           piece(at: Square(file: 7, rank: rank)) == Piece(side: side, kind: .rook),
           piece(at: Square(file: 5, rank: rank)) == nil, piece(at: Square(file: 6, rank: rank)) == nil,
           !isAttacked(Square(file: 5, rank: rank), by: side.opponent),
           !isAttacked(Square(file: 6, rank: rank), by: side.opponent) {
            moves.append(Move(from: from, to: Square(file: 6, rank: rank)))
        }
        if castlingRights & (2 << shift) != 0,
           piece(at: Square(file: 0, rank: rank)) == Piece(side: side, kind: .rook),
           piece(at: Square(file: 1, rank: rank)) == nil, piece(at: Square(file: 2, rank: rank)) == nil,
           piece(at: Square(file: 3, rank: rank)) == nil,
           !isAttacked(Square(file: 3, rank: rank), by: side.opponent),
           !isAttacked(Square(file: 2, rank: rank), by: side.opponent) {
            moves.append(Move(from: from, to: Square(file: 2, rank: rank)))
        }
    }

    private func isAttacked(_ square: Square, by side: Side) -> Bool {
        let pawnRank = square.rank + (side == .white ? -1 : 1)
        for offset in [-1, 1] {
            if piece(at: Square(file: square.file + offset, rank: pawnRank)) == Piece(side: side, kind: .pawn) { return true }
        }
        for (file, rank) in Self.knightOffsets {
            if piece(at: Square(file: square.file + file, rank: square.rank + rank)) == Piece(side: side, kind: .knight) { return true }
        }
        for (file, rank) in Self.kingOffsets {
            var target = Square(file: square.file + file, rank: square.rank + rank)
            var distance = 1
            while target.isValid {
                if let occupant = piece(at: target) {
                    if occupant.side == side {
                        if occupant.kind == .queen { return true }
                        if occupant.kind == .king && distance == 1 { return true }
                        if occupant.kind == .bishop && file != 0 && rank != 0 { return true }
                        if occupant.kind == .rook && (file == 0 || rank == 0) { return true }
                    }
                    break
                }
                target = Square(file: target.file + file, rank: target.rank + rank)
                distance += 1
            }
        }
        return false
    }

    private var hasInsufficientMaterial: Bool {
        let nonKings = board.enumerated().compactMap { index, piece -> (Int, Piece)? in
            guard let piece, piece.kind != .king else { return nil }
            return (index, piece)
        }
        if nonKings.isEmpty { return true }
        if nonKings.count == 1 { return [.bishop, .knight].contains(nonKings[0].1.kind) }
        guard nonKings.allSatisfy({ $0.1.kind == .bishop }) else { return false }
        let colors = Set(nonKings.map { ($0.0 % 8 + $0.0 / 8) % 2 })
        return colors.count == 1
    }

    private var boardFEN: String {
        var rows: [String] = []
        for rank in (0..<8).reversed() {
            var row = ""
            var empty = 0
            for file in 0..<8 {
                if let piece = board[rank * 8 + file] {
                    if empty > 0 { row += String(empty); empty = 0 }
                    let character = String(piece.kind.fenCharacter)
                    row += piece.side == .white ? character.uppercased() : character
                } else { empty += 1 }
            }
            if empty > 0 { row += String(empty) }
            rows.append(row)
        }
        return rows.joined(separator: "/")
    }

    private var castlingFEN: String {
        var value = ""
        for (mask, symbol) in [(UInt8(1), "K"), (2, "Q"), (4, "k"), (8, "q")] {
            if castlingRights & mask != 0 { value += symbol }
        }
        return value.isEmpty ? "-" : value
    }

    /// FIDE repetition considers an en passant field only when a legal capture is available.
    private var repetitionKey: String {
        let ep = hasLegalEnPassantCapture ? enPassantTarget?.notation ?? "-" : "-"
        return "\(boardFEN) \(sideToMove.rawValue) \(castlingFEN) \(ep)"
    }

    private var hasLegalEnPassantCapture: Bool {
        guard let target = enPassantTarget else { return false }
        let fromRank = target.rank + (sideToMove == .white ? -1 : 1)
        guard piece(at: Square(file: target.file, rank: fromRank)) == Piece(side: sideToMove.opponent, kind: .pawn) else { return false }
        for offset in [-1, 1] {
            let from = Square(file: target.file + offset, rank: fromRank)
            guard piece(at: from) == Piece(side: sideToMove, kind: .pawn) else { continue }
            var next = self
            next.apply(Move(from: from, to: target), recordHistory: false)
            if !next.isInCheck(sideToMove) { return true }
        }
        return false
    }

    private static let knightOffsets = [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)]
    private static let diagonals = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
    private static let orthogonals = [(1, 0), (-1, 0), (0, 1), (0, -1)]
    private static let kingOffsets = diagonals + orthogonals
}
