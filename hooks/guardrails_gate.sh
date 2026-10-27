#!/usr/bin/env bash
# PreToolUse gate — the first edit of a session waits until the guardrails skill is loaded.
#
# The SessionStart nudge alone wasn't enough: in harness-bench runs a third of agents edited without
# ever loading guardrails, often through Bash (`sed -i`, a heredoc) where no file-tool hook fires. So
# this gate watches Bash writes too, and denies the FIRST edit-like call once if the transcript has no
# guardrails Skill call. It never denies twice in a context: the retry goes through either way.
#
# Defaults ON; set components.guardrails_gate to false in .claude/harness.json to turn it off.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; . "$HERE/_harness_lib.sh"

[ "$(hcfg '.components."guardrails_gate"' 'true')" = "false" ] && exit 0

input=$(cat)
field() { printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null; }
tool=$(field .tool_name)

# Bash counts only when it writes files. Quoted strings are blanked first so `grep ">" x` isn't a write.
bash_writes() {
  local cmd; cmd=$(printf '%s' "$1" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g")
  printf '%s' "$cmd" | grep -qE '(^|[;&|(]|\n)[[:space:]]*(sudo[[:space:]]+)?(cp|mv|rm|touch|tee|patch|install|ln|truncate)[[:space:]]' && return 0
  printf '%s' "$cmd" | grep -qE '(sed|perl|ruby)[[:space:]]+(-[a-zA-Z]*[[:space:]]+)*-[a-zA-Z]*i' && return 0
  printf '%s' "$cmd" | grep -qE '(rubocop[[:space:]].*-[aA]\b|rails[[:space:]]+(g|generate|destroy)\b|git[[:space:]]+(apply|restore|checkout)[[:space:]])' && return 0
  printf '%s' "$1" | grep -qE 'File\.write|write_text\(|open\([^)]*,[[:space:]]*.w' && return 0
  printf '%s' "$cmd" | sed -E 's#[0-9]*>+[[:space:]]*(/dev/null|&[0-9])##g' | grep -qE '>' && return 0
  return 1
}

case "$tool" in
  Edit|Write|MultiEdit|NotebookEdit) ;;
  Bash) bash_writes "$(field .tool_input.command)" || exit 0 ;;
  *) exit 0 ;;
esac

transcript=$(field .transcript_path)
if [ -n "$transcript" ] && [ -f "$transcript" ] &&
   grep -qE '"skill"[[:space:]]*:[[:space:]]*"(harness:)?guardrails"' "$transcript"; then
  exit 0
fi

# One deny per session and agent context, so an agent that can't or won't load the skill isn't stuck.
marks="${TMPDIR:-/tmp}/harness-guardrails-gate"
mkdir -p "$marks" 2>/dev/null || exit 0
mark="$marks/$(field .session_id | tr -cd 'A-Za-z0-9_-')-$(field .agent_id | tr -cd 'A-Za-z0-9_-')"
[ -e "$mark" ] && exit 0
: > "$mark" 2>/dev/null || exit 0

jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",
  permissionDecisionReason:"GUARDRAILS FIRST: this is your first edit and the guardrails skill is not loaded. Invoke the harness:guardrails skill, read references/CODE.md, and run its before-the-first-edit items (C0: trace a user-visible change from its entrypoint), then retry this edit. This gate fires once."}}'
exit 0
