#!/usr/bin/env bash
# PreToolUse guard: a cycle phase's approval belongs to the human. Denies agent tool calls that write a
# phase's approval.json or run the approval tool; cycle.sh status reads decisions without either. On
# whenever the project has a harness config (components.cycle_guard: false turns it off). It stops an
# agent approving its own work by shortcut, not an agent deliberately disguising the command.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; . "$HERE/_harness_lib.sh"

input="$(cat)"
[ -n "$(harness_cfg)" ] || exit 0
component_on cycle_guard true || exit 0

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}
reason="Only the human approves a cycle phase. Tell them it's ready and ask them to run, in their own terminal (not through Claude): bash <harness>/tools/cycle_approve.sh. Read the result with cycle.sh status."

tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)"
case "$tool" in
  Bash)
    cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
    # Running the approval tool, or writing/moving/copying onto an approval.json. Reading is fine.
    # Commands only count at command position: the start, or after ; & | ( ` or $(, optionally behind
    # env/nohup/exec/command/time and their arguments.
    cmdpos='(^|[;&|(`{!]|\$\(|(^|[;&|(`{][[:space:]]*)(then|do|else)[[:space:]])[[:space:]]*'
    # A launcher may carry its own options, NAME=value settings or a variable NAME (env -u NAME), not
    # other commands' arguments.
    prefix='((env|nohup|exec|time|sudo|xargs)([[:space:]]+(-[^[:space:];&|]*|[A-Za-z_][A-Za-z0-9_]*=[^[:space:];&|]*|[A-Z_][A-Z0-9_]*))*[[:space:]]+)?'
    # approval.json as the last word of its command (a write's destination), not approval.json.bak
    end='["'"'"']?[[:space:]]*($|[;&|)<>]|[0-9]+[<>])'
    target='[^[:space:];&|]*(phases/[^/[:space:];&|]+/|\$[^/[:space:];&|]*/)approval\.json'
    # Match on the command's shape, not its text: heredoc bodies are dropped, newlines become ';', and
    # separators inside quotes are blanked (keeping $var and "$(…)", which the shell still expands), so a
    # commit message that mentions the tool isn't a command.
    shape="$(awk '
      inhd { t = $0; if (strip) sub(/^\t+/, "", t); if (t == hd) inhd = 0; next }
      { line = $0
        if (q == "" && match(line, /(^|[^<])<<-?[ \t]*["\047]?[A-Za-z_][A-Za-z0-9_]*["\047]?/)) {
          hd = substr(line, RSTART, RLENGTH); sub(/^[^<]/, "", hd); strip = (hd ~ /^<<-/)
          gsub(/^<<-?[ \t]*|["\047]/, "", hd); inhd = 1 }
        out = ""
        for (i = 1; i <= length(line); i++) {
          ch = substr(line, i, 1)
          if (ch == "\\" && q != "\047") { out = out "  "; i++; continue }
          if (q == "" && (ch == "\047" || ch == "\"")) q = ch
          else if (ch == q) q = ""
          else if (q == "\047" && index(";&|()`$<>!{", ch)) ch = " "
          else if (q == "\"" && index(";&|)`<>!{", ch)) ch = " "
          else if (q == "\"" && ch == "(" && substr(line, i - 1, 1) != "$") ch = " "
          out = out ch }
        # a newline inside quotes is part of the string, not a new command
        printf "%s%s", out, (q == "" ? "; " : " ") }' <<< "$cmd")"
    if grep -Eq \
        -e "${cmdpos}${prefix}(bash|sh|zsh|source|\\.)([[:space:]]+-[^n[:space:]][^[:space:]]*)*[[:space:]]+[^[:space:];&|]*cycle_approve" \
        -e "${cmdpos}${prefix}[^[:space:];&|]*cycle_approve\\.sh" \
        -e ">\\|?[[:space:]]*${target}${end}" \
        -e "${cmdpos}(tee|cp|mv|ln|install|rsync|sponge|truncate|dd|git[[:space:]]+mv)[[:space:]]([^;&|]*[[:space:]])?${target}${end}" \
        -e "(sed|perl|ruby)[[:space:]]+(-[a-zA-Z]*i|--in-place)([^;&|]*[[:space:]])?${target}${end}" \
        -e "${cmdpos}(rm|unlink|mv|git[[:space:]]+(rm|mv))[[:space:]]([^;&|]*[[:space:]])?${target}([\"'[:space:];&|)]|$)" <<< "$shape"; then
      deny "$reason"
    fi
    ;;
  Edit|Write|MultiEdit|NotebookEdit)
    f="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)"
    case "$f" in */phases/*/approval.json|phases/*/approval.json) deny "$reason" ;; esac
    ;;
esac
exit 0
