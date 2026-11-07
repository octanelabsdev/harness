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
NUDGE_OUT="$(CLAUDE_PROJECT_DIR="${TMPDIR:-/tmp}" bash "$HOOKS/skill_nudge.sh" </dev/null)"
[ "$(jq -s length <<< "$NUDGE_OUT" 2>/dev/null)" = 1 ] && ok "nudge stdout is exactly one JSON object" || no "nudge stdout is not a single JSON object: $NUDGE_OUT"
jq -e 'has("systemMessage") | not' <<< "$NUDGE_OUT" >/dev/null 2>&1 && ok "nudge stays model-only (no systemMessage)" || no "nudge leaks to the operator: $NUDGE_OUT"
NUDGE="$(jq -r '.hookSpecificOutput.additionalContext' <<< "$NUDGE_OUT" 2>/dev/null)"
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

# ---- session_start_banner (SessionStart) ----
echo "session_start_banner:"
R="$(mkrepo '{"components":{"session_banner":true},"stack":{"name":"rails"}}')"
OUT="$(CLAUDE_PROJECT_DIR="$R" bash "$HOOKS/session_start_banner.sh")"
jq -e . <<< "$OUT" >/dev/null 2>&1 && [ "$(jq -s length <<< "$OUT")" = 1 ] \
  && ok "stdout is exactly one JSON object, so Claude Code parses it" \
  || no "banner stdout is not a single JSON object (Claude Code shows it raw to the model only): $OUT"
jq -e '.systemMessage | test("HARNESS CHECK") and test("stack: rails")' <<< "$OUT" >/dev/null 2>&1 \
  && ok "the operator sees the banner as a systemMessage naming the stack" \
  || no "operator never sees the banner — no systemMessage with HARNESS CHECK + stack: $OUT"
jq -e '.hookSpecificOutput.hookEventName == "SessionStart" and (.hookSpecificOutput.additionalContext | test("HARNESS CHECK"))' <<< "$OUT" >/dev/null 2>&1 \
  && ok "the model still gets the banner as SessionStart additionalContext" \
  || no "model context lost the banner: $OUT"
printf '{"components":{"session_banner":false}}' > "$R/.claude/harness.json"
OUT="$(CLAUDE_PROJECT_DIR="$R" bash "$HOOKS/session_start_banner.sh")"; RC=$?
[ -z "$OUT" ] && [ "$RC" = 0 ] && ok "components.session_banner:false prints nothing" || no "banner shown while disabled (rc=$RC): $OUT"
rm -rf "$R"

# ---- harness_bootstrap (SessionStart) ----
echo "harness_bootstrap:"
R="$(mkrepo '{}')"; rm -f "$R/.claude/harness.json"
OUT="$(CLAUDE_PROJECT_DIR="$R" env -u HARNESS_NO_AUTOBOOTSTRAP bash "$HOOKS/harness_bootstrap.sh")"
[ "$(jq -s length <<< "$OUT" 2>/dev/null)" = 1 ] && ok "bootstrap stdout is exactly one JSON object" || no "bootstrap stdout is not a single JSON object: $OUT"
jq -e '(.systemMessage | test("AUTO-BOOTSTRAP")) and (.hookSpecificOutput.additionalContext | test("AUTO-BOOTSTRAP"))' <<< "$OUT" >/dev/null 2>&1 \
  && ok "the operator is told a harness.json was written for them" || no "bootstrap notice never reaches the operator: $OUT"
[ -f "$R/.claude/harness.json" ] && ok "bootstrap wrote .claude/harness.json" || no "bootstrap wrote no config"
OUT="$(CLAUDE_PROJECT_DIR="$R" env -u HARNESS_NO_AUTOBOOTSTRAP bash "$HOOKS/harness_bootstrap.sh")"
[ -z "$OUT" ] && ok "bootstrap is silent once a config exists" || no "bootstrap spoke over an existing config: $OUT"
rm -rf "$R"

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
run_cw() { # run_cw [session] -> hook stdout, stderr in $CW_TMP/err ($CW_STEPS = HARNESS_CONTEXT_STEPS, empty = unset)
  local w=(env -u HARNESS_CONTEXT_STEPS); [ -n "${CW_STEPS:-}" ] && w=(env HARNESS_CONTEXT_STEPS="$CW_STEPS")
  TMPDIR="$CW_TMP" CLAUDE_PROJECT_DIR="$R" "${w[@]}" bash "$HOOKS/context_warning.sh" 2>"$CW_TMP/err" <<EOF
{"session_id":"${1:-s1}","transcript_path":"$T","prompt":"next"}
EOF
}
fresh() { T="$R/transcript-$1.jsonl"; : > "$T"; } # fresh <name> -> start a new transcript

# No override: steps at 100K/150K/250K tokens.
usage 60000
[ -z "$(run_cw)" ] && ok "default steps: no warning at 60K" || no "warned at 60K on the default steps"
usage 99000
[ -z "$(run_cw)" ] && ok "user sees nothing under 100K" || no "warned under 100K"

usage 104000
OUT="$(run_cw)"
if jq -e '.systemMessage and .hookSpecificOutput.hookEventName == "UserPromptSubmit" and .hookSpecificOutput.additionalContext' <<< "$OUT" >/dev/null 2>&1; then
  ok "at 104K the user gets one JSON object with a systemMessage and model context"
else no "104K warning is not a single valid JSON object: $OUT"; fi
grep -q "crossed 100K" <<< "$OUT" && grep -q "Context is at 104K tokens" <<< "$OUT" && ok "warning names the size in tokens and the step crossed" || no "104K warning wording wrong: $OUT"
grep -q "not an instruction to stop" <<< "$OUT" && ok "model context says it is not an instruction to stop" || no "model context still mandates stopping: $OUT"
[ -z "$(run_cw)" ] && ok "the 100K step warns only once" || no "100K step warned twice"

usage 110000 999999
[ -z "$(run_cw)" ] && ok "a larger subagent call does not warn" || no "sidechain usage counted"
usage 155000
grep -q "crossed 150K" <<< "$(run_cw)" && ok "warns again at 150K" || no "150K step missing"
usage 260000
grep -q "crossed 250K" <<< "$(run_cw)" && ok "warns again at 250K" || no "250K step missing"
usage 800000
[ -z "$(run_cw)" ] && ok "no step past 250K, so no repeat warning" || no "warned past the last step"

usage 90000
[ -z "$(run_cw)" ] && ok "after /compact drops context, no warning" || no "warned after context dropped"
usage 105000
grep -q "crossed 100K" <<< "$(run_cw)" && ok "the 100K step re-arms after context drops" || no "100K step did not re-arm"

grep -q "crossed 100K" <<< "$(run_cw other)" && ok "a new session (after /clear) gets its own steps" || no "new session did not warn at 100K"

# Overrides: harness.json context_warning.steps, and HARNESS_CONTEXT_STEPS over it.
fresh cfg; usage 85000
printf '{"components":{},"context_warning":{"steps":[200000,80000]}}' > "$R/.claude/harness.json"
grep -q "crossed 80K" <<< "$(run_cw c2)" && ok "context_warning.steps [200000,80000]: warns at 80K, order ignored" || no "config steps not honored"
CW_STEPS=500000
[ -z "$(run_cw c3)" ] && ok "HARNESS_CONTEXT_STEPS overrides context_warning.steps" || no "env steps did not override config"
CW_STEPS="300000, 50000"
grep -q "crossed 50K" <<< "$(run_cw c4)" && ok "HARNESS_CONTEXT_STEPS takes a comma list with spaces" || no "env comma list not parsed"
CW_STEPS=""

fresh bad; usage 104000
printf '{"components":{},"context_warning":{"steps":"lots"}}' > "$R/.claude/harness.json"
OUT="$(run_cw c5)"
grep -q "crossed 100K" <<< "$OUT" && [ ! -s "$CW_TMP/err" ] && ok "non-array config steps fall back to the defaults" || no "bad config steps broke the fallback: err=$(cat "$CW_TMP/err") out=$OUT"
printf '{"components":{},"context_warning":{"steps":["0200000","x"]}}' > "$R/.claude/harness.json"
OUT="$(run_cw c6)"
grep -q "crossed 100K" <<< "$OUT" && [ ! -s "$CW_TMP/err" ] && ok "zero-padded and non-numeric config steps are dropped quietly" || no "config steps 0200000/x not handled: err=$(cat "$CW_TMP/err") out=$OUT"
printf '{"components":{}}' > "$R/.claude/harness.json"
n=0
for CW_STEPS in 08 0200000 12345678901234567890 ,,; do
  n=$((n+1)); OUT="$(run_cw "e$n")"; rc=$?
  [ "$rc" = 0 ] && [ ! -s "$CW_TMP/err" ] && grep -q "crossed 100K" <<< "$OUT" \
    && ok "HARNESS_CONTEXT_STEPS=$CW_STEPS is ignored: exit 0, no stderr, default steps" \
    || no "HARNESS_CONTEXT_STEPS=$CW_STEPS: rc=$rc err=$(cat "$CW_TMP/err") out=$OUT"
done
CW_STEPS=""

printf '{"components":{"context_warning":false}}' > "$R/.claude/harness.json"
[ -z "$(run_cw fresh)" ] && ok "components.context_warning:false silences it" || no "toggle off still warned"
printf '{"components":{}}' > "$R/.claude/harness.json"

OUT="$(TMPDIR="$CW_TMP" CLAUDE_PROJECT_DIR="$R" env -u HARNESS_CONTEXT_STEPS bash "$HOOKS/context_warning.sh" <<< '{"session_id":"x","transcript_path":"/nonexistent"}')"; rc=$?
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
denied "$OUT" && ok "retrying the edit without loading the skill is denied again" || no "second Edit let through: $OUT"
OUT="$(run_gg s1 Edit '{"file_path":"app/x.rb"}')"
denied "$OUT" && grep -q "3 of 3" <<< "$OUT" && ok "the third deny says it is the last" || no "third Edit not a final deny: $OUT"
OUT="$(run_gg s1 Edit '{"file_path":"app/x.rb"}')"
[ -z "$OUT" ] && ok "after 3 denies the edit goes through, so a session can't get stuck" || no "fourth Edit still denied: $OUT"
OUT="$(run_gg s1 Edit '{"file_path":"app/x.rb"}' sub1)"
denied "$OUT" && ok "a subagent's first edit gets its own count of denies" || no "subagent first edit not denied: $OUT"

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

# Headless runs with --no-session-persistence have no transcript file; the gate sees the Skill call itself.
T="$R/missing-transcript.jsonl"
OUT="$(run_gg s6 Edit '{"file_path":"app/x.rb"}')"
denied "$OUT" && ok "no transcript file: the first edit is still denied" || no "no transcript: not denied: $OUT"
run_gg s6 Skill '{"skill":"some-other-skill"}' > /dev/null
OUT="$(run_gg s6 Edit '{"file_path":"app/x.rb"}')"
denied "$OUT" && ok "loading a different skill doesn't open the gate" || no "other skill opened the gate: $OUT"
OUT="$(run_gg s6 Skill '{"skill":"harness:guardrails"}')"
[ -z "$OUT" ] && ok "the guardrails Skill call itself is never denied" || no "Skill call was gated: $OUT"
OUT="$(run_gg s6 Edit '{"file_path":"app/x.rb"}')"
[ -z "$OUT" ] && ok "after the guardrails Skill call, edits pass with no transcript to read" || no "edit denied after Skill call: $OUT"
OUT="$(run_gg s6 Edit '{"file_path":"app/x.rb"}' sub2)"
denied "$OUT" && ok "the main agent loading guardrails doesn't open a subagent's gate" || no "subagent inherited the load: $OUT"
T="$R/transcript.jsonl"

GG_SKILL='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"harness:guardrails"}}]}}'
GG_BOUNDARY='{"type":"system","subtype":"compact_boundary","compactMetadata":{"trigger":"auto"}}'
printf '%s\n%s\n' "$GG_SKILL" "$GG_BOUNDARY" > "$T"
OUT="$(run_gg c1 Edit '{"file_path":"app/x.rb"}')"
denied "$OUT" && ok "a guardrails load from before the last compaction doesn't count" || no "pre-compaction load opened the gate: $OUT"
printf '%s\n%s\n%s\n' "$GG_BOUNDARY" "$GG_SKILL" "$GG_BOUNDARY" > "$T"
OUT="$(run_gg c2 Edit '{"file_path":"app/x.rb"}')"
denied "$OUT" && ok "only the last compaction boundary matters" || no "load between two compactions opened the gate: $OUT"
printf '%s\n%s\n' "$GG_BOUNDARY" "$GG_SKILL" > "$T"
OUT="$(run_gg c3 Edit '{"file_path":"app/x.rb"}')"
[ -z "$OUT" ] && ok "loading guardrails again after compaction opens the gate" || no "post-compaction load still denied: $OUT"
printf '%s\n%s\n' "$GG_BOUNDARY" '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/plugin/skills/guardrails/references/CODE.md"}}]}}' > "$T"
OUT="$(run_gg c6 Edit '{"file_path":"app/x.rb"}')"
[ -z "$OUT" ] && ok "reading CODE.md with the Read tool counts as loading guardrails" || no "CODE.md Read didn't open the gate: $OUT"
printf '%s\n' '{"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "Bash", "input": {"command": "cat \"$HOME/Vault/guardrails/CODE.md\""}}]}}' > "$T"
OUT="$(run_gg c7 Edit '{"file_path":"app/x.rb"}')"
[ -z "$OUT" ] && ok "reading CODE.md with cat in Bash counts too" || no "CODE.md cat didn't open the gate: $OUT"
printf '%s\n' '{"type":"user","message":{"content":[{"type":"text","text":"routes to ~/Vault/guardrails/CODE.md; \"skill\":\"harness:guardrails\""}]}}' > "$T"
OUT="$(run_gg c8 Edit '{"file_path":"app/x.rb"}')"
denied "$OUT" && ok "instructions that only mention CODE.md or the skill don't count as loading it" || no "a mention opened the gate: $OUT"
: > "$T"

OUT="$(run_gg o1 Edit '{"file_path":"/Users/you/Vault/notes/decision.md"}')"
[ -z "$OUT" ] && ok "an edit to a file outside the repo isn't gated" || no "out-of-repo edit denied: $OUT"
OUT="$(run_gg o2 Write "$(jq -nc --arg p "$R/app/x.rb" '{file_path:$p}')")"
denied "$OUT" && ok "an absolute path inside the repo is still gated" || no "in-repo absolute path let through: $OUT"
OUT="$(run_gg o3 Write "$(jq -nc --arg p "${R}-sibling/app/x.rb" '{file_path:$p}')")"
[ -z "$OUT" ] && ok "a sibling directory sharing the repo's name prefix isn't the repo" || no "prefix sibling treated as repo: $OUT"

gg_bash() { # gg_bash <session> <command> -> hook stdout
  run_gg "$1" Bash "$(jq -nc --arg c "$(printf '%b' "$2")" '{command:$c}')"
}
n=0
for cmd in \
  'cat >> "$HOME/Vault/Notes/Out-of-Scope Backlog.md" <<'"'"'EOF'"'"'\n- found: x > y; rm -rf app\nEOF' \
  'B="$HOME/Vault/Notes/Backlog.md"; tail -5 "$B"; cat >> "$B" <<'"'"'EOF'"'"'\nnote\nEOF' \
  'cd "$HOME/Vault/RCA" && sed -n 1,5p rca.md && cat >> rca.md <<EOF\nnote\nEOF' \
  'bin/ci > $TMPDIR/ci.txt 2>&1; echo "EXIT=$?"; grep -E "a|b" $TMPDIR/ci.txt' \
  "cd $R; bin/rails test > /tmp/run.log 2>&1" \
  'echo note | tee -a ~/Vault/log.md' \
  'echo x > /dev/stderr'; do
  n=$((n+1)); OUT="$(gg_bash "v$n" "$cmd")"
  [ -z "$OUT" ] && ok "a write outside the repo isn't gated: $(head -1 <<< "$cmd" | cut -c1-60)" || no "out-of-repo write denied: $cmd"
done
for cmd in \
  'cp app/x.rb $TMPDIR/x.rb && sed -i "" s/a/b/ app/x.rb' \
  "cd $R; echo x > app/x.rb" \
  'echo x > $UNSET_VAR/x.rb' \
  "echo x > '\$HOME/x.rb'" \
  'python3 - <<EOF\nopen("app/x.rb","w").write("x")\nEOF' \
  'cat <<EOF | bash\necho x > app/x.rb\nEOF' \
  'echo x | tee -a $TMPDIR/log app/x.rb' \
  'echo x > >(cat > app/x.rb)' \
  'echo x > $HOME/../../repo/app/x.rb' \
  "echo x > $R/app/x.rb; echo y > \$TMPDIR/log"; do
  n=$((n+1)); OUT="$(gg_bash "v$n" "$cmd")"
  denied "$OUT" && ok "a write it can't place outside the repo stays gated: $(head -1 <<< "$cmd" | cut -c1-60)" || no "write let through: $cmd"
done
OUT="$(gg_bash v99 'echo x > app/x.rb')"
grep -q "Write or Edit tool" <<< "$OUT" && ok "a Bash deny says how to write a note outside the repo" || no "Bash deny lacks the out-of-repo hint: $OUT"
for _ in 1 2 3; do gg_bash b1 'echo x > app/x.rb' > /dev/null; done
OUT="$(run_gg b1 Edit '{"file_path":"app/x.rb"}')"
denied "$OUT" && grep -q "1 of 3" <<< "$OUT" && ok "Bash denies don't use up the file-edit denies" || no "Bash denies spent the Edit budget: $OUT"

git -C "$R" commit -q --allow-empty -m init
WT="${R}-wt"; git -C "$R" worktree add -q "$WT" 2>/dev/null
OUT="$(run_gg w1 Edit "$(jq -nc --arg p "$WT/app/x.rb" '{file_path:$p}')")"
denied "$OUT" && ok "an edit in a sibling worktree of the repo is still gated" || no "sibling worktree edit let through: $OUT"
OUT="$(gg_bash w2 "cd $WT; echo x > .claude/.small-fix")"
denied "$OUT" && ok "a Bash write into a sibling worktree is still gated" || no "sibling worktree Bash write let through: $OUT"
git -C "$R" worktree remove --force "$WT" 2>/dev/null; rm -rf "$WT"

run_compact() { # run_compact <session> -> the SessionStart(compact) event
  TMPDIR="$GG_TMP" CLAUDE_PROJECT_DIR="$R" bash "$HOOKS/guardrails_gate.sh" <<< \
    "$(jq -nc --arg s "$1" --arg p "$T" '{session_id:$s,hook_event_name:"SessionStart",source:"compact",transcript_path:$p}')"
}
run_gg c4 Skill '{"skill":"harness:guardrails"}' > /dev/null
run_gg c4 Skill '{"skill":"harness:guardrails"}' sub3 > /dev/null
OUT="$(run_compact c4)"; rc=$?
[ "$rc" = 0 ] && [ -z "$OUT" ] && ok "the compaction reset exits 0 silently" || no "compaction reset: rc=$rc out=$OUT"
OUT="$(run_gg c4 Edit '{"file_path":"app/x.rb"}')"
denied "$OUT" && grep -q "1 of 3" <<< "$OUT" && ok "after compaction, the next edit is denied until guardrails loads again" || no "edit let through after compaction: $OUT"
OUT="$(run_gg c4 Edit '{"file_path":"app/x.rb"}' sub3)"
[ -z "$OUT" ] && ok "compacting the main context leaves a subagent's load alone" || no "subagent lost its load on main compaction: $OUT"
for _ in 1 2 3; do run_gg c5 Edit '{"file_path":"app/x.rb"}' > /dev/null; done
run_compact c5 > /dev/null
OUT="$(run_gg c5 Edit '{"file_path":"app/x.rb"}')"
denied "$OUT" && grep -q "1 of 3" <<< "$OUT" && ok "compaction gives a fresh count of three denies" || no "deny count not reset by compaction: $OUT"
gg_compact="$(jq -r '[.hooks.SessionStart[] | select(.matcher == "compact") | .hooks[].command | select(test("guardrails_gate"))] | length' "$HOOKS/hooks.json")"
[ "$gg_compact" = 1 ] && ok "hooks.json runs the gate on SessionStart(compact)" || no "no SessionStart(compact) entry for the gate"

gg_matcher="$(jq -r '.hooks.PreToolUse[] | select(.hooks[].command|test("guardrails_gate")) | .matcher' "$HOOKS/hooks.json")"
[[ "|$gg_matcher|" == *"|Skill|"* ]] && ok "hooks.json routes Skill calls to the gate" || no "gate matcher lacks Skill: $gg_matcher"

printf '{"components":{"guardrails_gate":false}}' > "$R/.claude/harness.json"
OUT="$(run_gg s5 Edit '{"file_path":"app/x.rb"}')"
[ -z "$OUT" ] && ok "components.guardrails_gate:false turns it off" || no "toggle off still denied: $OUT"
rm -rf "$R" "$GG_TMP"

# ---- commit_gate (PreToolUse/PostToolUse) ----
echo "commit_gate:"
CG_TMP="$(mktemp -d "${TMPDIR:-/tmp}/harness-cgtest.XXXXXX")"
R="$(mkrepo "$(jq -cn '{components:{verification_gate:true},stack:{impl_dirs:["lib"],test_command:"bash t.sh"}}')")"
cat > "$R/t.sh" <<EOF
echo run >> "$CG_TMP/runs"
[ -f "$CG_TMP/red" ] && { echo "3 runs, 1 failures"; exit 1; }
echo "3 runs, 3 assertions, 0 failures"
EOF
printf 'v1\n' > "$R/lib/a.rb"
git -C "$R" add -A && git -C "$R" commit -qm base
run_cg() { # run_cg <event> <command> [tool_use_id] [interrupted] -> hook stdout
  TMPDIR="$CG_TMP" CLAUDE_PROJECT_DIR="$R" bash "$HOOKS/commit_gate.sh" <<< \
    "$(jq -nc --arg e "$1" --arg c "$2" --arg id "${3:-}" --argjson i "${4:-false}" --arg d "$R" \
      '{hook_event_name:$e,tool_name:"Bash",tool_input:{command:$c},tool_use_id:$id,cwd:$d,tool_response:{interrupted:$i}}')"
}
runs() { [ -f "$CG_TMP/runs" ] && wc -l < "$CG_TMP/runs" | tr -d ' ' || echo 0; }

printf 'notes\n' > "$R/docs/notes.md"
OUT="$(run_cg PreToolUse 'git commit -am "docs"')"
[ -z "$OUT" ] && [ "$(runs)" = 0 ] && ok "a commit with no implementation change isn't gated" || no "docs-only commit gated: $OUT"
printf 'v2\n' > "$R/lib/a.rb"
OUT="$(run_cg PreToolUse 'git commit -am "change a"')"
! denied "$OUT" && grep -q "green" <<< "$OUT" && [ "$(runs)" = 1 ] && ok "with no recorded pass, the gate runs the suite and allows the commit on green" || no "green run: runs=$(runs) out=$OUT"
OUT="$(run_cg PreToolUse 'git commit -am "change a"')"
[ -z "$OUT" ] && [ "$(runs)" = 1 ] && ok "the same tree again doesn't rerun the suite" || no "cached tree reran: runs=$(runs) out=$OUT"

printf 'v3\n' > "$R/lib/a.rb"; : > "$CG_TMP/red"
OUT="$(run_cg PreToolUse 'cd '"$R"' && git add lib && git commit -m "v3"')"
denied "$OUT" && grep -q "test_command failed" <<< "$OUT" && grep -q "1 failures" <<< "$OUT" && ok "a red suite denies the commit and shows the failing output" || no "red suite not denied: $OUT"
OUT="$(run_cg PreToolUse 'git commit -F - <<EOF
Fix "git push" docs
EOF')"
denied "$OUT" && ok "a commit with its message in a heredoc is still gated" || no "heredoc commit not gated: $OUT"

rm -f "$CG_TMP/red"; before=$(runs)
run_cg PreToolUse 'caffeinate -i -s bash t.sh > /tmp/ci.log 2>&1' t1 > /dev/null
run_cg PostToolUse 'caffeinate -i -s bash t.sh > /tmp/ci.log 2>&1' t1 > /dev/null
OUT="$(run_cg PreToolUse 'git commit -am "v3"')"
[ -z "$OUT" ] && [ "$(runs)" = "$before" ] && ok "a plain test_command run that exits 0 counts for its tree" || no "plain run not recorded: runs=$(runs) out=$OUT"

printf 'v4\n' > "$R/lib/a.rb"; : > "$CG_TMP/red"
run_cg PreToolUse 'bash t.sh 2>&1 | tail -3' t2 > /dev/null
run_cg PostToolUse 'bash t.sh 2>&1 | tail -3' t2 > /dev/null
run_cg PreToolUse 'bash t.sh; echo "EXIT=$?"' t3 > /dev/null
run_cg PostToolUse 'bash t.sh; echo "EXIT=$?"' t3 > /dev/null
run_cg PreToolUse 'bash t.sh' t4 > /dev/null
run_cg PostToolUse 'bash t.sh' t4 true > /dev/null
run_cg PreToolUse 'bash t.sh' t5 > /dev/null
OUT="$(run_cg PreToolUse 'git commit -am "v4"')"
denied "$OUT" && ok "piped, '; echo', interrupted and failed runs don't count as passes" || no "an untrustworthy run counted: $OUT"
rm -f "$CG_TMP/red"

touch "$R/.claude/.verification-warn"; before=$(runs)
OUT="$(run_cg PreToolUse 'git commit -am "v4"')"
! denied "$OUT" && grep -q "warn only" <<< "$OUT" && [ "$(runs)" = "$before" ] && ok ".verification-warn downgrades the gate to a warning that doesn't run the suite" || no "warn mode: runs=$(runs) out=$OUT"
rm -f "$R/.claude/.verification-warn"
jq '.components.commit_gate = false' "$R/.claude/harness.json" > "$CG_TMP/h.json" && cp "$CG_TMP/h.json" "$R/.claude/harness.json"
OUT="$(run_cg PreToolUse 'git commit -am "v4"')"
[ -z "$OUT" ] && ok "components.commit_gate:false turns it off" || no "toggle off still gated: $OUT"
jq 'del(.components.commit_gate) | .components.verification_gate = false' "$R/.claude/harness.json" > "$CG_TMP/h.json" && cp "$CG_TMP/h.json" "$R/.claude/harness.json"
OUT="$(run_cg PreToolUse 'git commit -am "v4"')"
[ -z "$OUT" ] && ok "off by default when verification_gate is off" || no "gated with verification_gate off: $OUT"
jq '.components.verification_gate = true' "$R/.claude/harness.json" > "$CG_TMP/h.json" && cp "$CG_TMP/h.json" "$R/.claude/harness.json"

OUT="$(run_cg PreToolUse 'git commit -am "v4"')"; before=$(runs)
git -C "$R" add -A && git -C "$R" commit -qm v4
OUT="$(run_cg PreToolUse 'git push -u origin feature')"
[ -z "$OUT" ] && [ "$(runs)" = "$before" ] && ok "a pass recorded before the commit covers the push" || no "push after green commit: runs=$(runs) out=$OUT"
printf 'v6\n' > "$R/lib/a.rb"
OUT="$(run_cg PreToolUse 'gh pr create --fill')"
[ -z "$OUT" ] && ok "a dirty working tree doesn't block a push when HEAD itself passed" || no "push of a tested HEAD denied: $OUT"
printf 'v5\n' > "$R/lib/a.rb"; git -C "$R" commit -qam v5; printf 'v6\n' > "$R/lib/a.rb"; before=$(runs)
OUT="$(run_cg PreToolUse 'gh pr create --fill')"
denied "$OUT" && grep -q "uncommitted implementation changes" <<< "$OUT" && [ "$(runs)" = "$before" ] && ok "an untested HEAD with uncommitted changes is denied without running the suite" || no "dirty push not denied: runs=$(runs) $OUT"
git -C "$R" checkout -q -- lib/a.rb

jq '.stack.test_timeout_sec = 900' "$R/.claude/harness.json" > "$CG_TMP/h.json" && cp "$CG_TMP/h.json" "$R/.claude/harness.json"
OUT="$(TMPDIR="$CG_TMP" CLAUDE_PROJECT_DIR="$R" bash "$HOOKS/commit_gate.sh" <<< \
  "$(jq -nc --arg d "$R" '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_use_id:"s1",cwd:$d,tool_input:{command:"caffeinate -i -s bash t.sh > /dev/null 2>&1",description:"run the suite",timeout:900000}}')")"
new_cmd="$(jq -r '.hookSpecificOutput.updatedInput.command // empty' <<< "$OUT")"
[[ "$new_cmd" == *"tools/run_tests.sh' --timeout 900 --wait 600 -- 'caffeinate -i -s bash t.sh > /dev/null 2>&1'"* ]] &&
  ok "a plain test run is rewritten to go through run_tests.sh with the configured timeout" || no "plain run not rewritten: $OUT"
[ "$(jq -r '.hookSpecificOutput.updatedInput | "\(.description)|\(.timeout)"' <<< "$OUT")" = "run the suite|900000" ] &&
  ok "the rewrite keeps the rest of the tool input" || no "rewrite dropped tool input fields: $OUT"
(cd "$CG_TMP" && bash -c "$new_cmd") && ok "the rewritten command runs the suite and exits 0 on green" || no "rewritten command failed on green"
: > "$CG_TMP/red"
(cd "$CG_TMP" && bash -c "$new_cmd") && no "rewritten command exited 0 on red" || ok "the rewritten command exits non-zero on red, so it can't be recorded as a pass"
rm -f "$CG_TMP/red"
jq '.stack.test_lock_wait_sec = 1' "$R/.claude/harness.json" > "$CG_TMP/h.json" && cp "$CG_TMP/h.json" "$R/.claude/harness.json"
held_cmd="$(jq -r '.hookSpecificOutput.updatedInput.command' <<< "$(run_cg PreToolUse 'bash t.sh' s2)")"
lockdir="$(git -C "$R" rev-parse --path-format=absolute --git-common-dir)/harness-test.lock"
mkdir "$lockdir" && printf '%s %s 600 %s\n' "$$" "$(date +%s)" "$(hostname)" > "$lockdir/owner"
before=$(runs); rc=0; (cd "$CG_TMP" && bash -c "$held_cmd") > /dev/null 2>&1 || rc=$?
[ "$rc" = 3 ] && [ "$(runs)" = "$before" ] && ok "while another suite holds the lock, the rewritten run waits and never runs alongside it" || no "rewritten run ignored the lock: rc=$rc runs=$(runs)"
rm -rf "$lockdir"
jq 'del(.stack.test_lock_wait_sec)' "$R/.claude/harness.json" > "$CG_TMP/h.json" && cp "$CG_TMP/h.json" "$R/.claude/harness.json"
OUT="$(run_cg PreToolUse "cd \"$R\" && bash t.sh")"
(cd "$CG_TMP" && bash -c "$(jq -r '.hookSpecificOutput.updatedInput.command' <<< "$OUT")") && ok "a quoted cd survives the rewrite" || no "quoted cd broke the rewrite: $OUT"
OUT="$(run_cg PreToolUse 'tools/run_tests.sh --wait 60 -- bash t.sh')"
[ -z "$(jq -r '.hookSpecificOutput.updatedInput // empty' <<< "$OUT" 2>/dev/null)" ] && ok "a run already going through run_tests.sh isn't rewritten" || no "run_tests.sh run rewritten again: $OUT"
OUT="$(run_cg PreToolUse 'bash t.sh 2>&1 | tail -3')"
[ -z "$OUT" ] && ok "a piped run isn't rewritten" || no "piped run rewritten: $OUT"
OUT="$(TMPDIR="$CG_TMP" CLAUDE_PROJECT_DIR="$R" bash "$HOOKS/commit_gate.sh" <<< \
  "$(jq -nc --arg d "$R" '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_use_id:"bg1",cwd:$d,tool_input:{command:"bash t.sh",run_in_background:true}}')")"
common_dir="$(git -C "$R" rev-parse --path-format=absolute --git-common-dir)"
grep -q "run_tests.sh" <<< "$OUT" && [ ! -f "$common_dir/harness-test-pending/bg1" ] && ok "a background run is serialized but never recorded as a pass" || no "background run: $OUT"

for c in 'echo "git commit -am x"' 'git commit --dry-run -a' 'git log --oneline -3'; do
  OUT="$(run_cg PreToolUse "$c")"
  [ -z "$OUT" ] && ok "not a commit or push: $c" || no "gated a non-ship command: $c"
done
cg_pre="$(jq -r '[.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[] | select(.command | test("commit_gate")) | .timeout][0] // empty' "$HOOKS/hooks.json")"
cg_post="$(jq -r '[.hooks.PostToolUse[] | select(.matcher == "Bash") | .hooks[].command | select(test("commit_gate"))] | length' "$HOOKS/hooks.json")"
[ "$cg_pre" = 1800 ] && [ "$cg_post" = 1 ] && ok "hooks.json routes Bash Pre/PostToolUse to the gate, with room to run the suite" || no "commit_gate routing: pre timeout=$cg_pre post=$cg_post"
rm -rf "$R" "$CG_TMP"

# ---- commit_gate + verification_gate: a Stop pass carries to the commit; the review must cover the tree ----
echo "commit_gate handoff and review:"
HO_TMP="$(mktemp -d "${TMPDIR:-/tmp}/harness-hotest.XXXXXX")"
R="$(mkrepo "$(jq -cn --arg c "echo run >> $HO_TMP/runs; echo '2 runs, 0 failures'" '{components:{verification_gate:true},stack:{impl_dirs:["lib"],test_command:$c}}')")"
git -C "$R" add -A && git -C "$R" commit -qm base
ho_cg() { # ho_cg <command> -> commit gate stdout
  TMPDIR="$HO_TMP" CLAUDE_PROJECT_DIR="$R" bash "$HOOKS/commit_gate.sh" <<< \
    "$(jq -nc --arg c "$1" --arg d "$R" '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c},cwd:$d}')"
}
ho_runs() { [ -f "$HO_TMP/runs" ] && wc -l < "$HO_TMP/runs" | tr -d ' ' || echo 0; }

printf 'x = 1\n' > "$R/lib/foo.rb"
run_stop "$R" false
OUT="$(ho_cg 'git commit -am "foo"')"
[ "$RC" = 0 ] && [ -z "$OUT" ] && [ "$(ho_runs)" = 1 ] && ok "a green Stop run is recorded, so the commit right after doesn't rerun the suite" || no "Stop pass not carried to the commit: rc=$RC runs=$(ho_runs) out=$OUT"
run_stop "$R" false
[ "$(ho_runs)" = 2 ] && ok "the Stop gate itself still runs the suite every time" || no "Stop gate reused a pass: runs=$(ho_runs)"

jq '.components.review_gate = true' "$R/.claude/harness.json" > "$HO_TMP/h.json" && cp "$HO_TMP/h.json" "$R/.claude/harness.json"
mkdir -p "$R/.claude/.review"; before=$(ho_runs)
OUT="$(ho_cg 'git commit -am "foo"')"
denied "$OUT" && grep -q "blind review" <<< "$OUT" && [ "$(ho_runs)" = "$before" ] && ok "with review_gate on and no review, the commit is denied before any suite run" || no "missing review not denied: $OUT"
SHA="$(cd "$R" && bash "$VER" --emit-sha)"
printf '{"diff_sha":"%s","verdict":"pass","findings":[]}' "$SHA" > "$R/.claude/.review/current.json"
OUT="$(ho_cg 'git commit -am "foo"')"
[ -z "$OUT" ] && ok "a fresh passing review plus a recorded green run lets the commit through" || no "reviewed and tested commit denied: $OUT"
printf 'x = 2\n' > "$R/lib/foo.rb"
OUT="$(ho_cg 'git commit -am "foo"')"
denied "$OUT" && grep -q "blind review" <<< "$OUT" && ok "an edit after the review makes it stale and the commit is denied" || no "stale review not denied: $OUT"
touch "$R/.claude/.verification-warn"
OUT="$(ho_cg 'git commit -am "foo"')"
! denied "$OUT" && grep -q "warn only" <<< "$OUT" && ok ".verification-warn makes a missing review advisory too" || no "warn mode review: $OUT"
rm -rf "$R" "$HO_TMP"

# ---- implicit profile: a git repo with no harness.json ----
echo "implicit profile:"
IP_TMP="$(mktemp -d "${TMPDIR:-/tmp}/harness-iptest.XXXXXX")"
R="$(mkrepo '{}')"; rm -f "$R/.claude/harness.json"
mkdir -p "$R/src" "$IP_TMP/bin"
printf '{"name":"x","scripts":{"test":"true"}}\n' > "$R/package.json"
printf 'v1\n' > "$R/src/a.js"
git -C "$R" add -A && git -C "$R" commit -qm base
cat > "$IP_TMP/bin/npm" <<EOF
#!/usr/bin/env bash
[ -f "$IP_TMP/red" ] && { echo "4 tests, 1 failures"; exit 1; }
echo "4 tests, 0 failures"
EOF
chmod +x "$IP_TMP/bin/npm"
ip_cg() { # ip_cg <command> -> commit gate stdout
  PATH="$IP_TMP/bin:$PATH" TMPDIR="$IP_TMP" CLAUDE_PROJECT_DIR="$R" bash "$HOOKS/commit_gate.sh" <<< \
    "$(jq -nc --arg c "$1" --arg d "$R" '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c},cwd:$d}')"
}

printf 'v2\n' > "$R/src/a.js"; : > "$IP_TMP/red"
OUT="$(ip_cg 'git commit -am "v2"')"
denied "$OUT" && grep -q "npm test" <<< "$OUT" && ok "with no harness.json, the commit gate enforces with the detected stack's test command" || no "implicit commit gate didn't deny a red suite: $OUT"
rm -f "$IP_TMP/red"
OUT="$(ip_cg 'git commit -am "v2"')"
! denied "$OUT" && grep -q "green" <<< "$OUT" && ok "and allows the commit once the suite is green" || no "implicit commit gate on green: $OUT"
[ ! -e "$R/.claude/harness.json" ] && [ -z "$(git -C "$R" status --porcelain -- .claude)" ] && ok "the implicit profile writes nothing into the repo" || no "implicit profile wrote into the repo"

: > "$IP_TMP/red"
OUT="$(PATH="$IP_TMP/bin:$PATH" CLAUDE_PROJECT_DIR="$R" bash "$HOOKS/verification_gate.sh" <<< '{"stop_hook_active":false}' 2>&1 1>/dev/null)"; RC=$?
[ "$RC" = 0 ] && grep -q "test_command failed" <<< "$OUT" && grep -q "warn-only" <<< "$OUT" && ok "with no harness.json, a red suite at Stop warns instead of blocking" || no "implicit Stop gate: rc=$RC out=$OUT"
rm -f "$IP_TMP/red"
OUT="$(run_pre "$R" "$R/src/a.js")"
[ -z "$OUT" ] && ok "the pipeline gate stays off with no harness.json" || no "pipeline gate ran implicitly: $OUT"
OUT="$(CLAUDE_PROJECT_DIR="$R" bash "$HOOKS/session_start_banner.sh")"
jq -r .systemMessage <<< "$OUT" | grep -q "detected 'node' preset" && ok "the banner says the detected preset is in use" || no "banner doesn't name the implicit profile: $OUT"

ND="$(mktemp -d "${TMPDIR:-/tmp}/harness-nogit.XXXXXX")"; printf '{}' > "$ND/package.json"; mkdir -p "$ND/src"; : > "$ND/src/a.js"
OUT="$(PATH="$IP_TMP/bin:$PATH" CLAUDE_PROJECT_DIR="$ND" bash "$HOOKS/verification_gate.sh" <<< '{"stop_hook_active":false}' 2>&1)"; RC=$?
[ "$RC" = 0 ] && [ -z "$OUT" ] && ok "outside a git repo, the gates stay inert" || no "non-git dir: rc=$RC out=$OUT"
rm -rf "$R" "$IP_TMP" "$ND"

echo
if [ "$fail" = 0 ]; then echo "OK: hook tests passed ($pass)."; exit 0; else echo "FAIL: $fail hook test(s), $pass passed." >&2; exit 1; fi
