import HarnessCore
import SwiftUI

struct ChatHistoryView: View {
  @ObservedObject var model: HarnessModel
  let space: TonkSpace?
  let allSpaces: Bool
  let onOpen: (ChatSession) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var search = ""
  private var sessions: [ChatSession] {
    let sessions =
      allSpaces
      ? (model.saved.sessions ?? []).sorted { $0.updatedAt > $1.updatedAt }
      : model.saved.chats(in: space?.id)
    return sessions.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(allSpaces ? "Chat history" : "Chats in \(space?.title ?? "this conversation")")
        .font(.title2.weight(.semibold))
      TextField("Find a chat", text: $search).textFieldStyle(.roundedBorder)
      if sessions.isEmpty {
        ContentUnavailableView("No chats yet", systemImage: "bubble.left.and.bubble.right")
      } else {
        List(sessions) { session in
          Button {
            onOpen(session)
          } label: {
            VStack(alignment: .leading, spacing: 6) {
              Text(session.title).font(.headline).lineLimit(2)
              HStack {
                Text(
                  allSpaces
                    ? (session.conversation.space?.title ?? "Unassigned") : session.provider.title)
                Spacer()
                Text(session.updatedAt, style: .date)
              }.font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, 6).contentShape(Rectangle())
          }.buttonStyle(.plain)
        }.listStyle(.inset)
      }
      if let error = model.error { Text(error).font(.caption).foregroundStyle(.secondary) }
      HStack {
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
      }
    }.padding(24).frame(width: 520, height: 440).nativeControl()
      .disabled(model.busy || model.connecting || model.creatingSpace || model.loginPending)
  }
}
