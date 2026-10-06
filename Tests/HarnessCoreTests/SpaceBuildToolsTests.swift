import XCTest

@testable import HarnessCore

final class SpaceBuildToolsTests: XCTestCase {
  func testProjectedExactEntityQueryAvoidsOversizeAndReturnsCompleteCount() throws {
    let rows: [JSONValue] = (0..<20).map { index in
      .object([
        "this": .string("id:issue-\(index)"),
        "fields": .object([
          "title": .string("Issue \(index)"),
          "assignee": .string(index < 7 ? "id:jack" : "id:someone-else"),
          "body": .string(String(repeating: "x", count: 8000)), "active": .bool(true),
        ]),
      ])
    }
    let data = try JSONEncoder().encode(
      JSONValue.object([
        "revision_before": .null, "revision_after": .null,
        "commits": .object(["claims": .number(0)]),
        "matches_after": .array([.object(["label": .string("issue"), "results": .array(rows)])]),
      ]))
    XCTAssertThrowsError(try SpaceBuildTools.result(data))
    let query: JSONValue = .object([
      "target": .string("issue"), "fields": .array([.string("title")]),
      "equals": .object(["assignee": .string("id:jack"), "active": .bool(true)]),
    ])
    XCTAssertEqual(try SpaceBuildTools.document(tool: "tonk_query", arguments: query), "issue:\n")
    let result = try SpaceBuildTools.result(data, query: query)["matches"].array[0]
    XCTAssertEqual(result["totalMatches"].int, 7)
    XCTAssertEqual(result["results"].array.count, 7)
    XCTAssertEqual(result["results"].array[0]["this"].string, "id:issue-0")
    XCTAssertEqual(result["results"].array[0]["fields"], .object(["title": .string("Issue 0")]))
    let noMatch: JSONValue = .object([
      "target": .string("issue"), "equals": .object(["assignee": .string("jack")]),
    ])
    XCTAssertEqual(
      try SpaceBuildTools.result(data, query: noMatch)["matches"].array[0]["totalMatches"].int, 0)
  }

  func testStructuredQueryRejectsMalformedArguments() throws {
    for extra: [String: JSONValue] in [
      ["fields": .string("title")], ["fields": .array([.number(1)])],
      ["equals": .array([])], ["space": .string("other")],
    ] {
      var fields = extra
      fields["target"] = .string("issue")
      XCTAssertThrowsError(
        try SpaceBuildTools.document(tool: "tonk_query", arguments: .object(fields)))
    }
  }

  func testApplyRequiresRevisionAndReportsUncertainResponsesWithoutRetryAdvice() throws {
    let document = "thing!:\n  this: id:test\n"
    for revision: JSONValue in [.null, .object(["tree": .string("test")])] {
      XCTAssertEqual(
        try SpaceBuildTools.document(
          tool: "tonk_apply",
          arguments: .object([
            "document": .string(document), "expectedRevision": revision,
          ])), document)
    }
    for arguments: JSONValue in [
      .object(["document": .string(document)]),
      .object(["document": .string(document), "expectedRevision": .string("any")]),
      .object(["document": .string(document), "expectedRevision": .null, "space": .string("other")]
      ),
    ] {
      XCTAssertThrowsError(try SpaceBuildTools.document(tool: "tonk_apply", arguments: arguments))
    }
    let before: JSONValue = .object(["tree": .string("before")])
    let after: JSONValue = .object(["tree": .string("after")])
    let data = try JSONEncoder().encode(
      JSONValue.object([
        "revision_before": before, "revision_after": after,
        "commits": .object(["claims": .number(1)]),
      ]))
    let result = try SpaceBuildTools.appliedResult(data, expectedRevision: before)
    XCTAssertEqual(result["revision"], after)
    XCTAssertEqual(result["revisionChanged"], .bool(true))
    XCTAssertEqual(result["renderingConfirmed"], .bool(false))
    XCTAssertThrowsError(try SpaceBuildTools.appliedResult(data, expectedRevision: .null)) {
      error in
      XCTAssertTrue(error.localizedDescription.contains("Do not repeat"))
    }
    XCTAssertThrowsError(
      try SpaceBuildTools.appliedResult(Data("{}".utf8), expectedRevision: before))
  }
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
