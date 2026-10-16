#!/usr/bin/env bash
# test_check_docs.sh — behavior tests for tools/check_docs.sh in throwaway repos. Wired into tools/ci.sh.
set -uo pipefail
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pass=0; fail=0
ok() { printf '  ✔ %s\n' "$1"; pass=$((pass+1)); }
no() { printf '  ✘ %s\n' "$1" >&2; fail=$((fail+1)); }

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/harness-docstest.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT

# repo <case> -> a repo with a "main" base commit and a feature branch checked out; sets R
repo() {
  R="$ROOT/$1"; mkdir -p "$R/tools" "$R/docs" "$R/hooks"
  git -C "$R" init -q -b main; git -C "$R" config user.email t@example.com; git -C "$R" config user.name t
  cp "$HERE/check_docs.sh" "$R/tools/"; echo a > "$R/hooks/gate.sh"; echo a > "$R/docs/x.md"
  git -C "$R" add -A; git -C "$R" commit -qm base; git -C "$R" checkout -qb feature
}
commit() { git -C "$R" add -A; git -C "$R" commit -qm "$1"; }
check() { DOCS_BASE=main bash "$R/tools/check_docs.sh" 2>&1; }
expect() { # expect <0|1> <label>
  local out rc; out="$(check)"; rc=$?
  [ "$rc" = "$1" ] && ok "$2" || no "$2 — rc=$rc: $out"
}

echo "check_docs:"
repo nochange;  expect 0 "no changes -> pass"
repo codeonly;  echo b > "$R/hooks/gate.sh"; commit "change gate"; expect 1 "behavior change without docs -> fail"
repo withdocs;  echo b > "$R/hooks/gate.sh"; echo b > "$R/docs/x.md"; commit "change gate + docs"; expect 0 "behavior change with docs -> pass"
repo readme;    echo b > "$R/hooks/gate.sh"; echo r > "$R/README.md"; commit "change gate + readme"; expect 0 "behavior change with README -> pass"
repo optout;    echo b > "$R/hooks/gate.sh"; commit "$(printf 'fix typo\n\nDocs-Not-Needed: internal rename')"; expect 0 "Docs-Not-Needed line -> pass"
repo emptyout;  echo b > "$R/hooks/gate.sh"; commit "$(printf 'x\n\nDocs-Not-Needed: ')"; expect 1 "empty Docs-Not-Needed reason -> fail"
repo testsonly; echo t > "$R/tools/test_gate.sh"; commit "add test"; expect 0 "test-only change -> pass"
repo uncommitted; echo b > "$R/hooks/gate.sh"; expect 1 "uncommitted behavior change without docs -> fail"
repo nobase;    echo b > "$R/hooks/gate.sh"; commit "x"
out="$(DOCS_BASE=nope bash "$R/tools/check_docs.sh" 2>&1)"; [ $? = 0 ] && ok "no base ref -> skipped" || no "no base ref -> $out"

echo
if [ "$fail" = 0 ]; then echo "OK: check_docs tests passed ($pass)."; else echo "FAIL: $fail check_docs test(s) failed ($pass passed)." >&2; exit 1; fi
