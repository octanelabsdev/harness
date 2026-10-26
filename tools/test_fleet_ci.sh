#!/usr/bin/env bash
# test_fleet_ci.sh — behavior tests for tools/fleet_ci.sh: each repo with the branch gets one bin/ci
# run on a tracked checkout of it, after its setup line, and the operator sees green/red plus signoff.
# A suite already running elsewhere holds the run back; nothing is merged.
#
# Remotes are local bare repos; gh, mise and pgrep are fakes on PATH. pgrep matches against a process
# list file (exit 0 match, 1 none, 3 error, like the real one), so suites really running on this
# machine don't affect the result. Wired into tools/ci.sh.
set -uo pipefail
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FCI="$HERE/fleet_ci.sh"
pass=0; fail=0
ok() { printf '  ✔ %s\n' "$1"; pass=$((pass+1)); }
no() { printf '  ✘ %s\n' "$1" >&2; fail=$((fail+1)); }
has()   { grep -qF -- "$2" <<< "$1" && ok "$3" || no "$3 — output lacked: $2"; }
lacks() { grep -qF -- "$2" <<< "$1" && no "$3 — output had: $2" || ok "$3"; }

tmp="${TMPDIR:-/tmp}"; tmp="${tmp%"${tmp##*[!/]}"}"; ROOT="$(mktemp -d "${tmp:-/tmp}/harness-fcitest.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT

export GIT_CONFIG_GLOBAL="$ROOT/gitconfig" GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git config --global init.defaultBranch main
export FLEET_CI_BUSY_WAIT=0
PROCS="$ROOT/procs"; printf '%s\n' "101 /bin/zsh -l" "102 vim bin/cinema.rb" "103 tail -f log/test.log" > "$PROCS"
BRANCH=chore/harness-v9.9.9-abc1234

BIN="$ROOT/bin"; LOG="$ROOT/calls.log"; mkdir -p "$BIN"; : > "$LOG"
cat > "$BIN/gh" <<EOF
#!/usr/bin/env bash
echo "gh \$*" >> "$LOG"
[ "\$1 \$2" = "pr view" ] && echo SUCCESS
exit 0
EOF
cat > "$BIN/mise" <<EOF
#!/usr/bin/env bash
case "\$1" in
  where) [ "\$2" = ruby@3.4.4 ];;
  exec)  echo "mise \$2 (in \$(basename "\$PWD"))" >> "$LOG"; shift 3; exec "\$@";;
esac
EOF
cat > "$BIN/pgrep" <<EOF
#!/usr/bin/env bash
[ -e "$ROOT/pgrep-broken" ] && { echo "pgrep: Cannot get process list" >&2; exit 3; }
grep -E -- "\$3" "$PROCS"
EOF
chmod +x "$BIN/gh" "$BIN/mise" "$BIN/pgrep"
export PATH="$BIN:$PATH"

# app <name> <bin/ci body> [ruby-version] -> checkout $ROOT/<name>, bare origin, $BRANCH pushed
app() {
  local d="$ROOT/$1"
  git init -q "$d"; mkdir -p "$d/bin"
  printf '#!/usr/bin/env bash\ncat > /dev/null\necho "upstream=$(git rev-parse --abbrev-ref @{u})" >> %s/%s.ran\n%s\n' "$ROOT" "$1" "$2" > "$d/bin/ci"
  chmod +x "$d/bin/ci"
  [ -n "${3:-}" ] && echo "$3" > "$d/.ruby-version"
  git -C "$d" add -A && git -C "$d" commit -q -m init
  git clone -q --bare "$d" "$ROOT/$1.git"
  git -C "$d" remote add origin "$ROOT/$1.git"
  git -C "$d" push -q origin "main:$BRANCH"
}

app green 'test -L config/master.key || { echo "no master.key"; exit 1; }; echo "all green"' ruby-3.4.4
mkdir -p "$ROOT/green/config"; echo secret > "$ROOT/green/config/master.key"
app red 'echo "3 failures"; exit 1'
app nobranch 'exit 0'; git -C "$ROOT/nobranch.git" branch -q -D "$BRANCH"
app badsetup 'exit 0'
cat > "$ROOT/fleet" <<EOF
# path base setup
$ROOT/green    main   mkdir -p config && ln -s "\$CHECKOUT/config/master.key" config/
$ROOT/nobranch main
$ROOT/red      main
$ROOT/badsetup main   echo "bundle: gem not found" && false
EOF

echo "fleet ci:"
out="$(bash "$FCI" "$BRANCH" "$ROOT/fleet" < /dev/null 2>&1)"; rc=$?
[ "$rc" = 1 ] && ok "a red repo -> exit 1" || no "expected exit 1, got $rc"$'\n'"$out"
has "$out" "✔ green: bin/ci green, signoff=SUCCESS" "operator sees green plus the PR's signoff status"
grep -qxF "upstream=origin/$BRANCH" "$ROOT/green.ran" 2>/dev/null && ok "bin/ci ran on a branch tracking origin (signoff can stamp it)" || no "upstream: $(cat "$ROOT/green.ran" 2>/dev/null)"
grep -qF "mise ruby@3.4.4 (in green)" "$LOG" && ok "bin/ci ran under the repo's Ruby" || no "no mise exec: $(cat "$LOG")"
has "$out" "– nobranch: no $BRANCH on origin" "repo without the branch -> skipped"
[ ! -e "$ROOT/nobranch.ran" ] && ok "skipped repo -> bin/ci not run" || no "bin/ci ran for nobranch"
has "$out" "✘ red: bin/ci red, signoff=SUCCESS — see " "red suite -> reported with the log path"
has "$out" "3 failures" "red suite -> tail of its output shown"
has "$out" "✘ badsetup: setup failed" "failing setup line -> reported"
has "$out" "bundle: gem not found" "failing setup line -> its output shown"
[ ! -e "$ROOT/badsetup.ran" ] && ok "failing setup -> bin/ci not run" || no "bin/ci ran after a failed setup"
logdir="$(sed -n 's/^Running bin\/ci on .* (logs: \(.*\))$/\1/p' <<< "$out")"
grep -qF "all green" "$logdir/green.log" 2>/dev/null && ok "full bin/ci log kept at the printed path" || no "no full log under '$logdir'"
for r in green red; do
  [ -z "$(git -C "$ROOT/$r" worktree list | sed 1d)" ] && ok "$r: temp worktree removed" || no "$r: leftover worktree"
  git -C "$ROOT/$r" rev-parse -q --verify "refs/heads/$BRANCH" >/dev/null && no "$r: local $BRANCH left behind" || ok "$r: no local branch left behind"
done
lacks "$(cat "$LOG")" "pr merge" "nothing merged"

echo "machine-wide wait:"
echo "$ROOT/green main mkdir -p config && ln -sf \"\$CHECKOUT/config/master.key\" config/" > "$ROOT/fleet-green"
for busy in "201 bash bin/ci" "202 /Users/you/.local/share/mise/installs/ruby/3.4.8/bin/rspec" "203 ruby bin/rails test:system"; do
  rm -f "$ROOT/green.ran"; cp "$PROCS" "$PROCS.quiet"; echo "$busy" >> "$PROCS"
  out="$(bash "$FCI" "$BRANCH" "$ROOT/fleet-green" < /dev/null 2>&1)"
  has "$out" "✘ green: another test suite kept running" "'${busy#* }' running elsewhere -> not run, said so"
  [ ! -e "$ROOT/green.ran" ] && ok "'${busy#* }' running elsewhere -> bin/ci not started" || no "bin/ci ran alongside '${busy#* }'"
  mv "$PROCS.quiet" "$PROCS"
done
rm -f "$ROOT/green.ran"; touch "$ROOT/pgrep-broken"
out="$(bash "$FCI" "$BRANCH" "$ROOT/fleet-green" < /dev/null 2>&1)"
has "$out" "✘ green: couldn't list processes" "process list unavailable -> fails closed, not run"
[ ! -e "$ROOT/green.ran" ] && ok "process list unavailable -> bin/ci not started" || no "bin/ci ran without a busy check"
rm "$ROOT/pgrep-broken"
out="$(bash "$FCI" "$BRANCH" "$ROOT/fleet-green" < /dev/null 2>&1)"
has "$out" "✔ green: bin/ci green" "editor/log processes that merely mention bin/ci or test -> not treated as busy"

echo "failures that aren't a red suite:"
app gone 'exit 0'; rm -rf "$ROOT/gone.git"
printf '%s\n' "$ROOT/gone main" "$ROOT/typo-path main" > "$ROOT/fleet-gone"
out="$(bash "$FCI" "$BRANCH" "$ROOT/fleet-gone" < /dev/null 2>&1)"; rc=$?
has "$out" "✘ gone: could not reach origin" "unreachable origin -> failed, not skipped"
has "$out" "✘ typo-path: not a git checkout" "mistyped path -> failed, not skipped"
[ "$rc" = 1 ] && ok "unreachable repos -> exit 1" || no "unreachable repos exit $rc"

app slow 'sleep 30'
echo "$ROOT/slow main" > "$ROOT/fleet-slow"
out="$(FLEET_CI_TIMEOUT=2 bash "$FCI" "$BRANCH" "$ROOT/fleet-slow" < /dev/null 2>&1)"
has "$out" "✘ slow: bin/ci timed out after 2s — last 200 lines in" "timeout -> says so"
tailf="$(sed -n 's/.*last 200 lines in \(.*\)$/\1/p' <<< "$out")"
[ -f "$tailf" ] && ok "timeout -> the log path it prints exists" || no "timeout log '$tailf' missing"

rm -f "$ROOT/green.ran"
out="$(FLEET_CI_TIMEOUT=soon bash "$FCI" "$BRANCH" "$ROOT/fleet-green" < /dev/null 2>&1)"
has "$out" "✘ green: run_tests.sh couldn't start bin/ci (exit 2); not run" "run_tests usage/setup error -> 'not run', not 'red'"
[ ! -e "$ROOT/green.ran" ] && ok "run_tests usage/setup error -> bin/ci really didn't run" || no "bin/ci ran despite exit 2"

echo "interrupted run:"
app sleepy 'sleep 20'
echo "$ROOT/sleepy main" > "$ROOT/fleet-sleepy"
# Ctrl-C signals the whole foreground process group; job control gives the run a group of its own
set -m; bash "$FCI" "$BRANCH" "$ROOT/fleet-sleepy" < /dev/null > "$ROOT/sleepy.out" 2>&1 & fpid=$!; set +m
for _ in $(seq 1 50); do [ -e "$ROOT/sleepy.ran" ] && break; sleep 0.2; done
t0=$SECONDS; kill -INT -- "-$fpid" 2>/dev/null; wait "$fpid" 2>/dev/null
[ $((SECONDS - t0)) -lt 10 ] && ok "interrupted -> stops promptly, not after the suite" || no "interrupted -> took $((SECONDS - t0))s to stop"
[ -z "$(git -C "$ROOT/sleepy" worktree list | sed 1d)" ] && ok "interrupted -> temp worktree removed" || no "interrupted -> leftover worktree: $(git -C "$ROOT/sleepy" worktree list)"
git -C "$ROOT/sleepy" rev-parse -q --verify "refs/heads/$BRANCH" >/dev/null && no "interrupted -> local $BRANCH left behind" || ok "interrupted -> no local branch left behind"

git -C "$ROOT/green" branch -q "$BRANCH" "origin/$BRANCH"
out="$(bash "$FCI" "$BRANCH" "$ROOT/fleet-green" < /dev/null 2>&1)"
has "$out" "✘ green: a local $BRANCH already exists" "existing local branch -> refused, not clobbered"

echo
echo "fleet_ci: $pass passed, $fail failed"
[ "$fail" = 0 ]
