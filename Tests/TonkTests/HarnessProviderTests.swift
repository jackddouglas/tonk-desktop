import Foundation
import HarnessCore
import XCTest

@testable import Tonk

final class HarnessProviderTests: XCTestCase {
  @MainActor
  func testDisabledProviderPreventsRequestsAndPreservesConfiguration() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = APIModelClient { _, _, _ in
      XCTFail("Disabled chat must not issue a request")
      return APIMessage(role: "assistant", text: "unexpected")
    }
    let model = HarnessModel(directory: directory, apiClient: client)
    let local = ModelConnection(provider: .ollama, model: "test")
    try await model.configureProvider(.ollama, connection: local, key: "")
    XCTAssertTrue(model.canSend)
    try await model.configureProvider(
      .disabled, connection: ModelConnection(provider: .disabled), key: "")
    XCTAssertFalse(model.canSend)
    await model.send("Do not send this")
    XCTAssertTrue(model.saved.conversation.messages.isEmpty)
    XCTAssertEqual(model.saved.connections?["ollama"], local)
    let reopened = HarnessModel(directory: directory)
    await reopened.connect()
    XCTAssertEqual(reopened.provider, .disabled)
    XCTAssertFalse(reopened.canSend)
  }

  @MainActor
  func testLocalAgentProposalPersistsAndSwitchArchivesWithoutForwardingHistory() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "provider-test-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var requests = 0
    let client = APIModelClient { request, _, delta in
      requests += 1
      let body = try JSONDecoder().decode(JSONValue.self, from: request.httpBody!)
      if requests == 1 {
        return APIMessage(
          role: "assistant",
          calls: [
            APIToolCall(
              id: "proposal", name: "tonk_propose_space",
              arguments: .object([
                "name": .string("Local model test"), "reason": .string("Keep a shared checklist"),
              ]))
          ])
      }
      XCTAssertEqual(body["messages"].array.last?["role"].string, "tool")
      XCTAssertTrue(body["messages"].array.last?["content"].string?.contains("true") == true)
      delta("Your proposal is ready.")
      return APIMessage(role: "assistant", text: "Your proposal is ready.")
    }
    let model = HarnessModel(directory: directory, apiClient: client)
    let connection = ModelConnection(provider: .local, model: "fixture-model")
    try await model.configureProvider(.local, connection: connection, key: "")
    XCTAssertTrue(model.canSend)
    await model.send("Make a checklist")
    await model.apiTask?.value
    XCTAssertNil(model.error)
    XCTAssertFalse(model.busy)
    XCTAssertEqual(requests, 2)
    XCTAssertEqual(model.saved.conversation.spaceProposal?.name, "Local model test")
    XCTAssertEqual(
      model.saved.conversation.messages.map(\.text),
      ["Make a checklist", "Your proposal is ready."])
    let reopened = HarnessModel(directory: directory)
    XCTAssertEqual(reopened.saved, model.saved)
    XCTAssertEqual(
      reopened.saved.conversation.apiHistory?.map(\.role),
      ["user", "assistant", "tool", "assistant"])
    var changed = connection
    changed.model = "another-fixture"
    try await model.configureProvider(.local, connection: changed, key: "")
    XCTAssertTrue(model.saved.conversation.messages.isEmpty)
    XCTAssertNil(model.saved.conversation.apiHistory)
    XCTAssertNil(model.saved.conversation.spaceProposal)
    let original = try XCTUnwrap(
      model.saved.sessions?.first { $0.id == reopened.saved.activeSessionID })
    XCTAssertEqual(original.conversation, reopened.saved.conversation)
    XCTAssertEqual(original.connection, connection)

  }

  @MainActor
  func testProviderChangeIsRejectedWhileBusyAndHiddenContinuationStaysHidden() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "provider-test-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = APIModelClient { request, _, delta in
      let body = try JSONDecoder().decode(JSONValue.self, from: request.httpBody!)
      XCTAssertEqual(body["messages"].array.last?["content"].string, "Continue in the new space")
      delta("Continuing.")
      return APIMessage(role: "assistant", text: "Continuing.")
    }
    let model = HarnessModel(directory: directory, apiClient: client)
    let connection = ModelConnection(provider: .local, model: "fixture-model")
    try await model.configureProvider(.local, connection: connection, key: "")
    model.busy = true
    do {
      try await model.configureProvider(
        .chatGPT, connection: ModelConnection(provider: .chatGPT), key: "")
      XCTFail("Changed while busy")
    } catch {}
    XCTAssertEqual(model.provider, .local)
    model.busy = false
    await model.send("Continue in the new space", showsUserMessage: false)
    await model.apiTask?.value
    XCTAssertEqual(model.saved.conversation.messages.map(\.role), ["assistant"])
    XCTAssertEqual(model.saved.conversation.apiHistory?.first?.text, "Continue in the new space")
  }
}
