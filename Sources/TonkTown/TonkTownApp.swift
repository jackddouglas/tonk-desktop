import AppKit
import SwiftUI

@main
struct TonkTownApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
  @StateObject private var model = HarnessModel()
  @StateObject private var runtime = RuntimeModel()

  var body: some Scene {
    Window("Tonk Town", id: "main") {
      ContentView(model: model, runtime: runtime)
        .frame(minWidth: 850, minHeight: 580)
        .task {
          delegate.model = model
          runtime.load()
          await model.connect()
          if ProcessInfo.processInfo.arguments.contains("--smoke-test") {
            await SmokeTest.run(model: model, runtime: runtime)
          }
        }
    }
    .defaultSize(width: 1180, height: 780)
    .commands {
      CommandGroup(replacing: .newItem) {
        Button("New conversation") { model.newConversation() }
          .keyboardShortcut("n").disabled(model.busy)
      }
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
