#!/usr/bin/env bash
# ci.sh — the canonical "run all checks" gate for this repo (Cleetus dogfooding itself).
#
# Fast and deterministic: static shipped-path hygiene, static load smoke (no live plugin install),
# and the fixture-driven hook behavior tests. This is what .claude/harness.json points test_command
# at, and what a pre-push hook should run. The FULL live load smoke (tools/smoke_load.sh with `claude`
# on PATH) is the separate pre-release check.
set -uo pipefail
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE/.." || exit 1

rc=0
# `producer | grep -q` under pipefail: grep exits on the first match, the producer can die of SIGPIPE
# (even printf, once the output passes the pipe buffer), and a match reads as a miss. Feed grep -q
# from a here-string instead: grep -q pattern <<< "$var". Pipelines split across lines aren't seen.
pipe_grep_lint() {
  local hits
  hits="$(grep -nE '(^|[^|])\|[[:space:]]*grep([[:space:]]+-[^[:space:]]+)*[[:space:]]+(-[a-zA-Z]*q[a-zA-Z]*|--quiet|--silent)([[:space:]]|$)' \
            tools/*.sh hooks/*.sh lib/*.sh install.sh | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#')"
  [ -z "$hits" ] && { echo "OK: no pipelines into grep -q"; return 0; }
  printf '%s\n' "$hits"; echo "FAIL: feed grep -q from a here-string (grep -q pattern <<< \"\$var\")" >&2; return 1
}
run() { local label="$1"; shift; echo "── $label ──"; "$@" || rc=1; echo; }

run "shipped-path hygiene" bash tools/check_shipped_paths.sh
run "load smoke (static)"  bash tools/smoke_load.sh --static-only
run "hook behavior"        bash tools/test_hooks.sh
run "cycle workflow"       bash tools/test_cycle.sh
run "self doctor"          bash tools/harness_doctor.sh
run "pipe-to-grep lint"    pipe_grep_lint

if [ "$rc" = 0 ]; then echo "CI OK"; else echo "CI FAILED" >&2; fi
exit "$rc"
