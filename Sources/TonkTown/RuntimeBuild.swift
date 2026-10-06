import Foundation
import HarnessCore

@MainActor
extension RuntimeModel {
  func performBuildTool(_ space: TonkSpace, tool: String, arguments: JSONValue) async throws
    -> JSONValue
  {
    if tool == "tonk_inspect_view" {
      _ = try SpaceTools.validate(tool: tool, arguments: arguments)
      let text = try await inspectView(space)
      return try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }
    guard tool == "tonk_apply" else {
      return try await evaluateReadOnly(space, tool: tool, arguments: arguments)
    }
    let document = try SpaceBuildTools.document(tool: tool, arguments: arguments)
    try requireSpaceReady(space)
    try Task.checkCancellation()
    let revision = String(
      decoding: try JSONEncoder().encode(arguments["expectedRevision"]), as: UTF8.self)
    let result: [String: Any]
    do {
      result = try await accountScript(
        Self.applyConditionalScript,
        arguments: [
          "subject": space.subject, "document": document, "expectedRevision": revision,
        ])
    } catch {
      // Once handed to WebKit, cancellation, timeout, navigation and lost replies
      // cannot prove the write did not happen. Never suggest replaying it.
      throw HarnessError.message(
        "The write outcome is unknown. Do not repeat it; query the space first.")
    }
    if let error = result["error"] as? String { throw HarnessError.message(error) }
    guard let response = result["response"] as? String else {
      throw HarnessError.message(
        "The write outcome is unknown. Do not repeat it; query the space first.")
    }
    // Do not turn post-commit cancellation/catalog changes into a retryable error.
    return try SpaceBuildTools.appliedResult(
      Data(response.utf8), expectedRevision: arguments["expectedRevision"])
  }

  static let applyConditionalScript = """
    const response = await fetch('/api/repository/' + encodeURIComponent(subject) + '/branch/main/evaluate/conditional', {
      method: 'POST', headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({document, expected_revision: JSON.parse(expectedRevision)}),
      signal: AbortSignal.timeout(60000)
    });
    if (response.status === 404 || response.status === 405)
      return {error: 'This worker does not support conditional writes. No fallback write was attempted.'};
    if (response.status === 412)
      return {error: 'The space changed since preview. Nothing was applied by this request. Read and preview again.'};
    if (response.status === 403)
      return {error: 'The worker denied this conditional build. Only authorized durable changes are supported; transient commands are unavailable.'};
    const text = await response.text();
    if (response.status === 400 || response.status === 422)
      return {error: 'The worker rejected the write: ' + text.slice(0, 2000) + '. Query the space before retrying.'};
    if (!response.ok || !(response.headers.get('content-type') || '').includes('json') || text.length > 2000000)
      return {error: 'The write outcome is unknown. Do not repeat it; query the space first.'};
    return {response: text};
    """

  func evaluateReadOnly(_ space: TonkSpace, tool: String, arguments: JSONValue) async throws
    -> JSONValue
  {
    let document = try SpaceBuildTools.document(tool: tool, arguments: arguments)
    try requireSpaceReady(space)
    try Task.checkCancellation()
    let result = try await accountScript(
      Self.evaluateReadOnlyScript,
      arguments: [
        "subject": space.subject, "document": document,
      ])
    try Task.checkCancellation()
    try requireSpaceReady(space)
    guard let response = result["response"] as? String else {
      throw HarnessError.message("The worker returned no evaluation response.")
    }
    return try SpaceBuildTools.result(Data(response.utf8))
  }

  static let evaluateReadOnlyScript = """
    const info = await api('/api/repository/' + encodeURIComponent(subject));
    if (info.subject !== subject || !Object.hasOwn(info.branch || {}, 'main'))
      throw new Error('The attached space has no available main branch.');
    const response = await fetch('/api/repository/' + encodeURIComponent(subject) + '/branch/main/evaluate?transact=false', {
      method: 'POST', headers: {'Content-Type': 'text/plain'}, body: document,
      signal: AbortSignal.timeout(60000)
    });
    if (!(response.headers.get('content-type') || '').includes('json'))
      throw new Error('The runtime does not support direct evaluation.');
    const text = await response.text();
    if (text.length > 2000000) throw new Error('The evaluation response is too large.');
    if (!response.ok) throw new Error('Evaluation failed (HTTP ' + response.status + '): ' + text.slice(0, 2000));
    return {response: text};
    """
}
