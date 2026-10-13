#!/usr/bin/env bash
# smoke_load.sh — pre-release gate: prove the plugin actually LOADS, not just that it validates.
#
# `claude plugin validate` and `claude plugin details` both check the manifest/inventory but do NOT
# reproduce session-start load errors — the "Duplicate hooks file detected" bug passed both and shipped
# in 0.1.0–0.1.2. This script adds two layers `validate` misses:
#
#   1. Static manifest hygiene (always runs, jq-only): encodes Claude Code's own rules — most importantly
#      that the manifest `hooks` key must NOT point at the standard hooks/hooks.json (it is auto-loaded;
#      referencing it again is the duplicate-hooks bug). This is the deterministic catch for that class.
#   2. Live install+load (runs when `claude` is available): installs the plugin into a throwaway config
#      dir and asserts the component inventory loads with the expected skills/hooks and no error text.
#
# Usage: tools/smoke_load.sh [REPO]   (default: the repo this script lives in)
#        tools/smoke_load.sh --static-only [REPO]

set -u
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATIC_ONLY=0; REPO=""
while [ "$#" -gt 0 ]; do
  case "$1" in --static-only) STATIC_ONLY=1; shift;; -h|--help) sed -n '2,17p' "$0"; exit 0;; *) REPO="$1"; shift;; esac
done
REPO="$(cd "${REPO:-$HERE/..}" && pwd)"
MANIFEST="$REPO/.claude-plugin/plugin.json"
fail=0
note() { printf '  %s\n' "$1"; }
bad()  { printf '  ✘ %s\n' "$1" >&2; fail=1; }
ok()   { printf '  ✔ %s\n' "$1"; }

echo "── harness load smoke ──  repo: $REPO"

# ---- 1. static manifest hygiene ----
echo "static manifest hygiene:"
[ -f "$MANIFEST" ] || { bad "no .claude-plugin/plugin.json"; exit 1; }
jq -e . "$MANIFEST" >/dev/null 2>&1 || { bad "plugin.json is not valid JSON"; exit 1; }

# The standard hooks file is auto-loaded. The manifest `hooks` key is only for ADDITIONAL files;
# if it (string or any array entry) resolves to the standard hooks/hooks.json, that is the duplicate.
dup="$(jq -r '
  (.hooks // empty) as $h
  | ($h | if type=="string" then [$h] elif type=="array" then . else [] end)
  | map(sub("^\\./";"")) | map(select(. == "hooks/hooks.json")) | .[]' "$MANIFEST" 2>/dev/null)"
if [ -n "$dup" ]; then
  bad "manifest.hooks references the auto-loaded standard file ($dup) — remove it (duplicate-hooks bug)"
else
  ok "manifest does not duplicate the standard hooks file"
fi

# The standard hooks file must exist and be well-formed with real events.
HF="$REPO/hooks/hooks.json"
if [ -f "$HF" ] && jq -e '.hooks | objects | keys | length > 0' "$HF" >/dev/null 2>&1; then
  ok "hooks/hooks.json present with events: $(jq -r '.hooks | keys | join(", ")' "$HF")"
else
  bad "hooks/hooks.json missing or has no events"
fi

if [ "$STATIC_ONLY" = 1 ]; then
  [ "$fail" = 0 ] && { echo "OK: static hygiene passed."; exit 0; } || { echo "FAIL: static hygiene." >&2; exit 1; }
fi

# ---- 2. live install + load into a throwaway config ----
CLAUDE_BIN="$(command -v claude || true)"
if [ -z "$CLAUDE_BIN" ]; then
  note "claude not on PATH — skipping live load (static hygiene already ran). Re-run where claude is installed."
  [ "$fail" = 0 ] && exit 0 || exit 1
fi
echo "live install + load:"
SMOKE="$(mktemp -d "${TMPDIR:-/tmp}/harness-smoke.XXXXXX")"
cleanup() { rm -rf "$SMOKE"; }
trap cleanup EXIT
export CLAUDE_CONFIG_DIR="$SMOKE"

"$CLAUDE_BIN" plugin marketplace add "$REPO" >/dev/null 2>&1 || bad "marketplace add failed"
"$CLAUDE_BIN" plugin install harness@harness >/dev/null 2>&1 || bad "plugin install failed"
det="$("$CLAUDE_BIN" plugin details harness 2>&1)"
if grep -qiE "error|failed|not found|duplicate" <<< "$det"; then
  bad "plugin details reported a problem:"; grep -iE "error|failed|not found|duplicate" <<< "$det" | sed 's/^/      /' >&2
else
  ok "installed and loaded clean"
fi
# Hooks are counted per EVENT (SessionStart, Stop, PreToolUse), not per script —
# adding a script under an existing event does not change this number.
grep -q "Hooks (3)" <<< "$det"  && ok "3 hook events present"  || bad "expected 3 hook events in inventory"
# 11 invocable items: 6 skills (blind-review, bookshelf, cycle, guardrails, product-manager, story-writer) + 5 commands (init, agents, status, doctor, update).
grep -q "Skills (11)" <<< "$det" && ok "11 skills + commands present" || bad "expected 11 skills+commands in inventory"
for cmd in init agents status doctor update; do
  grep -qw "$cmd" <<< "$det" && ok "/harness:$cmd command loaded" || bad "expected $cmd command in inventory"
done

if [ "$fail" = 0 ]; then echo "OK: plugin installs and loads clean."; else echo "FAIL: load smoke." >&2; fi
exit "$fail"
