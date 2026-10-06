import Foundation

/// Transport-independent tool schemas and validation. The host supplies the space;
/// callers cannot select a repository, branch, URL, or JavaScript to execute.
public enum SpaceBuildTools {
  public static let definitions: [JSONValue] = [
    .object([
      "name": .string("tonk_query"),
      "description": .string(
        "Read concept records from the local replica, without writes or network pull. Use fields to omit large body/source fields. equals filters exact saved values, including Entity URI strings. First query the people concept to resolve a person's exact this URI; never guess an entity from their name. Returns all matching rows or an explicit size error, never a partial count."
      ),
      "inputSchema": .object([
        "type": .string("object"), "additionalProperties": .bool(false),
        "required": .array([.string("target")]),
        "properties": .object([
          "target": .object(["type": .string("string")]),
          "fields": .object([
            "type": .string("array"), "items": .object(["type": .string("string")]),
          ]),
          "equals": .object(["type": .string("object"), "additionalProperties": .bool(true)]),
        ]),
      ]),
      "annotations": .object(["readOnlyHint": .bool(true)]),
    ]),
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
      guard Set(fields.keys).isSubset(of: ["target", "fields", "equals"]),
        let target = fields["target"]?.string,
        target.utf8.count <= 200,
        target.range(of: "^[A-Za-z][A-Za-z0-9_:/.-]*$", options: .regularExpression) != nil
      else { throw HarnessError.message("Provide only a concept name or URI as target.") }
      if let projection = fields["fields"] {
        guard case .array(let names) = projection, names.count <= 64,
          names.allSatisfy({ $0.string != nil && ($0.string?.utf8.count ?? 0) <= 200 })
        else { throw HarnessError.message("fields must be an array of at most 64 field names.") }
      }
      if let filters = fields["equals"] {
        guard case .object(let values) = filters, values.count <= 32,
          try JSONEncoder().encode(filters).count <= 16000
        else {
          throw HarnessError.message("equals must be a small object of exact saved field values.")
        }
      }
      return target + ":\n"
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

  public static func result(_ data: Data, query: JSONValue? = nil) throws -> JSONValue {
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
    var matches = value["matches_after"]
    if let query {
      _ = try document(tool: "tonk_query", arguments: query)
      let selected = query["fields"].array.compactMap(\.string)
      let hasProjection = query["fields"] != .null
      let filters: [String: JSONValue]
      if case .object(let values) = query["equals"] { filters = values } else { filters = [:] }
      matches = .array(
        try matches.array.map { block in
          guard case .object(var output) = block, case .array(let rows) = block["results"] else {
            throw HarnessError.message("Unexpected query result shape.")
          }
          for row in rows {
            guard row["this"].string != nil, case .object = row["fields"] else {
              throw HarnessError.message("Unexpected query record shape.")
            }
          }
          let filtered = rows.filter { row in
            guard case .object(let fields) = row["fields"] else { return false }
            return filters.allSatisfy { key, value in
              (key == "this" ? row["this"] : fields[key]) == value
            }
          }
          output["totalMatches"] = .number(Double(filtered.count))
          output["results"] = .array(
            try filtered.map { row in
              guard case .object(var record) = row, case .object(let fields) = row["fields"] else {
                throw HarnessError.message("Unexpected query record shape.")
              }
              if hasProjection {
                record["fields"] = .object(fields.filter { selected.contains($0.key) })
              }
              return .object(record)
            })
          return .object(output)
        })
    }
    guard try JSONEncoder().encode(matches).count <= 100_000 else {
      throw HarnessError.message(
        "Too many results. Call tonk_query with fields for only needed columns and equals for exact saved values. Resolve person/entity URIs from records first. No partial results were returned."
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
