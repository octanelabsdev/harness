#!/usr/bin/env bash
# PreToolUse gate — the first edit of a session waits until the guardrails skill is loaded.
#
# The SessionStart nudge alone wasn't enough: in harness-bench runs a third of agents edited without
# ever loading guardrails, often through Bash (`sed -i`, a heredoc) where no file-tool hook fires. So
# this gate watches Bash writes too, and denies edit-like calls while the transcript has no guardrails
# Skill call. It keeps denying until the skill loads (Haiku retried straight through a single
# deny in 4 of 29 bench runs), but at most three times per context, so an agent that can't load it
# isn't stuck.
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

# Marks are per session and agent context: `<id>` counts denies, `<id>.loaded` records the skill load.
marks="${TMPDIR:-/tmp}/harness-guardrails-gate"
mkdir -p "$marks" 2>/dev/null || exit 0
mark="$marks/$(field .session_id | tr -cd 'A-Za-z0-9_-')-$(field .agent_id | tr -cd 'A-Za-z0-9_-')"

# The gate sees the Skill call itself, because headless runs (--no-session-persistence) have no transcript.
case "$tool" in
  Skill) [[ "$(field .tool_input.skill)" =~ ^(harness:)?guardrails$ ]] && : > "$mark.loaded" 2>/dev/null; exit 0 ;;
  Edit|Write|MultiEdit|NotebookEdit) ;;
  Bash) bash_writes "$(field .tool_input.command)" || exit 0 ;;
  *) exit 0 ;;
esac

[ -e "$mark.loaded" ] && exit 0
transcript=$(field .transcript_path)
if [ -n "$transcript" ] && [ -f "$transcript" ] &&
   grep -qE '"skill"[[:space:]]*:[[:space:]]*"(harness:)?guardrails"' "$transcript"; then
  exit 0
fi

# The fourth attempt goes through, so an agent that can't load the skill isn't stuck.
denies=0; [ -f "$mark" ] && denies=$(wc -c < "$mark" | tr -d ' ')
[ "$denies" -ge 3 ] && exit 0
printf x >> "$mark" 2>/dev/null || exit 0
n=$((denies + 1))

jq -n --arg n "$n" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",
  permissionDecisionReason:("GUARDRAILS FIRST (deny \($n) of 3): the guardrails skill is not loaded, so this edit is refused. Retrying the edit will be refused again. Invoke the harness:guardrails skill, read references/CODE.md, and run its before-the-first-edit items (C0: trace a user-visible change from its entrypoint), then retry this edit.")}}'
exit 0
