#!/usr/bin/env bash
# PreToolUse gate — the first edit of a session waits until the guardrails skill is loaded.
#
# The SessionStart nudge alone wasn't enough: in harness-bench runs a third of agents edited without
# ever loading guardrails, often through Bash (`sed -i`, a heredoc) where no file-tool hook fires. So
# this gate watches Bash writes too, and denies edit-like calls while the transcript has no guardrails
# Skill call since the last compaction. It keeps denying until the skill loads (Haiku retried
# straight through a single deny in 4 of 29 bench runs), but at most three times per context, so an
# agent that can't load it isn't stuck.
#
# Defaults ON; set components.guardrails_gate to false in .claude/harness.json to turn it off.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; . "$HERE/_harness_lib.sh"

[ "$(hcfg '.components."guardrails_gate"' 'true')" = "false" ] && exit 0

input=$(cat)
field() { printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null; }
tool=$(field .tool_name)
repo=$(harness_repo)

blank_quotes() { printf '%s' "$1" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g"; }

# Every Bash write form except redirects and tee, whose targets can be resolved.
bash_edits_files() {
  local cmd; cmd=$(blank_quotes "$1")
  printf '%s' "$cmd" | grep -qE '(^|[;&|(]|\n)[[:space:]]*(sudo[[:space:]]+)?(cp|mv|rm|touch|patch|install|ln|truncate)[[:space:]]' && return 0
  printf '%s' "$cmd" | grep -qE '(sed|perl|ruby)[[:space:]]+(-[a-zA-Z]*[[:space:]]+)*-[a-zA-Z]*i' && return 0
  printf '%s' "$cmd" | grep -qE '(rubocop[[:space:]].*-[aA]\b|rails[[:space:]]+(g|generate|destroy)\b|git[[:space:]]+(apply|restore|checkout)[[:space:]])' && return 0
  printf '%s' "$1" | grep -qE 'File\.write|write_text\(|open\([^)]*,[[:space:]]*.w' && return 0
  return 1
}

# Bash counts only when it writes files. Quoted strings are blanked first so `grep ">" x` isn't a write.
bash_writes() {
  bash_edits_files "$1" && return 0
  local cmd; cmd=$(blank_quotes "$1")
  printf '%s' "$cmd" | grep -qE '(^|[;&|(]|\n)[[:space:]]*(sudo[[:space:]]+)?tee[[:space:]]' && return 0
  printf '%s' "$cmd" | sed -E 's#[0-9]*>+[[:space:]]*(/dev/null|&[0-9])##g' | grep -qE '>' && return 0
  return 1
}

# Every worktree of the repo counts as the repo: a sibling worktree holds the same code.
repo_roots() {
  [ -n "${roots:-}" ] || roots=$(printf '%s\n' "$repo"; git -C "$repo" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')
  printf '%s\n' "$roots"
}

outside_repo() { # outside_repo <absolute path>
  local p="$1" dir root
  case "$p" in /dev/*) return 0 ;; esac
  [[ "$p" == */../* || "$p" == */.. ]] && return 1
  dir=$(cd "$(dirname "$p")" 2>/dev/null && pwd -P) && dir="$dir/$(basename "$p")"
  while IFS= read -r root; do
    [ -n "$root" ] || continue
    [[ "$p/" == "$root/"* || ( -n "$dir" && "$dir/" == "$root/"* ) ]] && return 1
  done < <(repo_roots)
  return 0
}

# Anything it can't expand ($assigned holds earlier "name=value" assignments) fails, so the write stays gated.
expand_path() {
  local s="$1" name val i=0 re='\$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)'
  case "$s" in "~"|"~/"*) s="$HOME${s:1}" ;; esac
  while [[ "$s" =~ $re ]] && [ $((i += 1)) -le 20 ]; do
    name="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
    case "$name" in
      HOME) val="$HOME" ;;
      TMPDIR) val="${TMPDIR:-/tmp}" ;;
      *) val=$(printf '%s\n' "$assigned" | grep -E "^$name=" | tail -n 1); [ -n "$val" ] || return 1; val="${val#*=}" ;;
    esac
    s="${s/"${BASH_REMATCH[0]}"/$val}"
  done
  [[ "$s" == *'$'* || "$s" == *'`'* ]] && return 1
  printf '%s' "$s"
}

resolve_target() { # resolve_target <token as written> <cd base or ""> -> absolute path
  local t="$1"
  case "$t" in
    \'*\') t="${t:1:${#t}-2}"; [[ "$t" == *'$'* ]] && return 1 ;;
    \"*\") t="${t:1:${#t}-2}"; t=$(expand_path "$t") || return 1 ;;
    *) t=$(expand_path "$t") || return 1 ;;
  esac
  case "$t" in /*) ;; *) [ -n "$2" ] || return 1; t="$2/$t" ;; esac
  printf '%s' "$t"
}

# A heredoc body is inert data only when it feeds cat or tee; an interpreter or a pipe could run it.
strip_heredocs() {
  printf '%s\n' "$1" | awk -v q="'" '
    d != "" { line = $0; if (dash) sub(/^\t+/, "", line); if (line == d) d = ""; next }
    {
      print
      if (index($0, "<<<")) bad = 1
      s = $0; n = 0
      while (match(s, "<<-?[ \t]*[\"" q "]?[A-Za-z_][A-Za-z0-9_]*[\"" q "]?")) {
        pre = substr(s, 1, RSTART - 1); tok = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
        k = split(pre, parts, /[;&|]/); seg = parts[k]; sub(/^[ \t]+/, "", seg)
        if (seg !~ /^(cat|tee)([ \t]|$)/ || index(s, "|") || ++n > 1) bad = 1
        dash = (tok ~ /^<<-/); gsub("^<<-?[ \t]*[\"" q "]?|[\"" q "]$", "", tok); d = tok
      }
    }
    END { exit bad }'
}

# Vault notes and $TMPDIR logs pass; any write form it can't resolve keeps the command gated.
bash_writes_outside_repo_only() {
  local s blank assigned="" base="" a t n_ops n_tee targets found=0
  local tok='("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:];&|<>()"'"'"']+)'
  s=$(strip_heredocs "$1") || return 1
  bash_edits_files "$s" && return 1
  blank=$(blank_quotes "$s")
  [[ "$blank" == *'>('* ]] && return 1

  while IFS= read -r a; do
    a="${a#"${a%%[A-Za-z_]*}"}"
    t=$(resolve_target "${a#*=}" "") || continue
    assigned="$assigned${a%%=*}=$t"$'\n'
  done < <(printf '%s' "$s" | grep -oE "(^|[;&|[:space:]])[A-Za-z_][A-Za-z0-9_]*=$tok")

  local cd_re="^[[:space:]]*cd[[:space:]]+$tok[[:space:]]*(&&|;)"
  if [[ "$s" =~ $cd_re ]] && [ "$(printf '%s' "$blank" | grep -oE '(^|[;&|[:space:]])cd[[:space:]]' | wc -l)" -eq 1 ]; then
    base=$(resolve_target "${BASH_REMATCH[1]}" "") || base=""
  fi

  local no_dups='s/[0-9]*>>?[[:space:]]*&[0-9]*-?//g'
  n_ops=$(printf '%s' "$blank" | sed -E "$no_dups" | grep -oE '>>?' | wc -l)
  n_tee=$(printf '%s' "$blank" | grep -oE '(^|[;&|(]|[[:space:]])tee[[:space:]]' | wc -l)
  targets=$(printf '%s' "$s" | sed -E "$no_dups" | grep -oE "&?>>?[[:space:]]*$tok" | sed -E 's/^&?>>?[[:space:]]*//')
  [ "$(printf '%s' "$targets" | grep -c '')" -eq "$n_ops" ] || return 1
  t=$(printf '%s' "$s" | grep -oE "(^|[;&|(]|[[:space:]])tee[[:space:]]+(-a[[:space:]]+)?$tok[[:space:]]*($|[;&|)])" |
      sed -E 's/^.*tee[[:space:]]+(-a[[:space:]]+)?//; s/[[:space:]]*[;&|)]?$//')
  [ "$(printf '%s' "$t" | grep -c '')" -eq "$n_tee" ] || return 1
  targets=$(printf '%s\n%s' "$targets" "$t")

  while IFS= read -r a; do
    [ -n "$a" ] || continue
    t=$(resolve_target "$a" "$base") || return 1
    outside_repo "$t" || return 1
    found=$((found + 1))
  done <<< "$targets"
  [ "$found" -ge 1 ]
}

# Per session and agent: `<id>` and `<id>.bash` count edit and Bash denies, `<id>.loaded` the skill load.
marks="${TMPDIR:-/tmp}/harness-guardrails-gate"
mkdir -p "$marks" 2>/dev/null || exit 0
mark="$marks/$(field .session_id | tr -cd 'A-Za-z0-9_-')-$(field .agent_id | tr -cd 'A-Za-z0-9_-')"

# Compaction drops the loaded skill from context, so the main context has to load it again.
if [ "$(field .hook_event_name)" = SessionStart ]; then
  rm -f "$mark" "$mark.bash" "$mark.loaded" 2>/dev/null
  exit 0
fi

# The gate sees the Skill call itself, because headless runs (--no-session-persistence) have no transcript.
case "$tool" in
  Skill) [[ "$(field .tool_input.skill)" =~ ^(harness:)?guardrails$ ]] && : > "$mark.loaded" 2>/dev/null; exit 0 ;;
esac
[ -e "$mark.loaded" ] && exit 0

case "$tool" in
  Edit|Write|MultiEdit|NotebookEdit)
    # Vault notes and scratch files aren't repo code, and CODE.md is about repo files.
    path=$(field .tool_input.file_path); path=${path:-$(field .tool_input.notebook_path)}
    case "$path" in /*) outside_repo "$path" && exit 0 ;; esac
    budget="$mark" ;;
  Bash)
    cmd=$(field .tool_input.command)
    bash_writes "$cmd" || exit 0
    bash_writes_outside_repo_only "$cmd" && exit 0
    # Its own budget, so false denies on writes it can't resolve never use up the file-edit denies.
    budget="$mark.bash" ;;
  *) exit 0 ;;
esac

# Since the last compaction: a guardrails Skill call, or CODE.md read by the Read tool or a shell command.
loaded_since_compaction() {
  local from
  from=$(grep -nE '"subtype"[[:space:]]*:[[:space:]]*"compact_boundary"' "$1" | tail -n 1 | cut -d: -f1)
  tail -n +"$(( ${from:-0} + 1 ))" "$1" | grep -E 'guardrails' | jq -R 'fromjson? // empty' 2>/dev/null |
    jq -e -s 'any(.[]; .message.content? | arrays | any(.[];
      .type == "tool_use" and (
        (.name == "Skill" and ((.input.skill // "") | test("^(harness:)?guardrails$"))) or
        (.name == "Read" and ((.input.file_path // "") | test("guardrails/(references/)?CODE\\.md$"))) or
        (.name == "Bash" and ((.input.command // "") | test("guardrails/(references/)?CODE\\.md"))))))' >/dev/null 2>&1
}
transcript=$(field .transcript_path)
[ -n "$transcript" ] && [ -f "$transcript" ] && loaded_since_compaction "$transcript" && exit 0

# The fourth attempt goes through, so an agent that can't load the skill isn't stuck.
denies=0; [ -f "$budget" ] && denies=$(wc -c < "$budget" | tr -d ' ')
[ "$denies" -ge 3 ] && exit 0
printf x >> "$budget" 2>/dev/null || exit 0
n=$((denies + 1))
hint=""
[ "$tool" = Bash ] && hint=" Writing a note outside the repo? Use the Write or Edit tool with an absolute path; edits outside the repo are not gated."

jq -n --arg n "$n" --arg hint "$hint" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",
  permissionDecisionReason:("GUARDRAILS FIRST (deny \($n) of 3): the guardrails skill is not loaded, so this edit is refused. Retrying the edit will be refused again. Invoke the harness:guardrails skill, read references/CODE.md, and run its before-the-first-edit items (C0: trace a user-visible change from its entrypoint), then retry this edit." + $hint)}}'
exit 0
