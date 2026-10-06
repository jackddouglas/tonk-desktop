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

## Use

1. Click **Sign in to Tonk** and sign in with your passkey in the browser.
2. Open a space, then click **New chat** to work with an agent alongside it.
3. Open **Settings…** to choose ChatGPT, an API provider, or a local model.

ChatGPT sign-in requires the [Codex CLI](https://learn.chatgpt.com/docs/cli).

Chats and drafts stay on your Mac. Messages are sent to your selected model provider,
and API keys are stored in macOS Keychain.

For **Claude subscription**, install [Claude Code](https://code.claude.com/docs/en/setup),
select it in Settings, and use **Sign in with Claude**. Tonk uses the CLI's existing
subscription login and keeps credentials in Claude Code. Leave Model blank for its
default, or enter an alias such as `sonnet` or `opus`. `TONK_CLAUDE` can select an
executable when it isn't discovered automatically. Anthropic API-key access remains
a separate provider.
