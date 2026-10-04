import XCTest

@testable import HarnessCore

@MainActor
final class LocalRuntimeBridgeTests: XCTestCase {
  func testWriteCapabilityMustBeEnabledAndPassesExactRevision() async throws {
    let expected: JSONValue = .object(["tree": .string("preview")])
    let arguments: JSONValue = .object([
      "document": .string("thing!:"), "expectedRevision": expected,
    ])
    var calls = 0
    for enabled in [false, true] {
      let bridge = LocalRuntimeBridge(allowsWrites: enabled) { name, received in
        calls += 1
        XCTAssertEqual(name, "tonk_apply")
        XCTAssertEqual(received, arguments)
        return .object(["accepted": .bool(true)])
      }
      let config = try await bridge.start()
      var request = URLRequest(url: URL(string: config["url"].string! + "/call")!)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue("Bearer " + config["token"].string!, forHTTPHeaderField: "Authorization")
      request.httpBody = try JSONEncoder().encode(
        JSONValue.object(["name": .string("tonk_apply"), "arguments": arguments]))
      let (data, _) = try await URLSession.shared.data(for: request)
      let value = try JSONDecoder().decode(JSONValue.self, from: data)
      if enabled {
        XCTAssertEqual(value["result"]["accepted"], .bool(true))
      } else {
        XCTAssertEqual(value["error"], .string("This runtime connection is read-only."))
      }
      bridge.stop()
    }
    XCTAssertEqual(calls, 1)
  }
  func testAuthenticatedReadOnlyBridgeRejectsBrowserAndTargetOverrides() async throws {
    var calls = 0
    let bridge = LocalRuntimeBridge { name, arguments in
      calls += 1
      XCTAssertEqual(name, "tonk_query")
      XCTAssertEqual(arguments["target"], .string("thing"))
      return .object(["revision": .string("r1"), "committed": .bool(false)])
    }
    let config = try await bridge.start()
    defer { bridge.stop() }
    let base = try XCTUnwrap(config["url"].string)
    let token = try XCTUnwrap(config["token"].string)
    func request(
      _ path: String, body: JSONValue = .object([:]), authorized: Bool = true, origin: Bool = false
    ) async throws -> (Int, JSONValue) {
      var request = URLRequest(url: URL(string: base + path)!)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      if authorized { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
      if origin { request.setValue("https://example.com", forHTTPHeaderField: "Origin") }
      request.httpBody = try JSONEncoder().encode(body)
      let (data, response) = try await URLSession.shared.data(for: request)
      return (
        (response as! HTTPURLResponse).statusCode,
        try JSONDecoder().decode(JSONValue.self, from: data)
      )
    }
    let denied = try await request("/tools", authorized: false)
    XCTAssertEqual(denied.0, 403)
    let browser = try await request("/tools", origin: true)
    XCTAssertEqual(browser.0, 403)
    let listed = try await request("/tools")
    XCTAssertEqual(listed.1["tools"], .array(SpaceBuildTools.definitions))
    let queried = try await request(
      "/call",
      body: .object([
        "name": .string("tonk_query"), "arguments": .object(["target": .string("thing")]),
      ]))
    XCTAssertEqual(queried.1["result"]["revision"], .string("r1"))
    for arguments: JSONValue in [
      .object(["target": .string("thing"), "space": .string("other")]),
      .object(["document": .string("thing!:"), "transact": .bool(true)]),
    ] {
      let rejected = try await request(
        "/call",
        body: .object([
          "name": .string("tonk_query"), "arguments": arguments,
        ]))
      XCTAssertNotNil(rejected.1["error"].string)
    }
    let write = try await request(
      "/call",
      body: .object([
        "name": .string("tonk_apply"), "arguments": .object([:]),
      ]))
    XCTAssertNotNil(write.1["error"].string)
    XCTAssertEqual(calls, 1)
  }
}
