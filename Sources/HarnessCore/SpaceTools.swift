import Foundation

public enum SpaceTools {
  /// Adapt shared MCP/native schemas to the app-server's canonical function envelope.
  public static func agentDefinitions(includeCLI: Bool) -> [JSONValue] {
    let tools =
      definitions.array + SpaceBuildTools.definitions
      + [SpaceBuildTools.applyDefinition, SpaceProposal.definition]
      + (includeCLI ? [CLITools.definition] : [])
    return tools.map { tool in
      .object([
        "type": .string("function"), "name": tool["name"],
        "description": tool["description"], "inputSchema": tool["inputSchema"],
      ])
    }
  }

  public static let inspectionDefinition = TonkToolCatalog.definition("tonk_inspect_view")
  public static let definitions: JSONValue = .array([
    "tonk_inspect_view", "tonk_space_info", "tonk_space_schema", "tonk_rename_space",
  ].map(TonkToolCatalog.definition))

  public static func validate(tool: String, arguments: JSONValue) throws -> String? {
    guard case .object(let fields) = arguments else {
      throw HarnessError.message("Tool arguments must be an object.")
    }
    switch tool {
    case "tonk_space_info", "tonk_space_schema", "tonk_inspect_view":
      guard fields.isEmpty else {
        throw HarnessError.message("This tool accepts no arguments or target space.")
      }
      return nil
    case "tonk_rename_space":
      guard Set(fields.keys) == ["name"], let name = fields["name"]?.string,
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        name.count <= 120,
        !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
      else {
        throw HarnessError.message(
          "Provide only a nonempty name of at most 120 characters, without control characters.")
      }
      return name.trimmingCharacters(in: .whitespacesAndNewlines)
    default: throw HarnessError.message("Unknown Tonk tool.")
    }
  }
  @MainActor
  public static func waitForName(
    _ expected: String, read: () async throws -> String?,
    pause: () async throws -> Void = { try await Task.sleep(for: .milliseconds(500)) }
  ) async throws -> Bool {
    for attempt in 0..<10 {
      try Task.checkCancellation()
      if try await read() == expected { return true }
      if attempt < 9 { try await pause() }
    }
    return false
  }

  public static func response(_ text: String, success: Bool) -> JSONValue {
    .object([
      "success": .bool(success),
      "contentItems": .array([.object(["type": .string("inputText"), "text": .string(text)])]),
    ])
  }
}
