import SwiftUI

private struct ModelSettingsKey: FocusedValueKey { typealias Value = () -> Void }
private struct RefreshContentKey: FocusedValueKey { typealias Value = () -> Void }
private struct SearchFocusKey: FocusedValueKey { typealias Value = () -> Void }

extension FocusedValues {
  var refreshContent: (() -> Void)? {
    get { self[RefreshContentKey.self] }
    set { self[RefreshContentKey.self] = newValue }
  }
  var modelSettings: (() -> Void)? {
    get { self[ModelSettingsKey.self] }
    set { self[ModelSettingsKey.self] = newValue }
  }
  var focusSearch: (() -> Void)? {
    get { self[SearchFocusKey.self] }
    set { self[SearchFocusKey.self] = newValue }
  }
}

struct WindowCommands: Commands {
  @FocusedValue(\.modelSettings) private var modelSettings
  @FocusedValue(\.focusSearch) private var focusSearch

  @FocusedValue(\.refreshContent) private var refreshContent

  var body: some Commands {
    CommandGroup(replacing: .appSettings) {
      Button("Settings…") { modelSettings?() }
        .keyboardShortcut(",").disabled(modelSettings == nil)
    }
    CommandGroup(after: .toolbar) {
      Button("Refresh") { refreshContent?() }
        .keyboardShortcut("r").disabled(refreshContent == nil)
    }
    CommandGroup(after: .textEditing) {
      Button("Find…") { focusSearch?() }
        .keyboardShortcut("f").disabled(focusSearch == nil)
    }
  }
}
