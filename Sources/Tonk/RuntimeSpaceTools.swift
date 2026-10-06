import Foundation
import HarnessCore

@MainActor
extension RuntimeModel {
  func requireSpaceReady(_ space: TonkSpace) throws {
    guard catalogLoaded, !catalogLoading, spaces.contains(where: { $0.id == space.id }),
      catalogBranch != nil, !loading, !signInPending
    else {
      throw HarnessError.message(
        "The attached space is not ready or is no longer in this account. Refresh spaces and try again."
      )
    }
  }

  func performSpaceTool(space: TonkSpace, name: String?) async throws -> String {
    try requireSpaceReady(space)
    let branch = catalogBranch!
    let key = space.subject
    try Task.checkCancellation()
    let arguments: [String: Any] = ["key": key, "subject": space.subject, "branch": branch]
    let read = """
      const info = await api('/api/repository/' + encodeURIComponent(key));
      if (info.subject !== subject)
        throw new Error('The worker returned an unexpected space response (fields: ' + Object.keys(info).join(', ') + ').');
      return {subject: info.subject, name: info.label, branches: Object.keys(info.branch || {})};
      """
    var result = try await accountScript(read, arguments: arguments)
    if let name {
      try Task.checkCancellation()
      var writeArguments = arguments
      writeArguments["newName"] = name
      _ = try await accountScript(
        """
        await api('/api/profile/branch/' + encodeURIComponent(branch) + '/transact', {
          claims: [{op: 'assert', application: {
            predicate: {kind: 'transient', concept: {with: {
              name: {the: 'xyz.tonk.command.rename-repository/name', as: 'Text'},
              space: {the: 'xyz.tonk.rename-repository/space', as: 'Entity'}
            }}},
            parameters: {this: 'urn:uuid:' + crypto.randomUUID(), name: newName, space: subject}
          }}]
        });
        return {submitted: true};
        """, arguments: writeArguments)
      // Command effects settle after the transaction response. Read until the
      // requested value appears, but never repeat the write to chase an ack.
      let verified = try await SpaceTools.waitForName(name) {
        result = try await accountScript(read, arguments: arguments)
        return result["name"] as? String
      }
      guard verified else {
        throw HarnessError.message(
          "Rename was submitted, but the requested name was not confirmed. Read the space before retrying."
        )
      }
    }
    if name != nil || result["name"] as? String != spaces.first(where: { $0.id == space.id })?.title
    {
      await refreshSpaces()
    }
    let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    return String(decoding: data, as: UTF8.self)
  }
}

@MainActor
extension RuntimeModel {
  func readSpaceSchema(_ space: TonkSpace) async throws -> String {
    try requireSpaceReady(space)
    try Task.checkCancellation()
    let result = try await accountScript(
      """
      const path = '/api/repository/' + encodeURIComponent(subject) + '/branch/main/evaluate?transact=false';
      const info = await api('/api/repository/' + encodeURIComponent(subject));
      if (info.subject !== subject || !Object.hasOwn(info.branch || {}, 'main'))
        throw new Error('The attached space has no available main branch.');
      const response = await fetch(path, {
        method: 'POST', headers: {'Content-Type': 'text/plain'}, body: document,
        signal: AbortSignal.timeout(60000)
      });
      if (!response.ok) throw new Error('Schema inspection failed (HTTP ' + response.status + ').');
      if (!(response.headers.get('content-type') || '').includes('json'))
        throw new Error('The runtime does not support schema inspection.');
      const text = await response.text();
      if (text.length > 2000000) throw new Error('The space schema response is too large.');
      return {response: text};
      """, arguments: ["subject": space.subject, "document": SpaceSchema.query])
    try Task.checkCancellation()
    guard let text = result["response"] as? String else {
      throw HarnessError.message("The worker returned no schema response.")
    }
    return try SpaceSchema.summarize(Data(text.utf8))
  }
}
