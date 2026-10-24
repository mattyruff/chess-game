import Foundation

public enum Side: String, CaseIterable, Hashable, Sendable {
    case white, black

    public var opponent: Side { self == .white ? .black : .white }
}

public enum PieceKind: String, CaseIterable, Hashable, Sendable {
    case king, queen, rook, bishop, knight, pawn
}

public struct Piece: Equatable, Hashable, Sendable {
    public let side: Side
    public let kind: PieceKind

    public init(side: Side, kind: PieceKind) {
        self.side = side
        self.kind = kind
    }
}

/// Files a–h are 0–7; rank 0 is White's home rank.
public struct Square: Hashable, Sendable {
    public let file: Int
    public let rank: Int

    public init(file: Int, rank: Int) {
        self.file = file
        self.rank = rank
    }

    public init?(notation: String) {
        let bytes = Array(notation.utf8)
        guard bytes.count == 2, (97...104).contains(bytes[0]), (49...56).contains(bytes[1]) else { return nil }
        self.init(file: Int(bytes[0]) - 97, rank: Int(bytes[1]) - 49)
    }

    public var notation: String {
        guard isValid else { return "?" }
        return String(UnicodeScalar(file + 97)!) + String(rank + 1)
    }

    var isValid: Bool { (0..<8).contains(file) && (0..<8).contains(rank) }
    var index: Int { rank * 8 + file }
}

public struct Move: Equatable, Hashable, Sendable {
    public let from: Square
    public let to: Square
    public let promotion: PieceKind?

    public init(from: Square, to: Square, promotion: PieceKind? = nil) {
        self.from = from
        self.to = to
        self.promotion = promotion
    }

    public var coordinateNotation: String {
        from.notation + to.notation + (promotion.map { String($0.fenCharacter) } ?? "")
    }
}

public enum GameOutcome: Equatable, Sendable {
    case ongoing
    case checkmate(winner: Side)
    case stalemate
    case draw(reason: String)
}

public enum FENError: Error, Equatable, CustomStringConvertible {
    case invalid(String)

    public var description: String {
        switch self {
        case .invalid(let message): return "Invalid FEN: \(message)"
        }
    }
}

extension PieceKind {
    var fenCharacter: Character {
        switch self {
        case .king: return "k"
        case .queen: return "q"
        case .rook: return "r"
        case .bishop: return "b"
        case .knight: return "n"
        case .pawn: return "p"
        }
    }

    init?(fenCharacter: Character) {
        switch String(fenCharacter).lowercased() {
        case "k": self = .king
        case "q": self = .queen
        case "r": self = .rook
        case "b": self = .bishop
        case "n": self = .knight
        case "p": self = .pawn
        default: return nil
        }
    }
}
