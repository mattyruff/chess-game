import XCTest
@testable import ChessCore

final class PositionTests: XCTestCase {
    private func square(_ notation: String) -> Square { Square(notation: notation)! }

    private func move(_ from: String, _ to: String, promotion: PieceKind? = nil) -> Move {
        Move(from: square(from), to: square(to), promotion: promotion)
    }

    private func perft(_ position: Position, depth: Int) -> Int {
        if depth == 0 { return 1 }
        let moves = position.legalMoves()
        if depth == 1 { return moves.count }
        return moves.reduce(0) { total, move in total + perft(position.applyingUnchecked(move), depth: depth - 1) }
    }

    func testInitialPositionAndFENRoundTrip() throws {
        let position = Position()
        XCTAssertEqual(position.fen, "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
        XCTAssertEqual(position.piece(at: square("e1")), Piece(side: .white, kind: .king))
        XCTAssertEqual(position.piece(at: square("d8")), Piece(side: .black, kind: .queen))
        XCTAssertEqual(position.legalMoves().count, 20)
        XCTAssertEqual(position.outcome, .ongoing)
        XCTAssertEqual(try Position(fen: position.fen).fen, position.fen)
        XCTAssertNil(position.piece(at: Square(file: -1, rank: 0)))
        XCTAssertNil(Square(notation: "i1"))
        XCTAssertNil(Square(notation: "e10"))
    }

    func testInitialPositionPerft() {
        let position = Position()
        XCTAssertEqual(perft(position, depth: 2), 400)
        XCTAssertEqual(perft(position, depth: 3), 8_902)
        XCTAssertEqual(perft(position, depth: 4), 197_281)
    }

    func testKiwipetePerftCoversCastlingAndPins() throws {
        let position = try Position(fen: "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1")
        XCTAssertEqual(perft(position, depth: 1), 48)
        XCTAssertEqual(perft(position, depth: 2), 2_039)
        XCTAssertEqual(perft(position, depth: 3), 97_862)
    }

    func testEndgamePerftCoversEnPassantAndChecks() throws {
        let position = try Position(fen: "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1")
        XCTAssertEqual(perft(position, depth: 1), 14)
        XCTAssertEqual(perft(position, depth: 2), 191)
        XCTAssertEqual(perft(position, depth: 3), 2_812)
    }

    func testIllegalMovesDoNotChangePosition() {
        var position = Position()
        let before = position.fen
        XCTAssertFalse(position.play(move("e2", "e5")))
        XCTAssertFalse(position.play(move("e7", "e5")))
        XCTAssertFalse(position.play(Move(from: Square(file: -1, rank: 0), to: square("e4"))))
        XCTAssertEqual(position.fen, before)
        XCTAssertTrue(position.play(move("e2", "e4")))
        XCTAssertEqual(position.sideToMove, .black)
        XCTAssertEqual(position.enPassantTarget, square("e3"))
    }

    func testCastlingMovesKingAndRook() throws {
        var position = try Position(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
        XCTAssertTrue(position.legalMoves().contains(move("e1", "g1")))
        XCTAssertTrue(position.legalMoves().contains(move("e1", "c1")))
        XCTAssertTrue(position.play(move("e1", "g1")))
        XCTAssertEqual(position.piece(at: square("g1")), Piece(side: .white, kind: .king))
        XCTAssertEqual(position.piece(at: square("f1")), Piece(side: .white, kind: .rook))
        XCTAssertNil(position.piece(at: square("h1")))
        XCTAssertNil(position.piece(at: square("e1")))
        XCTAssertEqual(position.fen.split(separator: " ")[2], "kq")
        XCTAssertTrue(position.play(move("e8", "c8")))
        XCTAssertEqual(position.piece(at: square("d8")), Piece(side: .black, kind: .rook))
    }

    func testCannotCastleThroughCheckOrWithoutRook() throws {
        let attacked = try Position(fen: "4kr2/8/8/8/8/8/8/R3K2R w KQ - 0 1")
        XCTAssertFalse(attacked.legalMoves().contains(move("e1", "g1")))
        XCTAssertTrue(attacked.legalMoves().contains(move("e1", "c1")))
        let checked = try Position(fen: "4r1k1/8/8/8/8/8/8/R3K2R w KQ - 0 1")
        XCTAssertFalse(checked.legalMoves().contains(move("e1", "g1")))
        XCTAssertFalse(checked.legalMoves().contains(move("e1", "c1")))
        let missingRook = try Position(fen: "4k3/8/8/8/8/8/8/4K3 w KQ - 0 1")
        XCTAssertFalse(missingRook.legalMoves().contains(move("e1", "g1")))
        XCTAssertFalse(missingRook.legalMoves().contains(move("e1", "c1")))
    }

    func testRookReturningHomeDoesNotRestoreCastling() throws {
        var position = try Position(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
        for move in [move("h1", "h2"), move("h8", "h7"), move("h2", "h1"), move("h7", "h8")] {
            XCTAssertTrue(position.play(move))
        }
        XCTAssertFalse(position.legalMoves().contains(move("e1", "g1")))
        XCTAssertEqual(position.fen.split(separator: " ")[2], "Qq")
    }

    func testEnPassantCapturesAndExpires() throws {
        var position = try Position(fen: "4k3/3p4/8/4P3/8/8/8/4K3 b - - 0 1")
        XCTAssertTrue(position.play(move("d7", "d5")))
        XCTAssertTrue(position.legalMoves().contains(move("e5", "d6")))
        var expired = position
        XCTAssertTrue(expired.play(move("e1", "f1")))
        XCTAssertNil(expired.enPassantTarget)
        XCTAssertTrue(position.play(move("e5", "d6")))
        XCTAssertNil(position.piece(at: square("d5")))
        XCTAssertEqual(position.piece(at: square("d6")), Piece(side: .white, kind: .pawn))
        XCTAssertEqual(position.halfmoveClock, 0)
    }

    func testEnPassantCannotExposeOwnKing() throws {
        let position = try Position(fen: "7k/8/8/r4pPK/8/8/8/8 w - f6 0 1")
        XCTAssertFalse(position.legalMoves().contains(move("g5", "f6")))
    }

    func testPromotionRequiresAChoiceAndSupportsUnderpromotion() throws {
        let initial = try Position(fen: "7k/P7/8/8/8/8/8/7K w - - 0 1")
        XCTAssertEqual(initial.legalMoves().filter({ $0.from == square("a7") }).count, 4)
        for kind in [PieceKind.queen, .rook, .bishop, .knight] {
            var position = initial
            XCTAssertTrue(position.play(move("a7", "a8", promotion: kind)))
            XCTAssertEqual(position.piece(at: square("a8")), Piece(side: .white, kind: kind))
        }
        var position = initial
        XCTAssertFalse(position.play(move("a7", "a8")))
        XCTAssertFalse(position.play(move("a7", "a8", promotion: .king)))
        XCTAssertEqual(position.fen, initial.fen)
    }

    func testPinnedPieceCannotExposeKing() throws {
        let position = try Position(fen: "4r1k1/8/8/8/8/8/4R3/4K3 w - - 0 1")
        XCTAssertFalse(position.legalMoves().contains(move("e2", "d2")))
        XCTAssertTrue(position.legalMoves().contains(move("e2", "e8")))
    }

    func testFoolsMate() {
        var position = Position()
        for move in [move("f2", "f3"), move("e7", "e5"), move("g2", "g4"), move("d8", "h4")] {
            XCTAssertTrue(position.play(move))
        }
        XCTAssertTrue(position.isInCheck(.white))
        XCTAssertEqual(position.outcome, .checkmate(winner: .black))
        XCTAssertTrue(position.legalMoves().isEmpty)
        XCTAssertFalse(position.play(move("a2", "a3")))
    }

    func testStalemateAndCheckmateTakePriorityOverMoveClock() throws {
        let stalemate = try Position(fen: "7k/5K2/6Q1/8/8/8/8/8 b - - 100 1")
        XCTAssertFalse(stalemate.isInCheck(.black))
        XCTAssertEqual(stalemate.outcome, .stalemate)
        let mate = try Position(fen: "7k/6Q1/5K2/8/8/8/8/8 b - - 100 1")
        XCTAssertEqual(mate.outcome, .checkmate(winner: .white))
    }

    func testThreefoldRepetition() {
        var position = Position()
        let cycle = [move("g1", "f3"), move("g8", "f6"), move("f3", "g1"), move("f6", "g8")]
        for move in cycle { XCTAssertTrue(position.play(move)) }
        XCTAssertEqual(position.outcome, .ongoing)
        for move in cycle { XCTAssertTrue(position.play(move)) }
        XCTAssertEqual(position.outcome, .draw(reason: "Threefold repetition"))
        XCTAssertFalse(position.play(move("e2", "e4")))
    }

    func testRepetitionIgnoresUnusableEnPassantTarget() throws {
        var position = try Position(fen: "4k1n1/8/8/8/4P3/8/8/4K1N1 b - e3 0 1")
        let cycle = [move("g8", "f6"), move("g1", "f3"), move("f6", "g8"), move("f3", "g1")]
        for _ in 0..<2 { for move in cycle { XCTAssertTrue(position.play(move)) } }
        XCTAssertEqual(position.outcome, .draw(reason: "Threefold repetition"))
    }

    func testFiftyMoveRuleAndPawnReset() throws {
        var position = try Position(fen: "4k3/8/8/8/8/8/P7/R3K3 w - - 99 1")
        var reset = position
        XCTAssertTrue(position.play(move("a1", "b1")))
        XCTAssertEqual(position.outcome, .draw(reason: "Fifty-move rule"))
        XCTAssertTrue(reset.play(move("a2", "a3")))
        XCTAssertEqual(reset.halfmoveClock, 0)
        XCTAssertEqual(reset.outcome, .ongoing)
    }

    func testInsufficientMaterialIsConservative() throws {
        for fen in [
            "4k3/8/8/8/8/8/8/4K3 w - - 0 1",
            "4k3/8/8/8/8/8/8/2B1K3 w - - 0 1",
            "4k3/8/8/8/8/8/8/1N2K3 w - - 0 1",
            "4kb2/8/8/8/8/8/8/2B1K3 w - - 0 1"
        ] {
            XCTAssertEqual(try Position(fen: fen).outcome, .draw(reason: "Insufficient material"))
        }
        for fen in [
            "4k3/8/8/8/8/8/8/1NN1K3 w - - 0 1",
            "2b1k3/8/8/8/8/8/8/2B1K3 w - - 0 1",
            "4k3/8/8/8/8/8/P7/4K3 w - - 0 1"
        ] {
            XCTAssertEqual(try Position(fen: fen).outcome, .ongoing)
        }
    }

    func testMalformedFENIsRejected() {
        for fen in [
            "garbage", "8/8/8/8/8/8/8/8 w - - 0 1",
            "4k3/8/8/8/8/8/8/4K3 x - - 0 1",
            "4k3/8/8/8/8/8/8/4K3 w KK - 0 1",
            "4k3/8/8/8/8/8/8/4K3 w - a3 0 1",
            "4k3/8/8/8/8/8/8/4K3 w - - -1 1",
            "4k3/8/8/8/8/8/8/4K3 w - - 0 0"
        ] { XCTAssertThrowsError(try Position(fen: fen)) }
    }
}
