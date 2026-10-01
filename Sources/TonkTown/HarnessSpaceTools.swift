import Foundation
import HarnessCore

@MainActor
extension HarnessModel {
  var spaceInstructions: String {
    guard let space = saved.conversation.space else { return "\nNo Tonk space is attached." }
    return """

      Attached Tonk space: \(space.subject).
      Use tonk_space_info to get its current name. You may inspect this space and
      rename it when asked, using the provided tools. When available, use
      tonk_space_schema for concept names and typed fields on main. Schema presence
      does not prove records exist; truncation is not a complete inventory. No other mutations are
      supported yet. You cannot choose another target or access other spaces.
      """
  }

  func attachSpace(_ space: TonkSpace) {
    guard !busy else { return }
    newConversation()
    // newConversation preserves the old conversation if archival fails.
    guard saved.conversation.threadID == nil, saved.conversation.messages.isEmpty else { return }
    saved.conversation.space = space
    persist()
  }

  func callSpaceTool(_ params: JSONValue) async -> JSONValue {
    do {
      guard busy, params["threadId"].string == saved.conversation.threadID,
        let requestTurn = params["turnId"].string, requestTurn == activeTurnID,
        params["namespace"] == .null,
        let space = saved.conversation.space, let runtime,
        let tool = params["tool"].string
      else { throw HarnessError.message("No matching active turn with an attached space.") }
      let name = try SpaceTools.validate(tool: tool, arguments: params["arguments"])
      try Task.checkCancellation()
      let isSchema = tool == "tonk_space_schema"
      activity = isSchema ? "Reading schema" : (name == nil ? "Reading space" : "Renaming space")
      toolActivity.append(
        isSchema
          ? "Reading attached space schema"
          : (name == nil ? "Reading attached space" : "Renaming attached space"))
      let text: String
      if tool == "tonk_space_schema" {
        text = try await runtime.readSpaceSchema(space)
      } else {
        text = try await runtime.performSpaceTool(space: space, name: name)
      }
      try Task.checkCancellation()
      toolActivity.append(
        isSchema
          ? "Space schema received"
          : (name == nil ? "Space details received" : "Space rename verified"))
      activity = "Thinking"
      return SpaceTools.response(text, success: true)
    } catch {
      let detail =
        (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String
        ?? error.localizedDescription
      toolActivity.append("Space tool failed: \(detail)")
      return SpaceTools.response(detail, success: false)
    }
  }
}
