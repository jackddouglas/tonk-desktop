import AppKit
import Foundation

@MainActor
enum SmokeTest {
  static func run(model: HarnessModel, runtime: RuntimeModel) async {
    var report: [String: Any] = ["appServer": model.connected, "signedIn": model.signedIn]
    var lastProbe: [String: Any] = [:]
    for _ in 0..<40 {
      if let result = try? await runtime.probe() {
        lastProbe = result
        if result["health"] as? Bool == true && result["mounted"] as? Bool == true
          && runtime.catalogLoaded
        {
          break
        }
      }
      try? await Task.sleep(for: .seconds(1))
    }
    report["catalogLoaded"] = runtime.catalogLoaded
    report["spaceCount"] = runtime.spaces.count
    if let error = runtime.catalogError { report["catalogError"] = error }
    report["runtime"] = lastProbe
    report["passed"] =
      model.connected && lastProbe["health"] as? Bool == true
      && lastProbe["mounted"] as? Bool == true && runtime.catalogLoaded
    if let error = runtime.error { report["runtimeError"] = error }
    if let error = model.error { report["agentError"] = error }
    let arguments = ProcessInfo.processInfo.arguments
    if let index = arguments.firstIndex(of: "--inspect-space"),
      arguments.indices.contains(index + 1)
    {
      do {
        guard let space = runtime.spaces.first(where: { $0.id == arguments[index + 1] }) else {
          throw NSError(
            domain: "SmokeTest", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Requested space is not in the catalog"])
        }
        report["spaceInspection"] = try await runtime.performSpaceTool(space: space, name: nil)
        if arguments.contains("--inspect-schema") {
          report["spaceSchema"] = try await runtime.readSpaceSchema(space)
        }
      } catch {
        report["passed"] = false
        report["inspectionError"] =
          (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String
          ?? error.localizedDescription
      }
    }
    if let index = arguments.firstIndex(of: "--report"), arguments.indices.contains(index + 1) {
      let target = URL(fileURLWithPath: arguments[index + 1])
      if let data = try? JSONSerialization.data(
        withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
      {
        try? data.write(to: target, options: .atomic)
      }
    }
    model.shutdown()
    NSApp.terminate(nil)
  }
}
