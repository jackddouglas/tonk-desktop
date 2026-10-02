import Foundation
import XCTest

@testable import HarnessCore

final class TonkAuthorizationTests: XCTestCase {
  func testDeploymentsRejectEachOthersAuthorization() throws {
    XCTAssertNoThrow(
      try TonkAuthorization(
        data: payload(remote: "https://staging.tonk.xyz/ucan/"), deployment: .staging))
    XCTAssertThrowsError(try TonkAuthorization(data: payload(), deployment: .staging))
    XCTAssertThrowsError(
      try TonkAuthorization(
        data: payload(remote: "https://staging.tonk.xyz/ucan/"), deployment: .production))
    XCTAssertFalse(
      RuntimeLocation.isEmbedded(URL(string: "https://tonk.network")!, deployment: .staging))
    XCTAssertFalse(
      RuntimeLocation.isEmbedded(URL(string: "https://staging.tonk.xyz")!, deployment: .production))
    XCTAssertNotEqual(
      RuntimeLocation.Deployment.staging.dataDirectory,
      RuntimeLocation.Deployment.production.dataDirectory)
  }
  private func payload(remote: String = "https://tonk.network/ucan/", delegation: String = "00aAFF")
    throws -> Data
  {
    try JSONSerialization.data(withJSONObject: [
      "delegationHex": delegation, "credentialId": "test-credential",
      "remote": remote, "attachmentId": "test-attachment",
    ])
  }

  func testAcceptsTonkCallbackWithTrailingSlash() throws {
    let remote = "https://tonk.network/ucan/"
    // Foundation's URL.path drops this slash; compare URLComponents instead.
    XCTAssertEqual(URL(string: remote)?.path, "/ucan")
    let grant = try TonkAuthorization(data: payload(remote: remote))
    XCTAssertEqual(grant.remote, remote)
    XCTAssertEqual(grant.delegation, "00aAFF")
    XCTAssertEqual(grant.credential, "test-credential")
    XCTAssertNoThrow(try TonkAuthorization(data: payload(remote: "https://tonk.network/ucan")))
  }

  func testRejectsOtherDestinationsAndMalformedGrantsWithoutEchoingSecrets() throws {
    for remote in [
      "http://tonk.network/ucan/", "https://evil.example/ucan/",
      "https://tonk.network.evil.example/ucan/", "https://user@tonk.network/ucan/",
      "https://tonk.network:444/ucan/", "https://tonk.network/other/",
      "https://tonk.network/ucan/?secret=private", "https://tonk.network/ucan/#private",
      "https://tonk.network/%75can/",
    ] {
      XCTAssertThrowsError(try TonkAuthorization(data: payload(remote: remote))) { error in
        XCTAssertFalse(error.localizedDescription.contains("private"))
      }
    }
    for delegation in ["", "abc", "secret", "ＦＦ"] {
      XCTAssertThrowsError(try TonkAuthorization(data: payload(delegation: delegation)))
    }
    XCTAssertThrowsError(try TonkAuthorization(data: Data("{}".utf8)))
    XCTAssertThrowsError(try TonkAuthorization(data: Data("private invalid JSON".utf8))) { error in
      XCTAssertFalse(error.localizedDescription.contains("private"))
    }
  }
}
