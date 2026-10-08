import Foundation

public struct SpaceProposal: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let name: String
  public let reason: String
  public var branch: String?
  public var account: String?
  public var submitted = false

  public init(arguments: JSONValue) throws {
    guard case .object(let fields) = arguments,
      Set(fields.keys) == Set(["name", "reason"]),
      let name = fields["name"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
      let reason = fields["reason"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
      !name.isEmpty, name.count <= 80, !reason.isEmpty, reason.count <= 300,
      !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    else {
      throw HarnessError.message(
        "Provide a space name (1–80 characters) and reason (1–300 characters).")
    }
    self.id = "urn:uuid:" + UUID().uuidString
    self.name = name
    self.reason = reason
  }

  public static let definition = TonkToolCatalog.definition("tonk_propose_space")

  public func createdSpace(status: String, detail: String) throws -> TonkSpace? {
    if status == "failed" { throw HarnessError.message(detail) }
    guard status == "created" else { return nil }
    guard detail.hasPrefix("/space/"), !detail.contains("?"), !detail.contains("#") else {
      throw HarnessError.message("The worker returned an invalid creation receipt.")
    }
    let subject = String(detail.dropFirst("/space/".count))
    let data = try JSONSerialization.data(withJSONObject: [["subject": subject, "name": name]])
    return try TonkSpace.decodeCatalog(data).first
  }
}
