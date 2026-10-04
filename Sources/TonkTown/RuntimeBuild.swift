import Foundation
import HarnessCore

@MainActor
extension RuntimeModel {
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
