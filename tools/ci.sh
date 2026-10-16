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
run() { local label="$1"; shift; echo "── $label ──"; "$@" || rc=1; echo; }

run "shipped-path hygiene" bash tools/check_shipped_paths.sh
run "load smoke (static)"  bash tools/smoke_load.sh --static-only
run "hook behavior"        bash tools/test_hooks.sh
run "installer behavior"   bash tools/test_install.sh
run "docs check behavior" bash tools/test_check_docs.sh
run "docs updated"         bash tools/check_docs.sh
run "self doctor"          bash tools/harness_doctor.sh

if [ "$rc" = 0 ]; then echo "CI OK"; else echo "CI FAILED" >&2; fi
exit "$rc"
