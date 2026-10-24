import Foundation

/// Portable Game Center payload validation. A remote board is never trusted:
/// replay each move from the initial position using the same rules as local play.
public struct MatchArchive: Sendable {
    public let moves: [Move]
    public let position: Position
    public static let maximumBytes = 128 * 1024
    public static let maximumMoves = 4096

    public init(moves: [Move]) throws {
        guard moves.count <= Self.maximumMoves else { throw ArchiveError.tooLarge }
        var position = Position()
        for move in moves {
            guard position.play(move) else { throw ArchiveError.invalidMove }
        }
        self.moves = moves
        self.position = position
    }

    public init(data: Data?) throws {
        guard let data, !data.isEmpty else { try self.init(moves: []); return }
        guard data.count <= Self.maximumBytes else { throw ArchiveError.tooLarge }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.version == 1 else { throw ArchiveError.unsupportedVersion }
        guard envelope.moves.count <= Self.maximumMoves else { throw ArchiveError.tooLarge }
        let moves = try envelope.moves.map { notation -> Move in
            let bytes = Array(notation.utf8)
            guard bytes.count == 4 || bytes.count == 5,
                  let from = Square(notation: String(decoding: bytes[0..<2], as: UTF8.self)),
                  let to = Square(notation: String(decoding: bytes[2..<4], as: UTF8.self)) else { throw ArchiveError.invalidMove }
            var promotion: PieceKind?
            if bytes.count == 5 {
                switch bytes[4] {
                case 113: promotion = .queen
                case 114: promotion = .rook
                case 98: promotion = .bishop
                case 110: promotion = .knight
                default: throw ArchiveError.invalidMove
                }
            }
            return Move(from: from, to: to, promotion: promotion)
        }
        try self.init(moves: moves)
    }

    public func encoded() throws -> Data {
        let data = try JSONEncoder().encode(Envelope(version: 1, moves: moves.map(\.coordinateNotation)))
        guard data.count <= Self.maximumBytes else { throw ArchiveError.tooLarge }
        return data
    }

    private struct Envelope: Codable {
        let version: Int
        let moves: [String]
    }

    public enum ArchiveError: LocalizedError {
        case invalidMove, tooLarge, unsupportedVersion
        public var errorDescription: String? {
            switch self {
            case .invalidMove: return "The match contains an invalid chess move."
            case .tooLarge: return "The match exceeds the supported history size."
            case .unsupportedVersion: return "This match uses a different game version. Update the app to continue."
            }
        }
    }
}
