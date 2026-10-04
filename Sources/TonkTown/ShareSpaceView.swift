import AppKit
import HarnessCore
import SwiftUI

struct ShareSpaceView: View {
  @ObservedObject var runtime: RuntimeModel
  let space: TonkSpace
  @Environment(\.dismiss) private var dismiss
  @State private var link: URL?
  @State private var creating = false
  @State private var failed = false
  @State private var copied = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Share “\(space.title)”").font(.title2.weight(.semibold))
      Text("Anyone with this invitation link can join and collaborate in this space.")
        .foregroundStyle(.secondary)
      if creating {
        ProgressView("Creating invitation…")
      } else if failed {
        Text(
          "Couldn’t confirm the invitation. Check your connection and sharing settings in Tonk before creating another link."
        )
        .foregroundStyle(.secondary)
      } else if link != nil {
        Text(copied ? "Invitation copied" : "Your invitation is ready")
          .accessibilityLabel(copied ? "Invitation copied" : "Your invitation is ready")
      }
      HStack {
        Button("Done") { dismiss() }.keyboardShortcut(.cancelAction).disabled(creating)
        Spacer()
        if let link {
          Button(copied ? "Copy again" : "Copy invitation") {
            NSPasteboard.general.clearContents()
            copied = NSPasteboard.general.setString(link.absoluteString, forType: .string)
          }
        } else if !failed {
          Button("Create invitation") {
            creating = true
            Task {
              do { link = try await runtime.createShareLink(space) } catch { failed = true }
              creating = false
            }
          }.disabled(creating)
        }
      }
    }
    .padding(24).frame(width: 420).nativeControl()
    .interactiveDismissDisabled(creating)
  }
}
