import HarnessCore
import SwiftUI

struct ContentView: View {
  @ObservedObject var model: HarnessModel
  @ObservedObject var runtime: RuntimeModel
  @State private var draft = ""
  @State private var showPersonality = false
  @State private var showRuntime = true
  @FocusState private var composing: Bool

  var body: some View {
    HSplitView {
      chat.frame(minWidth: 360, idealWidth: 470)
      if showRuntime { workspace.frame(minWidth: 420, maxWidth: .infinity) }
    }
    .toolbar {
      ToolbarItem(placement: .navigation) {
        Button {
          model.newConversation()
        } label: {
          Label("New conversation", systemImage: "square.and.pencil")
        }
        .disabled(model.busy).help("New conversation")
      }
      ToolbarItem {
        Button {
          showPersonality = true
        } label: {
          Label("Agent personality", systemImage: "person.crop.circle")
        }
        .disabled(model.busy).help("Agent personality")
      }
      ToolbarItem {
        Button {
          showRuntime.toggle()
        } label: {
          Label("Show Tonk", systemImage: "sidebar.right")
        }
        .help("Show or hide Tonk")
      }
    }
    .sheet(isPresented: $showPersonality) {
      PersonalityView(profile: model.saved.profile) { model.updateProfile($0) }
    }
  }

  private var chat: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        Image(systemName: "person.crop.circle.fill").font(.system(size: 30)).foregroundStyle(
          .secondary)
        VStack(alignment: .leading, spacing: 3) {
          Text(model.saved.profile.name).font(.headline)
          Text(model.connecting ? "Connecting…" : model.accountLabel)
            .font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        if !model.connected {
          Button("Reconnect") { Task { await model.connect() } }.disabled(model.connecting)
        } else if model.signedIn {
          Menu {
            Button("Sign out") { Task { await model.signOut() } }.disabled(model.busy)
          } label: {
            Image(systemName: "ellipsis.circle")
          }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Account options")
        }
      }.padding(20)
      Divider()
      if let space = model.saved.conversation.space {
        HStack {
          Image(systemName: "link")
          Text(
            "Attached: \(runtime.spaces.first(where: { $0.id == space.id })?.title ?? space.title)")
          Spacer()
          Button("Connect CLI") { model.cliConnectionTask = Task { await model.connectCLI() } }
            .disabled(model.busy)
        }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.top, 12)
        if !model.cliMessage.isEmpty {
          Text(model.cliMessage).font(.caption).textSelection(.enabled).padding(.horizontal, 20)
        }
      }

      ScrollViewReader { reader in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 22) {
            if model.saved.conversation.messages.isEmpty {
              VStack(alignment: .leading, spacing: 12) {
                Text("What’s on your mind?").font(
                  .system(size: 26, weight: .medium, design: .serif))
                Text("A place to think things through, make a plan, or begin something small.")
                  .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
              }.padding(.vertical, 40)
            }
            ForEach(model.saved.conversation.messages) { message in
              VStack(alignment: .leading, spacing: 7) {
                Text(message.role == "user" ? "You" : model.saved.profile.name)
                  .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(
                  (try? AttributedString(
                    markdown: message.text,
                    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                    ?? AttributedString(message.text)
                ).textSelection(.enabled)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
              .padding(message.role == "user" ? 14 : 0)
              .background(
                message.role == "user" ? Color.primary.opacity(0.045) : .clear,
                in: RoundedRectangle(cornerRadius: 14))
            }
            if !model.toolActivity.isEmpty {
              DisclosureGroup("Space activity (\(model.toolActivity.count))") {
                ForEach(Array(model.toolActivity.enumerated()), id: \.offset) { _, entry in
                  Text(entry).font(.caption).foregroundStyle(.secondary)
                }
              }.font(.caption)
            }
            if model.busy {
              HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(model.activity).font(.caption).foregroundStyle(.secondary)
              }
            } else if model.saved.conversation.lastTurnStatus == "interrupted" {
              Text("Reply stopped").font(.caption).foregroundStyle(.secondary)
            }
            Color.clear.frame(height: 1).id("end")
          }.padding(20)
        }
        .onChange(of: model.saved.conversation.messages) { _, _ in
          reader.scrollTo("end", anchor: .bottom)
        }
      }

      if let error = model.error {
        HStack(alignment: .top) {
          Image(systemName: "exclamationmark.circle")
          Text(error).font(.callout).textSelection(.enabled)
          Spacer(minLength: 0)
          Button {
            model.error = nil
          } label: {
            Image(systemName: "xmark")
          }.buttonStyle(.plain).accessibilityLabel("Dismiss error")
        }.padding(12).background(Color.orange.opacity(0.12)).padding(.horizontal, 16).padding(
          .bottom, 8)
      }

      if model.connected && !model.signedIn {
        VStack(spacing: 10) {
          if model.loginPending {
            ProgressView("Finish signing in in your browser")
            Button("Cancel sign-in") { Task { await model.cancelLogin() } }
          } else {
            Button("Sign in with ChatGPT") { Task { await model.signIn() } }.buttonStyle(
              .borderedProminent)
            Text("Tonk Town keeps its own sign-in on this Mac.").font(.caption).foregroundStyle(
              .secondary)
          }
        }.frame(maxWidth: .infinity).padding(20)
      } else {
        HStack(alignment: .bottom, spacing: 10) {
          TextField("Message \(model.saved.profile.name)", text: $draft, axis: .vertical)
            .textFieldStyle(.plain).lineLimit(1...8).focused($composing)
            .onSubmit { submit() }.disabled(!model.canSend)
          if model.busy {
            Button {
              Task { await model.stopTurn() }
            } label: {
              Image(systemName: "stop.fill")
            }
            .disabled(!model.canStop).accessibilityLabel("Stop reply")
          } else {
            Button(action: submit) { Image(systemName: "arrow.up") }
              .buttonStyle(.borderedProminent)
              .disabled(
                !model.canSend || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              )
              .accessibilityLabel("Send message")
          }
        }.padding(14).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
          .padding(16)
      }
    }
  }

  private var workspace: some View {
    VStack(spacing: 0) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text(runtime.selectedSpace?.title ?? "Your spaces").font(.headline).lineLimit(1)
          if runtime.selectedSpace != nil {
            Button("All spaces") { runtime.showSpaces() }.buttonStyle(.link)
          }
        }
        Spacer()
        if let space = runtime.selectedSpace {
          Button("Use for chat") { model.attachSpace(space) }
            .disabled(model.busy || model.saved.conversation.space?.id == space.id)
            .help(
              "Start a new conversation that can inspect this space’s schema and rename it. The current conversation is archived."
            )
        }
        if runtime.loading { ProgressView().controlSize(.small) }
        Button {
          runtime.load()
        } label: {
          Image(systemName: "arrow.clockwise")
        }.help("Reload Tonk").accessibilityLabel("Reload Tonk").disabled(runtime.signInPending)
        Button {
          NSWorkspace.shared.open(runtime.selectedSpace?.url ?? RuntimeLocation.home)
        } label: {
          Image(systemName: "arrow.up.right.square")
        }
        .help("Open Tonk in your browser").accessibilityLabel("Open Tonk in browser")
      }.padding(20)
      if runtime.signInPending {
        HStack {
          ProgressView().controlSize(.small)
          Text(
            runtime.attachingAccount
              ? "Connecting your Tonk account…" : "Finish signing in in your browser"
          )
          .font(.callout)
          Spacer()
          Button("Cancel") { runtime.cancelSignIn() }.disabled(runtime.attachingAccount)
        }.padding(.horizontal, 20).padding(.bottom, 12)
      } else {
        HStack {
          if let message = runtime.accountMessage {
            Text(message).font(.caption).textSelection(.enabled)
          }
          Spacer()
          if runtime.accountConnected {
            Text("Tonk connected").font(.caption).foregroundStyle(.secondary)
          } else {
            Button("Sign in to Tonk") { Task { await runtime.signIn() } }.disabled(runtime.loading)
          }
        }.padding(.horizontal, 20).padding(.bottom, 12)
      }
      Divider()
      ZStack {
        RuntimeView(model: runtime)
          .allowsHitTesting(runtime.selectedSpace != nil)
          .accessibilityHidden(runtime.selectedSpace == nil)
        if runtime.selectedSpace == nil {
          SpacePickerView(runtime: runtime)
        }
        if let error = runtime.error {
          ContentUnavailableView {
            Label("Couldn’t open Tonk", systemImage: "network")
          } description: {
            Text(error)
          } actions: {
            Button("Try again") { runtime.load() }
          }
          .background(.background)
        }
      }
    }
  }

  private func submit() {
    guard model.canSend, !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return
    }
    let text = draft
    draft = ""
    Task { await model.send(text) }
  }
}

private struct PersonalityView: View {
  @Environment(\.dismiss) var dismiss
  @State var profile: AgentProfile
  var save: (AgentProfile) -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Your agent").font(.title2.weight(.semibold))
      TextField("Name", text: $profile.name).textFieldStyle(.roundedBorder)
      Text("Personality").font(.headline)
      TextEditor(text: $profile.soul).font(.body).frame(height: 190)
        .padding(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
        .accessibilityLabel("Agent personality")
      Text("Changes apply to your next message.").font(.caption).foregroundStyle(.secondary)
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Save") {
          profile.name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
          save(profile)
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(
          profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || profile.soul.count > 16000)
      }
    }.padding(24).frame(width: 460)
  }
}
