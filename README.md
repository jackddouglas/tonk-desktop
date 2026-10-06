# Tonk

A native Mac workspace for Tonk spaces and chat.
SwiftUI owns the space grid, conversations, and chat history. ChatGPT uses Codex app-server;
API-key providers and localhost models use a direct streaming agent loop.
WKWebView runs Tonk's existing web app.

## Run

Requires macOS 15+ and full Xcode 26+ with Swift 6.0+ and Icon Composer.
ChatGPT subscription sign-in also requires the
[Codex CLI](https://learn.chatgpt.com/docs/cli); API providers do not. Developed with Swift 6.4 and
Codex CLI 0.159.3. Markdown rendering and native drag selection use Textual; SwiftPM resolves its dependencies.

```sh
bash scripts/build-app.sh
open ".build/Tonk.app"
```

The build compiles `Resources/Tonk.icon` into the native layered app icon and
an `.icns` fallback. Its vector circles reproduce the colors and proportions of
`rust/tonk-ui/assets/images/tonk-icon.png` in the Tonk monorepo: raspberry
`#AA2659`, blue `#71BBE7`, and yellow `#D9E020`. Edit the layers in Icon Composer.

Local builds use the single available **Apple Development** signing identity.
For multiple identities, set `TONK_TOWN_SIGN_IDENTITY` to the desired certificate
fingerprint. A stable signature lets macOS retain WebKit Keychain authorization
across rebuilds. Switching from an older ad-hoc build can still require one
approval. Explicit `TONK_TOWN_SIGN_IDENTITY=-` builds remain available but may
prompt again after executable changes. No Keychain items or access rules are
changed by the build script. See [Apple's signing identity explanation](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).

Use the app bundle: `swift run` does not include the Info.plist configuration
that enables Tonk's service-worker domain in the embedded web view.

1. On first launch, **Sign in to Tonk** opens your browser to use your existing
   Tonk passkey. The app accepts the device grant and opens your space grid.
   If already signed in, the app opens directly to the grid.
2. Open a space to see its content filling the window. **New chat**,
   **Chat history**, and **Show chat** controls are in the glass window toolbar. **New chat** opens a fresh
   chat alongside it; **Show chat** reveals the most recent conversation.
3. Use **Settings…** in the Tonk menu to choose ChatGPT subscription sign-in,
   an API-key provider, or a local model. ChatGPT sign-in remains a separate step.
4. **New chat** starts a separate conversation in the current space. **Chat history**
   lists only that space's conversations and offers **New chat**. Chat history is
   available inside a space, with no global history screen. Older unassigned chats
   remain preserved in local storage.
5. Chats remember their model configuration, tool history, and unsent draft.
   They are stored locally on this Mac; they are not shared space records or synced chats.
6. **All spaces** returns to the grid. Opening a different space changes to that
   space's chat; individual chats cannot query other spaces.

Existing conversations and archived transcripts are imported without deleting or
rewriting their original archive files. Legacy profile data is preserved for
compatibility, but personality editing and personalized agent instructions are removed.

The CLI is discovered at `/opt/homebrew/bin/codex`, `/usr/local/bin/codex`, or
`~/.nix-profile/bin/codex`. To select another binary, launch the bundled
executable from a terminal with `TONK_TOWN_CODEX=/absolute/path/to/codex`.

## Model providers

Open **Settings…** in the Tonk menu (or press **Command-comma**).
The model pill above chat and **More → Model settings…** open the same sheet.
Keep ChatGPT subscription sign-in, or choose:

- **OpenAI API**: OpenAI API key and model ID, distinct from ChatGPT subscription sign-in.
- **Anthropic**: API key and model ID, using the Messages API.
- **Google Gemini**, **OpenRouter**, **Groq**, **Mistral**, or **Grok (xAI)**: API key and model ID.
- **Ollama**: a running local server (defaults to `http://localhost:11434/v1`) and an installed model ID.
- **Disabled**: browse spaces without sending chat requests; saved providers and chats are retained.
- **Local server**: an OpenAI-compatible streaming Chat Completions endpoint,
  such as `http://localhost:1234/v1` or `http://localhost:11434/v1`, and the model
  ID loaded by that server. The app connects to an existing server; it does not
  download models or launch the model server. Keys are optional.
- **Custom OpenAI-compatible**: a custom HTTPS base URL, model ID, and optional key.

Keys are stored in macOS Keychain, separately from transcripts, and scoped to the
provider and base URL. Leave the key blank to retain it; **Remove saved key** deletes
it. Changing endpoint clears an unsaved key entry. Remote endpoints require HTTPS;
HTTP is allowed only on loopback. Redirects are rejected rather than forwarding keys.

The chat header shows the active model ID for both ChatGPT and API providers.
ChatGPT settings list models from the live app-server catalog. API models stream
Markdown replies and use the same pinned Tonk tools as ChatGPT.
Models and their endpoints must support tool calling; text-only mode is not supported. Model IDs are
entered explicitly, since availability depends on the provider and account.
This first adapter supports text and function calling, not vision, provider-specific
reasoning modes, or model discovery. Compatibility with every model routed through
an OpenAI-compatible API is not assumed.

Changing provider, model, endpoint, or tool settings saves the conversation in history and
starts a fresh one, retaining its attached Tonk space. Earlier chat history is not
forwarded to the new provider. API conversation history and completed tool results
survive reopening. Interrupted tools are recorded as unknown outcomes and are not
replayed automatically. Stop cannot undo a write already submitted. Each turn is
limited to 24 model requests, with no automatic request retries.

Protocol fixtures and localhost HTTP tests cover both wire formats, streaming,
tool dispatch, cancellation, persistence, and switching. Real hosted-provider calls
and actual local model weights still require a live configuration to verify.

## First increment

- Streaming native chat, stop, errors, and reconnect.
- Selectable GitHub-flavored Markdown messages: tables, headings, nested and task
  lists, blockquotes, fenced code, links, images, and inline formatting. Wide tables
  and code blocks scroll horizontally. This does not add LaTeX math or executable HTML.
- Neutral chat with saved sessions and drafts per space.
- Transcript persistence and Codex thread resumption across launches.
- New chat retains previous sessions in native chat history.
- Browser ChatGPT login and cancellation, with an isolated Codex profile.
- Interactive hosted Tonk runtime with persistent web storage and reload.

New attached conversations can inspect space identity and branch names, list
named concepts and typed fields on `main`, rename with worker readback, and use
`tonk_inspect_view` to read the open preview's rendered text and control states.
Preview inspection includes bounded uncaught errors from nested sandboxed frames;
WebKit may redact error details. It is not a screenshot or an interaction test.
It accepts no target or JavaScript arguments and requires the attached space to
be open in the preview. Schema inspection includes runtime concepts, reports
truncation, and does not read records. Existing threads retain their original
tool set: open the space and start a **New chat** to get the schema tool. The native app fixes the
target; this is an application boundary using the signed-in worker, not a
separately delegated CLI identity. Tool activity is visible in the conversation.
Stop cancels pending responses, but cannot undo a write already submitted.

Shell tools, web search, and multi-agent execution are disabled; unsupported
server requests are declined. Scoped CLI record inspection, authoring, and sync are verified on staging;
shared collaboration remains future work.

Tonk assets load from `https://tonk.network`; they are not bundled from the
neighboring Rust checkout. The embedded web profile is separate from Safari
and from the CLI's replica and identity. Browser-assisted Tonk sign-in is verified. In-app passkey ceremonies, offline startup, and collaboration remain unverified.

## Local data

`~/Library/Application Support/Tonk Town/` contains:

- `state.json`: active transcript, per-space sessions, drafts, provider settings, and API tool history (no API keys).
- `Conversations/`: legacy archives imported into native chat history; original files are preserved.
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
No model call or credential is needed for this test. Pass `--inspect-space <DID>`
to additionally read an existing space through the same native tool adapter;
this uses the existing Tonk web session and does not mutate the space. Add
`--inspect-schema` to also check the fixed read-only schema query.

Manual integration checks: sign in, receive a real response, stop a reply,
reopen and ask about the previous conversation, switch between saved chats, and
interact with the embedded runtime.

## Code map

- `HarnessCore/AppServerClient.swift`: bounded JSON-line process transport,
  initialization, timeouts, disconnect handling, and unsupported requests.
- `HarnessCore/Conversation.swift`: local state, message assembly, legacy profile data,
  and URL boundaries.
- `TonkTown/HarnessModel.swift`: authentication and conversation lifecycle.
- `TonkTown/RuntimeView.swift`: persistent, app-bound WebKit runtime.
- `TonkTown/ContentView.swift`: native chat, onboarding, and space navigation.

Protocol shape was checked against `codex app-server generate-json-schema` from
the installed CLI. Reference: [Codex app-server](https://learn.chatgpt.com/docs/app-server).

## Isolated staging experiment

Quit Tonk, then launch the signed app against staging:

```sh
open '.build/Tonk.app' --args --staging
```

The window reads “Tonk — Staging”. It uses `staging.tonk.xyz`, a separate
persistent WebKit store, and `~/Library/Application Support/Tonk Town Staging`
for conversations, agent sign-in, and CLI replicas. Sign in directly to a
staging account and create a disposable staging space. Production grants are
rejected in this mode. Do not import production-backed spaces for this test.
Launching without `--staging` returns to the existing production profile.

Read-only staging verification:

```sh
bash scripts/smoke.sh --staging --inspect-worker
```

The CLI connection integration is still experimental.

When the assistant first uses a space tool that needs the CLI, the harness automatically
imports a scoped tool invitation into that profile's per-space state directory.
Existing connections and interrupted imports are reused. The assistant can use `tonk_cli` to read
notation/views/events guides, inspect schema and records, preview a document,
and apply an authorized edit with automatic sync. The tool cannot select a
shell, executable, filesystem path, other space, or invitation command. New
conversations receive new tool definitions; existing app-server threads retain
their original tool set.

The staging experiment has verified a real model-driven checklist edit in the
native runtime. The installed CLI currently emits an account-directory warning
for this isolated connection, even though content sync and rendering succeed.

The interactive authoring experiment verifies
model-built checkboxes and an agent refinement preserving a manual completion.
CLI schema/record reads now pull first and fail if synchronization fails, rather
than returning a stale local replica as current shared state.

## Native passkeys and cross-space chat

This version uses the existing browser passkey/device-grant flow. Direct in-app
passkeys are feasible in principle but deferred: Apple requires the app's
`webcredentials` associated-domain entitlement and a matching hosted AASA entry.
Tonk also needs both custody PRF outputs, not just a signed login assertion.
A native implementation needs a focused compatibility spike for those outputs,
credential providers, account import, and production/staging relying-party IDs.
See [Apple's passkey documentation](https://developer.apple.com/documentation/authenticationservices/supporting-passkeys).

Cross-space chat remains a separate proposed mode: explicitly selected spaces,
read-only bounded queries, and source labels on each result. It is not enabled by
opening chat history across spaces. Writes would continue to require a single
space-scoped conversation.

For isolated onboarding QA, pair `--data-dir /tmp/your-test-profile` with
`--web-data-id <UUID>` to isolate the WebKit account as well as native chat state.

### Focused space reads

`tonk_query` takes `{ "document": "…inline Tonk notation…" }` and forwards it
unchanged to the existing `evaluate?transact=false` endpoint. Neither the harness
nor an extra worker endpoint implements filtering or projection.

Read `tonk_space_schema` to find attribute domains. Concept queries return the
whole concept, including omitted fields. Domain queries return just the fields
written in the query. For example, after resolving one person record:

```yaml
test.issue:
  this: ?issue
  assignee: id:jack
  title: ?title
  status: "In progress"
```

Here `test.issue` and `id:jack` are fixture values, not defaults. Use actual schema
attribute domains and saved entity URIs. Quote literal strings: bare `jack` means
name resolution, not text. Resolve people separately before querying assignments;
an empty join can still return independent matches in other blocks. Query each
active status separately when needed and count distinct issue identities only
from complete results. No aggregate syntax is assumed.

The 2 MB worker response and 100 KB matches limits remain; oversized results fail
explicitly, never silently truncate. Original `{ "target": "concept" }` callers
still work. The short-lived host-side `fields`/`equals` arguments now return a
migration error. Start a new ChatGPT chat to receive the current tool schema.

For a real-worker regression, serve the existing runtime using
`scripts/serve-local-runtime.py`, then run `scripts/smoke-thin-query.js` through
an isolated browser as described in `scripts/local-build-smoke.md`. It verifies
person resolution, exact assignment/status filtering, projection of a 120 KB body,
zero matches, and unchanged revisions with zero committed claims.

### Signing out

The **More** menu in the title bar offers **Sign out of Tonk** and, when the
ChatGPT provider is signed in, **Sign out of ChatGPT**. These are separate accounts.
Tonk sign-out unlinks the app’s device through the existing account endpoint,
closes the space, and returns to onboarding. Local chat files and saved model keys
are retained; this is not account deletion. The external MCP bridge is stopped.

## Liquid Glass workspace

On macOS 26 and later, the window uses native Liquid Glass controls, with a
shared glass container for related actions, a floating glass composer, and
matching search fields. Earlier macOS versions use the existing material and
bordered-control fallbacks. Reduce Transparency uses an opaque custom surface.

The toolbar contains All spaces, Show/Hide chat, New chat, Chat history, Share,
and More. More contains Refresh, Open in browser, model settings and sign-out.
The current space title stays in the title bar.

Keyboard commands: Command-[ returns to spaces, Option-Command-0 toggles chat,
Command-N starts a chat, Shift-Command-H opens history, Command-F focuses the
visible search, Command-R refreshes, and Command-comma opens settings. In search,
Escape clears a query; with an empty query, Escape can dismiss the sheet.

