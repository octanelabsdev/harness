#!/usr/bin/env bash
# PreToolUse/PostToolUse gate — git commit, git push and gh pr create need a green test_command run on
# the exact tree being shipped.
#
# An agent saying the tests passed isn't evidence, and neither is a Bash exit code once the run is
# piped or followed by `; echo EXIT=$?`. So a pass counts only for the working-tree hash it ran on. It
# is recorded when test_command runs as a Bash command of its own and exits 0 (PostToolUse fires only
# on success), or when this gate runs the suite itself: with no pass for the tree being shipped, the
# gate runs test_command (serialized by run_tests.sh) and denies on red.
#
# With components.review_gate on, the blind review must also cover the tree (tools/review_verify.sh).
# On whenever verification_gate is; components.commit_gate false turns it off. .claude/.verification-warn
# downgrades it to a warning that never runs the suite.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; . "$HERE/_harness_lib.sh"
. "$HERE/../lib/harness_detect.sh"

input=$(cat)
field() { printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null; }
[ "$(field .tool_name)" = Bash ] || exit 0
event=$(field .hook_event_name)
cmd=$(field .tool_input.command)
cwd=$(field .cwd); cwd=${cwd:-${CLAUDE_PROJECT_DIR:-$PWD}}

unquote() { local s="$1"; case "$s" in \"*\"|\'*\') s="${s:1:${#s}-2}" ;; esac; printf '%s' "$s"; }
expand_home() {
  local s; s=$(unquote "$1")
  case "$s" in "~"|"~/"*) s="$HOME${s:1}" ;; esac
  s="${s//\$\{HOME\}/$HOME}"; printf '%s' "${s//\$HOME/$HOME}"
}

# The repo the command acts on: a leading `cd <dir>`, else `git -C <dir>`, else the shell's cwd.
target_dir() {
  local d="" cd_re='^[[:space:]]*cd[[:space:]]+("[^"]*"|[^[:space:];&|]+)[[:space:]]*(&&|;)'
  local gc_re='git[[:space:]]+-C[[:space:]]+("[^"]*"|[^[:space:];&|]+)'
  if [[ "$1" =~ $cd_re ]] || [[ "$1" =~ $gc_re ]]; then d=$(expand_home "${BASH_REMATCH[1]}"); fi
  case "$d" in "") printf '%s' "$cwd" ;; /*) printf '%s' "$d" ;; *) printf '%s' "$cwd/$d" ;; esac
}

repo=$(git -C "$(target_dir "$cmd")" rev-parse --show-toplevel 2>/dev/null) || exit 0
export CLAUDE_PROJECT_DIR="$repo"   # read that repo's harness.json, not the session's
harness_load_cfg

[ "$(hcfg '.components."commit_gate"' "$(hcfg '.components."verification_gate"' 'false')")" = true ] || exit 0
raw_cmd="$(hcfg '.stack.test_command' '')"
test_cmd="$(harness_resolve_test_command "$repo" "$raw_cmd" "$(hcfg '.stack.name' '')")"
[ -n "$test_cmd" ] || exit 0

common=$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
pending="$common/harness-test-pending"
worktree_tree() { harness_worktree_tree "$repo"; }
has_pass() { harness_has_pass "$repo" "$1" "$test_cmd"; }
record_pass() { harness_record_pass "$repo" "$1" "$test_cmd"; }

# test_command as a command of its own: a leading cd, caffeinate/time or run_tests.sh, and trailing
# redirects are fine; a pipe or `; echo` would hide its exit code.
plain_test_run() {
  local c
  c=$(printf '%s' "$1" | sed -E \
    -e 's/^[[:space:]]*cd[[:space:]]+("[^"]*"|[^[:space:];&|]+)[[:space:]]*(&&|;)[[:space:]]*//' \
    -e 's/^(caffeinate([[:space:]]+-[a-zA-Z]+)*|time)[[:space:]]+//' \
    -e 's/^(bash[[:space:]]+)?[^[:space:]]*tools\/run_tests\.sh([[:space:]]+--[a-z-]+([[:space:]]+[0-9]+)?)*[[:space:]]+--[[:space:]]+//' \
    -e 's/([[:space:]]+[0-9&]?>>?[[:space:]]*&?[^[:space:];&|<>]+)+[[:space:]]*$//' \
    -e 's/[[:space:]]+$//')
  [ "$c" = "$test_cmd" ]
}

# commit, push (git push or gh pr create), or nothing. Heredoc bodies and quoted strings are dropped
# first, so a commit message or a note that mentions `git push` doesn't count.
ship_kind() {
  local s git_re='(^|[;&|(]|[[:space:]])git([[:space:]]+-[Cc][[:space:]]+[^[:space:]]+)*[[:space:]]+'
  s=$(printf '%s\n' "$1" | awk -v q="'" '
    d != "" { line = $0; sub(/^\t+/, "", line); if (line == d) d = ""; next }
    { print; if (match($0, "<<-?[ \t]*[\"" q "]?[A-Za-z_][A-Za-z0-9_]*")) { d = substr($0, RSTART, RLENGTH); gsub("^<<-?[ \t]*[\"" q "]?", "", d) } }' |
    sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g")
  [[ "$s" == *--dry-run* ]] && return 0
  if printf '%s' "$s" | grep -qE "${git_re}commit([[:space:]]|$)"; then echo commit
  elif printf '%s' "$s" | grep -qE "${git_re}push([[:space:]]|$)|(^|[;&|(]|[[:space:]])gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)"; then echo push
  fi
}

case "$event" in
  PostToolUse)
    f="$pending/$(field .tool_use_id | tr -cd 'A-Za-z0-9_-')"
    if [ -f "$f" ] && [ "$(field .tool_response.interrupted)" != true ]; then record_pass "$(cat "$f")"; fi
    rm -f "$f" 2>/dev/null
    exit 0 ;;
  PreToolUse) ;;
  *) exit 0 ;;
esac

# The agent's run goes through run_tests.sh too, so it takes the same lock as the gates' runs and can't
# overlap another suite on a shared test database. updatedInput replaces the whole tool input, and
# permission rules are checked against the rewritten command.
serialize_run() {
  local runner q t w
  [[ "$cmd" == *run_tests.sh* ]] && return 0
  runner="$(cd "$HERE/.." && pwd)/tools/run_tests.sh"
  q=$(printf '%s' "$cmd" | sed "s/'/'\\\\''/g")
  t=$(hcfg '.stack.test_timeout_sec' '600'); [[ "$t" =~ ^[0-9]+$ ]] || t=600
  w=$(hcfg '.stack.test_lock_wait_sec' '600'); [[ "$w" =~ ^[0-9]+$ ]] || w=600
  jq -n --argjson input "$(field '.tool_input')" \
    --arg c "(cd '$repo' && bash '$runner' --timeout $t --wait $w -- '$q')" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",updatedInput:($input + {command:$c}),
      additionalContext:"COMMIT GATE: this test run goes through tools/run_tests.sh, so it waits for any other suite instead of overlapping it."}}'
}

if plain_test_run "$cmd"; then
  if [ "$(field .tool_input.run_in_background)" != true ] && id=$(field .tool_use_id | tr -cd 'A-Za-z0-9_-') && [ -n "$id" ] &&
     mkdir -p "$pending" 2>/dev/null; then
    find "$pending" -type f -mtime +1 -delete 2>/dev/null
    tree=$(worktree_tree) && printf '%s' "$tree" > "$pending/$id"
  fi
  serialize_run
  exit 0
fi

kind=$(ship_kind "$cmd")
[ -n "$kind" ] || exit 0

impl_in() { local p; while IFS= read -r p; do [ -n "$p" ] && path_under "$p" impl_dirs && return 0; done; return 1; }
dirty_impl() { git -C "$repo" status --porcelain 2>/dev/null | cut -c4- | sed 's/.* -> //' | impl_in; }

key=""; can_run=1
if [ "$kind" = commit ]; then
  dirty_impl || exit 0
else
  base=""
  for ref in '@{u}' origin/HEAD origin/main origin/master; do
    base=$(git -C "$repo" merge-base HEAD "$ref" 2>/dev/null) && break
  done
  if [ -n "$base" ] && ! git -C "$repo" diff --name-only "$base" HEAD 2>/dev/null | impl_in && ! dirty_impl; then
    exit 0
  fi
  # Uncommitted implementation changes mean the working tree isn't what gets pushed, so only a pass
  # recorded for HEAD's own tree counts.
  if dirty_impl; then key=$(harness_head_tree "$repo"); can_run=0; fi
fi
[ -n "$key" ] || key=$(worktree_tree) || exit 0

deny() { jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'; exit 0; }
advise() { jq -n --arg c "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$c}}'; exit 0; }
warn=""; [ -f "$repo/.claude/.verification-warn" ] && warn=1

# Checked before the suite: it's cheap, and a tested tree with a stale review still can't ship.
if [ "$(hcfg '.components."review_gate"' 'false')" = true ] &&
   ! rv_out="$(cd "$repo" && bash "$HERE/../tools/review_verify.sh" 2>&1)"; then
  msg="COMMIT GATE — the blind review doesn't cover this tree (components.review_gate):
$rv_out
Run the blind-review skill on the current diff, then retry."
  [ -n "$warn" ] && advise "$msg [warn only — remove .claude/.verification-warn to enforce]"
  deny "$msg"
fi

has_pass "$key" && exit 0
[ -n "$warn" ] && advise "COMMIT GATE (warn): no green \`$test_cmd\` run is recorded for this tree. [warn only — remove .claude/.verification-warn to enforce]"
[ "$can_run" = 1 ] || deny "COMMIT GATE: HEAD has no green \`$test_cmd\` run recorded, and the working tree has uncommitted implementation changes, so the gate can't test what you are pushing. Commit or stash them, then retry: the gate runs the suite on a clean tree."

hook_timeout_sec="$(jq -r '[.hooks.PreToolUse[].hooks[] | select(.command | test("commit_gate")) | .timeout][0] // 600' "$HERE/hooks.json" 2>/dev/null || echo 600)"
budget_sec=$(( hook_timeout_sec - 60 ))
test_timeout_sec="$(hcfg '.stack.test_timeout_sec' '600')"
lock_wait_sec="$(hcfg '.stack.test_lock_wait_sec' '600')"
case "$test_timeout_sec$lock_wait_sec" in
  *[!0-9]*) ;;
  *)
    test_timeout_sec=$((10#$test_timeout_sec)); lock_wait_sec=$((10#$lock_wait_sec))
    [ "$test_timeout_sec" -gt "$budget_sec" ] && test_timeout_sec="$budget_sec"
    [ $(( test_timeout_sec + lock_wait_sec )) -gt "$budget_sec" ] && lock_wait_sec=$(( budget_sec - test_timeout_sec ))
    ;;
esac

log_copy="$(mktemp "${TMPDIR:-/tmp}/harness-commit-log.XXXXXX" 2>/dev/null || true)"
trc=0
test_out="$(cd "$repo" && bash "$HERE/../tools/run_tests.sh" --timeout "$test_timeout_sec" --wait "$lock_wait_sec" --log-copy "${log_copy:-/dev/null}" -- "$(harness_wrap_ruby "$repo" "$test_cmd")" 2>&1)" || trc=$?
full_out="$( [ -n "$log_copy" ] && cat "$log_copy" 2>/dev/null || true)"
[ -n "$log_copy" ] && rm -f "$log_copy"
[ "$trc" = 0 ] && harness_ran_zero_tests "${full_out:-$test_out}" && trc=5

if [ "$trc" = 0 ]; then
  record_pass "$key"
  advise "COMMIT GATE: ran \`$test_cmd\` on this tree — green."
fi
case "$trc" in
  2) verdict="SETUP ERROR — tests did NOT run (bad stack.test_timeout_sec / stack.test_lock_wait_sec, or the test lock can't be created)" ;;
  3) verdict="UNVERIFIED — another test run held the lock past ${lock_wait_sec}s; tests did NOT run" ;;
  4) verdict="UNVERIFIED — test_command exceeded ${test_timeout_sec}s and was killed" ;;
  5) verdict="UNVERIFIED — no tests ran (the command passed but every summary reported 0 tests)" ;;
  *) verdict="test_command failed" ;;
esac
deny "COMMIT GATE — $verdict: $test_cmd
$(printf '%s\n' "$test_out" | tail -n 40)
Fix the failures, then retry. A plain \`$test_cmd\` run that exits 0 on this tree also counts."
