import XCTest

@testable import HarnessCore

@MainActor
final class LocalRuntimeBridgeTests: XCTestCase {
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
