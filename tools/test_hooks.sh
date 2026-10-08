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
verify() { (cd "$1" && bash "$VER" >/dev/null 2>&1); }   # verify <repo> -> exit code of the checker
finding() { printf '{"file":"%s","line":%s,"severity":"improvement","summary":"s","failure_scenario":"f"}' "$1" "$2"; }

# A large diff: grep -q matching early used to SIGPIPE the producer under pipefail and reject a valid citation.
setup_review_repo; seq 1 20000 | sed 's/^/n = /' > "$R/lib/big.rb"
SHA="$(cd "$R" && bash "$VER" --emit-sha)"
write_art "$R" "{\"diff_sha\":\"$SHA\",\"verdict\":\"pass\",\"findings\":[$(finding lib/big.rb 2)]}"
verify "$R"; rc=$?
[ "$rc" = 0 ] && ok "large diff: early changed-line citation validates (no SIGPIPE false reject)" || no "large diff: expected 0, got $rc"
rm -rf "$R"

echo
if [ "$fail" = 0 ]; then echo "OK: hook tests passed ($pass)."; exit 0; else echo "FAIL: $fail hook test(s), $pass passed." >&2; exit 1; fi
