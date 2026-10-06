import Foundation
import HarnessCore

@MainActor
extension HarnessModel {
  func importChatHistory() throws {
    guard saved.importedLegacyChats != true else { return }
    var next = saved
    next.checkpointChat()
    let archiveRoot = root.appendingPathComponent("Conversations")
    if FileManager.default.fileExists(atPath: archiveRoot.path) {
      for directory in try FileManager.default.contentsOfDirectory(
        at: archiveRoot, includingPropertiesForKeys: [.contentModificationDateKey])
      {
        guard UUID(uuidString: directory.lastPathComponent) != nil else { continue }
        let old = try StateStore(directory: directory).load()
        guard !old.conversation.messages.isEmpty else { continue }
        let date =
          try directory.resourceValues(forKeys: [.contentModificationDateKey])
          .contentModificationDate ?? .distantPast
        let session = ChatSession(id: directory.lastPathComponent, state: old, updatedAt: date)
        if !(next.sessions ?? []).contains(where: { $0.id == session.id }) {
          next.sessions?.append(session)
        }
      }
    }
    next.importedLegacyChats = true
    try store.save(next)
    saved = next
  }

  func openChat(_ id: String) async -> Bool {
    guard storageAvailable, !busy, !creatingSpace, !connecting, !loginPending else { return false }
    do {
      var next = saved
      try next.restoreChat(id)
      try store.save(next)
      saved = next
      toolActivity = []
      spaceCreationError = nil
      await connect()
      return true
    } catch {
      self.error = error.localizedDescription
      return false
    }
  }

  func openSpaceChat(_ space: TonkSpace) async -> Bool {
    guard storageAvailable, !busy, !creatingSpace, !connecting, !loginPending else { return false }
    if saved.conversation.space?.id == space.id { return true }
    if let existing = saved.chats(in: space.id).first { return await openChat(existing.id) }
    attachSpace(space)
    return saved.conversation.space?.id == space.id
  }
}
