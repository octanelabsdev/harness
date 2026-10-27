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

# ---- verification_gate test runs: lock, timeout, budget (tools/run_tests.sh) ----
echo "verification_gate (test runs):"
# vcfg <test_command> [extra stack json] -> harness.json body (jq-built, so commands may contain quotes)
vcfg() {
  local extra="${2:-}"; [ -n "$extra" ] || extra='{}'   # not "${2:-{}}": bash 3.2 expands that to a stray brace
  jq -cn --arg c "$1" --argjson x "$extra" '{components:{verification_gate:true},stack:({impl_dirs:["lib"],test_command:$c} + $x)}'
}
committed_repo() { R="$(mkrepo "$1")"; git -C "$R" commit -q --allow-empty -m base; : > "$R/lib/foo.rb"; }
O="$(mktemp -d "${TMPDIR:-/tmp}/harness-hookout.XXXXXX")"   # side-channel files live OUTSIDE the repo
runs() { wc -l < "$O/runs" | tr -d ' '; }

# Two sessions stopping at once on a shared test DB: the second waits instead of colliding.
shared="echo run >> $O/runs; mkdir $O/db 2>/dev/null || { echo COLLISION; exit 1; }; sleep 2; rmdir $O/db"
committed_repo "$(vcfg "$shared")"; : > "$O/runs"
( run_stop "$R" false; echo "$RC" > "$O/rc.a" ) & ( run_stop "$R" false; echo "$RC" > "$O/rc.b" ) & wait
[ "$(cat "$O/rc.a")" = 0 ] && [ "$(cat "$O/rc.b")" = 0 ] && [ "$(runs)" = 2 ] \
  && ok "concurrent stops on a shared test DB -> serialized, neither collides" \
  || no "concurrent stops: expected 0/0 with the suite run, got $(cat "$O/rc.a")/$(cat "$O/rc.b"), $(runs) runs"
rm -rf "$R"

# A pass always comes from a real run: an unchanged tree re-runs on every stop, nothing is reused.
committed_repo "$(vcfg "echo run >> $O/runs")"; : > "$O/runs"
run_stop "$R" false; run_stop "$R" false
[ "$RC" = 0 ] && [ "$(runs)" = 2 ] && ok "unchanged tree, two stops -> suite runs both times (no reuse)" || no "no reuse: expected 2 runs + exit 0, got $(runs), rc $RC"
rm -rf "$R"

# A lock left by a dead run is cleared, not waited on. (Started now, so only the dead pid can make it stale.)
committed_repo "$(vcfg "echo run >> $O/runs")"; : > "$O/runs"; mkdir "$R/.git/harness-test.lock"
bash -c 'exit 0' & dead=$!; wait "$dead"
printf '%s %s 600\n' "$dead" "$(date +%s)" > "$R/.git/harness-test.lock/owner"
run_stop "$R" false
[ "$RC" = 0 ] && [ "$(runs)" = 1 ] && ok "stale lock from a dead run -> cleared, suite runs" || no "stale lock: expected 0 + 1 run, got $RC, $(runs)"
rm -rf "$R"

# A live pid that has held the lock past its own limits is a dead run's pid reused by another process.
# Wait cap 5s < the holder's 30s life, so only recognising it as stale (not outwaiting it) can pass.
committed_repo "$(vcfg "echo run >> $O/runs" '{"test_lock_wait_sec":5}')"; : > "$O/runs"
sleep 30 & reused=$!
mkdir "$R/.git/harness-test.lock"; printf '%s 0 600\n' "$reused" > "$R/.git/harness-test.lock/owner"
run_stop "$R" false
[ "$RC" = 0 ] && [ "$(runs)" = 1 ] && ok "lock past its owner's limits (reused pid) -> cleared, suite runs" || no "pid reuse: expected 0 + 1 run, got $RC, $(runs)"
kill "$reused" 2>/dev/null; wait "$reused" 2>/dev/null
rm -rf "$R"

# A live holder past the wait cap -> UNVERIFIED block (tests did not run), never a silent pass.
committed_repo "$(vcfg "echo run >> $O/runs" '{"test_lock_wait_sec":1}')"; : > "$O/runs"
sleep 30 & holder=$!
mkdir "$R/.git/harness-test.lock"; printf '%s %s 600\n' "$holder" "$(date +%s)" > "$R/.git/harness-test.lock/owner"
run_stop "$R" false
[ "$RC" = 2 ] && [ "$(runs)" = 0 ] && [[ "$OUT" == *UNVERIFIED*lock* ]] \
  && ok "lock held past test_lock_wait_sec -> blocks as UNVERIFIED, suite not run" || no "busy: expected exit 2 + UNVERIFIED + 0 runs, got $RC, $(runs) runs: $OUT"
[ -d "$R/.git/harness-test.lock" ] && ok "busy: another session's lock is left in place" || no "busy: removed a lock it did not own"
kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
rm -rf "$R"

# A suite past test_timeout_sec is killed and blocks as UNVERIFIED, before Claude Code's hook timeout can.
committed_repo "$(vcfg "sleep 20" '{"test_timeout_sec":1}')"
t0="$(date +%s)"; run_stop "$R" false; took_sec=$(( $(date +%s) - t0 ))
[ "$RC" = 2 ] && [[ "$OUT" == *UNVERIFIED*exceeded* ]] && [ "$took_sec" -lt 10 ] \
  && ok "suite past test_timeout_sec -> killed in ${took_sec}s, blocks as UNVERIFIED" || no "timeout: expected exit 2 + UNVERIFIED in <10s, got $RC in ${took_sec}s: $OUT"
[ ! -d "$R/.git/harness-test.lock" ] && ok "timeout: lock released" || no "timeout: lock left behind"
rm -rf "$R"

# Two waiters on the same dead lock still run one at a time. (This does not isolate the reap mutex: the
# owner re-read alone closes all but a microsecond window, so a mutex regression would not turn it red.)
committed_repo "$(vcfg "$shared")"; : > "$O/runs"
bash -c 'exit 0' & dead=$!; wait "$dead"
mkdir "$R/.git/harness-test.lock"; printf '%s 0\n' "$dead" > "$R/.git/harness-test.lock/owner"
( run_stop "$R" false; echo "$RC" > "$O/rc.a" ) & ( run_stop "$R" false; echo "$RC" > "$O/rc.b" ) & wait
[ "$(cat "$O/rc.a")" = 0 ] && [ "$(cat "$O/rc.b")" = 0 ] \
  && ok "two stops on one stale lock -> still serialized, no collision" \
  || no "stale-lock race: expected 0/0, got $(cat "$O/rc.a")/$(cat "$O/rc.b")"
rm -rf "$R"

# Settings that would outlast the hook's own timeout are capped: the lock wait gives way first.
committed_repo "$(vcfg "echo run >> $O/runs" '{"test_timeout_sec":1740,"test_lock_wait_sec":600}')"; : > "$O/runs"
sleep 30 & holder=$!
mkdir "$R/.git/harness-test.lock"; printf '%s 0\n' "$holder" > "$R/.git/harness-test.lock/owner"
t0="$(date +%s)"; run_stop "$R" false; took_sec=$(( $(date +%s) - t0 ))
[ "$RC" = 2 ] && [[ "$OUT" == *UNVERIFIED*lock* ]] && [ "$took_sec" -lt 10 ] \
  && ok "timeout + wait over the hook budget -> wait capped (busy in ${took_sec}s, not 600s)" || no "budget cap: expected fast UNVERIFIED busy, got $RC in ${took_sec}s: $OUT"
kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
rm -rf "$R"

# run_stop with a 10s cap: a gate that never returns sets RC=hung instead of hanging the suite.
run_stop_capped() {
  ( run_stop "$1" false; echo "$RC" > "$O/rc.c"; printf '%s' "$OUT" > "$O/out.c" ) & local g=$!
  for _ in $(seq 100); do kill -0 "$g" 2>/dev/null || break; sleep 0.1; done
  if kill -0 "$g" 2>/dev/null; then pkill -P "$g" 2>/dev/null; kill "$g" 2>/dev/null; RC=hung; OUT=""
  else wait "$g"; RC="$(cat "$O/rc.c")"; OUT="$(cat "$O/out.c")"; fi
}

# Permission-based setups mean nothing to root (a CI container), so those cases are skipped there.
if [ "$(id -u)" = 0 ]; then
  echo "  - skipped (running as root): unremovable stale lock, non-writable .git"
else
  # A stale lock this run can't remove (root-owned from a container or sudo run) ends as BUSY at the
  # wait cap — never an endless spin that Claude Code would cancel into a silent pass.
  committed_repo "$(vcfg "echo run >> $O/runs" '{"test_lock_wait_sec":2}')"; : > "$O/runs"
  bash -c 'exit 0' & dead=$!; wait "$dead"
  mkdir "$R/.git/harness-test.lock"; printf '%s 0 600\n' "$dead" > "$R/.git/harness-test.lock/owner"
  chmod a-w "$R/.git/harness-test.lock"
  run_stop_capped "$R"
  [ "$RC" = 2 ] && [ "$(runs)" = 0 ] && [[ "$OUT" == *UNVERIFIED* ]] \
    && ok "unremovable stale lock -> UNVERIFIED block at the wait cap, suite not run" \
    || no "unremovable stale lock: expected exit 2 + UNVERIFIED + 0 runs, got $RC, $(runs): $OUT"
  chmod u+w "$R/.git/harness-test.lock"
  rm -rf "$R"

  # A lock that can't even be created (.git not writable) is a setup error at once — not a wait, not a spin.
  committed_repo "$(vcfg "echo run >> $O/runs" '{"test_lock_wait_sec":5}')"; : > "$O/runs"
  chmod a-w "$R/.git"
  t0="$(date +%s)"; run_stop_capped "$R"; took_sec=$(( $(date +%s) - t0 ))
  chmod u+w "$R/.git"
  [ "$RC" = 2 ] && [ "$(runs)" = 0 ] && [[ "$OUT" == *"SETUP ERROR"* ]] && [ "$took_sec" -lt 4 ] \
    && ok "non-writable .git -> SETUP ERROR block in ${took_sec}s, suite not run" \
    || no "non-writable .git: expected fast exit 2 + SETUP ERROR + 0 runs, got $RC in ${took_sec}s, $(runs): $OUT"
  rm -rf "$R"
fi

# A lock written on another host or container: its pid means nothing here, so a "dead" pid doesn't make
# it stale — only its own limits do.
committed_repo "$(vcfg "echo run >> $O/runs" '{"test_lock_wait_sec":1}')"; : > "$O/runs"
bash -c 'exit 0' & dead=$!; wait "$dead"
mkdir "$R/.git/harness-test.lock"; printf '%s %s 600 some-other-host\n' "$dead" "$(date +%s)" > "$R/.git/harness-test.lock/owner"
run_stop_capped "$R"
[ "$RC" = 2 ] && [ "$(runs)" = 0 ] && [[ "$OUT" == *UNVERIFIED*lock* ]] \
  && ok "lock from another host within its limits -> respected (busy), not reaped by pid" \
  || no "foreign-host lock: expected exit 2 + UNVERIFIED + 0 runs, got $RC, $(runs): $OUT"
rm -rf "$R"

# Killing the runner (TERM) stops a suite that ignores TERM before the lock is released.
R="$(mkrepo '{}')"; git -C "$R" commit -q --allow-empty -m base
( cd "$R" && exec bash "$HERE/run_tests.sh" -- "trap '' TERM; sleep 4; touch $O/survived" ) </dev/null >/dev/null 2>&1 & runner=$!
sleep 1; kill -TERM "$runner"
for _ in $(seq 60); do kill -0 "$runner" 2>/dev/null || break; sleep 0.1; done
lock_left=""; [ -d "$R/.git/harness-test.lock" ] && lock_left=1
sleep 5   # past the suite's own 4s: a surviving suite would have created the file by now
[ ! -f "$O/survived" ] && [ -z "$lock_left" ] && ok "runner killed -> TERM-ignoring suite killed too, lock released" \
  || no "runner killed: suite survived=$([ -f "$O/survived" ] && echo yes || echo no), lock left=${lock_left:-no}"
rm -rf "$R" "$O/survived"

# A zero timeout is a config error, not a timeout on every run.
committed_repo "$(vcfg "echo run >> $O/runs" '{"test_timeout_sec":0}')"; : > "$O/runs"
run_stop "$R" false
[ "$RC" = 2 ] && [ "$(runs)" = 0 ] && [[ "$OUT" == *"SETUP ERROR"* ]] && ok "test_timeout_sec: 0 -> SETUP ERROR, suite not run" || no "zero timeout: expected SETUP ERROR + 0 runs, got $RC, $(runs): $OUT"
rm -rf "$R"

# A non-numeric limit is a config error that blocks — never read as a test result.
committed_repo "$(vcfg "echo run >> $O/runs" '{"test_timeout_sec":"10m"}')"; : > "$O/runs"
run_stop "$R" false
[ "$RC" = 2 ] && [ "$(runs)" = 0 ] && [[ "$OUT" == *"SETUP ERROR"* ]] && ok "non-integer test_timeout_sec -> SETUP ERROR block, suite not run" || no "config error: expected exit 2 + SETUP ERROR + 0 runs, got $RC, $(runs): $OUT"
rm -rf "$R"

# A daemon the suite detaches (own session) must not hold the gate past its timeout via an inherited pipe.
# (Daemon lives 15s; the gate must return well before that, then the test kills the daemon.)
committed_repo "$(vcfg "perl -MPOSIX -e 'fork and exit; POSIX::setsid(); open(F, \">$O/daemon.pid\"); print F \$\$; close F; sleep 15'; sleep 30" '{"test_timeout_sec":2}')"
t0="$(date +%s)"; run_stop "$R" false; took_sec=$(( $(date +%s) - t0 ))
[ "$RC" = 2 ] && [ "$took_sec" -lt 10 ] && ok "detached daemon in the suite -> gate still returns at the timeout (${took_sec}s)" \
  || no "detached daemon: expected exit 2 in <10s, got $RC in ${took_sec}s"
[ -f "$O/daemon.pid" ] && kill "$(cat "$O/daemon.pid")" 2>/dev/null; rm -f "$O/daemon.pid"
rm -rf "$R"

# A flag given without its value is a usage error, not an endless argument loop.
R="$(mkrepo '{}')"
( cd "$R" && bash "$HERE/run_tests.sh" --timeout ) >/dev/null 2>&1 & arg=$!
for _ in $(seq 50); do kill -0 "$arg" 2>/dev/null || break; sleep 0.1; done
if kill -0 "$arg" 2>/dev/null; then kill "$arg"; no "run_tests --timeout with no value hangs"
else wait "$arg"; [ $? = 2 ] && ok "run_tests --timeout with no value -> usage error (exit 2)" || no "missing value: expected exit 2"; fi
rm -rf "$R"

# A zero-padded limit is decimal, not octal (bash reads 0900 as an invalid octal number).
committed_repo "$(vcfg "echo run >> $O/runs" '{"test_timeout_sec":"0900","test_lock_wait_sec":"0090"}')"; : > "$O/runs"
run_stop "$R" false
[ "$RC" = 0 ] && [ "$(runs)" = 1 ] && ok "zero-padded limits (0900) -> read as decimal, suite runs green" || no "leading zero: expected 0 + 1 run, got $RC, $(runs): $OUT"
rm -rf "$R"

# The Stop hook's own timeout must outlast the runner's default wait + run (600 + 600), or Claude Code
# cancels the hook mid-suite and the turn ends with no decision.
stop_timeout_sec="$(jq -r '.hooks.Stop[0].hooks[] | select(.command|test("verification_gate")) | .timeout // 0' "$HOOKS/hooks.json")"
[ "$stop_timeout_sec" -gt 1200 ] && ok "hooks.json Stop timeout (${stop_timeout_sec}s) exceeds lock wait + test timeout" || no "hooks.json Stop timeout ${stop_timeout_sec}s must exceed 1200s"
rm -rf "$O"

# ---- verification_gate test command: auto resolution, zero-test guard, Ruby pin ----
echo "verification_gate (test command):"
O="$(mktemp -d "${TMPDIR:-/tmp}/harness-hookout.XXXXXX")"
STUB="$O/bin"; mkdir -p "$STUB"
# Stub runners record what ran and print a real-looking summary, so no Ruby is needed.
cat > "$STUB/bundle" <<EOF
#!/usr/bin/env bash
echo "bundle \$*" >> "$O/ran"; echo "3 examples, 0 failures"
EOF
# Stub mise: `where` succeeds only for versions listed in $O/mise-installed, like the real one.
cat > "$STUB/mise" <<EOF
#!/usr/bin/env bash
if [ "\$1" = where ]; then grep -qx "\${2#ruby@}" "$O/mise-installed"; exit; fi
echo "mise \$*" >> "$O/mise"
while [ \$# -gt 0 ] && [ "\$1" != -- ]; do shift; done; shift; exec "\$@"
EOF
chmod +x "$STUB/bundle" "$STUB/mise"
echo 3.4.4 > "$O/mise-installed"
# rails_repo <rspec|minitest> <test_command> [bin/rails output] -> R: a Rails repo with an impl change
rails_repo() {
  committed_repo "$(vcfg "$2" '{"name":"rails"}')"
  echo 'gem "rails"' > "$R/Gemfile"
  if [ "$1" = rspec ]; then mkdir -p "$R/spec"; printf 'GEM\n  specs:\n    rspec-rails (7.1.1)\n' > "$R/Gemfile.lock"; fi
  mkdir -p "$R/bin"
  printf '#!/usr/bin/env bash\necho "bin/rails $*" >> "%s/ran"; echo "%s"\n' "$O" "${3:-2 runs, 2 assertions, 0 failures, 0 errors, 0 skips}" > "$R/bin/rails"
  chmod +x "$R/bin/rails"; : > "$O/ran"; : > "$O/mise"
}
ran() { cat "$O/ran"; }

rails_repo rspec auto; PATH="$STUB:$PATH" run_stop "$R" false
[ "$RC" = 0 ] && [ "$(ran)" = "bundle exec rspec" ] && ok "auto in an RSpec repo -> runs bundle exec rspec" || no "auto rspec: expected bundle exec rspec + exit 0, got '$(ran)', $RC: $OUT"
rm -rf "$R"

rails_repo minitest auto; PATH="$STUB:$PATH" run_stop "$R" false
[ "$RC" = 0 ] && [ "$(ran)" = "bin/rails test" ] && ok "auto in a Minitest repo -> runs bin/rails test" || no "auto minitest: expected bin/rails test + exit 0, got '$(ran)', $RC: $OUT"
rm -rf "$R"

# The beanlink case: an explicit command wins over auto, and when it finds no tests the gate blocks.
rails_repo rspec "bin/rails test" "0 runs, 0 assertions, 0 failures, 0 errors, 0 skips"; PATH="$STUB:$PATH" run_stop "$R" false
[ "$(ran)" = "bin/rails test" ] && ok "explicit test_command wins over auto" || no "explicit: expected bin/rails test to run, got '$(ran)'"
[ "$RC" = 2 ] && [[ "$OUT" == *"UNVERIFIED — no tests ran"* ]] && ok "green run with 0 tests -> blocks as UNVERIFIED" || no "zero tests: expected exit 2 + UNVERIFIED, got $RC: $OUT"
touch "$R/.claude/.verification-warn"; PATH="$STUB:$PATH" run_stop "$R" false
[ "$RC" = 0 ] && [[ "$OUT" == *"no tests ran"* ]] && ok "0 tests + .verification-warn -> warns, does not block" || no "zero tests warn: expected exit 0 + message, got $RC: $OUT"
rm -rf "$R"

committed_repo "$(vcfg 'echo "0 examples, 0 failures"')"; run_stop "$R" false
[ "$RC" = 2 ] && ok "RSpec '0 examples' -> blocks" || no "0 examples: expected exit 2, got $RC"
rm -rf "$R"

committed_repo "$(vcfg 'echo "0 tests, 0 assertions, 0 failures, 0 errors, 0 skips"')"; run_stop "$R" false
[ "$RC" = 2 ] && ok "minitest-reporters '0 tests' -> blocks" || no "0 tests: expected exit 2, got $RC"
rm -rf "$R"

committed_repo "$(vcfg 'echo "Ran 0 tests in 0.001s"')"; run_stop "$R" false
[ "$RC" = 0 ] && ok "'Ran 0 tests in' (no comma) is not read as a summary" || no "Ran 0 tests: expected exit 0, got $RC: $OUT"
rm -rf "$R"

# Multi-step runners (bin/ci) can print an empty summary for one step; any real count is a pass.
committed_repo "$(vcfg 'echo "0 runs, 0 assertions, 0 failures, 0 errors, 0 skips"; echo "12 examples, 0 failures"')"; run_stop "$R" false
[ "$RC" = 0 ] && ok "one zero summary beside a real one -> passes" || no "mixed summaries: expected exit 0, got $RC: $OUT"
rm -rf "$R"

committed_repo "$(vcfg 'echo "10 runs, 30 assertions, 0 failures, 0 errors, 0 skips"')"; run_stop "$R" false
[ "$RC" = 0 ] && ok "'10 runs' is not read as '0 runs'" || no "10 runs: expected exit 0, got $RC: $OUT"
rm -rf "$R"

rails_repo minitest auto; echo "ruby-3.4.4" > "$R/.ruby-version"; PATH="$STUB:$PATH" run_stop "$R" false
[ "$RC" = 0 ] && grep -q '^mise exec ruby@3.4.4 -- bash -c' "$O/mise" && [ "$(ran)" = "bin/rails test" ] \
  && ok ".ruby-version + mise -> runs under mise exec ruby@3.4.4" || no "ruby pin: expected mise exec ruby@3.4.4, got '$(cat "$O/mise")', ran '$(ran)', $RC: $OUT"
rm -rf "$R"

# mise for other tools but Ruby from rbenv: mise lacks the version, so it must not run (or install) it.
rails_repo minitest auto; echo "3.3.9" > "$R/.ruby-version"; PATH="$STUB:$PATH" run_stop "$R" false
[ "$RC" = 0 ] && [ ! -s "$O/mise" ] && [ "$(ran)" = "bin/rails test" ] \
  && ok "mise without that Ruby installed -> command runs unwrapped" || no "mise lacks ruby: expected no mise exec, got '$(cat "$O/mise")', ran '$(ran)', $RC: $OUT"
rm -rf "$R"

# auto follows the configured stack.name, not a fresh detection that could disagree with it.
# No Gemfile, bin/rails or config/application.rb, so detection says generic; stack.name still says rails.
committed_repo "$(vcfg auto '{"name":"rails"}')"; run_stop "$R" false
[[ "$OUT" == *"test_command failed: bin/rails test"* ]] && ok "auto uses stack.name even when detection wouldn't say rails" || no "auto by name: expected bin/rails test to be run, got $RC: $OUT"
rm -rf "$R"

committed_repo "$(vcfg auto '{"name":"generic"}')"; run_stop "$R" false
[ "$RC" = 2 ] && [[ "$OUT" == *"SETUP ERROR"*"no resolver"* ]] && ok "auto with no resolver for the stack -> blocks as SETUP ERROR, never skips" || no "auto unresolved: expected exit 2 + SETUP ERROR, got $RC: $OUT"
rm -rf "$R"

# A real summary more than 200 lines above an empty one must still count: the guard reads the whole log.
committed_repo "$(vcfg 'echo "240 runs, 900 assertions, 0 failures, 0 errors, 0 skips"; for i in $(seq 250); do echo step output; done; echo "0 runs, 0 assertions, 0 failures, 0 errors, 0 skips"')"
run_stop "$R" false
[ "$RC" = 0 ] && ok "real summary beyond the 200-line tail -> still passes" || no "long log: expected exit 0, got $RC: $OUT"
rm -rf "$R"

# Without mise the command runs as written (PATH holds no mise; the function needs only tr).
out="$(PATH=/usr/bin:/bin bash -c '. "$1"; harness_wrap_ruby "$2" "bin/rails test"' _ "$HERE/../lib/harness_detect.sh" "$O")"
echo "3.4.4" > "$O/.ruby-version"
out2="$(PATH=/usr/bin:/bin bash -c '. "$1"; harness_wrap_ruby "$2" "bin/rails test"' _ "$HERE/../lib/harness_detect.sh" "$O")"
[ "$out" = "bin/rails test" ] && [ "$out2" = "bin/rails test" ] && ok "no mise on PATH -> command unchanged" || no "no mise: got '$out' / '$out2'"

# Doctor names the resolved command and flags an explicit Rails command that contradicts the repo.
rails_repo rspec "bin/rails test"
dout="$(CLAUDE_PROJECT_DIR="$R" bash "$HERE/harness_doctor.sh" 2>&1)"
[[ "$dout" == *"verification_gate runs: bin/rails test"* ]] && [[ "$dout" == *"suite runs with 'bundle exec rspec'"* ]] \
  && ok "doctor flags explicit bin/rails test in an RSpec repo" || no "doctor mismatch: expected the resolved command + mismatch note: $dout"
rm -rf "$R"
rails_repo rspec auto
dout="$(CLAUDE_PROJECT_DIR="$R" bash "$HERE/harness_doctor.sh" 2>&1)"
[[ "$dout" == *"verification_gate runs: bundle exec rspec (auto)"* ]] && [[ "$dout" != *"suite runs with"* ]] \
  && ok "doctor shows the auto-resolved command, no mismatch" || no "doctor auto: $dout"
rm -rf "$R"
committed_repo "$(vcfg auto '{"name":"generic"}')"
dout="$(CLAUDE_PROJECT_DIR="$R" bash "$HERE/harness_doctor.sh" 2>&1)"; drc=$?
[ "$drc" = 2 ] && [[ "$dout" == *"has no resolver"* ]] && ok "doctor fails on auto with no resolver" || no "doctor unresolved: expected exit 2 + no resolver, got $drc: $dout"
rm -rf "$R" "$O"

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
T="$R/transcript.jsonl"
usage() { # usage <main-thread tokens> [sidechain tokens] -> appends assistant entries to $T
  printf '{"type":"user","message":{"content":"hi"}}\n' >> "$T"
  printf '{"type":"assistant","isSidechain":false,"message":{"usage":{"input_tokens":2,"cache_creation_input_tokens":1000,"cache_read_input_tokens":%s}}}\n' "$(($1 - 1002))" >> "$T"
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

# No override: a 1M window, steps 750K/850K/950K.
usage 160000
[ -z "$(run_cw)" ] && ok "default 1M window: no warning at 160K" || no "warned at 160K on the default window"
usage 700000
[ -z "$(run_cw)" ] && ok "user sees nothing under 750K" || no "warned under 750K"

usage 760000
OUT="$(run_cw)"
if jq -e '.systemMessage and .hookSpecificOutput.hookEventName == "UserPromptSubmit" and .hookSpecificOutput.additionalContext' <<< "$OUT" >/dev/null 2>&1; then
  ok "at 760K the user gets one JSON object with a systemMessage and model context"
else no "760K warning is not a single valid JSON object: $OUT"; fi
grep -q "crossed 750K" <<< "$OUT" && grep -q "760K of a 1M window (76%)" <<< "$OUT" && ok "warning names the size and the share of the window" || no "760K warning wording wrong: $OUT"
grep -q "not an instruction to stop" <<< "$OUT" && ok "model context says it is not an instruction to stop" || no "model context still mandates stopping: $OUT"
[ -z "$(run_cw)" ] && ok "the 750K step warns only once" || no "750K step warned twice"

usage 765000 999999
[ -z "$(run_cw)" ] && ok "a larger subagent call does not warn" || no "sidechain usage counted"
usage 860000
grep -q "crossed 850K" <<< "$(run_cw)" && ok "warns again at 85% (850K)" || no "850K step missing"

usage 90000
[ -z "$(run_cw)" ] && ok "after /compact drops context, no warning" || no "warned after context dropped"
usage 755000
grep -q "crossed 750K" <<< "$(run_cw)" && ok "the 750K step re-arms after context drops" || no "750K step did not re-arm"

grep -q "crossed 750K" <<< "$(run_cw other)" && ok "a new session (after /clear) gets its own steps" || no "new session did not warn at 750K"

# Overrides: harness.json context_warning.window, and HARNESS_CONTEXT_WINDOW over it.
fresh cfg200
printf '{"components":{},"context_warning":{"window":200000}}' > "$R/.claude/harness.json"
usage 175000
OUT="$(run_cw c2)"
grep -q "crossed 170K" <<< "$OUT" && grep -q "of a 200K window" <<< "$OUT" && ok "context_warning.window 200K: steps at 150K/170K/190K" || no "200K window steps wrong: $OUT"
CW_WINDOW=1000000
[ -z "$(run_cw c3)" ] && ok "HARNESS_CONTEXT_WINDOW overrides context_warning.window" || no "env window did not override config"
usage 760000
grep -q "crossed 750K" <<< "$(run_cw c3)" && ok "HARNESS_CONTEXT_WINDOW 1M: warns at 750K, not the config's 190K" || no "env window 750K step missing"
CW_WINDOW=650000
usage 500000
grep -q "crossed 487K" <<< "$(run_cw c4)" && ok "HARNESS_CONTEXT_WINDOW 650K: warns at 487K" || no "env window 650K step missing"
CW_WINDOW=""

fresh bad; usage 760000
printf '{"components":{},"context_warning":{"window":"lots"}}' > "$R/.claude/harness.json"
OUT="$(run_cw c5)"
grep -q "760K of a 1M window" <<< "$OUT" && [ ! -s "$CW_TMP/err" ] && ok "a non-numeric config window falls back to 1M" || no "bad config window broke the fallback: err=$(cat "$CW_TMP/err") out=$OUT"
printf '{"components":{},"context_warning":{"window":"0200000"}}' > "$R/.claude/harness.json"
OUT="$(run_cw c6)"
grep -q "760K of a 1M window" <<< "$OUT" && [ ! -s "$CW_TMP/err" ] && ok "a zero-padded config window is ignored quietly" || no "config window 0200000 not handled: err=$(cat "$CW_TMP/err") out=$OUT"
printf '{"components":{}}' > "$R/.claude/harness.json"
n=0
for CW_WINDOW in 08 0200000 12345678901234567890; do
  n=$((n+1)); OUT="$(run_cw "e$n")"; rc=$?
  [ "$rc" = 0 ] && [ ! -s "$CW_TMP/err" ] && grep -q "760K of a 1M window" <<< "$OUT" \
    && ok "HARNESS_CONTEXT_WINDOW=$CW_WINDOW is ignored: exit 0, no stderr, 1M window" \
    || no "HARNESS_CONTEXT_WINDOW=$CW_WINDOW: rc=$rc err=$(cat "$CW_TMP/err") out=$OUT"
done
CW_WINDOW=""

printf '{"components":{"context_warning":false}}' > "$R/.claude/harness.json"
[ -z "$(run_cw fresh)" ] && ok "components.context_warning:false silences it" || no "toggle off still warned"
printf '{"components":{}}' > "$R/.claude/harness.json"

OUT="$(TMPDIR="$CW_TMP" CLAUDE_PROJECT_DIR="$R" env -u HARNESS_CONTEXT_WINDOW bash "$HOOKS/context_warning.sh" <<< '{"session_id":"x","transcript_path":"/nonexistent"}')"; rc=$?
[ "$rc" = 0 ] && [ -z "$OUT" ] && ok "a missing transcript exits 0 silently" || no "missing transcript: rc=$rc out=$OUT"
rm -rf "$R" "$CW_TMP"

# ---- guardrails_gate (PreToolUse) ----
echo "guardrails_gate:"
R="$(mkrepo '{"components":{}}')"
GG_TMP="$(mktemp -d "${TMPDIR:-/tmp}/harness-ggtest.XXXXXX")"
T="$R/transcript.jsonl"; : > "$T"
run_gg() { # run_gg <session> <tool> <tool_input json> [agent_id] -> hook stdout
  TMPDIR="$GG_TMP" CLAUDE_PROJECT_DIR="$R" bash "$HOOKS/guardrails_gate.sh" <<< \
    "$(jq -nc --arg s "$1" --arg t "$2" --argjson i "$3" --arg a "${4:-}" --arg p "$T" '{session_id:$s,agent_id:$a,tool_name:$t,tool_input:$i,transcript_path:$p}')"
}
denied() { [ "$(jq -r '.hookSpecificOutput.permissionDecision // "none"' <<< "$1" 2>/dev/null)" = deny ]; }

OUT="$(run_gg s1 Edit '{"file_path":"app/x.rb"}')"
denied "$OUT" && grep -q "harness:guardrails" <<< "$OUT" && ok "first Edit without guardrails loaded is denied, naming the skill" || no "first Edit not denied: $OUT"
OUT="$(run_gg s1 Edit '{"file_path":"app/x.rb"}')"
[ -z "$OUT" ] && ok "the retry goes through: the gate fires once per session" || no "second Edit denied again: $OUT"
OUT="$(run_gg s1 Edit '{"file_path":"app/x.rb"}' sub1)"
denied "$OUT" && ok "a subagent's first edit gets its own single deny" || no "subagent first edit not denied: $OUT"

OUT="$(run_gg s2 Bash '{"command":"sed -i s/a/b/ app/models/book/exporter.rb"}')"
denied "$OUT" && ok "a first edit through Bash (sed -i) is denied too" || no "sed -i not caught: $OUT"
for cmd in "cat > app/x.rb <<EOF" "python3 - <<'E'\nopen(p,'w').write(s)\nE" "cp a.rb b.rb" "echo x >> log.txt"; do
  n=$((${n:-0}+1)); OUT="$(run_gg "w$n" Bash "$(jq -nc --arg c "$(printf '%b' "$cmd")" '{command:$c}')")"
  denied "$OUT" && ok "Bash write is an edit: $cmd" || no "Bash write missed: $cmd"
done
for cmd in "cat app/models/book.rb" "grep -rn \"a > b\" app" "bin/rails test 2>&1 | tail -5" "ls > /dev/null" "git diff"; do
  n=$((n+1)); OUT="$(run_gg "r$n" Bash "$(jq -nc --arg c "$cmd" '{command:$c}')")"
  [ -z "$OUT" ] && ok "Bash read is not an edit: $cmd" || no "Bash read treated as an edit: $cmd"
done
OUT="$(run_gg s3 Read '{"file_path":"app/x.rb"}')"
[ -z "$OUT" ] && ok "non-edit tools pass" || no "Read was gated: $OUT"

printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"harness:guardrails"}}]}}\n' > "$T"
OUT="$(run_gg s4 Edit '{"file_path":"app/x.rb"}')"
[ -z "$OUT" ] && ok "with guardrails loaded, the first edit passes" || no "edit denied after guardrails loaded: $OUT"
: > "$T"

printf '{"components":{"guardrails_gate":false}}' > "$R/.claude/harness.json"
OUT="$(run_gg s5 Edit '{"file_path":"app/x.rb"}')"
[ -z "$OUT" ] && ok "components.guardrails_gate:false turns it off" || no "toggle off still denied: $OUT"
rm -rf "$R" "$GG_TMP"

echo
if [ "$fail" = 0 ]; then echo "OK: hook tests passed ($pass)."; exit 0; else echo "FAIL: $fail hook test(s), $pass passed." >&2; exit 1; fi
