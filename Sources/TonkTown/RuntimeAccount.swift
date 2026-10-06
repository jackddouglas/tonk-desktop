import AppKit
import HarnessCore
import WebKit

@MainActor
extension RuntimeModel {
  func signOut() async throws {
    guard accountConnected, !signInPending, !catalogLoading else {
      throw CallbackError("Wait for the current account operation to finish.")
    }
    catalogTask?.cancel()
    stopMCPBridge()
    _ = try await accountScript(Self.signOutScript)
    accountConnected = false
    accountMessage = nil
    selectedSpace = nil
    spaces = []
    catalogBranch = nil
    catalogLoaded = false
    catalogError = nil
    error = nil
    webView.load(URLRequest(url: RuntimeLocation.home))
  }

  static let signOutScript = """
    // This route unlinks this device; it does not delete the Tonk account.
    const response = await fetch('/api/account', {
      method: 'DELETE', signal: AbortSignal.timeout(60000)
    });
    if (!response.ok) throw new Error('Tonk sign-out failed (HTTP ' + response.status + ').');
    const account = await api('/api/account');
    if (!['rootMissing', 'unregistered'].includes(account.status))
      throw new Error('A Tonk account is still active. Refresh before trying again.');
    return {signedOut: true};
    """

  func cancelSignIn() { callback?.cancel() }

  func signIn() async {
    guard RuntimeLocation.deployment != .local else {
      accountMessage = "The local test runtime uses local-only spaces."
      return
    }
    guard !signInPending else { return }
    signInPending = true
    accountMessage = nil
    let handoff = BrowserCallback()
    callback = handoff
    defer {
      handoff.cancel()
      callback = nil
      signInPending = false
      attachingAccount = false
    }
    do {
      let identity = try await accountScript(
        """
        const root = await api('/api/identity/root');
        const account = await api('/api/account');
        if (!root.deviceDid) throw new Error('The runtime did not return a device identity.');
        return {deviceDid: root.deviceDid, rootDid: root.rootDid || '', status: account.status};
        """)
      guard let device = identity["deviceDid"] as? String else {
        throw CallbackError("The Tonk runtime is not ready. Reload and try again.")
      }
      if identity["status"] as? String == "registered" {
        accountConnected = true
        accountMessage = "Your Tonk account is connected."
        return
      }
      let callbackURL = try await handoff.start()
      var url = URLComponents(
        url: RuntimeLocation.home.appendingPathComponent("settings/link"),
        resolvingAgainstBaseURL: false)!
      url.queryItems = [
        URLQueryItem(name: "audience", value: device),
        URLQueryItem(name: "callback", value: callbackURL.absoluteString),
        URLQueryItem(name: "name", value: "Tonk Town"),
      ]
      if let root = identity["rootDid"] as? String, !root.isEmpty {
        url.queryItems?.append(URLQueryItem(name: "expectedAccount", value: root))
      }
      guard let authURL = url.url, NSWorkspace.shared.open(authURL) else {
        throw CallbackError("Couldn’t open your default browser.")
      }
      let data = try await handoff.receive()
      let grant = try TonkAuthorization(data: data)
      let delegation = grant.delegation
      let credential = grant.credential
      let remote = grant.remote
      attachingAccount = true
      // Values are structured arguments, never interpolated JavaScript. The worker checks the
      // signature, audience and root authority, and refuses an incompatible existing account.
      let result = try await accountScript(
        """
        const before = await api('/api/identity/root');
        if (before.deviceDid !== device || (before.rootDid || '') !== expectedRoot)
          throw new Error('The active Tonk profile changed during sign-in. Try again.');
        const root = await api('/api/identity/root', {credentialId: credential, delegationHex: delegation});
        if (root.status !== 'ready' || root.deviceDid !== device)
          throw new Error('The runtime did not accept the device authorization.');
        const account = await api('/api/account/attach', {
          provider: runtimeOrigin, rootDid: root.rootDid,
          credentialId: credential, delegationHex: delegation, remote
        });
        if (account.status !== 'registered' || account.deviceDid !== device)
          throw new Error('Tonk accepted the device grant but account setup is incomplete. Try signing in again.');
        return {status: account.status};
        """,
        arguments: [
          "device": device, "expectedRoot": identity["rootDid"] ?? "",
          "credential": credential, "delegation": delegation, "remote": remote,
        ])
      if result["status"] as? String == "registered" {
        accountConnected = true
        accountMessage = "Your Tonk account is connected."
        webView.reload()
        NSApp.activate(ignoringOtherApps: true)
      }
    } catch is CancellationError {
      accountMessage = "Tonk sign-in cancelled."
    } catch {
      let message =
        (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String
        ?? error.localizedDescription
      accountMessage = "Couldn’t connect Tonk: \(message)"
    }
  }

  func accountScript(_ script: String, arguments: [String: Any] = [:]) async throws
    -> [String: Any]
  {
    guard let url = webView.url, RuntimeLocation.isEmbedded(url) else {
      throw CallbackError("Open the Tonk runtime before signing in.")
    }
    let result = try await webView.callAsyncJavaScript(
      """
      if (location.origin !== runtimeOrigin || !navigator.serviceWorker?.controller)
        throw new Error('The Tonk worker is not ready. Reload and try again.');
      async function api(path, body) {
        if (runtimeOrigin === 'http://127.0.0.1:4187' && path.startsWith('/api/profile/branch/'))
          path = path.replace('/api/profile/branch/', '/api/repository/profile:tonk/branch/');
        const response = await fetch(path, {
          method: body ? 'POST' : 'GET', headers: {'Content-Type': 'application/json'},
          body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(60000)
        });
        // Do not echo responses or grants into native diagnostics.
        if (!response.ok) throw new Error(path + ' failed (HTTP ' + response.status + ').');
        if (!(response.headers.get('content-type') || '').includes('json'))
          throw new Error('The installed Tonk runtime does not support ' + path + '.');
        return await response.json();
      }
      \(script)
      """,
      arguments: arguments.merging(["runtimeOrigin": RuntimeLocation.home.absoluteString]) {
        _, trusted in trusted
      }, in: nil, contentWorld: .page)
    guard let object = result as? [String: Any] else {
      throw CallbackError("Invalid runtime response.")
    }
    return object
  }
}
