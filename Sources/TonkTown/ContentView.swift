import HarnessCore
import SwiftUI

struct ContentView: View {
  @ObservedObject var model: HarnessModel
  @ObservedObject var runtime: RuntimeModel
  @State private var draft = ""
  @State private var showPersonality = false
  @State private var sharingSpace: TonkSpace?
  @State private var showRuntime = true
  @FocusState private var composing: Bool

  var body: some View {
    HSplitView {
      chat.frame(minWidth: 340, idealWidth: 440)
      if showRuntime { workspace.frame(minWidth: 380, maxWidth: .infinity) }
    }
    .nativeControl()
    .toolbar {
      ToolbarItem(placement: .navigation) {
        Button {
          model.newConversation()
        } label: {
          Label("New conversation", systemImage: "square.and.pencil")
        }
        .disabled(model.busy || model.creatingSpace).help("New conversation")
      }
      ToolbarItem {
        Button {
          showPersonality = true
        } label: {
          Label("Agent personality", systemImage: "person.crop.circle")
        }
        .disabled(model.busy || model.creatingSpace).help("Agent personality")
      }
      ToolbarItem {
        Button {
          showRuntime.toggle()
        } label: {
          Label("Show Tonk", systemImage: "sidebar.right")
        }
        .help("Show or hide Tonk").keyboardShortcut("0", modifiers: [.command, .option])
      }
    }
    .sheet(item: $sharingSpace) { space in
      ShareSpaceView(runtime: runtime, space: space)
    }
    .sheet(isPresented: $showPersonality) {
      PersonalityView(profile: model.saved.profile) { model.updateProfile($0) }
    }
  }

  private var chat: some View {
    VStack(spacing: 0) {
      ScrollViewReader { reader in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 22) {
            ForEach(ChatTranscript.grouped(model.saved.conversation.messages)) { message in
              VStack(alignment: .leading, spacing: 7) {
                if message.role == "user" {
                  Text("You")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                MessageMarkdown(text: message.text)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
              .padding(message.role == "user" ? 14 : 0)
              .background(
                message.role == "user" ? Color(nsColor: .controlBackgroundColor) : .clear,
                in: RoundedRectangle(cornerRadius: 14)
              )
              .overlay {
                if message.role == "user" {
                  RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                    .allowsHitTesting(false)
                }
              }
            }
            if !model.toolActivity.isEmpty {
              DisclosureGroup("Space activity (\(model.toolActivity.count))") {
                ForEach(Array(model.toolActivity.enumerated()), id: \.offset) { _, entry in
                  Text(entry).font(.caption).foregroundStyle(.secondary)
                }
              }.font(.caption)
            }
            if let proposal = model.saved.conversation.spaceProposal {
              VStack(alignment: .leading, spacing: 10) {
                Text("Create “\(proposal.name)”?").font(.headline)
                Text(proposal.reason).foregroundStyle(.secondary)
                if let error = model.spaceCreationError {
                  Text(error).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
                if model.creatingSpace {
                  HStack {
                    ProgressView().controlSize(.small)
                    Text("Creating space…")
                  }
                } else {
                  HStack {
                    Button(proposal.submitted ? "Check status" : "Create space") {
                      showRuntime = true
                      Task { await model.acceptSpaceProposal() }
                    }.disabled(!model.canSend)
                    Button(proposal.submitted ? "Dismiss" : "Not now") {
                      model.dismissSpaceProposal()
                    }
                    .disabled(model.busy || model.creatingSpace)
                  }
                }
              }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
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
          }.frame(maxWidth: 680).padding(24).frame(maxWidth: .infinity)
        }
        .overlay {
          if model.saved.conversation.messages.isEmpty && !model.busy {
            Text("Send a message to start")
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
              .padding(24)
              .allowsHitTesting(false)
          }
        }
        .onChange(of: model.saved.conversation.messages) { _, _ in
          reader.scrollTo("end", anchor: .bottom)
        }
      }

    }
    .background(Color(nsColor: .textBackgroundColor))
    .safeAreaInset(edge: .top, spacing: 0) {
      chatHeader.padding(12).background(Color(nsColor: .textBackgroundColor))
    }
    .safeAreaInset(edge: .bottom, spacing: 0) { composer }
  }

  private var chatHeader: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        Image(systemName: "person.crop.circle.fill").font(.title2).foregroundStyle(
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
            Button("Sign out") { Task { await model.signOut() } }.disabled(
              model.busy || model.creatingSpace)
          } label: {
            Image(systemName: "ellipsis").frame(width: 20, height: 20)
          }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .frame(width: 32, height: 32).controlSurface(radius: 16)
            .fixedSize().accessibilityLabel("Account options")
        }
      }.padding(.horizontal, 16).padding(.vertical, 12)
      if let space = model.saved.conversation.space {
        HStack {
          Image(systemName: "link")
          Text(
            "\(runtime.spaces.first(where: { $0.id == space.id })?.title ?? space.title)")
          Spacer()
        }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.bottom, 12)
      }

    }
  }

  private var composer: some View {
    VStack(spacing: 0) {
      if let error = model.error {
        HStack(alignment: .top) {
          Image(systemName: "exclamationmark.circle")
          Text(error).font(.callout).textSelection(.enabled).lineSpacing(4)
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
            Button("Sign in with ChatGPT") { Task { await model.signIn() } }.nativeControl(
              prominent: true)
            Text("Tonk Town keeps its own sign-in on this Mac.").font(.caption).foregroundStyle(
              .secondary)
          }
        }.frame(maxWidth: .infinity).padding(20)
      } else {
        HStack(alignment: .bottom, spacing: 10) {
          TextField("Message \(model.saved.profile.name)", text: $draft, axis: .vertical)
            .textFieldStyle(.plain).lineLimit(1...8).focused($composing)
            .onSubmit { submit() }.disabled(!model.canSend)
            .accessibilityLabel("Message \(model.saved.profile.name)")
          if model.busy {
            Button {
              Task { await model.stopTurn() }
            } label: {
              Image(systemName: "stop.fill").frame(width: 20, height: 20)
            }
            .nativeControl(circular: true).disabled(!model.canStop).accessibilityLabel("Stop reply")
          } else {
            Button(action: submit) { Image(systemName: "arrow.up").frame(width: 20, height: 20) }
              .nativeControl(prominent: true, circular: true)
              .disabled(
                !model.canSend || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              )
              .accessibilityLabel("Send message")
          }
        }.padding(16).controlSurface(radius: 24)
          .padding(.horizontal, 16).padding(.bottom, 16).padding(.top, 8)
      }
    }
  }

  private var workspace: some View {
    ZStack {
      RuntimeView(model: runtime)
        .allowsHitTesting(runtime.selectedSpace != nil)
        .accessibilityHidden(runtime.selectedSpace == nil)
      if runtime.selectedSpace == nil { SpacePickerView(runtime: runtime) }
      if let error = runtime.error {
        ContentUnavailableView {
          Label("Couldn’t open Tonk", systemImage: "network")
        } description: {
          Text(error)
        } actions: {
          Button("Try again") { runtime.load() }
        }.background(.background)
      }
    }
    .background(.background)
    .safeAreaInset(edge: .top, spacing: 0) {
      VStack(spacing: 12) {
        HStack(spacing: 12) {
          if runtime.selectedSpace != nil {
            Button {
              runtime.showSpaces()
            } label: {
              Image(systemName: "chevron.left").frame(width: 20, height: 20)
            }.nativeControl(circular: true).help("All spaces").accessibilityLabel("All spaces")
          }
          VStack(alignment: .leading, spacing: 3) {
            Text(runtime.selectedSpace?.title ?? "Spaces")
              .font(.headline).lineLimit(1)
              .help(runtime.selectedSpace?.title ?? "Spaces")
            if runtime.selectedSpace != nil {
              Text("Shared context and live content")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
          }
          Spacer(minLength: 0)
          if let space = runtime.selectedSpace, model.saved.conversation.space?.id != space.id {
            Button("Use for chat") { model.attachSpace(space) }
              .disabled(model.busy || model.creatingSpace)
              .help("Start a new conversation with this space. Your current conversation is saved.")
          }
          if let space = runtime.selectedSpace {
            Button {
              sharingSpace = space
            } label: {
              Image(systemName: "square.and.arrow.up").frame(width: 20, height: 20)
            }.nativeControl(circular: true).help("Share space").accessibilityLabel("Share space")
              .disabled(runtime.loading || !runtime.accountConnected)
          }
          if runtime.loading { ProgressView().controlSize(.small) }
          Menu {
            Button("Refresh", systemImage: "arrow.clockwise") {
              if runtime.selectedSpace == nil {
                Task { await runtime.refreshSpaces() }
              } else {
                runtime.load()
              }
            }.disabled(runtime.signInPending)
            Button("Open in browser", systemImage: "arrow.up.right.square") {
              NSWorkspace.shared.open(runtime.selectedSpace?.url ?? RuntimeLocation.home)
            }
          } label: {
            Image(systemName: "ellipsis").frame(width: 20, height: 20)
          }
          .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
          .frame(width: 32, height: 32).controlSurface(radius: 16).fixedSize()
          .accessibilityLabel("Space options").help("Space options")
        }
        if runtime.signInPending {
          HStack {
            ProgressView().controlSize(.small)
            Text(
              runtime.attachingAccount
                ? "Connecting your account…" : "Finish signing in in your browser"
            )
            .font(.callout)
            Spacer(minLength: 0)
            Button("Cancel") { runtime.cancelSignIn() }.disabled(runtime.attachingAccount)
          }
        } else if !runtime.accountConnected && RuntimeLocation.deployment != .local {
          HStack {
            if let message = runtime.accountMessage {
              Text(message).font(.caption).textSelection(.enabled)
            }
            Spacer(minLength: 0)
            Button("Sign in to Tonk") { Task { await runtime.signIn() } }.disabled(runtime.loading)
          }
        }
      }.padding(16).padding(12)
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
      Form {
        TextField("Name", text: $profile.name)
        Section("Personality") {
          TextEditor(text: $profile.soul).font(.body).frame(minHeight: 180)
            .scrollContentBackground(.hidden).multilineTextAlignment(.leading)
            .accessibilityLabel("Agent personality")
        }
      }.formStyle(.grouped)
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
    }.padding(24).frame(width: 480).nativeControl()
  }
}
