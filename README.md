# Tonk Town

A small native Mac harness: one personal agent beside the live Tonk runtime.
SwiftUI owns the conversation and personality editor. Codex app-server owns
ChatGPT authentication and inference. WKWebView runs Tonk's existing web app.

## Run

Requires macOS 14+, Xcode command-line tools with Swift 5.9+, and the
[Codex CLI](https://learn.chatgpt.com/docs/cli). Developed with Swift 6.4 and
Codex CLI 0.159.3. No Swift package dependencies.

```sh
bash scripts/build-app.sh
open ".build/Tonk Town.app"
```

Use the app bundle: `swift run` does not include the Info.plist configuration
that enables Tonk's service-worker domain in the embedded web view.

1. Click **Sign in with ChatGPT** and complete authentication in your browser.
2. Send a message to Robin. Use the person button to edit the name and personality.
3. Quit and reopen to continue the same conversation.
4. Find a space in the native right-hand list and open it in the Tonk runtime.
   **All spaces** returns to the picker; refresh reloads the catalog.
5. **Sign in to Tonk** opens the default browser for passkey approval and returns
   a device grant to the embedded worker. Account sign-in, space-list hydration,
   and persistence after reopening are verified; see
   the current plan.

The CLI is discovered at `/opt/homebrew/bin/codex`, `/usr/local/bin/codex`, or
`~/.nix-profile/bin/codex`. To select another binary, launch the bundled
executable from a terminal with `TONK_TOWN_CODEX=/absolute/path/to/codex`.

## First increment

- Streaming native chat, stop, errors, and reconnect.
- Editable local agent personality, applied on the next message.
- Transcript persistence and Codex thread resumption across launches.
- New conversation archives the previous local transcript.
- Browser ChatGPT login and cancellation, with an isolated Codex profile.
- Interactive hosted Tonk runtime with persistent web storage and reload.

The agent cannot yet inspect or modify the Tonk pane. Shell tools, web search,
and multi-agent execution are disabled; unsupported server requests are
declined. Native space navigation is implemented; Tonk CLI tools and the
shared-space round trip are next.

Tonk assets load from `https://tonk.network`; they are not bundled from the
neighboring Rust checkout. The embedded web profile is separate from Safari
and from the CLI's replica and identity. Browser-assisted Tonk sign-in is verified. In-app passkey ceremonies, CLI sync,
offline startup, and collaboration remain unverified.

## Local data

`~/Library/Application Support/Tonk Town/` contains:

- `state.json`: active transcript and personality.
- `Conversations/`: archived transcripts created by New conversation.
- `Codex/`: this app's Codex profile, credentials, and server threads.
- `Workspace/`: the agent's otherwise empty working directory.

Credentials are handled by Codex and never copied from the developer's existing
profile. Native transcripts are local files, not encrypted by this app, and
sent messages go to the authenticated model provider. WebKit manages Tonk's
persistent browser storage separately. The app exposes no privileged native
message handler to web content.

This is a local experiment using app-server authentication. Review the
[Sign in with ChatGPT requirements](https://developers.openai.com/siwc) before
commercial distribution; app-server authentication is not a commercial or
hosted-service integration.

## Verify

```sh
swift test
bash scripts/build-app.sh
bash scripts/smoke.sh
git diff --check
```

The native smoke test opens the built app with an isolated, signed-out agent
profile. It checks app-server initialization plus an active Tonk service worker,
JSON health response, mounted Tonk iframe, and loaded native space catalog. Reports stay in ignored
`artifacts/smoke.*/report.json`. WebKit data remains the app's regular web store.
No model call or credential is needed for this test.

Manual integration checks: sign in, receive a real response, stop a reply,
reopen and ask about the previous conversation, edit the personality, and
interact with the embedded runtime.

## Code map

- `HarnessCore/AppServerClient.swift`: bounded JSON-line process transport,
  initialization, timeouts, disconnect handling, and unsupported requests.
- `HarnessCore/Conversation.swift`: local state, message assembly, personality,
  and URL boundaries.
- `TonkTown/HarnessModel.swift`: authentication and conversation lifecycle.
- `TonkTown/RuntimeView.swift`: persistent, app-bound WebKit runtime.
- `TonkTown/ContentView.swift`: native chat and personality UI.

Protocol shape was checked against `codex app-server generate-json-schema` from
the installed CLI. Reference: [Codex app-server](https://learn.chatgpt.com/docs/app-server).
