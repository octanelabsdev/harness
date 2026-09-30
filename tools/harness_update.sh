#!/usr/bin/env bash
# harness_update.sh — check for, and move to, a newer Cleetus release tag.
#
# Consumers pin the harness marketplace to an immutable release tag (install.sh writes
# extraKnownMarketplaces.<mkt>.source.ref[+sha] into settings.json). A pinned marketplace does NOT
# auto-update, so a new release does not reach a pinned machine on its own. Moving to a newer tag is:
#   bump the `ref` (and sha) in settings.json  →  /plugin marketplace update <mkt>  →  /reload-plugins.
# This script only does the first step. There is no `remove + re-add`; the settings source is
# authoritative, but a reload alone does NOT re-fetch the marketplace clone at the new tag — the old
# version keeps loading until `/plugin marketplace update` pulls it (observed on 0.2.1 → 0.2.2).
#
# NOTE: only `ref` is observably enforced through the settings→startup path (a tag-level pin); the `sha`
# is written for completeness but is not the guarantee. Protect your release tags. See the discovery note
# "plugin-marketplace-version-resolution" and install.sh for the honest supply-chain story.
#
# Modes:
#   (no args) | --check   read-only: report installed vs latest tag. exit 0 up-to-date, 10 newer available.
#   --apply               bump the pin in the settings file that declares the marketplace, then print the
#                         reload instruction. exit 0 on bump/up-to-date, non-zero on error.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"

MKT_NAME="harness"; MKT_REPO="octanelabsdev/harness"   # matches install.sh (self-referencing marketplace)
MODE="check"
case "${1:-}" in
  --apply) MODE="apply";;
  --check|"") MODE="check";;
  -h|--help) sed -n '2,20p' "$0"; exit 0;;
  *) echo "harness_update: unknown arg '$1' (use --check or --apply)" >&2; exit 2;;
esac

# Currently loaded version = plugin.json at the resolved plugin root (the checked-out marketplace clone).
CUR="$(jq -r '.version // empty' "$PLUGIN/.claude-plugin/plugin.json" 2>/dev/null)"

# Latest release tag upstream (highest vN.N.N). Network; degrade gracefully offline.
LATEST_TAG="$(git ls-remote --tags --refs "https://github.com/$MKT_REPO" 2>/dev/null \
  | sed 's#.*refs/tags/##' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)"

if [ -z "$LATEST_TAG" ]; then
  echo "── Cleetus update ──"
  echo "  installed: ${CUR:-unknown}"
  echo "  could not reach $MKT_REPO to list release tags (offline?) — try again with a network."
  exit 0
fi
LATEST="${LATEST_TAG#v}"

newer() { [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$2" ]; }

echo "── Cleetus update ──"
echo "  installed:   ${CUR:-unknown}"
echo "  latest tag:  $LATEST_TAG"

if [ -z "$CUR" ] || ! newer "$CUR" "$LATEST"; then
  echo "  up to date."
  exit 0
fi

# A newer tag exists.
if [ "$MODE" = check ]; then
  echo "  ⤴ a newer release is available: $CUR → $LATEST_TAG"
  echo "     run  /harness:update --apply  to move to it (then /plugin marketplace update $MKT_NAME, /reload-plugins)."
  exit 10
fi

# --- apply: find the settings file that declares the marketplace, bump ref (+sha), print reload note ---
repo_root="$(git -C "${CLAUDE_PROJECT_DIR:-$PWD}" rev-parse --show-toplevel 2>/dev/null || printf '%s' "${CLAUDE_PROJECT_DIR:-$PWD}")"
CANDIDATES=("$repo_root/.claude/settings.json" "$repo_root/.claude/settings.local.json" "$HOME/.claude/settings.json")
TARGET_SETTINGS=""
for f in "${CANDIDATES[@]}"; do
  [ -f "$f" ] || continue
  if jq -e --arg m "$MKT_NAME" '.extraKnownMarketplaces[$m] // empty' "$f" >/dev/null 2>&1; then
    TARGET_SETTINGS="$f"; break
  fi
done
if [ -z "$TARGET_SETTINGS" ]; then
  echo "  ✘ no settings.json declares the '$MKT_NAME' marketplace (looked in project + user scope)." >&2
  echo "     run the installer to (re)establish the pin:  bash \"$PLUGIN/install.sh\" \"$repo_root\"" >&2
  exit 3
fi

# Resolve the sha for the new tag (peeled), like install.sh; ref-only if unresolvable.
NEW_SHA="$(git ls-remote "https://github.com/$MKT_REPO" "$LATEST_TAG" "$LATEST_TAG^{}" 2>/dev/null \
  | awk '$2 ~ /\^\{\}$/ {peeled=$1} $2 !~ /\^\{\}$/ {plain=$1} END {print (peeled != "" ? peeled : plain)}')"

if ! python3 - "$TARGET_SETTINGS" "$MKT_NAME" "$LATEST_TAG" "$NEW_SHA" <<'PY'
import json, os, sys
p, mkt, ref, sha = sys.argv[1:5]
try:
    s = json.load(open(p)) if os.path.getsize(p) > 0 else {}
except Exception as e:
    print(f"  ✘ could not read {p}: {e}", file=sys.stderr); sys.exit(1)
entry = s.get("extraKnownMarketplaces", {}).get(mkt)
if not entry or "source" not in entry:
    print(f"  ✘ {mkt} not declared in {p}", file=sys.stderr); sys.exit(1)
src = entry["source"]
src["ref"] = ref
src.pop("sha", None)
if sha:
    src["sha"] = sha
with open(p, "w") as f:
    json.dump(s, f, indent=2); f.write("\n")
print(f"  ✔ bumped {mkt} → {ref}" + (f"@{sha[:12]}" if sha else " (ref only)") + f" in {p}")
PY
then
  echo "  ✘ failed to update $TARGET_SETTINGS (permission? invalid JSON?)" >&2
  exit 1
fi

echo
echo "  Activate it:  run  /plugin marketplace update $MKT_NAME   then  /reload-plugins"
echo "                (a reload alone keeps loading $CUR — the update step fetches $LATEST_TAG)"
# Not this script's own path: it lives in the $CUR cache dir and would keep reporting $CUR.
echo "  Then verify:  run  /harness:update   — it should report up to date."
exit 0
