#!/usr/bin/env bash
# run_tests.sh — run the project's test command so that concurrent runs can't stomp each other.
#
#   run_tests.sh [--timeout SEC] [--wait SEC] [--log-copy FILE] -- <command>   (run from inside the repo)
#
# Every Claude session (and every worktree of the same repo) shares one test database unless the app
# isolates it, so two suites running at once fail each other at random. This runner:
#   - takes a repo-wide lock (in the git common dir, so all worktrees share it) and waits for a holder
#     rather than running alongside it;
#   - kills the suite and everything it spawned when it exceeds --timeout.
# It always runs the suite: a result is never reused, so a pass always comes from a real run.
#
# Exit: 0 green · 1 red · 2 usage/config error · 3 busy (lock wait exceeded, NOT run) · 4 timed out.
# A hand-run suite takes the same lock: tools/run_tests.sh -- bin/ci
set -uo pipefail

timeout_sec=600; wait_sec=600; log_copy=""
while [ $# -gt 0 ]; do
  case "$1" in
    --timeout|--wait)
      [ $# -ge 2 ] || { echo "run_tests: $1 needs a value" >&2; exit 2; }
      if [ "$1" = --timeout ]; then timeout_sec="$2"; else wait_sec="$2"; fi
      shift 2 ;;
    --log-copy)   # copy the complete suite log here (only stdout's last 200 lines come back otherwise)
      [ $# -ge 2 ] || { echo "run_tests: $1 needs a value" >&2; exit 2; }
      log_copy="$2"; shift 2 ;;
    --) shift; break ;;
    *)  echo "run_tests: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
cmd="$*"
[ -n "$cmd" ] || { echo "run_tests: no command given" >&2; exit 2; }
for n in "$timeout_sec" "$wait_sec"; do
  case "$n" in ''|*[!0-9]*) echo "run_tests: --timeout/--wait must be whole seconds, got '$n'" >&2; exit 2 ;; esac
done
timeout_sec=$((10#$timeout_sec)); wait_sec=$((10#$wait_sec))   # "0900" is decimal 900, not octal
[ "$timeout_sec" -gt 0 ] || { echo "run_tests: --timeout must be at least 1 second" >&2; exit 2; }

abs_dir() { (cd "$1" 2>/dev/null && pwd -P); }
common="$(abs_dir "$(git rev-parse --git-common-dir 2>/dev/null)")" \
  && gitdir="$(abs_dir "$(git rev-parse --git-dir 2>/dev/null)")" \
  || { echo "run_tests: not inside a git repo" >&2; exit 2; }
lock="$common/harness-test.lock"
reap="$common/harness-test.lock.reap"
log="$gitdir/harness-test-run.log"

mtime_sec() { # GNU first: BSD rejects -c with no stdout; GNU would read `-f %m` as a file named "%m".
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null
}
older_than_10s() { local m; m="$(mtime_sec "$1")" || return 1; [ $(( $(date +%s) - m )) -ge 10 ]; }

# Without a terminal (hooks), the suite gets its own process group, so a timeout kills everything in that
# group, and writes to a log file rather than the gate's pipe — a daemon the suite detached would
# otherwise hold that pipe open past the timeout. Anything the suite moves into a group or session of its
# own (a detached daemon, a driver spawned with its own pgroup) is NOT killed. With a terminal (a
# hand-run), its output streams live instead; descendants are found with pgrep (which some sandboxes
# block) to kill them on timeout.
own_group=""; [ -t 0 ] || own_group=1
kill_tree() { # kill_tree <signal> <pid> — the pid and every descendant it can find
  local c
  for c in $(pgrep -P "$2" 2>/dev/null); do kill_tree "$1" "$c"; done
  kill "-$1" "$2" 2>/dev/null
}
kill_suite() { # kill_suite <signal>
  if [ -n "$own_group" ]; then kill "-$1" -- "-$child" 2>/dev/null
  else kill_tree "$1" "$child"; fi
}

owned=""; child=""
stop_suite() { # TERM, a short grace, then KILL — the suite must be gone before the lock is released
  local i
  kill_suite TERM
  for i in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$child" 2>/dev/null || break; sleep 0.2; done
  kill_suite KILL
  wait "$child" 2>/dev/null; child=""
}
release() {
  trap '' TERM INT HUP   # a second signal mid-cleanup must not skip the KILL or leave the lock behind
  [ -n "$child" ] && stop_suite
  # Only remove a lock this process holds — never another session's.
  [ -n "$owned" ] && [ "$(cat "$lock/owner" 2>/dev/null)" = "$owned" ] && rm -rf "$lock"
}
trap release EXIT
trap 'exit 143' TERM INT HUP

host="$(hostname 2>/dev/null || echo unknown-host)"

# Stale = left by a crashed run: no owner written within 10s of mkdir; the owner pid is gone; or the lock
# has outlived the owner's own limits (owner line = "pid start_sec timeout_sec host"), which also covers a
# dead run's pid being reused by an unrelated process. A pid is only meaningful on the host (or container)
# that wrote it, so for a lock from elsewhere only the limits are trusted.
lock_owner_is_stale() { # lock_owner_is_stale <owner-line>
  [ -n "$1" ] || { older_than_10s "$lock"; return; }
  local pid start_sec limit_sec owner_host LC_ALL=C   # C locale: the kill error text must not be translated
  read -r pid start_sec limit_sec owner_host <<<"$1"
  if [ -z "$owner_host" ] || [ "$owner_host" = "$host" ]; then
    # Only ESRCH means dead. EPERM ("Operation not permitted") is a live process this one can't signal —
    # a sandboxed hand-run, another user — and its lock must be respected.
    case "$(kill -0 "$pid" 2>&1)" in *"No such process"*) return 0 ;; esac
  fi
  case "$start_sec" in ''|*[!0-9]*) return 1 ;; esac   # unparseable -> trust the lock
  case "$limit_sec" in ''|*[!0-9]*) return 1 ;; esac
  [ "$(date +%s)" -gt $(( start_sec + limit_sec + 120 )) ]
}
# Two waiters can both see the same dead owner; only the one holding the reap mutex clears the lock, and
# it re-reads the owner first, so it can't delete a lock another waiter has just taken.
clear_stale_lock() {
  [ -d "$reap" ] && older_than_10s "$reap" && rmdir "$reap" 2>/dev/null   # a reaper that died mid-reap
  mkdir "$reap" 2>/dev/null || return 0
  local current; current="$(cat "$lock/owner" 2>/dev/null)"
  if [ -d "$lock" ] && lock_owner_is_stale "$current"; then
    echo "run_tests: clearing stale lock left by a dead run (${current:-no owner})" >&2
    rm -rf "$lock"
  fi
  rmdir "$reap" 2>/dev/null
}

wait_deadline_sec=$(( $(date +%s) + wait_sec ))
announced=""
# Every pass that doesn't take the lock reaches the deadline check and sleeps, except a retry straight
# after a stale lock was actually removed — so no failure mode can spin until Claude Code cancels the hook.
while :; do
  mkdir_err="$(LC_ALL=C mkdir "$lock" 2>&1)" && break
  case "$mkdir_err" in
    *"File exists"*) ;;   # held (or a stray file/symlink at the path): wait for it below
    *) echo "run_tests: SETUP ERROR — cannot create the test lock ($mkdir_err); not run" >&2; exit 2 ;;
  esac
  if lock_owner_is_stale "$(cat "$lock/owner" 2>/dev/null)"; then
    clear_stale_lock
    [ -e "$lock" ] || [ -L "$lock" ] || continue
  fi
  if [ "$(date +%s)" -ge "$wait_deadline_sec" ]; then
    echo "run_tests: BUSY — another test run has held the lock for ${wait_sec}s ($(cat "$lock/owner" 2>/dev/null)); not run" >&2
    exit 3
  fi
  [ -z "$announced" ] && { echo "run_tests: another test run is in progress — waiting for it" >&2; announced=1; }
  sleep 0.2
done
owned="$$ $(date +%s) $timeout_sec $host"
printf '%s\n' "$owned" > "$lock/owner"

[ -n "$own_group" ] && set -m
if [ -n "$own_group" ]; then bash -c "$cmd" >"$log" 2>&1 & else bash -c "$cmd" & fi
child=$!
set +m
show_log() { [ -n "$own_group" ] && tail -n 200 "$log" 2>/dev/null; return 0; }
run_deadline_sec=$(( $(date +%s) + timeout_sec ))
while kill -0 "$child" 2>/dev/null; do
  if [ "$(date +%s)" -ge "$run_deadline_sec" ]; then
    stop_suite
    show_log
    echo "run_tests: TIMEOUT — '$cmd' exceeded ${timeout_sec}s and was killed" >&2
    exit 4
  fi
  sleep 0.2
done
wait "$child"; rc=$?; child=""
# Copied while the lock is still held, so another run can't overwrite the log first.
[ -n "$log_copy" ] && [ -n "$own_group" ] && cp "$log" "$log_copy" 2>/dev/null
show_log
[ "$rc" = 0 ] || exit 1
exit 0
