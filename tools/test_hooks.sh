#!/usr/bin/env bash
# test_hooks.sh — fixture-driven behavior tests for the harness gate hooks.
#
# Feeds synthetic hook JSON on stdin into the gate scripts inside a throwaway git repo and asserts the
# decision/output. No live Claude needed. This is the regression guard for the gates' actual behavior
# (the load smoke only proves the plugin loads). Wired into tools/ci.sh.
set -uo pipefail
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS="$HERE/../hooks"
pass=0; fail=0
ok() { printf '  ✔ %s\n' "$1"; pass=$((pass+1)); }
no() { printf '  ✘ %s\n' "$1" >&2; fail=$((fail+1)); }

# mkrepo <harness.json body> -> path to a throwaway git repo with impl/ui/test/docs dirs
mkrepo() {
  local d; d="$(mktemp -d "${TMPDIR:-/tmp}/harness-hooktest.XXXXXX")"
  git -C "$d" init -q
  git -C "$d" config user.email test@example.com
  git -C "$d" config user.name test
  mkdir -p "$d/.claude" "$d/lib" "$d/app" "$d/test/system" "$d/docs"
  printf '%s' "$1" > "$d/.claude/harness.json"
  # Return the PHYSICAL path so it matches `git rev-parse --show-toplevel` (macOS /tmp -> /private/tmp
  # symlink); otherwise the gate's file-path prefix strip fails and it looks "not under impl_dirs".
  # Validate it before returning — callers `rm -rf` this, so never hand back a fallback like cwd.
  local phys; phys="$(cd "$d" && pwd -P)" || { echo "mkrepo: cd failed for $d" >&2; exit 1; }
  case "$phys" in
    *harness-hooktest.*) printf '%s' "$phys" ;;
    *) echo "mkrepo: refusing to return unexpected temp path '$phys'" >&2; exit 1 ;;
  esac
}

run_pre() { # run_pre <repo> <abs-file-path> -> hook stdout
  CLAUDE_PROJECT_DIR="$1" bash "$HOOKS/pipeline_gate.sh" <<EOF
{"tool_input":{"file_path":"$2"}}
EOF
}

# ---- pipeline_gate (PreToolUse) ----
echo "pipeline_gate:"
PCFG='{"components":{"pipeline_gate":true},"stack":{"impl_dirs":["lib"],"ui_dirs":["app"],"operator_test_dir":"test/system","test_command":""}}'
R="$(mkrepo "$PCFG")"

# warn (no story, no .pipeline-block): the safety property — must NOT auto-approve, must NOT deny.
out="$(run_pre "$R" "$R/lib/foo.rb")"
if printf '%s' "$out" | grep -q '"permissionDecision"'; then
  no "warn: emitted a permissionDecision (must fall through to normal permission flow)"
else
  ok "warn: no permissionDecision — no auto-approve"
fi
printf '%s' "$out" | grep -q '"additionalContext"' && ok "warn: surfaces advisory via additionalContext" || no "warn: expected an additionalContext advisory"

# block mode (.pipeline-block present) -> deny
touch "$R/.claude/.pipeline-block"
out="$(run_pre "$R" "$R/lib/foo.rb")"
[ "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null)" = deny ] && ok "block: denies the edit" || no "block: expected permissionDecision deny"
rm -f "$R/.claude/.pipeline-block"

# DoR-passing story (dor_lint exit 0) -> silent allow (verdict COMPUTED, not a self-written stamp)
cat > "$R/.claude/current-story.yaml" <<'YAML'
id: STORY-1
title: Admin sees their invitations
source: PRD 3.2
operator: admin
goal: an admin sees the invitations they sent
business_rules:
  - id: BR1
    predicate: an invitation belongs to the admin who created it
acceptance_criteria:
  - given: an admin with 2 sent invitations
    when: they visit the Reviews page
    then: they see both listed
    covers: [BR1]
    outcome_type: rendered
out_of_scope:
  - editing an invitation after it is sent
YAML
out="$(run_pre "$R" "$R/lib/foo.rb")"
[ -z "$out" ] && ok "DoR-passing story (dor_lint exit 0): silent allow" || no "passing story: expected silence, got: $out"

# NOT-READY story (dor_lint exit 1) -> warn advises, still no decision (no auto-approve)
cat > "$R/.claude/current-story.yaml" <<'YAML'
id: STORY-2
title: vague
source: PRD
operator: admin
goal: do the thing
business_rules:
  - id: BR1
    predicate: something happens
acceptance_criteria:
  - given: a user
    when: they act
    then: it works
    covers: [BR1]
    outcome_type: rendered
out_of_scope: []
YAML
out="$(run_pre "$R" "$R/lib/foo.rb")"
if printf '%s' "$out" | grep -q '"permissionDecision"'; then no "NOT-READY story: emitted a decision (must not auto-approve)"; else ok "NOT-READY story: no permissionDecision (warn)"; fi
printf '%s' "$out" | grep -q '"additionalContext"' && ok "NOT-READY story: surfaces the lint verdict via additionalContext" || no "NOT-READY story: expected additionalContext"
# NOT-READY story + block mode -> deny
touch "$R/.claude/.pipeline-block"
out="$(run_pre "$R" "$R/lib/foo.rb")"
[ "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null)" = deny ] && ok "NOT-READY story + block: denies" || no "NOT-READY block: expected deny"
rm -f "$R/.claude/.pipeline-block" "$R/.claude/current-story.yaml"

# small-fix bypass -> advise, still no decision (no auto-approve)
printf 'quick typo\n' > "$R/.claude/.small-fix"
out="$(run_pre "$R" "$R/lib/foo.rb")"
if printf '%s' "$out" | grep -q '"permissionDecision"'; then no "small-fix: emitted a decision (must not auto-approve)"; else ok "small-fix: no permissionDecision"; fi
printf '%s' "$out" | grep -q '"additionalContext"' && ok "small-fix: surfaces the bypass notice" || no "small-fix: expected an additionalContext notice"
rm -f "$R/.claude/.small-fix"

# non-implementation path -> not gated (silent)
out="$(run_pre "$R" "$R/docs/readme.md")"
[ -z "$out" ] && ok "non-impl path: not gated (silent)" || no "non-impl path: expected silent, got: $out"

rm -rf "$R"

# ---- verification_gate (Stop) ----
echo "verification_gate:"
run_stop() { # run_stop <repo> <stop_hook_active bool> -> sets RC (exit code), OUT (stderr)
  OUT="$(CLAUDE_PROJECT_DIR="$1" bash "$HOOKS/verification_gate.sh" <<EOF 2>&1 1>/dev/null
{"stop_hook_active":$2}
EOF
)"; RC=$?
}
VBASE='{"components":{"verification_gate":true},"stack":{"impl_dirs":["lib"],"ui_dirs":["app"],"operator_test_dir":"test/system","test_command":"%s"}}'

# passing tests + impl change -> stop allowed (exit 0); also proves the removed .last-review gate is gone
R="$(mkrepo "$(printf "$VBASE" "true")")"; : > "$R/lib/foo.rb"
run_stop "$R" false
[ "$RC" = 0 ] && ok "green tests, impl changed -> stop allowed (no .last-review gate)" || no "green: expected exit 0, got $RC"
rm -rf "$R"

# failing tests + impl change -> block (exit 2)
R="$(mkrepo "$(printf "$VBASE" "false")")"; : > "$R/lib/foo.rb"
run_stop "$R" false
[ "$RC" = 2 ] && ok "red tests, impl changed -> blocks (exit 2)" || no "red: expected exit 2, got $RC"
rm -rf "$R"

# failing tests + .verification-warn opt-out -> warn only (exit 0)
R="$(mkrepo "$(printf "$VBASE" "false")")"; : > "$R/lib/foo.rb"; touch "$R/.claude/.verification-warn"
run_stop "$R" false
[ "$RC" = 0 ] && ok "red tests + .verification-warn -> does not block (warn opt-out)" || no "warn opt-out: expected exit 0, got $RC"
rm -rf "$R"

# no impl change (only docs) -> tests not run, stop allowed
R="$(mkrepo "$(printf "$VBASE" "false")")"; : > "$R/docs/note.md"
run_stop "$R" false
[ "$RC" = 0 ] && ok "no impl change -> gate does not run tests / does not block" || no "no impl: expected exit 0, got $RC"
rm -rf "$R"

# loop guard: stop_hook_active=true -> never re-blocks even with red tests + impl change
R="$(mkrepo "$(printf "$VBASE" "false")")"; : > "$R/lib/foo.rb"
run_stop "$R" true
[ "$RC" = 0 ] && ok "loop guard: stop_hook_active=true never re-blocks" || no "loop guard: expected exit 0, got $RC"
rm -rf "$R"

# ---- verification_gate review layer (opt-in via components.review_gate) ----
echo "verification_gate (review layer):"
VER="$HERE/review_verify.sh"
RVBASE='{"components":{"verification_gate":true,"review_gate":true},"stack":{"impl_dirs":["lib"],"ui_dirs":["app"],"operator_test_dir":"test/system","test_command":"true"}}'
setup_review_repo() { # sets globals R (committed base + impl change) and SHA (canonical diff sha)
  # NB: call directly, never as $(setup_review_repo) — command substitution would trap R in a subshell.
  R="$(mkrepo "$RVBASE")"; mkdir -p "$R/.claude/.review"
  git -C "$R" add -A >/dev/null 2>&1; git -C "$R" commit -qm base >/dev/null 2>&1
  mkdir -p "$R/lib"; printf 'x = 1\n' > "$R/lib/foo.rb"
  SHA="$(cd "$R" && bash "$VER" --emit-sha)"
}
write_art() { printf '%s' "$2" > "$1/.claude/.review/current.json"; }

# opt-in default OFF: review_gate absent + no artifact -> not enforced (allow)
R="$(mkrepo '{"components":{"verification_gate":true},"stack":{"impl_dirs":["lib"],"test_command":"true"}}')"; : > "$R/lib/foo.rb"
run_stop "$R" false
[ "$RC" = 0 ] && ok "review_gate off (default): not enforced -> stop allowed" || no "review off: expected 0, got $RC"
rm -rf "$R"

# review_gate on + valid pass artifact -> allow
setup_review_repo; write_art "$R" "{\"diff_sha\":\"$SHA\",\"verdict\":\"pass\",\"findings\":[]}"
run_stop "$R" false
[ "$RC" = 0 ] && ok "review_gate on + valid pass artifact -> stop allowed" || no "review pass: expected 0, got $RC"
rm -rf "$R"

# review_gate on + no artifact -> block
setup_review_repo
run_stop "$R" false
[ "$RC" = 2 ] && ok "review_gate on + missing artifact -> blocks" || no "review missing: expected 2, got $RC"
rm -rf "$R"

# review_gate on + changes-requested (critical) -> block
setup_review_repo; write_art "$R" "{\"diff_sha\":\"$SHA\",\"verdict\":\"changes-requested\",\"findings\":[{\"file\":\"lib/foo.rb\",\"line\":1,\"severity\":\"critical\",\"summary\":\"bug\",\"failure_scenario\":\"crash\"}]}"
run_stop "$R" false
[ "$RC" = 2 ] && ok "review_gate on + changes-requested -> blocks" || no "review changes: expected 2, got $RC"
rm -rf "$R"

# anti-fake: finding cites a line not in the diff -> invalid -> block
setup_review_repo; write_art "$R" "{\"diff_sha\":\"$SHA\",\"verdict\":\"pass\",\"findings\":[{\"file\":\"lib/foo.rb\",\"line\":999,\"severity\":\"improvement\",\"summary\":\"x\",\"failure_scenario\":\"y\"}]}"
run_stop "$R" false
[ "$RC" = 2 ] && ok "review_gate on + finding cites non-diff line -> blocks (anti-fake)" || no "review antifake: expected 2, got $RC"
rm -rf "$R"

# review_gate on + changes-requested + .verification-warn -> downgrade (allow)
setup_review_repo; write_art "$R" "{\"diff_sha\":\"$SHA\",\"verdict\":\"changes-requested\",\"findings\":[{\"file\":\"lib/foo.rb\",\"line\":1,\"severity\":\"critical\",\"summary\":\"bug\",\"failure_scenario\":\"crash\"}]}"
touch "$R/.claude/.verification-warn"
run_stop "$R" false
[ "$RC" = 0 ] && ok "review_gate + .verification-warn -> warn only (allow)" || no "review warn: expected 0, got $RC"
rm -rf "$R"

# ---- review_verify.sh direct (artifact freshness + citations) ----
echo "review_verify:"
verify() { VOUT="$(cd "$1" && bash "$VER" 2>&1)"; }   # verify <repo> -> exit code; VOUT = its message
finding() { printf '{"file":"%s","line":%s,"severity":"improvement","summary":"s","failure_scenario":"f"}' "$1" "$2"; }

# A large diff: grep -q matching early used to SIGPIPE the producer under pipefail and reject a valid citation.
setup_review_repo; seq 1 20000 | sed 's/^/n = /' > "$R/lib/big.rb"
SHA="$(cd "$R" && bash "$VER" --emit-sha)"
write_art "$R" "{\"diff_sha\":\"$SHA\",\"verdict\":\"pass\",\"findings\":[$(finding lib/big.rb 2)]}"
verify "$R"; rc=$?
[ "$rc" = 0 ] && ok "large diff: early changed-line citation validates (no SIGPIPE false reject)" || no "large diff: expected 0, got $rc"
rm -rf "$R"

# Committed-work repo: base has lib/old.rb; the reviewed change edits it, stages one new file, leaves one untracked.
setup_committed_repo() { # sets R, SHA, BASE (review stamped with base, nothing committed yet)
  R="$(mkrepo "$RVBASE")"; mkdir -p "$R/.claude/.review"
  seq 1 10 | sed 's/^/v = /' > "$R/lib/old.rb"
  git -C "$R" add -A; git -C "$R" commit -qm base
  sed -i.bak 's/^v = 9$/v = 90/' "$R/lib/old.rb"; rm -f "$R/lib/old.rb.bak"
  printf 'z = 1\n' > "$R/lib/zeta.rb"; git -C "$R" add lib/zeta.rb
  printf 'x = 1\n' > "$R/lib/alpha.rb"
  SHA="$(cd "$R" && bash "$VER" --emit-sha)"; BASE="$(cd "$R" && bash "$VER" --emit-base)"
  write_art "$R" "{\"base\":\"$BASE\",\"diff_sha\":\"$SHA\",\"verdict\":\"pass\",\"findings\":[$(finding lib/old.rb 9),$(finding lib/alpha.rb 1),$(finding lib/zeta.rb 1)]}"
}
commit_reviewed_work() { # two commits, so the reviewed diff spans a range
  git -C "$1" add lib/alpha.rb; git -C "$1" commit -qm one
  git -C "$1" add -A; git -C "$1" commit -qm two
}

setup_committed_repo
verify "$R"; rc=$?
[ "$rc" = 0 ] && ok "base-stamped review, uncommitted -> fresh" || no "base uncommitted: expected 0, got $rc"
commit_reviewed_work "$R"
verify "$R"; rc=$?
[ "$rc" = 0 ] && ok "base-stamped review, work committed in 2 commits -> fresh, findings still cite changed lines" || no "base committed: expected 0, got $rc"
printf 'y = 2\n' >> "$R/lib/alpha.rb"
verify "$R"; rc=$?
[ "$rc" = 2 ] && ok "committed review + uncommitted edit after -> stale" || no "base + uncommitted edit: expected 2, got $rc"
git -C "$R" commit -qam three
verify "$R"; rc=$?
[ "$rc" = 2 ] && ok "committed review + committed edit after -> stale" || no "base + committed edit: expected 2, got $rc"
rm -rf "$R"

# After the commit, a finding must still cite a changed hunk relative to base (line 1 is outside it).
setup_committed_repo
write_art "$R" "{\"base\":\"$BASE\",\"diff_sha\":\"$SHA\",\"verdict\":\"pass\",\"findings\":[$(finding lib/old.rb 1)]}"
commit_reviewed_work "$R"
verify "$R"; rc=$?
[ "$rc" = 2 ] && [[ "$VOUT" == *"lib/old.rb:1, which is not a changed line"* ]] \
  && ok "committed review: finding citing an unchanged line still rejected" || no "base antifake: expected 2 + citation error, got $rc: $VOUT"
rm -rf "$R"

# A symbolic base moves with the branch, so it cannot pin a review: treated as legacy, stale once committed.
setup_committed_repo
write_art "$R" "{\"base\":\"HEAD\",\"diff_sha\":\"$SHA\",\"verdict\":\"pass\",\"findings\":[]}"
commit_reviewed_work "$R"
verify "$R"; rc=$?
[ "$rc" = 2 ] && [[ "$VOUT" == *stale* ]] && ok "symbolic base (HEAD) -> legacy check, stale after commit" || no "symbolic base: expected stale, got $rc: $VOUT"
rm -rf "$R"

# A base that is not a commit in this repo is invalid, never silently accepted.
setup_committed_repo
write_art "$R" "{\"base\":\"0000000000000000000000000000000000000000\",\"diff_sha\":\"$SHA\",\"verdict\":\"pass\",\"findings\":[]}"
verify "$R"; rc=$?
[ "$rc" = 2 ] && ok "unknown base commit -> rejected" || no "unknown base: expected 2, got $rc"
rm -rf "$R"

# Legacy artifact (no base): fresh while uncommitted, stale once committed — unchanged behavior.
setup_review_repo; write_art "$R" "{\"diff_sha\":\"$SHA\",\"verdict\":\"pass\",\"findings\":[$(finding lib/foo.rb 1)]}"
verify "$R"; rc=$?
[ "$rc" = 0 ] && ok "legacy artifact (no base), uncommitted -> fresh" || no "legacy uncommitted: expected 0, got $rc"
git -C "$R" add -A; git -C "$R" commit -qm work
verify "$R"; rc=$?
[ "$rc" = 2 ] && ok "legacy artifact (no base), committed -> stale as before" || no "legacy committed: expected 2, got $rc"
rm -rf "$R"

# ---- skill_nudge (SessionStart) ----
echo "skill_nudge:"
NUDGE="$(CLAUDE_PROJECT_DIR="${TMPDIR:-/tmp}" bash "$HOOKS/skill_nudge.sh" </dev/null)"
# Every guardrails playbook needs its trigger in the nudge; a new playbook fails here until added.
declare -A TRIGGER=([CODE]="first file edit" [DEBUG]="failed command" [VERIFY]="before claiming" [TRAPS]="language trap"
                    [RUNTIME]="code path live" [MECHANISM]="external system" [PRECEDENT]="existing code as the pattern"
                    [SCOPE]="beyond the ask")
for f in "$HERE/../skills/guardrails/references/"*.md; do
  p="$(basename "$f" .md)"
  if [ -z "${TRIGGER[$p]:-}" ]; then no "nudge: playbook $p has no trigger mapped — add it to skill_nudge.sh and this test"
  elif grep -qF "${TRIGGER[$p]}" <<< "$NUDGE"; then ok "nudge mentions the $p trigger"
  else no "nudge lacks the $p trigger ('${TRIGGER[$p]}')"; fi
done

# ---- context_warning (UserPromptSubmit) ----
echo "context_warning:"
R="$(mkrepo '{"components":{}}')"
CW_TMP="$(mktemp -d "${TMPDIR:-/tmp}/harness-cwtest.XXXXXX")"
T="$R/transcript.jsonl"; RM=""
usage() { # usage <main-thread tokens> [sidechain tokens] -> appends assistant entries to $T ($RM = requestedModel)
  printf '{"type":"user","message":{"content":"hi"}}\n' >> "$T"
  printf '{"type":"assistant","isSidechain":false,"requestedModel":"%s","message":{"usage":{"input_tokens":2,"cache_creation_input_tokens":1000,"cache_read_input_tokens":%s}}}\n' "$RM" "$(($1 - 1002))" >> "$T"
  [ -n "${2:-}" ] && printf '{"type":"assistant","isSidechain":true,"message":{"usage":{"input_tokens":%s}}}\n' "$2" >> "$T"
  return 0
}
run_cw() { # run_cw [session] -> hook stdout, stderr in $CW_TMP/err ($CW_WINDOW = HARNESS_CONTEXT_WINDOW, empty = unset)
  local w=(env -u HARNESS_CONTEXT_WINDOW); [ -n "${CW_WINDOW:-}" ] && w=(env HARNESS_CONTEXT_WINDOW="$CW_WINDOW")
  TMPDIR="$CW_TMP" CLAUDE_PROJECT_DIR="$R" "${w[@]}" bash "$HOOKS/context_warning.sh" 2>"$CW_TMP/err" <<EOF
{"session_id":"${1:-s1}","transcript_path":"$T","prompt":"next"}
EOF
}
fresh() { T="$R/transcript-$1.jsonl"; : > "$T"; } # fresh <name> -> start a new transcript

# Unknown window: no marker, no override, never over 200K -> assumed 200K, steps 150K/170K/190K.
usage 120000
[ -z "$(run_cw)" ] && ok "user sees nothing under 150K" || no "warned under 150K"

usage 160000
OUT="$(run_cw)"
if jq -e '.systemMessage and .hookSpecificOutput.hookEventName == "UserPromptSubmit" and .hookSpecificOutput.additionalContext' <<< "$OUT" >/dev/null 2>&1; then
  ok "at 160K the user gets one JSON object with a systemMessage and model context"
else no "160K warning is not a single valid JSON object: $OUT"; fi
grep -q "160K" <<< "$OUT" && ok "warning names the current size (160K)" || no "warning lacks the size: $OUT"
grep -q "not an instruction to stop" <<< "$OUT" && ok "model context says it is not an instruction to stop" || no "model context still mandates stopping: $OUT"
grep -q "Window size unknown" <<< "$OUT" && ok "unknown window: the user is told how to set it" || no "unknown-window hint missing: $OUT"
[ -z "$(run_cw)" ] && ok "the 150K step warns only once" || no "150K step warned twice"

usage 165000 999999
[ -z "$(run_cw)" ] && ok "a larger subagent call neither warns nor implies a bigger window" || no "sidechain usage counted"
usage 172000
grep -q "crossed 170K" <<< "$(run_cw)" && ok "assumed 200K window: warns at 170K" || no "assumed-window 170K step missing"

usage 90000
[ -z "$(run_cw)" ] && ok "after /compact drops context, no warning" || no "warned after context dropped"
usage 155000
grep -q "crossed 150K" <<< "$(run_cw)" && ok "the 150K step re-arms after context drops" || no "150K step did not re-arm"

grep -q "crossed 150K" <<< "$(run_cw other)" && ok "a new session (after /clear) gets its own steps" || no "new session did not warn at 150K"

usage 210000
[ -z "$(run_cw)" ] && ok "a call over 200K implies a 1M window: no warning at 210K" || no "warned at 210K after the window was inferred"

# 1M window from an explicit [1m] model -> 750K/850K/950K.
fresh one-m; RM="claude-opus-5-5[1m]"
usage 160000
[ -z "$(run_cw m1)" ] && ok "[1m] model: no warning at 160K" || no "[1m] model warned at 160K"
usage 760000
OUT="$(run_cw m1)"
grep -q "crossed 750K" <<< "$OUT" && grep -q "of a 1M window (76%)" <<< "$OUT" && ok "[1m] model: warns at 75% and names the share of the window" || no "[1m] 750K step wrong: $OUT"
usage 860000
grep -q "crossed 850K" <<< "$(run_cw m1)" && ok "[1m] model: warns again at 85%" || no "[1m] 850K step missing"
RM=""

# Overrides: harness.json context_warning.window, and HARNESS_CONTEXT_WINDOW over it.
fresh cfg
printf '{"components":{"context_warning":true},"context_warning":{"window":1000000}}' > "$R/.claude/harness.json"
usage 160000
[ -z "$(run_cw c1)" ] && ok "context_warning.window 1M: no warning at 160K" || no "config window ignored at 160K"
usage 750000
grep -q "crossed 750K" <<< "$(run_cw c1)" && ok "context_warning.window 1M: warns at 750K" || no "config window 750K step missing"

fresh cfg200
printf '{"components":{},"context_warning":{"window":200000}}' > "$R/.claude/harness.json"
usage 175000
grep -q "crossed 170K" <<< "$(run_cw c2)" && ok "context_warning.window 200K: steps at 150K/170K/190K" || no "200K window steps wrong"
CW_WINDOW=1000000
[ -z "$(run_cw c3)" ] && ok "HARNESS_CONTEXT_WINDOW overrides context_warning.window" || no "env window did not override config"
usage 760000
grep -q "crossed 750K" <<< "$(run_cw c3)" && ok "HARNESS_CONTEXT_WINDOW 1M: warns at 750K, not the config's 190K" || no "env window 750K step missing"
CW_WINDOW=""

fresh bad; usage 175000
printf '{"components":{},"context_warning":{"window":"lots"}}' > "$R/.claude/harness.json"
grep -q "crossed 170K" <<< "$(run_cw c4)" && ok "a non-numeric config window falls back to the assumed 200K" || no "bad config window broke the fallback"
printf '{"components":{},"context_warning":{"window":"0200000"}}' > "$R/.claude/harness.json"
grep -q "crossed 170K" <<< "$(run_cw c5)" && [ ! -s "$CW_TMP/err" ] && ok "a zero-padded config window is ignored quietly" || no "config window 0200000 not handled: $(cat "$CW_TMP/err")"
printf '{"components":{}}' > "$R/.claude/harness.json"
n=0
for CW_WINDOW in 08 0200000 12345678901234567890; do
  n=$((n+1)); OUT="$(run_cw "e$n")"; rc=$?
  [ "$rc" = 0 ] && [ ! -s "$CW_TMP/err" ] && grep -q "crossed 170K" <<< "$OUT" \
    && ok "HARNESS_CONTEXT_WINDOW=$CW_WINDOW is ignored: exit 0, no stderr, assumed 200K" \
    || no "HARNESS_CONTEXT_WINDOW=$CW_WINDOW: rc=$rc err=$(cat "$CW_TMP/err") out=$OUT"
done
CW_WINDOW=""

printf '{"components":{"context_warning":false}}' > "$R/.claude/harness.json"
[ -z "$(run_cw fresh)" ] && ok "components.context_warning:false silences it" || no "toggle off still warned"
printf '{"components":{}}' > "$R/.claude/harness.json"

OUT="$(TMPDIR="$CW_TMP" CLAUDE_PROJECT_DIR="$R" env -u HARNESS_CONTEXT_WINDOW bash "$HOOKS/context_warning.sh" <<< '{"session_id":"x","transcript_path":"/nonexistent"}')"; rc=$?
[ "$rc" = 0 ] && [ -z "$OUT" ] && ok "a missing transcript exits 0 silently" || no "missing transcript: rc=$rc out=$OUT"
rm -rf "$R" "$CW_TMP"

echo
if [ "$fail" = 0 ]; then echo "OK: hook tests passed ($pass)."; exit 0; else echo "FAIL: $fail hook test(s), $pass passed." >&2; exit 1; fi
