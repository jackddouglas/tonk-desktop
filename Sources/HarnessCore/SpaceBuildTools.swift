import Foundation

/// Transport-independent tool schemas and validation. The host supplies the space;
/// callers cannot select a repository, branch, URL, or JavaScript to execute.
public enum SpaceBuildTools {
  public static let definitions: [JSONValue] = [
    definition(
      "tonk_query",
      "Evaluate inline Tonk query notation against the local replica, read-only. Pass document unchanged; no host filtering. Read schema for exact attribute domains. Concept heads return the full concept; use domain heads to select only listed fields. Quote text literals; Entity values use exact saved URIs. Resolve a person first, then query by their URI; an empty joined block does not guarantee other blocks are empty. Returns complete matches or an explicit size error, never a partial count.",
      key: "document"),
    definition(
      "tonk_preview",
      "Notation basics: concept: queries; concept!: asserts fields. To update an existing record, use concept!: with its exact this: URI and only the fields to change. Validate inline Tonk notation against the preview's local replica without committing. Returns current query matches, not a rendered preview or a proposed-state diff.",
      key: "document"),
  ]

  public static let applyDefinition: JSONValue = .object([
    "name": .string("tonk_apply"),
    "description": .string(
      "Apply authorized durable inline notation to the attached local space only if its revision still matches preview. Transient commands are unavailable. Read and preview again on conflict. Never retry an uncertain write; query first. Does not confirm remote sync or rendering."
    ),
    "inputSchema": .object([
      "type": .string("object"), "additionalProperties": .bool(false),
      "required": .array([.string("document"), .string("expectedRevision")]),
      "properties": .object([
        "document": .object(["type": .string("string")]),
        "expectedRevision": .object([
          "anyOf": .array([
            .object(["type": .string("object"), "additionalProperties": .bool(true)]),
            .object(["type": .string("null")]),
          ])
        ]),
      ]),
    ]),
    "annotations": .object([
      "readOnlyHint": .bool(false), "destructiveHint": .bool(true), "idempotentHint": .bool(false),
    ]),
  ])

  private static func definition(_ name: String, _ description: String, key: String) -> JSONValue {
    .object([
      "name": .string(name), "description": .string(description),
      "inputSchema": .object([
        "type": .string("object"), "additionalProperties": .bool(false),
        "required": .array([.string(key)]),
        "properties": .object([key: .object(["type": .string("string")])]),
      ]),
      "annotations": .object(["readOnlyHint": .bool(true)]),
    ])
  }

  public static func document(tool: String, arguments: JSONValue) throws -> String {
    guard case .object(let fields) = arguments else {
      throw HarnessError.message("Tool arguments must be an object.")
    }
    switch tool {
    case "tonk_apply":
      guard Set(fields.keys) == ["document", "expectedRevision"],
        let revision = fields["expectedRevision"],
        isRevision(revision),
        try JSONEncoder().encode(revision).count <= 16000
      else {
        throw HarnessError.message(
          "Provide document and the exact expectedRevision returned by preview (including null for an empty branch)."
        )
      }
      return try document(
        tool: "tonk_preview", arguments: .object(["document": fields["document"] ?? .null]))
    case "tonk_query":
      // Compatibility for saved threads/MCP callers using the original concept-only tool.
      if Set(fields.keys) == ["target"], let target = fields["target"]?.string,
        target.utf8.count <= 200,
        target.range(of: "^[A-Za-z][A-Za-z0-9_:/.-]*$", options: .regularExpression) != nil
      {
        return target + ":\n"
      }
      guard Set(fields.keys) == ["document"] else {
        throw HarnessError.message(
          "Pass query notation as document. Host fields/equals filtering is no longer supported; use domain queries with explicit fields and literal filters."
        )
      }
      return try document(tool: "tonk_preview", arguments: arguments)
    case "tonk_preview":
      guard Set(fields.keys) == ["document"], let document = fields["document"]?.string,
        !document.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        document.utf8.count <= 32000,
        document.range(of: "!(?!:)|%TAG", options: .regularExpression) == nil
      else {
        throw HarnessError.message(
          "Provide only inline notation, up to 32 KB, without YAML tags or includes.")
      }
      return document
    default: throw HarnessError.message("Unknown direct build tool.")
    }
  }

  public static func appliedResult(_ data: Data, expectedRevision: JSONValue) throws -> JSONValue {
    let uncertain = HarnessError.message(
      "The write outcome could not be confirmed. Do not repeat it; query the space first.")
    guard data.count <= 2_000_000,
      let value = try? JSONDecoder().decode(JSONValue.self, from: data),
      case .object(let fields) = value, fields["revision_before"] != nil,
      fields["revision_after"] != nil, value["revision_before"] == expectedRevision,
      let claims = value["commits"]["claims"].int, claims >= 0,
      isRevision(value["revision_after"]),
      claims == 0 || value["revision_after"] != .null
    else { throw uncertain }
    return .object([
      "revision": value["revision_after"], "previousRevision": value["revision_before"],
      "revisionChanged": .bool(value["revision_before"] != value["revision_after"]),
      "claims": .number(Double(claims)), "accepted": .bool(true),
      "renderingConfirmed": .bool(false),
      "scope": .string(
        "Local conditional evaluation completed. Rendering and remote synchronization are not confirmed. Query records and inspect the preview; do not repeat this write."
      ),
    ])
  }

  private static func isRevision(_ value: JSONValue) -> Bool {
    switch value {
    case .null, .object: return true
    default: return false
    }
  }

  public static func result(_ data: Data) throws -> JSONValue {
    guard data.count <= 2_000_000 else {
      throw HarnessError.message("Worker response exceeds the tool limit.")
    }
    let value = try JSONDecoder().decode(JSONValue.self, from: data)
    guard case .object(let fields) = value,
      fields["revision_before"] != nil, fields["revision_after"] != nil,
      value["revision_before"] == value["revision_after"],
      value["commits"]["claims"] == .number(0),
      case .array = value["matches_after"]
    else { throw HarnessError.message("The worker did not confirm a read-only evaluation.") }
    let matches = value["matches_after"]
    guard try JSONEncoder().encode(matches).count <= 100_000 else {
      throw HarnessError.message(
        "Too many results. Narrow the notation document: use attribute-domain heads with only needed fields and exact saved Entity URI filters. Concept queries include omitted fields. No partial results were returned."
      )
    }
    return .object([
      "revision": value["revision_after"], "committed": .bool(false),
      "matches": matches,
      "scope": .string(
        "Local replica; current matches only. No sync, commit, rendered preview, or proposed-state diff."
      ),
    ])
  }
}
