<p align="center">
  <img src="Resources/Tonk.png" width="180" alt="Tonk app icon">
</p>

<h1 align="center">Tonk</h1>

<p align="center">
  A native macOS workspace for Tonk spaces and agents.
</p>

## Build

Requires macOS 15 or later and full Xcode 26 or later with Swift 6 and Icon Composer.

```sh
swift test
bash scripts/build-app.sh
open .build/Tonk.app
```

For the experimental direct passkey flow on `tonk.network`, build with the
Tonk Labs signing identity and its Associated Domains provisioning profile:

```sh
TONK_SIGN_IDENTITY='Developer ID Application: Tonk Labs LTD (8WVKS2F24C)' \
TONK_PROVISIONING_PROFILE="$HOME/Downloads/Tonk_Desktop_Developer_ID.provisionprofile" \
  bash scripts/build-app.sh
```

Install that bundle in `~/Applications` before testing: macOS must discover the
installed app's domain association. The domain must serve an AASA file allowing
`8WVKS2F24C.xyz.tonk`. See [the passkey investigation](experiments/wk-passkey/README.md)
for the temporary association route and device-test evidence. Builds without a
profile keep browser sign-in. Live direct login and opening a restored space
passed in the integrated build. The native catalog now subscribes to worker
updates after background sync; automatic first-login restoration was confirmed
in the test build. The latest build adds visible restoration progress while
waiting for the initial spaces.

## Use

1. Click **Sign in to Tonk** and approve your passkey. Ordinary builds open the
   browser; provisioned builds use the system passkey sheet and offer
   **Sign in through browser** as a fallback.
2. Open a space, then click **New chat** to work with an agent alongside it.
3. Open **Settings…** to choose ChatGPT, an API provider, or a local model.

ChatGPT sign-in requires the [Codex CLI](https://learn.chatgpt.com/docs/cli).

Chats and drafts stay on your Mac. Messages are sent to your selected model provider,
and API keys are stored in macOS Keychain.

For **Claude subscription**, install [Claude Code](https://code.claude.com/docs/en/setup),
select it in Settings, and use **Sign in with Claude**. Tonk uses the CLI's existing
subscription login and keeps credentials in Claude Code. After sign-in, choose a
model from the CLI's model list or keep **Default from Claude Code**. `TONK_CLAUDE` can select an
executable when it isn't discovered automatically. Anthropic API-key access remains
a separate provider.
