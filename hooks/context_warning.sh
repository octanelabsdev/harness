#!/usr/bin/env bash
# UserPromptSubmit hook — warn when a session's context gets large.
#
# Nearly all token spend is cache reads, so every call costs roughly the size of the context. A long
# session re-reads everything it has accumulated on every turn. This hook reads the live context size
# from the transcript (the last main-thread assistant call's input + cache_creation + cache_read
# tokens) and warns once at each step: 150K, 200K, 300K. The operator sees a systemMessage; the model
# gets additionalContext so it can suggest /session-end at a clean stopping point.
#
# Steps re-arm when context drops back below them (after /compact). /clear starts a new session id,
# so it starts fresh. Informational, so it defaults ON — set components.context_warning to false in
# .claude/harness.json to silence it.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; . "$HERE/_harness_lib.sh"

[ "$(hcfg '.components."context_warning"' 'true')" = "false" ] && { cat >/dev/null 2>&1; exit 0; }

input="$(cat)"
transcript="$(jq -r '.transcript_path // empty' <<< "$input" 2>/dev/null)"
session="$(jq -r '.session_id // empty' <<< "$input" 2>/dev/null | tr -cd 'A-Za-z0-9_-')"
[ -n "$transcript" ] && [ -f "$transcript" ] && [ -n "$session" ] || exit 0

# The last usage is near the end; tail keeps this cheap on multi-MB transcripts.
tokens="$(tail -n 500 "$transcript" | jq -rs '
  [ .[] | select(.type == "assistant" and (.isSidechain | not) and .message.usage != null) ]
  | last | .message.usage
  | if . == null then empty
    else (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0) end
' 2>/dev/null)"
case "$tokens" in ''|*[!0-9]*) exit 0 ;; esac

level=0
for t in 150000 200000 300000; do [ "$tokens" -ge "$t" ] && level=$t; done

state_dir="${TMPDIR:-/tmp}/harness-context-warning"
state="$state_dir/$session"
mkdir -p "$state_dir" 2>/dev/null || exit 0
last="$(cat "$state" 2>/dev/null)"; case "$last" in ''|*[!0-9]*) last=0 ;; esac

if [ "$level" -le "$last" ]; then
  [ "$level" -lt "$last" ] && printf '%s' "$level" > "$state"
  exit 0
fi
printf '%s' "$level" > "$state"

k=$((tokens / 1000))
case "$level" in
  150000) user="Context is at ${k}K tokens. Every turn re-reads all of it. Wrap this task soon: /session-end, then /clear and /session-start." ;;
  200000) user="Context is at ${k}K tokens. Past 200K is where most token spend goes. Finish the current step, then /session-end, /clear, /session-start." ;;
  *)      user="Context is at ${k}K tokens. This session is expensive on every turn. Stop at the next safe point: /session-end, /clear, /session-start." ;;
esac
model="HARNESS CONTEXT: this session's context is about ${k}K tokens (crossed $((level / 1000))K). At the next clean stopping point, not mid-edit, tell the user and suggest /session-end, then /clear and /session-start. Don't start new unrelated work in this session."

jq -nc --arg u "$user" --arg m "$model" \
  '{systemMessage: $u, hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $m}}'
exit 0
