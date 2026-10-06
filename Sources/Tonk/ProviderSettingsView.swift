import HarnessCore
import SwiftUI

struct ProviderSettingsView: View {
  @ObservedObject var model: HarnessModel
  @Environment(\.dismiss) private var dismiss
  @State private var selected: ModelProvider
  @State private var connection: ModelConnection
  @State private var key = ""
  @State private var saving = false
  @State private var showAdvancedSettings = false
  @State private var error: String?

  init(model: HarnessModel) {
    self.model = model
    _selected = State(initialValue: model.provider)
    _connection = State(initialValue: model.connection)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("Model provider").font(.title2.weight(.semibold))
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text("Provider")
          Spacer()
          Menu {
            Picker("Provider", selection: $selected) {
              ForEach(ModelProvider.allCases) { provider in Text(provider.title).tag(provider) }
            }.pickerStyle(.inline)
          } label: {
            HStack(spacing: 8) {
              Text(selected.title)
              Image(systemName: "chevron.down").font(.caption.weight(.semibold))
            }
          }.modifier(SettingsMenuStyle())
        }
        if selected == .chatGPT {
          if !model.subscriptionModels.isEmpty {
            HStack {
              Text("Model")
              Spacer()
              Menu {
                Picker("Model", selection: $connection.model) {
                  if !model.subscriptionModels.contains(where: { $0.id == connection.model }) {
                    Text(connection.model.isEmpty ? "Choose a model" : connection.model).tag(
                      connection.model)
                  }
                  ForEach(model.subscriptionModels) { item in Text(item.name).tag(item.id) }
                }.pickerStyle(.inline)
              } label: {
                HStack(spacing: 8) {
                  Text(
                    model.subscriptionModels.first(where: { $0.id == connection.model })?.name
                      ?? (connection.model.isEmpty ? "Choose a model" : connection.model))
                  Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                }
              }.modifier(SettingsMenuStyle())
            }
          } else {
            SettingsTextField(
              title: "Model ID", text: $connection.model, prompt: "Default from ChatGPT")
          }
          if let error = model.modelCatalogError {
            Text(error).font(.caption).foregroundStyle(.secondary)
          }
        } else if selected != .disabled {
          SettingsTextField(
            title: "Model ID", text: $connection.model, prompt: "Enter the provider’s model ID"
          )
          .autocorrectionDisabled()
          if selected == .local || selected == .ollama || selected == .compatible {
            SettingsTextField(title: "Base URL", text: $connection.baseURL)
              .autocorrectionDisabled()
            Text(
              [.local, .ollama].contains(selected)
                ? "Use an OpenAI-compatible server, such as http://localhost:1234/v1 or http://localhost:11434/v1."
                : "Enter the HTTPS base URL for an OpenAI-compatible API, including /v1 if required."
            )
            .font(.caption).foregroundStyle(.secondary)
          }
          SettingsTextField(
            title: selected.requiresKey ? "API key" : "API key (optional)", text: $key,
            prompt: "Leave blank to keep the saved key", secure: true)
          HStack {
            Text("Keys are stored in your Mac’s Keychain.").font(.caption).foregroundStyle(
              .secondary)
            Spacer()
            Button("Remove saved key", role: .destructive) {
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
        }
      }.controlSize(.regular)
      Divider()
      Text(
        "Changing provider or model starts a new conversation. Your previous transcript is saved on this Mac, and the attached space stays open."
      )
      .font(.caption).foregroundStyle(.secondary)
      if let error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
      HStack {
        Button("Advanced…") { showAdvancedSettings = true }
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button(saving ? "Saving…" : "Apply") {
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
      }.controlSize(.regular)
    }
    .padding(24).frame(width: 540).nativeControl().disabled(saving)
    .interactiveDismissDisabled(saving)
    .sheet(isPresented: $showAdvancedSettings) { AdvancedSettingsView() }
    .onChange(of: selected) { _, value in
      if connection.provider != value {
        connection = model.saved.connections?[value.rawValue] ?? ModelConnection(provider: value)
      }
      key = ""
      error = nil
    }
    .onChange(of: connection.baseURL) { _, _ in key = "" }
  }
}

private struct SettingsMenuStyle: ViewModifier {
  func body(content: Content) -> some View {
    content.menuStyle(.borderlessButton).menuIndicator(.hidden)
      .padding(.horizontal, 8).padding(.vertical, 4)
      .controlSurface(radius: 12).fixedSize()
  }
}

private struct SettingsTextField: View {
  let title: String
  @Binding var text: String
  var prompt = ""
  var secure = false
  @FocusState private var focused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
      Group {
        if secure {
          SecureField(title, text: $text, prompt: Text(prompt))
        } else {
          TextField(title, text: $text, prompt: Text(prompt))
        }
      }.textFieldStyle(.plain).focused($focused).accessibilityLabel(title)
        .padding(10).controlSurface(radius: 12)
        .overlay {
          RoundedRectangle(cornerRadius: 12)
            .strokeBorder(focused ? Color.accentColor : .clear, lineWidth: 2)
            .allowsHitTesting(false)
        }
    }
  }
}
