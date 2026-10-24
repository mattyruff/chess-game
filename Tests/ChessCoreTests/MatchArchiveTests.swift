import XCTest
@testable import ChessCore

final class MatchArchiveTests: XCTestCase {
    private func data(_ moves: [String], version: Int = 1) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["version": version, "moves": moves])
    }

    func testRoundTripPreservesEnPassantAndMoveHistory() throws {
        let archive = try MatchArchive(data: data(["e2e4", "a7a6", "e4e5", "d7d5"]))
        let restored = try MatchArchive(data: archive.encoded())
        XCTAssertEqual(archive.moves, restored.moves)
        XCTAssertEqual(archive.position.fen, restored.position.fen)
        XCTAssertTrue(restored.position.legalMoves().contains(Move(from: Square(notation: "e5")!, to: Square(notation: "d6")!)))
    }

    func testReplayPreservesRepetitionDraw() throws {
        let cycle = ["g1f3", "g8f6", "f3g1", "f6g8"]
        let restored = try MatchArchive(data: data(cycle + cycle))
        XCTAssertEqual(restored.position.outcome, .draw(reason: "Threefold repetition"))
        XCTAssertThrowsError(try MatchArchive(data: data(cycle + cycle + ["e2e4"])))
    }

    func testRejectsCorruptedIllegalAndUnknownVersionPayloads() throws {
        for moves in [["e2e5"], ["e7e5"], ["e2e4k"], ["x1e4"], ["e2e4", "e2e3"], ["💥"]] {
            XCTAssertThrowsError(try MatchArchive(data: data(moves)))
        }
        XCTAssertThrowsError(try MatchArchive(data: data([], version: 2)))
        XCTAssertThrowsError(try MatchArchive(data: Data("not json".utf8)))
        XCTAssertThrowsError(try MatchArchive(data: Data(repeating: 0, count: MatchArchive.maximumBytes + 1)))
    }

    func testEmptyNewMatchStartsAtInitialPosition() throws {
        XCTAssertEqual(try MatchArchive(data: nil).position.fen, Position().fen)
        XCTAssertEqual(try MatchArchive(data: Data()).position.legalMoves().count, 20)
    }
}
