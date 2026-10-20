#!/usr/bin/env bash
# Stop hook — verification gate, stack-agnostic.
#
# When a turn ends with implementation code changed (per the stack profile's impl_dirs), it RUNS the
# project's canonical test_command and BLOCKS if it fails — a red test is a fact, not a judgment, so
# it is safe to block on. It also reminds (advisory) when a UI/impl change shipped without an
# operator-journey test. Inert unless components.verification_gate is true in .claude/harness.json.
#
# Enforcement posture: a test_command failure BLOCKS by default (locked decision — Layer-0 checks are
# deterministic). Adopters rolling out gradually can downgrade to warn-only by creating
# .claude/.verification-warn (a failure is then surfaced but does not block). The operator-test check
# is always advisory — it is a heuristic, not a pass/fail.
#
# Stop-hook mechanics (verified against the hooks guide): exit 2 prevents the stop and continues the
# conversation so Claude addresses the gap; exit 0 lets the turn end. The stop_hook_active guard keeps
# a block from looping. (Whether exit-2 stderr is shown to the model is not spelled out in the docs;
# the block/continue itself is — the enforcement does not depend on the message being surfaced.)
#
# NOTE: the old .claude/.last-review "was it reviewed?" check was removed — it compared a model-written
# marker to HEAD and could not tell a real review from a claimed one. A real review gate returns backed
# by a reviewer artifact (harness roadmap phase 3).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; . "$HERE/_harness_lib.sh"
. "$HERE/../lib/harness_detect.sh"
INPUT="$(cat)"

# Loop guard — never re-block once continuation was already requested.
[ "$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)" = "true" ] && exit 0

component_on verification_gate || exit 0   # inert unless enabled for this project

repo="$(harness_repo)"; cd "$repo" 2>/dev/null || exit 0
changed="$(git status --porcelain 2>/dev/null || true)"
[ -z "$changed" ] && exit 0

op_test="$(hcfg '.stack.operator_test_dir' '')"
raw_cmd="$(hcfg '.stack.test_command' '')"
test_cmd="$(harness_resolve_test_command "$repo" "$raw_cmd" "$(hcfg '.stack.name' '')")"
review_gate="$(hcfg '.components."review_gate"' 'false')"
impl=""; ui=""; op_changed=""
while IFS= read -r line; do
  [ -n "$line" ] || continue
  p="${line:3}"                       # strip the 2-char status + space
  p="${p%% -> *}"                     # handle renames
  path_under "$p" impl_dirs && impl=1
  path_under "$p" ui_dirs && ui=1
  if [ -n "$op_test" ]; then case "$p" in "$op_test"/*) op_changed=1 ;; esac; fi
done <<< "$changed"

[ -z "$impl" ] && exit 0   # no implementation change in flight → nothing to gate

# Advisory heuristic (never blocks): UI changed but no operator-journey test alongside it.
op_note=""
if [ -n "$ui" ] && [ -n "$op_test" ] && [ -z "$op_changed" ]; then
  op_note="Operator-task test: implementation UI changed but no $op_test/ change. Add a test that walks the operator's journey (act -> assert the observable outcome), not just an internal-state check."
fi

# Layer 0 — run the canonical test_command and BLOCK on failure (deterministic, unfakeable).
# run_tests.sh serializes runs across sessions/worktrees (a shared test DB makes concurrent suites fail
# each other). Its limits must stay under the Stop hook's timeout in hooks.json: a hook killed by Claude
# Code renders no decision, i.e. a silent pass.
if [ -n "$test_cmd" ] || [ "$raw_cmd" = auto ]; then
  test_timeout_sec="$(hcfg '.stack.test_timeout_sec' '600')"
  lock_wait_sec="$(hcfg '.stack.test_lock_wait_sec' '600')"
  # Fit wait + run inside the hook's own timeout (60s margin for the kill grace and the review layer):
  # the lock wait gives way first, then the run itself. Non-integers fall through to
  # run_tests.sh, which rejects them as a config error.
  hook_timeout_sec="$(jq -r '[.hooks.Stop[].hooks[] | select(.command | test("verification_gate")) | .timeout][0] // 600' "$HERE/hooks.json" 2>/dev/null || echo 600)"
  budget_sec=$(( hook_timeout_sec - 60 ))
  case "$test_timeout_sec$lock_wait_sec" in
    *[!0-9]*) ;;
    *)
      test_timeout_sec=$((10#$test_timeout_sec)); lock_wait_sec=$((10#$lock_wait_sec))   # "0900" -> 900, not octal
      [ "$test_timeout_sec" -gt "$budget_sec" ] && test_timeout_sec="$budget_sec"
      [ $(( test_timeout_sec + lock_wait_sec )) -gt "$budget_sec" ] && lock_wait_sec=$(( budget_sec - test_timeout_sec ))
      ;;
  esac
  trc=0; test_out=""
  if [ -z "$test_cmd" ]; then
    trc=6   # "auto" with no resolver for this stack must not skip the tests silently
  else
    log_copy="$(mktemp "${TMPDIR:-/tmp}/harness-gate-log.XXXXXX" 2>/dev/null || true)"
    test_out="$(bash "$HERE/../tools/run_tests.sh" --timeout "$test_timeout_sec" --wait "$lock_wait_sec" --log-copy "${log_copy:-/dev/null}" -- "$(harness_wrap_ruby "$repo" "$test_cmd")" 2>&1)" || trc=$?
    full_out="$( [ -n "$log_copy" ] && cat "$log_copy" 2>/dev/null || true)"
    [ -n "$log_copy" ] && rm -f "$log_copy"
    # A green run that executed no tests is a misconfigured command, not a pass. Judge the whole log:
    # test_out is only its last 200 lines, which can drop a real summary and keep an empty one.
    [ "$trc" = 0 ] && harness_ran_zero_tests "${full_out:-$test_out}" && trc=5
  fi
  if [ "$trc" != 0 ]; then
    case "$trc" in
      2) verdict="SETUP ERROR — tests did NOT run (bad stack.test_timeout_sec / stack.test_lock_wait_sec, or the test lock can't be created; details below)" ;;
      3) verdict="UNVERIFIED — another test run held the lock past ${lock_wait_sec}s; tests did NOT run" ;;
      4) verdict="UNVERIFIED — test_command exceeded ${test_timeout_sec}s (stack.test_timeout_sec, capped to fit the ${hook_timeout_sec}s hook timeout) and was killed" ;;
      5) verdict="UNVERIFIED — no tests ran (the command passed but every summary reported 0 tests; check stack.test_command)" ;;
      6) verdict="SETUP ERROR — test_command is \"auto\" but stack.name '$(hcfg '.stack.name' '')' has no resolver; set an explicit command" ;;
      *) verdict="test_command failed" ;;
    esac
    {
      echo "VERIFICATION GATE — $verdict: ${test_cmd:-$raw_cmd}"
      printf '%s\n' "$test_out" | tail -n 40
      [ -n "$op_note" ] && echo "$op_note"
    } >&2
    if [ -f "$repo/.claude/.verification-warn" ]; then
      echo "(.claude/.verification-warn present — warn-only, not blocking.)" >&2
      exit 0
    fi
    exit 2
  fi
fi

# Layer 2 (opt-in via components.review_gate) — a blind code review must exist for THIS exact diff,
# verified against it (not self-reported). review_verify.sh exits 0=pass, 1=changes-requested, 2=stale/missing.
if [ "$review_gate" = "true" ]; then
  rv="$HERE/../tools/review_verify.sh"
  if [ -f "$rv" ] && ! rv_out="$(bash "$rv" 2>&1)"; then
    { echo "VERIFICATION GATE — code review not satisfied for the current diff:"; printf '%s\n' "$rv_out"; } >&2
    if [ -f "$repo/.claude/.verification-warn" ]; then
      echo "(.claude/.verification-warn present — warn-only, not blocking.)" >&2
    else
      exit 2
    fi
  fi
fi

# test_command passed (or none configured) — surface the advisory heuristic, non-blocking.
if [ -n "$op_note" ]; then
  { echo "VERIFICATION GATE (advisory):"; echo "  - $op_note"; } >&2
fi
exit 0
