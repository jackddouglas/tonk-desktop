import WebKit
import XCTest

@testable import TonkTown

@MainActor
final class RuntimeInspectionTests: XCTestCase {
  func testSandboxedFramesAndControlState() async throws {
    let inspector = RuntimeInspection()
    let configuration = WKWebViewConfiguration()
    inspector.install(on: configuration.userContentController)
    let webView = WKWebView(
      frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
    webView.loadHTMLString(
      """
      <html><body><h1>Outer fixture</h1>
      <script>setTimeout(() => { throw new Error("outer failure"); }, 100);</script>
      <div hidden>HIDDEN_SENTINEL</div>
      <input type="password" value="PASSWORD_SENTINEL">
      <iframe sandbox="allow-scripts" srcdoc="<html><body><label><input type='checkbox' checked>Pack food</label><button>Save</button><script>setTimeout(() => { throw new Error('fixture failure'); }, 100);</script></body></html>"></iframe>
      </body></html>
      """, baseURL: URL(string: "https://staging.tonk.xyz"))
    var result: [String: Any] = [:]
    for _ in 0..<50 {
      result = try await inspector.snapshot(in: webView)
      let frames = result["frames"] as? [[String: Any]] ?? []
      if frames.count >= 2, String(describing: frames).contains("outer failure"),
        String(describing: frames).contains("Script error.")
      {
        break
      }
      try await Task.sleep(for: .milliseconds(100))
    }
    let frames = try XCTUnwrap(result["frames"] as? [[String: Any]])
    XCTAssertEqual(frames.count, 2)
    let encoded = String(
      decoding: try JSONSerialization.data(withJSONObject: result), as: UTF8.self)
    XCTAssertTrue(encoded.contains("Outer fixture"))
    XCTAssertTrue(encoded.contains("Pack food"))
    XCTAssertTrue(encoded.contains("outer failure"), encoded)
    XCTAssertTrue(encoded.contains("Script error."), encoded)
    XCTAssertFalse(encoded.contains("HIDDEN_SENTINEL"))
    XCTAssertFalse(encoded.contains("PASSWORD_SENTINEL"))
    let controls = frames.flatMap { $0["controls"] as? [[String: Any]] ?? [] }
    let checkbox = try XCTUnwrap(controls.first { $0["type"] as? String == "checkbox" })
    XCTAssertEqual(checkbox["checked"] as? Bool, true)
    inspector.reset()
    let cleared = try await inspector.snapshot(in: webView)
    XCTAssertEqual((cleared["frames"] as? [[String: Any]])?.count, 0)
  }
}
