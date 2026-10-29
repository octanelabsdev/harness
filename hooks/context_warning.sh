#!/usr/bin/env bash
# UserPromptSubmit hook — warn when a session's context gets large.
#
# Nearly all token spend is cache reads, so every call costs roughly the size of the context. A long
# session re-reads everything it has accumulated on every turn. This hook reads the live context size
# from the transcript (the last main-thread assistant call's input + cache_creation + cache_read
# tokens) and warns once at each step: 100K, 150K and 250K tokens. The steps are fixed token counts,
# not a share of the window, because cost tracks context size: a 1M window would otherwise stay quiet
# until 750K, long after turns got expensive. The operator sees a systemMessage; the model gets
# additionalContext so it can mention a clean break when one comes up.
#
# The steps, first match wins: $HARNESS_CONTEXT_STEPS (comma list), then context_warning.steps in
# .claude/harness.json, then 100000,150000,250000. Invalid entries are dropped; none left means default.
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
  [ .[] | select(.type == "assistant" and (.isSidechain | not) and .message.usage != null) ] | last // empty
  | .message.usage | (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)
' 2>/dev/null)"
case "$tokens" in ''|*[!0-9]*) exit 0 ;; esac

steps="${HARNESS_CONTEXT_STEPS:-$(hcfg '.context_warning.steps? | map(tostring) | join(",")' '')}"
valid=()
IFS=', ' read -ra raw <<< "$steps"
for t in ${raw[@]+"${raw[@]}"}; do
  # Leading zeros read as octal in $(( )) and over 9 digits risks overflow, so both are dropped.
  [[ "$t" =~ ^[1-9][0-9]{0,8}$ ]] && valid+=("$t")
done
[ "${#valid[@]}" -gt 0 ] || valid=(100000 150000 250000)

level=0
for t in "${valid[@]}"; do
  [ "$tokens" -ge "$t" ] && [ "$t" -gt "$level" ] && level=$t
done

state_dir="${TMPDIR:-/tmp}/harness-context-warning"
state="$state_dir/$session"
mkdir -p "$state_dir" 2>/dev/null || exit 0
last="$(cat "$state" 2>/dev/null)"; case "$last" in ''|*[!0-9]*) last=0 ;; esac

if [ "$level" -le "$last" ]; then
  [ "$level" -lt "$last" ] && printf '%s' "$level" > "$state"
  exit 0
fi
printf '%s' "$level" > "$state"

size="$((tokens / 1000))K tokens"
user="Context is at ${size}. Every turn re-reads all of it, so a clean break at a natural stopping point (/session-end, /clear, /session-start) keeps turns cheaper."
model="HARNESS CONTEXT: this session's context is about ${size} (crossed $((level / 1000))K). This is information, not an instruction to stop: carry on with the current task. If a natural stopping point comes up, you may mention to the user that /session-end, then /clear and /session-start, would start a fresh, cheaper context."

jq -nc --arg u "$user" --arg m "$model" \
  '{systemMessage: $u, hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $m}}'
exit 0
