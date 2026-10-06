import SwiftUI

struct TonkWelcomeView: View {
  @ObservedObject var runtime: RuntimeModel
  var body: some View {
    VStack(spacing: 24) {
      Spacer()
      Image(systemName: "square.grid.2x2").font(.system(size: 48, weight: .light))
        .foregroundStyle(.secondary)
      VStack(spacing: 12) {
        Text("Welcome to Tonk Town").font(.largeTitle.weight(.semibold))
        Text("Your spaces, with a chat to help you build.")
          .font(.title3).foregroundStyle(.secondary)
      }
      VStack(spacing: 14) {
        if runtime.signInPending {
          ProgressView(
            runtime.attachingAccount
              ? "Connecting your account…" : "Finish signing in in your browser")
          Button("Cancel") { runtime.cancelSignIn() }.disabled(runtime.attachingAccount)
        } else if runtime.loading
          || !runtime.catalogLoaded && runtime.catalogError == nil && runtime.error == nil
        {
          ProgressView("Connecting to Tonk…")
        } else {
          Button("Sign in to Tonk", systemImage: "person.crop.circle.badge.checkmark") {
            Task { await runtime.signIn() }
          }.nativeControl().controlSize(.large)
            .disabled(runtime.loading)
          Text(
            "Use your existing Tonk passkey in your browser.\nYou’ll return here when sign-in is complete."
          )
          .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        if let message = runtime.accountMessage ?? runtime.error ?? runtime.catalogError {
          Text(message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
          if !runtime.signInPending { Button("Try again") { runtime.load() } }
        }
      }.frame(maxWidth: 430)
      Spacer()
      Text("Choose ChatGPT, an API provider, or a local model when you start chatting.")
        .font(.caption).foregroundStyle(.secondary).padding(.bottom, 28)
    }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity).background(.background)
  }
}
