import XCTest
@testable import ChessCore

final class AITests: XCTestCase {
    func testEveryDifficultyReturnsLegalMoveWithoutChangingPosition() {
        let position = Position()
        let originalFEN = position.fen
        let legal = position.legalMoves()
        for difficulty in Difficulty.allCases {
            guard let move = ChessAI.bestMove(in: position, difficulty: difficulty) else {
                return XCTFail("\(difficulty) did not return an opening move")
            }
            XCTAssertTrue(legal.contains(move), "\(difficulty) returned an illegal move")
            XCTAssertEqual(position.fen, originalFEN)
        }
    }

    func testEveryDifficultyFindsFoolsMate() throws {
        let position = try Position(fen: "rnbqkbnr/pppp1ppp/8/4p3/6P1/5P2/PPPPP2P/RNBQKBNR b KQkq g3 0 2")
        for difficulty in Difficulty.allCases {
            let move = try XCTUnwrap(ChessAI.bestMove(in: position, difficulty: difficulty))
            XCTAssertEqual(move.coordinateNotation, "d8h4", "\(difficulty) missed mate in one")
            var next = position
            XCTAssertTrue(next.play(move))
            XCTAssertEqual(next.outcome, .checkmate(winner: .black))
        }
    }

    func testIntermediateCapturesAnUndefendedQueen() throws {
        let position = try Position(fen: "4k3/8/8/8/3q4/8/3R4/4K3 w - - 0 1")
        let move = try XCTUnwrap(ChessAI.bestMove(in: position, difficulty: .intermediate))
        XCTAssertEqual(move.coordinateNotation, "d2d4")
    }

    func testComputerSelectsQueenPromotion() throws {
        let position = try Position(fen: "7k/P7/8/8/8/8/8/7K w - - 0 1")
        let move = try XCTUnwrap(ChessAI.bestMove(in: position, difficulty: .intermediate))
        XCTAssertEqual(move.coordinateNotation, "a7a8q")
    }

    func testComputerStopsAfterMateOrDraw() throws {
        let mate = try Position(fen: "rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3")
        let draw = try Position(fen: "4k3/8/8/8/8/8/8/4K3 w - - 0 1")
        for difficulty in Difficulty.allCases {
            XCTAssertNil(ChessAI.bestMove(in: mate, difficulty: difficulty))
            XCTAssertNil(ChessAI.bestMove(in: draw, difficulty: difficulty))
        }
    }
}
