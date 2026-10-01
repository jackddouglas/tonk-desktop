import Foundation
import HarnessCore

@MainActor
extension RuntimeModel {
  func performSpaceTool(space: TonkSpace, name: String?) async throws -> String {
    guard catalogLoaded, !catalogLoading, spaces.contains(where: { $0.id == space.id }),
      let branch = catalogBranch, !loading, !signInPending
    else {
      throw HarnessError.message(
        "The attached space is not ready or is no longer in this account. Refresh spaces and try again."
      )
    }
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
