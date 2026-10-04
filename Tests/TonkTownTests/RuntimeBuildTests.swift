import WebKit
import XCTest

@testable import TonkTown

@MainActor
final class RuntimeBuildTests: XCTestCase {
  func testConditionalWriteNeverFallsBackOrRetriesAndClassifiesConflicts() async throws {
    let webView = WKWebView()
    webView.loadHTMLString("<input id='draft' value='keep'>", baseURL: nil)
    for _ in 0..<100 {
      if !webView.isLoading { break }
      try await Task.sleep(for: .milliseconds(20))
    }
    let script = """
      let requests = [];
      async function fetch(path, options) {
        requests.push({path, body: JSON.parse(options.body)});
        return {status, ok: status === 200, headers: {get: () => 'application/json'}, text: async () => '{}'};
      }
      async function apply() { \(RuntimeModel.applyConditionalScript) }
      const result = await apply();
      return {requests, result, draft: window.document.getElementById('draft').value};
      """
    for status in [200, 400, 403, 404, 412, 500] {
      let result =
        try await webView.callAsyncJavaScript(
          script,
          arguments: [
            "subject": "did:key:z123", "document": "thing!:",
            "expectedRevision": "null", "status": status,
          ], in: nil, contentWorld: .page) as! [String: Any]
      let requests = result["requests"] as! [[String: Any]]
      XCTAssertEqual(requests.count, 1)
      XCTAssertEqual(
        requests[0]["path"] as? String,
        "/api/repository/did%3Akey%3Az123/branch/main/evaluate/conditional")
      let body = requests[0]["body"] as! [String: Any]
      XCTAssertTrue(body["expected_revision"] is NSNull)
      XCTAssertEqual(body["document"] as? String, "thing!:")
      XCTAssertEqual(result["draft"] as? String, "keep")
      let outcome = result["result"] as! [String: Any]
      if status == 200 { XCTAssertEqual(outcome["response"] as? String, "{}") }
      if status == 404 {
        XCTAssertTrue((outcome["error"] as? String)?.contains("No fallback") == true)
      }
      if status == 403 {
        XCTAssertTrue((outcome["error"] as? String)?.contains("denied") == true)
      }
      if status == 412 {
        XCTAssertTrue((outcome["error"] as? String)?.contains("Nothing was applied") == true)
      }
      if status == 500 {
        XCTAssertTrue((outcome["error"] as? String)?.contains("Do not repeat") == true)
      }
    }
  }
  func testEvaluationUsesOnlyLocalDryRunAndKeepsPreviewIntact() async throws {
    let webView = WKWebView()
    webView.loadHTMLString("<input id='draft' value='keep this'>", baseURL: nil)
    for _ in 0..<100 {
      if !webView.isLoading { break }
      try await Task.sleep(for: .milliseconds(20))
    }
    let script = """
      const original = window.document.getElementById('draft');
      original.focus();
      let requests = [];
      async function api(path) {
        requests.push(path);
        return {subject: matches ? subject : 'wrong', branch: {main: {}}};
      }
      async function fetch(path, options) {
        requests.push(path);
        if (options.method !== 'POST' || options.headers['Content-Type'] !== 'text/plain' || options.body !== document)
          throw new Error('Unexpected request');
        return {ok: true, headers: {get: () => 'application/json'}, text: async () => '{"ok":true}'};
      }
      async function evaluate() { \(RuntimeModel.evaluateReadOnlyScript) }
      let rejected = false;
      try { await evaluate(); } catch { rejected = true; }
      return {requests, rejected, sameNode: original === window.document.getElementById('draft'),
        focused: window.document.activeElement === original, value: original.value};
      """
    for matches in [true, false] {
      let result =
        try await webView.callAsyncJavaScript(
          script,
          arguments: [
            "subject": "did:key:z123", "document": "thing!:\n  this: id:test", "matches": matches,
          ], in: nil, contentWorld: .page) as! [String: Any]
      let requests = result["requests"] as! [String]
      XCTAssertEqual(requests.count, matches ? 2 : 1)
      if matches {
        XCTAssertEqual(
          requests.last, "/api/repository/did%3Akey%3Az123/branch/main/evaluate?transact=false")
      }
      XCTAssertEqual(result["rejected"] as? Bool, !matches)
      XCTAssertEqual(result["sameNode"] as? Bool, true)
      XCTAssertEqual(result["focused"] as? Bool, true)
      XCTAssertEqual(result["value"] as? String, "keep this")
    }
  }
}
