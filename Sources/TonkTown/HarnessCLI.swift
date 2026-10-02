import Foundation
import HarnessCore

@MainActor
extension HarnessModel {
  func connectCLI() async {
    guard !busy, let space = saved.conversation.space, let runtime else { return }
    busy = true
    activity = "Connecting CLI"
    defer {
      busy = false
      activity = ""
      cliConnectionTask = nil
    }
    do {
      let cli = TonkCLI(root: root, subject: space.subject)
      if cli.pendingLink != nil || !cli.isConnected {
        let link: String
        if let pending = cli.pendingLink {
          link = pending
        } else {
          link = try await runtime.createCLILink(space)
        }
        try Task.checkCancellation()
        try await cli.connect(link: link)
      }
      _ = try await cli.status()
      cliMessage = "CLI connected to \(space.title)"
    } catch is CancellationError {
      cliMessage = "CLI connection cancelled."
    } catch {
      let detail =
        (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String
        ?? error.localizedDescription
      cliMessage = "CLI connection failed: \(detail)"
    }
  }
}
