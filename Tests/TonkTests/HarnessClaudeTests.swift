import Foundation
import HarnessCore
import XCTest

@testable import Tonk

@MainActor
final class HarnessClaudeTests: XCTestCase {
  func testClaudeStreamsAndRecoversExpiredLoginWithoutUsingAPIClient() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let executable = directory.appendingPathComponent("claude")
    try """
    #!/usr/bin/python3
    import sys,json
    if sys.argv[1:3] == ['auth','status']:
        print(json.dumps({'loggedIn':True,'authMethod':'claude.ai'}),flush=True)
    else:
        prompt=sys.stdin.read()
        if prompt == 'expired':
            print(json.dumps({'type':'result','subtype':'error_during_execution','is_error':True,'errors':['Failed to authenticate: OAuth session expired']}),flush=True)
        else:
            print(json.dumps({'type':'assistant','message':{'id':'fixture','content':[{'type':'text','text':'Claude response'}]}}),flush=True)
            print(json.dumps({'type':'result','subtype':'success','is_error':False}),flush=True)
    """.write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    let api = APIModelClient { _, _, _ in
      XCTFail("Claude subscription must not call the API-key client")
      return APIMessage(role: "assistant")
    }
    let model = HarnessModel(
      directory: directory, apiClient: api, claudeClient: ClaudeCodeClient(executable: executable))
    defer { model.shutdown() }
    try await model.configureProvider(
      .claude, connection: ModelConnection(provider: .claude), key: "")
    XCTAssertTrue(model.canSend)
    await model.send("hello")
    await model.apiTask?.value
    XCTAssertEqual(model.saved.conversation.lastTurnStatus, "completed")
    XCTAssertEqual(model.saved.conversation.claudeSessionStarted, true)
    XCTAssertTrue(model.saved.conversation.messages.contains { $0.text == "Claude response" })
    model.newConversation()
    await model.send("expired")
    await model.apiTask?.value
    XCTAssertFalse(model.signedIn)
    XCTAssertNil(model.saved.conversation.threadID)
    XCTAssertEqual(model.saved.conversation.lastTurnStatus, "failed")
    XCTAssertTrue(model.error?.contains("Sign in with Claude") == true)
    try await model.configureProvider(
      .disabled, connection: ModelConnection(provider: .disabled), key: "")
    XCTAssertFalse(model.canSend)
  }
}
