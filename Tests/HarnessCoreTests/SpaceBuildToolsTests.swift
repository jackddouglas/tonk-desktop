import XCTest

@testable import HarnessCore

final class SpaceBuildToolsTests: XCTestCase {
  func testQueryCannotInjectNotationOrChangeTargetSpace() throws {
    XCTAssertEqual(
      try SpaceBuildTools.document(
        tool: "tonk_query", arguments: .object(["target": .string("packing-item")])),
      "packing-item:\n")
    for target in [
      "", "thing:\nother!:", "thing\n", "!include", "'thing'", String(repeating: "x", count: 201),
    ] {
      XCTAssertThrowsError(
        try SpaceBuildTools.document(
          tool: "tonk_query", arguments: .object(["target": .string(target)])))
    }
    XCTAssertThrowsError(
      try SpaceBuildTools.document(
        tool: "tonk_query",
        arguments: .object(["target": .string("thing"), "space": .string("elsewhere")])))
  }

  func testPreviewAllowsAssertionsButRejectsIncludesAndOverrides() throws {
    let document = "thing!:\n  this: id:test\n"
    XCTAssertEqual(
      try SpaceBuildTools.document(
        tool: "tonk_preview", arguments: .object(["document": .string(document)])), document)
    for source in ["  ", "!include /etc/passwd", "%TAG foo", String(repeating: "x", count: 32001)] {
      XCTAssertThrowsError(
        try SpaceBuildTools.document(
          tool: "tonk_preview", arguments: .object(["document": .string(source)])))
    }
    XCTAssertThrowsError(
      try SpaceBuildTools.document(
        tool: "tonk_preview",
        arguments: .object(["document": .string(document), "transact": .bool(true)])))
  }

  func testResultRequiresProofOfNoCommitAndPreservesStructuredMatches() throws {
    var envelope: [String: JSONValue] = [
      "revision_before": .string("r1"), "revision_after": .string("r1"),
      "commits": .object(["claims": .number(0)]),
      "matches_after": .array([.object(["label": .string("thing"), "results": .array([])])]),
    ]
    func result() throws -> JSONValue {
      try SpaceBuildTools.result(JSONEncoder().encode(JSONValue.object(envelope)))
    }
    let actual = try result()
    XCTAssertEqual(actual["revision"], .string("r1"))
    XCTAssertEqual(actual["matches"], envelope["matches_after"])
    XCTAssertEqual(actual["committed"], .bool(false))
    envelope["revision_after"] = .string("r2")
    XCTAssertThrowsError(try result())
    envelope["revision_after"] = .string("r1")
    envelope["commits"] = .object(["claims": .number(1)])
    XCTAssertThrowsError(try result())
    envelope["commits"] = .object(["claims": .number(0)])
    envelope.removeValue(forKey: "revision_before")
    XCTAssertThrowsError(try result())
  }
}
