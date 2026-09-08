# Security policy

## What Whisky Claude touches on your system

| Path | What | Reversible by uninstall? |
|---|---|---|
| `/Applications/Whisky Claude.app` | App bundle | yes |
| `~/.claude/settings.json` | Adds 4 hook entries; preserves anything else; timestamped backup created before modify | yes |
| `~/.claude/scripts/wc-event.sh` | Hook helper script | yes |
| `~/.claude/pet-events/` | IPC dir; transient JSON files (consumed + deleted within ms) | yes |
| `~/.claude/logs/wc-event.log` | Hook invocation log (timestamps + event types + raw hook payloads from Claude Code) | yes |
| macOS Login Item: "Whisky Claude" | Auto-launches the app on login | yes |
| `IOPMAssertion` (`kIOPMAssertPreventUserIdleSystemSleep`) | Held while the app runs; released on quit | yes (automatic) |
| `UserDefaults` for `com.ahmadsharaf.WhiskyClaude` | Settings persistence | yes |

Microphone access and Speech Recognition access are only requested when the user opts in via Settings → Voice. Both are off by default.

## Threat model

Whisky Claude assumes you trust the code in your `~/.claude/` directory — Claude Code itself, your custom hooks, etc. Its hook helper script is **only ever invoked by Claude Code as a hook**, and writes a small JSON envelope to a directory only the app reads.

The mascot window cannot be clicked through (it intentionally passes mouse events to whatever's underneath), so it can't be used as a phishing surface.

## What we don't do

- No network calls.
- No telemetry, no analytics, no crash reporting.
- No clipboard access.
- No keystroke logging.
- Audio buffers from the microphone are analyzed in-place by Apple's frameworks and discarded — they are never persisted or transmitted.
- Hook payloads from Claude Code (which may include conversation context as part of the `Stop` hook's `last_assistant_message`) are written to `~/.claude/logs/wc-event.log` for diagnostic visibility. The log file is under your home directory and is removed by the uninstaller. **If you are running Claude Code with confidential context and don't want hook payloads in the diagnostic log, disable the log line by editing `~/.claude/scripts/wc-event.sh` and removing the `printf ' payload: ...'` line.**

## Reporting a vulnerability

If you believe you've found a security issue, please open a private security advisory at https://github.com/Whisky-11/whisky-claude/security/advisories/new. Don't file it as a public issue.

We aim to acknowledge within a few days. For low-severity issues a regular PR is fine.

## Verifying a build

The Release build is ad-hoc codesigned (`codesign -s -`). This is enough for macOS to launch it from `/Applications`, but it's **not** a Developer ID signature — the app isn't notarized.

If you want to verify what you're running matches the source:

```bash
# Confirm the bundle's signature is ad-hoc (not signed by an unrelated cert)
codesign -dv "/Applications/Whisky Claude.app" 2>&1 | grep -E "Authority|Identifier"
# Should print:  Identifier=com.ahmadsharaf.WhiskyClaude  Authority=(no value — ad-hoc)

# Recompute the bundle hash from your own source clone
cd /path/to/your/whisky-claude/clone
./scripts/install.sh   # build + install — outputs the same bundle the repo produces
```

If you don't trust the binary, build from source. That's the supported path.
