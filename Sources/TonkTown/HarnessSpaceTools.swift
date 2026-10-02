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
      does not prove records exist; truncation is not a complete inventory.
      The harness connects space tools automatically. tonk_cli can inspect, preview, and apply notation
      to this attached space. Read the notation/views guides and existing schema first.
      Preview before applying. Apply only changes requested by the user; read records
      back after applying. The app runtime is the visual proof; CLI success alone is not.
      CLI read operations inspect the local replica; apply automatically pulls then pushes.
      Do not issue account, grant, invitation, or filesystem operations through notation. You cannot choose another target or access other spaces.
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
      if tool == "tonk_cli" {
        let arguments = try CLITools.arguments(params["arguments"])
        let cli = try await prepareCLI(for: space, runtime: runtime)
        activity = "Using Tonk CLI"
        toolActivity.append("CLI: " + (params["arguments"]["operation"].string ?? ""))
        let output = try await cli.run(arguments)
        try Task.checkCancellation()
        activity = "Thinking"
        toolActivity.append("CLI operation completed")
        return SpaceTools.response(CLITools.summarize(output), success: true)
      }
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
