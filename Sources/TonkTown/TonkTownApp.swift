import AppKit
import HarnessCore
import SwiftUI

@main
struct TonkTownApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
  @StateObject private var model = HarnessModel()
  @StateObject private var runtime = RuntimeModel()

  var body: some Scene {
    Window(RuntimeLocation.deployment == .staging ? "Tonk Town — Staging" : "Tonk Town", id: "main")
    {
      ContentView(model: model, runtime: runtime)
        .frame(minWidth: 850, minHeight: 580)
        .background(WindowAppearance())
        .task {
          delegate.model = model
          model.runtime = runtime
          runtime.load()
          await model.connect()
          if ProcessInfo.processInfo.arguments.contains("--smoke-test") {
            await SmokeTest.run(model: model, runtime: runtime)
          }
        }
    }
    .defaultSize(width: 1180, height: 780)
    .windowToolbarStyle(.unifiedCompact)
    .commands {
      CommandGroup(replacing: .newItem) {
        Button("New conversation") { model.newConversation() }
          .keyboardShortcut("n").disabled(model.busy)
      }
    }
  }
}

private struct WindowAppearance: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView { SeparatorlessView() }
  func updateNSView(_ nsView: NSView, context: Context) {}

  private final class SeparatorlessView: NSView {
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      // The automatic separator spans both panes at the taller chat header's edge.
      window?.titlebarSeparatorStyle = .none
    }
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  weak var model: HarnessModel?
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
  }
  func applicationWillTerminate(_ notification: Notification) { model?.shutdown() }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
