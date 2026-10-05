import HarnessCore
import SwiftUI

struct ProviderSettingsView: View {
  @ObservedObject var model: HarnessModel
  @Environment(\.dismiss) private var dismiss
  @State private var selected: ModelProvider
  @State private var connection: ModelConnection
  @State private var key = ""
  @State private var saving = false
  @State private var error: String?

  init(model: HarnessModel) {
    self.model = model
    _selected = State(initialValue: model.provider)
    _connection = State(initialValue: model.connection)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("Model provider").font(.title2.weight(.semibold))
      Form {
        Picker("Provider", selection: $selected) {
          ForEach(ModelProvider.allCases) { provider in Text(provider.title).tag(provider) }
        }
        if selected == .chatGPT {
          Text("Use your ChatGPT subscription with the existing browser sign-in.")
            .foregroundStyle(.secondary)
        } else {
          TextField(
            "Model ID", text: $connection.model, prompt: Text("Enter the provider’s model ID")
          )
          .autocorrectionDisabled()
          if selected == .local || selected == .compatible {
            TextField("Base URL", text: $connection.baseURL)
              .autocorrectionDisabled()
            Text(
              selected == .local
                ? "Use an OpenAI-compatible server, such as http://localhost:1234/v1 or http://localhost:11434/v1."
                : "Enter the HTTPS base URL for an OpenAI-compatible API, including /v1 if required."
            )
            .font(.caption).foregroundStyle(.secondary)
          }
          SecureField(
            selected.requiresKey ? "API key" : "API key (optional)", text: $key,
            prompt: Text("Leave blank to keep the saved key"))
          HStack {
            Text("Keys are stored in your Mac’s Keychain.").font(.caption).foregroundStyle(
              .secondary)
            Spacer()
            Button("Remove saved key") {
              do {
                try model.credentials.remove(connection)
                key = ""
                if connection.provider == model.provider
                  && connection.baseURL == model.connection.baseURL
                {
                  try model.connectAPI()
                }
              } catch { self.error = error.localizedDescription }
            }.controlSize(.small)
          }
          Toggle("Enable Tonk tools", isOn: $connection.toolsEnabled)
          Text(
            "The model must support tool calling to build and inspect spaces. Turn this off for text-only models."
          )
          .font(.caption).foregroundStyle(.secondary)
        }
      }.formStyle(.grouped)
      Text(
        "Changing provider, model, or tool settings starts a new conversation. Your previous transcript is saved on this Mac, and the attached space stays open."
      )
      .font(.caption).foregroundStyle(.secondary)
      if let error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button(saving ? "Saving…" : "Use provider") {
          saving = true
          error = nil
          connection.model = connection.model.trimmingCharacters(in: .whitespacesAndNewlines)
          connection.baseURL = connection.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
          Task {
            defer { saving = false }
            do {
              try await model.configureProvider(selected, connection: connection, key: key)
              dismiss()
            } catch { self.error = error.localizedDescription }
          }
        }.nativeControl(prominent: true).keyboardShortcut(.defaultAction)
      }
    }
    .padding(24).frame(width: 540).nativeControl().disabled(saving)
    .onChange(of: selected) { _, value in
      connection = model.saved.connections?[value.rawValue] ?? ModelConnection(provider: value)
      key = ""
      error = nil
    }
    .onChange(of: connection.baseURL) { _, _ in key = "" }
  }
}
