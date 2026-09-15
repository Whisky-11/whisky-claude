# Whisky Claude

> A native macOS companion for [Claude Code](https://claude.com/claude-code). **Clawd**, the Claude Code pixel pet, lives beside the notch on your MacBook — it idles when nothing's happening, hunches over a laptop and types while Claude is working, perks up when Claude needs your input, and celebrates when a task finishes. It also plays a sound when Claude needs your attention.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift 6](https://img.shields.io/badge/Swift-6-orange) ![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue)

> [!NOTE]
> **The mascot art ships with this repo** — clone and build and Clawd is there.
> As of v1.3.0 Whisky Claude is **AGPL-3.0**, not MIT. It moved licence
> specifically so the Clawd frames ([clawd-on-desk](https://github.com/rullerzhou-afk/clawd-on-desk),
> AGPL-3.0) could be distributed with the app instead of leaving everyone with an
> empty notch. See [NOTICE](NOTICE) for full attribution.

---

## What it does

When you run `claude` in any terminal — Terminal.app, iTerm, Warp, whatever — Whisky Claude reacts via Claude Code's hook system:

| Claude Code event | What happens |
|---|---|
| Working (Claude is thinking / running tools) | Clawd hunches over a laptop and **types** (cycling typing / thinking / debugging poses) |
| Notification (Claude needs your input) | Clawd switches to its **notification** pose + a dramatic spin/scale pop + **plays an attention sound** |
| Stop (Claude finished its turn) | Clawd does its **happy** pose + a celebratory bounce + **plays a done sound** |
| Idle | Clawd lives its life — paces between the left and right side of the notch and cycles through its idle repertoire (reading, juggling, sweeping, grooving…) |

Plus:

- **Slap the Mac** — a single hard desk-slap triggers "Open Claude in Terminal" (Settings → Voice → enable). On-device via SoundAnalysis; no audio is stored or transmitted.
- **"Hey Claude" / "Hey Whisky"** wake words — on-device via Apple's `Speech` framework. Audio never leaves your Mac.
- **Pick your own sounds** — Settings → General lets you replace the bundled attention + done audio with any local file (`.mp3` / `.wav` / `.m4a` / `.aiff` / `.caf`). Preview button next to each picker so you can audition before saving.
- **Keeps your Mac awake** so long-running Claude Code sessions don't get interrupted by system idle sleep. (Display sleep still respected.)
- **Menu bar icon** — static Claude logo; click for Open Terminal / Settings / Quit.

## Privacy

- **No network calls.** Everything runs locally.
- **Microphone audio** (used only when the slap trigger or wake-word recognizer is enabled — **both off by default**) is analyzed in-buffer via a shared audio session and immediately discarded. It is never saved to disk, never sent anywhere.
- **Claude Code hooks** write event payloads to `~/.claude/pet-events/`. Each event is consumed within milliseconds and deleted.
- Sandboxing intentionally disabled — needs to read `~/.claude/pet-events/` and post an `IOPMAssertion`.

## Install

```bash
git clone https://github.com/Whisky-11/whisky-claude.git
cd whisky-claude
./scripts/install.sh
```

The installer:
1. Builds the Release config and signs with a stable self-signed certificate if one is installed in your login keychain (falls back to ad-hoc otherwise — see [Persistent permissions](#persistent-permissions) below)
2. Detects a change of signing identity vs the previously-installed copy and resets stale TCC grants only when needed
3. Copies the app to `/Applications/Whisky Claude.app`
4. Installs the Claude Code hook helper to `~/.claude/scripts/wc-event.sh` — **unless [force-ai-foundation](https://github.com/ForceAI-KW/force-ai-foundation) already owns it** (see [Hook helper ownership](#hook-helper-ownership) below), in which case this step is skipped so the two installers can't silently overwrite each other
5. Wires the 4 hooks (`Stop`, `Notification`, `PreToolUse`, `UserPromptSubmit`) into `~/.claude/settings.json` — safely, preserving any other hooks you already have
6. Registers as a macOS Login Item so it auto-starts at login
7. Cleans up build artifacts so they don't appear as duplicate apps in Spotlight

### Hook helper ownership

`~/.claude/scripts/wc-event.sh` is a small shell script, not an app-specific file — if you also run [force-ai-foundation](https://github.com/ForceAI-KW/force-ai-foundation) (which installs its own `ops/wc-event.sh` to the same path as part of its general Claude Code hook tooling), **foundation owns that file**, not Whisky Claude. `./scripts/install.sh` detects this — an already-installed helper carrying a `# claude-hook:` declaration header, or a `force-ai-foundation` checkout on this machine — and skips writing to it rather than overwriting it, whichever installer happens to run last. Without this check, the "last installer wins" silently: an older copy overwriting a fixed one previously let an unbounded-growth log accumulate to 240MB of raw tool payloads.

If foundation is not present, `./scripts/install.sh` installs the bundled copy at `scripts/dot-claude/wc-event.sh` as before — same event JSON format written to `~/.claude/pet-events/`. That bundled copy is kept in sync with foundation's canonical version so a standalone install gets the same safe (metadata-only, size-capped) logging behaviour; see the comment at the top of `scripts/dot-claude/wc-event.sh` for how to refresh it.

### Persistent permissions (v1.2.0+)

By default `./scripts/install.sh` ad-hoc-signs the binary, which means every reinstall produces a new code signature — and macOS keys TCC grants (Accessibility, Microphone, Speech Recognition) to that signature. Result: you re-grant after every reinstall.

To make grants survive reinstalls, drop a stable self-signed code-signing certificate into your login keychain named **"Ahmad Sharaf Code Signing"** (rename to taste; just update the `SIGN_ID` variable in `scripts/install.sh` to match). One-time setup with OpenSSL + `security import`:

```bash
# 1. Generate a self-signed RSA key + cert (valid 10 years)
openssl req -x509 -newkey rsa:2048 -keyout codesign.key -out codesign.crt \
  -days 3650 -nodes -subj "/CN=Ahmad Sharaf Code Signing"
# 2. Bundle into PKCS#12
openssl pkcs12 -export -inkey codesign.key -in codesign.crt \
  -out codesign.p12 -passout pass:
# 3. Import into login keychain
security import codesign.p12 -k ~/Library/Keychains/login.keychain-db -P "" -T /usr/bin/codesign
# 4. Mark it trusted for code signing
security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
  -k "" ~/Library/Keychains/login.keychain-db
```

Once installed, every future `./scripts/install.sh` keeps the same Designated Requirement and your grants persist forever.

The installer also handles the migration: if you've already installed Whisky Claude with ad-hoc signing and then add a stable cert, the next install detects the DR change and calls `tccutil reset` for every relevant TCC bucket so you get one clean round of prompts. From then on, no more re-grants.

### Uninstall

Either:
- **From the app**: Menu bar icon → Settings → About → "Uninstall Whisky Claude…"
- **From the shell**: `./scripts/uninstall.sh`

Both paths walk through every install side-effect in reverse and back up `~/.claude/settings.json` before modifying it.

## Updating

Whisky Claude updates itself via [Sparkle](https://sparkle-project.org). It checks
for new versions in the background, and you can check anytime from the menu bar
icon → **Check for Updates…**. Toggle the background checks in Settings → General.
Updates are EdDSA-signed and install in place — no need to re-run the installer.

(The app is self-signed, not Apple-notarized, so only the *first* download is
Gatekeeper-quarantined — right-click → Open once. Updates after that are seamless.)

Maintainers: see [`docs/RELEASING.md`](docs/RELEASING.md) to cut a release.

## How it works

```
┌─ Claude Code session anywhere ──────────────────┐
│  Hook fires                                     │
│  (Stop / Notification / PreToolUse / UserPrompt)│
│                  │                              │
│                  ▼                              │
│  ~/.claude/scripts/wc-event.sh                  │
│  (writes event JSON atomically via mv)          │
│                  │                              │
│                  ▼                              │
│  ~/.claude/pet-events/<uuid>.json               │
└─────────────────────────────────────────────────┘
                   │
                   ▼
┌─ Whisky Claude ─────────────────────────────────┐
│  EventWatcher  (DispatchSource on the dir)      │
│       │                                         │
│       ▼                                         │
│  AttentionState.apply  →  NotificationCenter    │
│       │           │                │            │
│       ▼           ▼                ▼            │
│  MascotWindow  SoundPlayer    MenuBarIcon       │
│  .triggerBounce  .play            (static)      │
└─────────────────────────────────────────────────┘
```

The mascot is a borderless `NSPanel` at `statusBar` level, positioned using `NSScreen.builtIn.auxiliaryTopLeftArea`/`auxiliaryTopRightArea` so it reads real notch measurements, not guesses. It's `ignoresMouseEvents = true` so it never intercepts clicks, and constrained horizontally to the notch's outline so it never covers menu items in apps with long menu bars (Xcode, Logic, Final Cut).

More detail in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Requirements

- macOS 13 or later (tested on macOS 26)
- A MacBook with a notch is ideal; works on un-notched Macs too (mascot anchors to menu bar bottom)
- For wake words: microphone + Speech Recognition permission (macOS prompts on first use)
- **To open Terminal as a new tab in your existing window** (vs. a new window every time): Accessibility permission. The first time you click "Open Claude in Terminal" or say the wake word, Whisky Claude shows a one-shot dialog with a button that deep-links to System Settings → Privacy & Security → Accessibility. Without it, Terminal still opens — just as a new window. With ad-hoc signing the binary's signature changes on every reinstall (you'd re-grant each time); see [Persistent permissions](#persistent-permissions) above for the stable-cert setup that fixes this once and for all.

## Settings

Click the menu bar icon → **Settings…**

- **General** — toggle the mascot, sounds, "keep Mac awake", **and pick custom audio files** for attention + done events (with a one-click preview button)
- **Voice** — opt into wake words ("hey Claude" / "hey Whisky")
- **About** — version info, links, and the uninstall button

## Credits

Whisky Claude is a heavily modified fork of [**Notchy**](https://github.com/adamlyttleapps/notchy) by [Adam Lyttle](https://github.com/adamlyttleapps), licensed under MIT. Many architectural decisions (NSPanel-over-notch, status item ownership, SwiftUI hosted in AppKit) came from his work. The mascot, choreography, voice triggers, Claude Code integration, and uninstall flow are original.

The mascot is **Clawd**, the Claude Code pixel pet by Anthropic. The animation
frames come from [**clawd-on-desk**](https://github.com/rullerzhou-afk/clawd-on-desk)
(AGPL-3.0) and **are distributed with this repo** under that same licence — which is
why Whisky Claude is AGPL-3.0 rather than MIT. "Claude" and "Clawd" are trademarks of
Anthropic; this project is independent and not affiliated with or endorsed by them.

## Contributing

Bug reports + PRs welcome.

## License

[**AGPL-3.0**](LICENSE). Changed from MIT in v1.3.0 so the Clawd mascot art (AGPL-3.0) could ship with the app.

Upstream Notchy portions remain MIT © Adam Lyttle and are available under MIT from the upstream project — the notice is preserved in [NOTICE](NOTICE), along with mascot attribution and trademark notices.
