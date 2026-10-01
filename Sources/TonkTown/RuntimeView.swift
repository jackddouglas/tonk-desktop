import AppKit
import HarnessCore
import SwiftUI
import WebKit

@MainActor
final class RuntimeModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
  @Published var loading = true
  @Published var error: String?
  @Published var ready = false
  let webView: WKWebView

  override init() {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .default()
    configuration.limitsNavigationsToAppBoundDomains = true
    webView = WKWebView(frame: .zero, configuration: configuration)
    super.init()
    webView.navigationDelegate = self
    webView.uiDelegate = self
    webView.isInspectable = true
  }

  func load() {
    loading = true
    error = nil
    ready = false
    webView.load(URLRequest(url: RuntimeLocation.home))
  }

  func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    loading = true
    error = nil
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    loading = false
  }

  func webView(
    _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    fail(error)
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    fail(error)
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    loading = false
    ready = false
    error = "The Tonk runtime stopped. Reload to reconnect."
  }

  private func fail(_ failure: Error) {
    if (failure as NSError).code == NSURLErrorCancelled { return }
    loading = false
    ready = false
    error = failure.localizedDescription
  }

  func webView(
    _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    guard let url = navigationAction.request.url else {
      decisionHandler(.cancel)
      return
    }
    // The Tonk renderer owns its sandboxed guest frames; restrict top-level navigation only.
    if navigationAction.targetFrame?.isMainFrame == false {
      decisionHandler(.allow)
      return
    }
    if RuntimeLocation.isEmbedded(url) {
      decisionHandler(.allow)
      return
    }
    if navigationAction.navigationType == .linkActivated && RuntimeLocation.isExternal(url) {
      NSWorkspace.shared.open(url)
    }
    decisionHandler(.cancel)
  }

  func webView(
    _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
    for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
  ) -> WKWebView? {
    if let url = navigationAction.request.url, RuntimeLocation.isExternal(url) {
      NSWorkspace.shared.open(url)
    }
    return nil
  }

  /// Read-only probe; there is no JavaScript-to-native privileged bridge.
  func probe() async throws -> [String: Any] {
    let result = try await webView.callAsyncJavaScript(
      """
      const controlled = !!navigator.serviceWorker?.controller;
      let health = false;
      if (controlled) {
          try {
              const response = await fetch('/api/health', {signal: AbortSignal.timeout(4000)});
              const type = response.headers.get('content-type') || '';
              health = response.ok && type.includes('json');
          } catch {}
      }
      const site = document.querySelector('tonk-site');
      const frame = site?.querySelector('iframe') || site?.shadowRoot?.querySelector('iframe');
      const mounted = !!frame && frame.getBoundingClientRect().width > 0;
      return { serviceWorker: 'serviceWorker' in navigator, controlled, mounted,
               health, title: document.title, url: location.origin + location.pathname,
               bodyCharacters: document.body?.innerText.length || 0 };
      """, arguments: [:], in: nil, contentWorld: .page)
    let value = result as? [String: Any] ?? [:]
    ready = value["health"] as? Bool == true && value["mounted"] as? Bool == true
    return value
  }
}

struct RuntimeView: NSViewRepresentable {
  @ObservedObject var model: RuntimeModel
  func makeNSView(context: Context) -> WKWebView { model.webView }
  func updateNSView(_ nsView: WKWebView, context: Context) {}
}
