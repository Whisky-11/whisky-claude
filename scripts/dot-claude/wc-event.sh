#!/bin/bash
# --------------------------------------------------------------------
# SYNCED COPY — canonical source: ops/wc-event.sh in ForceAI-KW/force-ai-foundation
# (github.com/ForceAI-KW/force-ai-foundation). Used only for a STANDALONE Whisky
# Claude install (no force-ai-foundation checked out) — scripts/install.sh detects
# a foundation-managed ~/.claude/scripts/wc-event.sh and skips overwriting it, so
# whichever installer runs last no longer silently wins. Do not hand-edit; refresh
# with:
#   git -C ~/Desktop/projects/force-ai-foundation fetch origin
#   git -C ~/Desktop/projects/force-ai-foundation show origin/master:ops/wc-event.sh \
#     > scripts/dot-claude/wc-event.sh
# --------------------------------------------------------------------
# --------------------------------------------------------------------
# claude-hook declaration — read by ops/dead-gate-detect.sh, which fails the
# OS self-check if a declared hook is not actually registered in
# ~/.claude/settings.json. A shipped-but-unwired hook never fires and reads
# as coverage; ops/self-eval-gate.sh sat that way until 2026-09-04.
# claude-hook: Stop
# claude-hook: Notification
# claude-hook: PreToolUse
# claude-hook: UserPromptSubmit
# --------------------------------------------------------------------
# Whisky Claude hook helper — writes a pet-event JSON for WhiskyClaude.app
# to consume + logs every invocation to ~/.claude/logs/wc-event.log so the
# user can verify hooks are firing from real Claude Code sessions.
# Usage: wc-event.sh <event_type>   (attention | thinking | working | done | idle)

set -u
EVENT_TYPE="${1:-idle}"
LOG="$HOME/.claude/logs/wc-event.log"
EVENTS_DIR="$HOME/.claude/pet-events"

mkdir -p "$(dirname "$LOG")" "$EVENTS_DIR"

# Rotate the log if it has grown past ~1MB. Runs on every hook event, so keep
# it cheap: a single stat-based size check, no `wc -l`, no extra subprocesses
# beyond mv/chmod (and those only fire when we actually rotate). Keeps exactly
# one generation (wc-event.log.1) and re-applies 600 perms — the log carried
# secrets before payload logging was removed below, and 240MB/264k lines of
# unbounded growth is what this guards against (2026-09-15).
MAX_LOG_BYTES=$((1024 * 1024))
if [ -f "$LOG" ]; then
    # GNU stat first: on Linux, `stat -f %z` does NOT error (`-f` means
    # "filesystem", not "format" there) — it silently prints filesystem
    # status instead of the file size, so the `||` fallback never fires and
    # the size check gets garbage. `-c %s` fails cleanly on Linux only when
    # wrong; trying it first means BSD (macOS) falls through to `-f %z`
    # exactly when it should, and Linux never reaches the ambiguous form.
    log_size=$(stat -c %s "$LOG" 2>/dev/null || stat -f %z "$LOG" 2>/dev/null || echo 0)
    if [ "$log_size" -gt "$MAX_LOG_BYTES" ]; then
        mv -f "$LOG" "$LOG.1"
        : > "$LOG"
        chmod 600 "$LOG"
    fi
fi

# Read hook payload from stdin (Claude Code's hook spec sends JSON here).
payload=$(cat 2>/dev/null || echo '{}')
ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Extract identifying fields with jq if available; otherwise leave blank.
# `sanitize` strips newlines/CR so a crafted field can never forge a second
# log line (log injection) or break the one-line-per-event format.
sanitize() { printf '%s' "$1" | tr -d '\n\r' | cut -c1-200; }
if command -v jq >/dev/null 2>&1; then
    session_id=$(sanitize "$(printf '%s' "$payload" | jq -r '.session_id // ""')")
    message=$(printf '%s' "$payload" | jq -r '.message // ""')
    hook_event_name=$(sanitize "$(printf '%s' "$payload" | jq -r '.hook_event_name // ""')")
    tool_name=$(sanitize "$(printf '%s' "$payload" | jq -r '.tool_name // ""')")
else
    session_id=""
    message=""
    hook_event_name=""
    tool_name=""
fi

# Append a ONE-LINE summary to the log — never the payload body. Use ISO8601
# UTC so log entries sort naturally even across timezones.
#
# NOTE: never log the raw payload or free-text fields (message/prompt) — the
# payload carries tool_input.command and file contents verbatim, which
# routinely contains live DATABASE_URLs, PATs and API keys. Only safe,
# structural identifiers (session_id/hook_event_name/tool_name) are logged;
# payload_bytes proves hooks are firing without keeping the bytes.
{
    echo "[$ts] event=$EVENT_TYPE pid=$$ ppid=$PPID payload_bytes=${#payload} session_id=$session_id hook_event_name=$hook_event_name tool_name=$tool_name"
} >> "$LOG" 2>&1

uuid=$(uuidgen | tr 'A-Z' 'a-z')
final="$EVENTS_DIR/$uuid.json"
tmp="$EVENTS_DIR/$uuid.json.tmp"

# Write to a .tmp file FIRST, then rename atomically to .json. This avoids
# a race where the watcher (DispatchSource on .write events) reads the file
# while we're still streaming bytes into it — Swift's JSONDecoder would
# see truncated content and silently drop the event. The .tmp suffix means
# the watcher's `pathExtension == "json"` filter ignores it during writing.
cat > "$tmp" <<EOF
{
  "type": "$EVENT_TYPE",
  "ts": "$ts",
  "session_id": "$session_id",
  "message": $(printf '%s' "$message" | jq -Rs . 2>/dev/null || echo '""')
}
EOF
mv "$tmp" "$final"
