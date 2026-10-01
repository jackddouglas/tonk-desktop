import Foundation
import XCTest

@testable import HarnessCore

final class SpaceToolsTests: XCTestCase {
  func testRejectsTargetOverridesAndInvalidWrites() throws {
    XCTAssertNil(try SpaceTools.validate(tool: "tonk_space_info", arguments: .object([:])))
    XCTAssertEqual(
      try SpaceTools.validate(
        tool: "tonk_rename_space", arguments: .object(["name": .string("  Scratch  ")])), "Scratch")
    for name in ["", "   ", "a\nb", String(repeating: "x", count: 121)] {
      XCTAssertThrowsError(
        try SpaceTools.validate(
          tool: "tonk_rename_space", arguments: .object(["name": .string(name)])))
    }
    for tool in ["tonk_space_info", "tonk_rename_space"] {
      XCTAssertThrowsError(
        try SpaceTools.validate(
          tool: tool, arguments: .object(["name": .string("ok"), "space": .string("other-space")])))
    }
    XCTAssertThrowsError(try SpaceTools.validate(tool: "shell", arguments: .object([:])))
  }

  @MainActor
  func testReadbackWaitsForEffectsAndStopsWithoutResubmitting() async throws {
    var reads = 0
    let verified = try await SpaceTools.waitForName(
      "New",
      read: {
        reads += 1
        return reads < 3 ? "Old" : "New"
      }, pause: {})
    XCTAssertTrue(verified)
    XCTAssertEqual(reads, 3)
    reads = 0
    let missing = try await SpaceTools.waitForName(
      "New",
      read: {
        reads += 1
        return "Old"
      }, pause: {})
    XCTAssertFalse(missing)
    XCTAssertEqual(reads, 10)
    do {
      _ = try await SpaceTools.waitForName(
        "New", read: { "Old" }, pause: { throw CancellationError() })
      XCTFail("Cancellation must stop verification")
    } catch { XCTAssertTrue(error is CancellationError) }
  }

  func testAttachmentPersistsAndOldConversationsRemainReadable() throws {
    let space = try XCTUnwrap(
      TonkSpace.decodeCatalog(Data("[{\"subject\":\"did:key:z123\",\"name\":\"Scratch\"}]".utf8))
        .first)
    var conversation = Conversation()
    conversation.space = space
    XCTAssertEqual(
      try JSONDecoder().decode(Conversation.self, from: JSONEncoder().encode(conversation)).space,
      space)
    XCTAssertNil(
      try JSONDecoder().decode(Conversation.self, from: Data("{\"messages\":[]}".utf8)).space)
  }
}
