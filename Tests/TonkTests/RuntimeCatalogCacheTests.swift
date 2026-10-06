import Foundation
import HarnessCore
import XCTest

@testable import Tonk

@MainActor
final class RuntimeCatalogCacheTests: XCTestCase {
  private func space() throws -> TonkSpace {
    try TonkSpace.decodeCatalog(Data("[{\"subject\":\"did:key:zABC\",\"name\":\"Cached space\"}]".utf8))[0]
  }

  func testCacheShowsCardsBeforeAnyWebNavigationWithoutClaimingLogin() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let writer = RuntimeModel()
    writer.prepareCatalogCache(directory: directory)
    try writer.acceptCatalog([space()], branch: "account/test", root: "did:key:account", status: "registered")
    let reader = RuntimeModel()
    reader.prepareCatalogCache(directory: directory)
    XCTAssertNil(reader.webView.url, "No runtime navigation is needed for the native cache")
    XCTAssertTrue(reader.showsSpacePicker)
    XCTAssertTrue(reader.showingCachedCatalog)
    XCTAssertEqual(reader.spaces.first?.title, "Cached space")
    XCTAssertFalse(reader.accountStatusKnown)
    XCTAssertFalse(reader.accountConnected)
  }

  func testEarlyClickWaitsForLiveMembershipAndRejectsAccountSwitch() async throws {
    for (sameAccount, member) in [(true, true), (false, true), (true, false)] {
      let runtime = RuntimeModel()
      let cached = try space()
      runtime.spaces = [cached]
      runtime.showingCachedCatalog = true
      runtime.cachedAccountRoot = "original"
      runtime.catalogLoaded = true
      var finished = false
      let opening = Task {
        let result = await runtime.spaceForOpening(cached)
        finished = true
        return result
      }
      for _ in 0..<100 {
        if runtime.pendingSpace != nil { break }
        await Task.yield()
      }
      XCTAssertNotNil(runtime.pendingSpace)
      XCTAssertFalse(finished)
      try runtime.acceptCatalog(member ? [cached] : [], branch: "main", root: sameAccount ? "original" : "other", status: "registered")
      let result = await opening.value
      XCTAssertEqual(result != nil, sameAccount && member)
      XCTAssertNil(runtime.pendingSpace)
    }
  }

  func testSignedOutResponseClearsSnapshotAndShowsOnboarding() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let runtime = RuntimeModel()
    runtime.prepareCatalogCache(directory: directory)
    try runtime.acceptCatalog([space()], branch: "main", root: "account", status: "registered")
    try runtime.acceptCatalog([], branch: "main", root: "", status: "rootMissing")
    XCTAssertTrue(runtime.accountStatusKnown)
    XCTAssertFalse(runtime.showsSpacePicker)
    let restarted = RuntimeModel()
    restarted.prepareCatalogCache(directory: directory)
    XCTAssertFalse(restarted.showingCachedCatalog)
  }

  func testCacheScopesAreIsolatedAndCorruptSnapshotIsIgnored() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = SpaceCatalogCache(directory: directory, scope: "remoteA|profileA")
    try first.save(.init(accountRoot: "root", branch: "main", spaces: [space()]))
    XCTAssertNotNil(first.load())
    XCTAssertNil(SpaceCatalogCache(directory: directory, scope: "remoteA|profileB").load())
    XCTAssertNil(SpaceCatalogCache(directory: directory, scope: "remoteB|profileA").load())
    let files = try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("SpaceCatalogs"), includingPropertiesForKeys: nil)
    try Data("corrupt".utf8).write(to: files[0])
    XCTAssertNil(first.load())
  }
}
