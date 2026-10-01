import AppKit
import HarnessCore
import SwiftUI

@MainActor
final class HarnessModel: ObservableObject {
  @Published var saved = SavedState()
  @Published var connected = false
  @Published var connecting = false
  @Published var signedIn = false
  @Published var accountLabel = "Not signed in"
  @Published var busy = false
  @Published var activity = ""
  @Published var error: String?
  @Published var loginPending = false
  let client = AppServerClient()
  let root: URL
  let store: StateStore
  private var loginID: String?
  @Published private var turnID: String?
  private var resumed = false
  private var saveTask: Task<Void, Never>?
  private var storageAvailable = true

  init() {
    let arguments = ProcessInfo.processInfo.arguments
    if let index = arguments.firstIndex(of: "--data-dir"), arguments.indices.contains(index + 1) {
      root = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
    } else {
      root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Tonk Town", isDirectory: true)
    }
    store = StateStore(directory: root)
    do { saved = try store.load() } catch {
      storageAvailable = false
      self.error =
        "Could not read your saved conversation. It has been preserved at \(root.path)/state.json. \(error.localizedDescription)"
    }
    client.onNotification = { [weak self] method, params in self?.receive(method, params) }
    client.onDisconnect = { [weak self] message in
      guard let self else { return }
      self.connected = false
      self.busy = false
      self.resumed = false
      self.turnID = nil
      self.loginID = nil
      self.loginPending = false
      self.error = message
      self.persist()
    }
  }

  var canSend: Bool { connected && signedIn && !busy && !loginPending && storageAvailable }

  func connect() async {
    guard !connecting else { return }
    connecting = true
    defer { connecting = false }
    if storageAvailable { error = nil }
    client.stop()
    connected = false
    resumed = false
    busy = false
    loginID = nil
    loginPending = false
    turnID = nil
    do {
      let candidates = [
        ProcessInfo.processInfo.environment["TONK_TOWN_CODEX"],
        "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
          ".nix-profile/bin/codex"
        ).path,
      ]
      guard
        let path = candidates.compactMap({ $0 }).first(where: {
          FileManager.default.isExecutableFile(atPath: $0)
        })
      else {
        throw HarnessError.message(
          "Codex was not found. Install the Codex CLI, then reconnect. TONK_TOWN_CODEX can select another executable."
        )
      }
      try await client.start(
        executable: URL(fileURLWithPath: path),
        home: root.appendingPathComponent("Codex"),
        workspace: root.appendingPathComponent("Workspace"))
      connected = true
      try await refreshAccount()
    } catch { self.error = error.localizedDescription }
  }

  func refreshAccount() async throws {
    let result = try await client.request(
      "account/read", params: .object(["refreshToken": .bool(false)]))
    signedIn = result["account"]["type"].string == "chatgpt"
    accountLabel = signedIn ? "ChatGPT connected" : "Not signed in"
  }

  func signIn() async {
    guard connected, !loginPending else { return }
    loginPending = true
    error = nil
    do {
      let result = try await client.request(
        "account/login/start", params: .object(["type": .string("chatgpt")]))
      loginID = result["loginId"].string
      guard let address = result["authUrl"].string, let url = URL(string: address),
        url.scheme == "https"
      else {
        throw HarnessError.message("Codex did not return a valid sign-in address.")
      }
      guard NSWorkspace.shared.open(url) else {
        throw HarnessError.message("Could not open your browser for sign-in.")
      }
    } catch {
      if let loginID {
        _ = try? await client.request(
          "account/login/cancel", params: .object(["loginId": .string(loginID)]))
      }
      loginPending = false
      loginID = nil
      self.error = error.localizedDescription
    }
  }

  func cancelLogin() async {
    guard let loginID else { return }
    do {
      _ = try await client.request(
        "account/login/cancel", params: .object(["loginId": .string(loginID)]))
      self.loginID = nil
      loginPending = false
    } catch { self.error = error.localizedDescription }
  }

  func signOut() async {
    guard !busy else { return }
    do {
      _ = try await client.request("account/logout")
      signedIn = false
      accountLabel = "Not signed in"
      resumed = false
    } catch { self.error = error.localizedDescription }
  }

  func send(_ text: String) async {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard canSend, !trimmed.isEmpty else { return }
    busy = true
    saved.conversation.lastTurnStatus = nil
    error = nil
    activity = "Thinking"
    do {
      var parameters: [String: JSONValue] = [
        "cwd": .string(root.appendingPathComponent("Workspace").path),
        "developerInstructions": .string(saved.profile.instructions),
        "sandbox": .string("read-only"), "approvalPolicy": .string("never"),
      ]
      if let threadID = saved.conversation.threadID {
        if !resumed {
          parameters["threadId"] = .string(threadID)
          _ = try await client.request("thread/resume", params: .object(parameters))
          resumed = true
        }
      } else {
        let result = try await client.request("thread/start", params: .object(parameters))
        guard let threadID = result["thread"]["id"].string else {
          throw HarnessError.message("The agent did not create a conversation.")
        }
        saved.conversation.threadID = threadID
        resumed = true
      }
      guard let threadID = saved.conversation.threadID else {
        throw HarnessError.message("No active conversation.")
      }
      saved.conversation.messages.append(ChatMessage(role: "user", text: trimmed))
      persist()
      let result = try await client.request(
        "turn/start",
        params: .object([
          "threadId": .string(threadID),
          "input": .array([
            .object([
              "type": .string("text"), "text": .string(trimmed), "text_elements": .array([]),
            ])
          ]),
        ]))
      // Completion can arrive before the request continuation is scheduled.
      if busy { turnID = result["turn"]["id"].string }
    } catch {
      busy = false
      activity = ""
      turnID = nil
      self.error = error.localizedDescription
      persist()
    }
  }

  func stopTurn() async {
    guard let threadID = saved.conversation.threadID, let turnID else { return }
    activity = "Stopping"
    do {
      _ = try await client.request(
        "turn/interrupt",
        params: .object([
          "threadId": .string(threadID), "turnId": .string(turnID),
        ]))
    } catch {
      self.error = error.localizedDescription
      activity = "Stop failed"
    }
  }

  var canStop: Bool { busy && turnID != nil }

  func newConversation() {
    guard !busy else { return }
    // Keep previous local transcripts, even though this first UI shows only the active one.
    do {
      if !saved.conversation.messages.isEmpty {
        let archive = root.appendingPathComponent("Conversations/\(UUID().uuidString)")
        try StateStore(directory: archive).save(saved)
      }
      saved.conversation = Conversation()
      resumed = false
      error = nil
      persist()
    } catch { self.error = error.localizedDescription }
  }

  func updateProfile(_ profile: AgentProfile) {
    guard !busy else { return }
    saved.profile = profile
    resumed = false  // Reapply developer instructions on the next resume.
    persist()
  }

  func persist() {
    saveTask?.cancel()
    guard storageAvailable else { return }
    do { try store.save(saved) } catch {
      self.error = "Could not save the conversation: \(error.localizedDescription)"
    }
  }

  func shutdown() {
    if busy { saved.conversation.lastTurnStatus = "interrupted" }
    persist()
    client.stop()
  }

  private func receive(_ method: String, _ params: JSONValue) {
    if method == "account/login/completed" {
      loginPending = false
      loginID = nil
      if params["success"].bool != true {
        error = params["error"].string ?? "Sign-in did not complete."
      }
      Task { try? await refreshAccount() }
      return
    }
    if method == "account/updated" {
      Task { try? await refreshAccount() }
      return
    }
    if method == "harness/unsupportedRequest" {
      error =
        "The agent requested a tool this first harness does not support. Nothing was approved."
      return
    }
    guard params["threadId"].string == saved.conversation.threadID else { return }
    switch method {
    case "turn/started":
      turnID = params["turn"]["id"].string
    case "item/agentMessage/delta":
      guard let id = params["itemId"].string, let delta = params["delta"].string else { return }
      saved.conversation.appendDelta(itemID: id, text: delta)
      activity = "Replying"
      saveTask?.cancel()
      saveTask = Task { [weak self] in
        do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
        self?.persist()
      }
    case "item/completed":
      let item = params["item"]
      if item["type"].string == "agentMessage", let id = item["id"].string,
        let text = item["text"].string
      {
        saved.conversation.completeMessage(itemID: id, text: text)
        persist()
      }
    case "turn/completed":
      busy = false
      turnID = nil
      activity = ""
      saved.conversation.lastTurnStatus = params["turn"]["status"].string
      if params["turn"]["status"].string == "failed" {
        error = params["turn"]["error"]["message"].string ?? "The reply failed. Try again."
      }
      persist()
    case "error":
      error = params["error"]["message"].string ?? "The agent encountered an error."
    default: break
    }
  }
}
