import AppKit
import HarnessCore
import SwiftUI

@main
struct TonkTownApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
  @StateObject private var model = HarnessModel()
  @StateObject private var runtime = RuntimeModel()

  var body: some Scene {
    Window(RuntimeLocation.deployment.title, id: "main") {
      ContentView(model: model, runtime: runtime)
        .frame(minWidth: 850, minHeight: 580)
        .background(WindowAppearance())
        .task {
          delegate.model = model
          delegate.runtime = runtime
          model.runtime = runtime
          await runtime.startMCPBridge(root: model.root)
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
        Button("New chat") {
          model.startSpaceChat()
        }
        .keyboardShortcut("n").disabled(
          model.openedSpace == nil || model.busy || model.creatingSpace || model.loginPending
            || model.connecting)
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
  weak var runtime: RuntimeModel?
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
  }
  func applicationWillTerminate(_ notification: Notification) {
    runtime?.stopMCPBridge()
    model?.shutdown()
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
